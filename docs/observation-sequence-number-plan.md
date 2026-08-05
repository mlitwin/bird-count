# Plan: Strictly Increasing Observation Sequence Numbers

## Status

| Layer | Status |
|---|---|
| Schema (wire contract) | ✅ Done — deployed |
| DynamoDB GSI `gsi_observationNumber` | ✅ Done — deployed |
| Valkey (ElastiCache Serverless) | ✅ Done — deployed, seeded |
| `seq-maintenance` Lambda | ✅ Done — deployed |
| Backend sync/pull (guarded INCR, HWM-primary pull, noop repair, 503) | ✅ Done — deployed |
| Lambda authorizer (M2M + user tokens) | ✅ Done — deployed (see note below) |
| E2E test suite | ✅ Done — 37 checks, runs via `make e2e` |
| iOS `ObservationRecordDTO`: add `observationNumber` | ⬜ Not started |
| iOS `ObservationStore`: `serverSyncedHWM`, `localObservationNumberMax`, `applyServerObservationNumbers` | ⬜ Not started |
| iOS `CloudAPIClient`: HWM in request, `observationNumber` in applied, `tripSequenceHighWater` in response | ⬜ Not started |
| iOS `CloudSyncService`: send HWM, call `applyServerObservationNumbers`, retire `cursorRewindMs` | ⬜ Not started |
| iOS P2P: `localObservationNumberMax` in hello, delta-send optimization | ⬜ Not started |

### Auth note (not in original plan)

The JWT authorizer was replaced with a Lambda authorizer (`birdcount-{env}-authorizer`) because Cognito `client_credentials` access tokens (version 2) carry no `aud` claim, so API Gateway's built-in JWT authorizer always rejected M2M tokens with 401. The Lambda authorizer validates user tokens by `aud` (iOS + web client IDs) and M2M tokens by `scope` (resource server identifier + `/sync`). It runs outside the VPC to reach Cognito's public JWKS endpoint.

---

## Problem Statement

Observations currently have no ordering guarantee beyond `serverUpdatedAt` (a millisecond timestamp). A monotonically increasing, server-assigned `observationNumber` scoped per trip enables:

- Efficient delta sync: clients can send a single integer high-watermark instead of a timestamp cursor, eliminating clock-skew rewind hacks.
- Reliable P2P sync: peers exchange watermarks and only transmit what the other side is missing.
- Audit trails and conflict detection.

Trip scope is intentional: the number space is bounded and semantically meaningful. v1 has one implicit trip ("shared"); the design extends naturally when multi-trip support lands.

### What `observationNumber` is (and is not)

**`observationNumber` is a per-trip *write sequence*, not a stable creation ordinal.** It is (re)assigned by the server on *every accepted write* to a record — creation *and* every subsequent edit. A record edited three times will have carried three different numbers over its lifetime; only the latest is stored. This is the same model as a CouchDB `update_seq` or a database row-version column.

**Mutation model (no deletes).** The app is append-only: records are never deleted. There are exactly two kinds of write, both of which get a fresh `observationNumber` and propagate to clients identically:
- **Append** — a new ledger entry (including *negate* entries that reduce a species count; already supported). This is the "creation" path: a new record, new id, new number, delivered to peers via the import path.
- **Edit** — an additive change to an existing entry (e.g. adding an observed location to one that only had the detected location). Edits **do not change counts** — counts move *only* by appending negate entries — but an edit is still an accepted write: it bumps the record's `observationNumber` to a fresh high value, so it re-enters the delta above every client's HWM and syncs back like a new record.

Because nothing is ever removed, the design needs no tombstones and no "record vanished" signal — the write sequence + LWW merge cover every case. Whole-record LWW still applies to concurrent edits of the *same* entry (latest `updatedAt` wins, so a competing additive field can be lost); this is a pre-existing merge property, independent of `observationNumber`, and counts are unaffected because they never change via edits.

> This model is not an assumption — it's what the code already enforces. The schema documents it verbatim ("Records are immutable after creation except the location/status backfill on the originating device… Adjustment children carry a (possibly negative) count and a `parentId`; the ledger total is the recursive sum" — `bird-count-schema/schemas/observation.schema.json:5`), the DynamoDB module is "Append-only ledger: no TTL, nothing is ever deleted" (`bird-count-backend/terraform/modules/db/main.tf:5`), and the only mutating merge branch is the whole-record LWW at `bird-count-ios/BirdCount/Stores/ObservationStore.swift:498`. "Append" = a new ledger entry or adjustment child; "edit" = the location/status backfill.

This semantic is not a stylistic choice — the delta-sync and HWM-filter mechanisms below are *only correct* under it:

- The server's pull optimization filters out records whose current `observationNumber <= serverSyncedHWM`. If numbers were a *stable* creation ordinal, an edit to an old record (say #10, client's HWM = 100) would leave its number at 10, the filter would exclude it (`10 <= 100`), and **the client would silently lose the edit**. Because the number bumps to a fresh high value on every write, the edited record re-enters the delta above the HWM and is delivered.
- Consequently the *live* set of records does **not** occupy a contiguous `1..N` range: numbers assigned to superseded versions are abandoned. "Gap-free" applies to the counter itself (every `INCR` is consumed by exactly one accepted write), not to the set of currently-live numbers.

Because this field does not provide a stable "observation #42 of this trip" identity, any UI ordinal is a separate concern and is out of scope for this plan.

---

## Data Model Changes

### New field on `ObservationRecordDTO` (schema + wire)

```json
"observationNumber": {
  "type": "integer",
  "minimum": 1,
  "description": "Strictly increasing, server-assigned sequence number scoped to the trip. Absent on legacy records that predate this feature."
}
```

- Optional in the schema (`not` in `required`) so legacy clients can ignore it.
- Set by the server at write time; clients must treat it as read-only.
- Stored in DynamoDB on `StoredObservation` as `observationNumber?: number`.

### DynamoDB

Add `observationNumber` as a top-level attribute on stored items, and build a **GSI `(pk, observationNumber)`** now — partition key = trip `pk`, sort key = `observationNumber`. This GSI is the primary pull mechanism (see *Protocol Changes → HWM-primary pull*): the server queries `observationNumber > serverSyncedHWM ORDER BY observationNumber ASC` and paginates in number order.

Because an edit reassigns a record's `observationNumber` to a fresh high value, DynamoDB moves that record's GSI entry (delete old key, insert new) — so the GSI always holds exactly one entry per live record at its *current* number, and a number-ordered query returns each record at most once. The existing `serverUpdatedAt` GSI is retained only for the legacy cursor fallback (clients that don't yet send the HWM) and for the deferred date-range feature.

---

## Valkey (Auto-Incrementor)

### Why Valkey

Lambda is stateless and ephemeral; DynamoDB conditional writes can implement a counter but at O(N) retries under contention. Valkey's `INCR` is atomic, O(1), and purpose-built for this. ElastiCache Serverless (Valkey mode) is the lowest-ops fit for the current infrastructure.

### Key scheme

```
trip:<tripId>:seq          # current high-water integer, starts at 1
```

For v1 (single trip): `trip:shared:seq`.

### Lambda → Valkey connection

- VPC is required for ElastiCache. Lambda must be placed in the same VPC with a security group that allows outbound port 6379 to the ElastiCache security group.
- Use the `ioredis` client.
- Connection is established once per Lambda cold start and reused across warm invocations.

### Sequence number assignment

In `sync.ts`, for each accepted observation (result = `"written"`), issue a **guarded INCR** — increment only if the key already exists, otherwise fail loudly:

```typescript
// Lua, run via EVAL — atomic. Returns the new number, or -1 if the key is absent.
const INCR_IF_EXISTS = `
  if redis.call('EXISTS', KEYS[1]) == 1 then
    return redis.call('INCR', KEYS[1])
  else
    return -1
  end`;

const n = await valkey.eval(INCR_IF_EXISTS, 1, `trip:${scope}:seq`);
if (n === -1) throw new SeqNotSeededError();   // → 503, see Resilience
stored.observationNumber = n;
```

Why guarded rather than a bare `INCR`: a bare `INCR` on an **absent** key auto-creates it at `1`. Because the counter is seeded only by the `seq-maintenance` Lambda (below), the write-path Lambda never seeds the key itself, so an absent key always means "not seeded yet, or lost to a failover/flush." Auto-creating at `1` there would silently mint duplicate low numbers and corrupt the whole sequence. The guard turns that corruption into a clean 503 that an operator resolves by re-invoking `seq-maintenance` (`action: "seed"`). This single change removes the entire distributed-lock cold-start dance and the warm-Lambda key-loss heuristics that earlier drafts needed.

`INCR` is atomic: concurrent Lambdas cannot receive the same number. Numbers are assigned in write-acceptance order, not in observation time order — this is intentional and acceptable.

**Ordering vs. the DynamoDB write.** The guarded INCR happens *before* the DynamoDB write. If the write then fails, the number is burned and the sequence has a permanent gap. Sequence *values* are therefore not guaranteed gap-free; only the invariant "no two accepted writes share a number" holds. This is fine for HWM/watermark use (clients tolerate gaps) but means `tripSequenceHighWater` (below) is a high-water mark, not a live count. If burned-number gaps must be avoided, INCR after a successful conditional write instead — accept the extra round-trip, and note that a mid-write crash then leaves a record with no number (repaired lazily on its next update, or by backfill).

**Which writes get a number.** Every accepted mutation (`putResult === "written"`) increments — both append (new ledger entry, incl. negate entries) and edit (additive change to an existing entry) — per the mutation model in the Problem Statement. Equal-`updatedAt` re-uploads (noop path) preserve the existing `observationNumber` and do **not** issue a new INCR; this prevents a first/recovery sync (which re-uploads the entire ledger) from renumbering everything. There are no deletes, so there is no tombstone case to handle.

---

## Valkey Population (Maintenance Lambda)

The Valkey counter is seeded by a dedicated **maintenance Lambda**, never lazily by the write-path Lambda. The write-path Lambda only ever issues the guarded INCR above; if the key is absent it returns 503 (see Resilience) rather than trying to seed.

### Why a maintenance Lambda (not a locally-run script)

The counter lives in Valkey, which is only reachable **inside the VPC**. A locally-run script would need a bastion or SSM tunnel each time — fine once, but fragile for the operation that matters most: re-seeding *during* an incident (failover/flush), when the write path is already 503ing and someone is under pressure. Packaging the seed logic as an in-VPC Lambda makes re-seed a single, repeatable, audited `aws lambda invoke` with no network plumbing, no local Valkey client, and IAM-gated access. It reuses the same VPC/SG config the write-path Lambda already needs.

### `seq-maintenance` Lambda

A separate function (own IAM role, in the same private subnets and security group as the write-path Lambda so it can reach both DynamoDB and Valkey). It is **not** wired to API Gateway — it is invoked manually/operationally only. It takes a small JSON event and supports a few actions:

```jsonc
// seed (idempotent): compute MAX(observationNumber) from DynamoDB, raise-only SET
{ "action": "seed",   "trip": "shared", "dryRun": true }
// inspect: return current key value + computed DynamoDB max, write nothing
{ "action": "status", "trip": "shared" }
// backfill+seed: assign numbers to unnumbered records, then seed (see Transition & Backfill)
{ "action": "backfill", "trip": "shared", "dryRun": true }
```

Seed logic (`action: "seed"` / tail of `"backfill"`):

1. Compute `MAX(observationNumber)` across the trip's partition. Because `observationNumber` order and `serverUpdatedAt` order can differ (INCR/write skew), the max is **not** necessarily the last item by timestamp — scan the whole partition. (Small dataset; a full scan is fine for v1.)
2. `SET trip:<trip>:seq <max>` — only ever raising it. Guard with a check-and-set (or a small Lua `if new > current then SET`) so a re-run against an already-live counter can never *lower* it below an already-issued number.
3. If no numbered observations exist, `SET trip:<trip>:seq 0` so the first guarded INCR returns 1.
4. Return `{ before, dynamoMax, after, wrote }` so the operator sees exactly what happened.

`dryRun: true` performs the scan and reports `before`/`dynamoMax`/what it *would* write, without mutating Valkey — always run it first.

### How to invoke

```bash
# read-only status check
make seq-status                  # ENV=dev by default

# re-seed after a key-loss incident: dry-run first, eyeball the numbers, then commit
make seq-seed                    # DRYRUN=true by default — safe to run first
make seq-seed DRYRUN=false       # writes to Valkey

# initial rollout or recovery backfill
make seq-backfill                # dry-run
make seq-backfill DRYRUN=false   # assigns numbers + seeds counter

# target prod
make seq-status ENV=prod
make seq-seed   ENV=prod DRYRUN=false
```

All targets inject 1Password credentials via `op run` (same pattern as the rest of the Makefile). `DRYRUN` defaults to `true` so a bare `make seq-seed` / `make seq-backfill` is always safe.

Invocations:

1. ✅ Initial rollout: `action: "backfill"` (dry-run, then real) — completed before write-path Lambda went live.
2. ✅ Immediately after deploy: `action: "backfill"` again for deploy-window stragglers — completed.
3. On demand, if the key is ever lost (failover, flush, cluster replacement): `action: "seed"`.

### Resilience — 503, do not degrade

If Valkey is unavailable, or the guarded INCR returns the "absent key" sentinel, the write path returns **503** and does not persist the observation:

- The server **never** stores a new record without an `observationNumber`. Any legacy unnumbered records were cleared by the initial backfill; the repair path in the noop branch handles the edge case of a prior `setObservationNumber` failure.
- Clients treat 503 as a transient sync failure and retry with backoff. They remain fully functional offline: local capture and P2P are unaffected, so a Valkey outage degrades *cloud sync availability*, not the app.
- The existing 5xx CloudWatch alarm fires on sustained 503s. No dedicated Valkey-error alarm is deployed yet — the generic 5xx is sufficient for v1.

---

## Transition & Backfill

### Existing observations

Pre-feature records in DynamoDB have no `observationNumber`. These are treated as legacy and assigned numbers by the `seq-maintenance` Lambda's `backfill` action.

#### Backfill = the maintenance Lambda's `backfill` action

Backfill and the Valkey seed are the same `seq-maintenance` code path (`action: "backfill"`):

1. Scan all items in the `changes` GSI ordered by `serverUpdatedAt` ascending (deterministic, reproducible).
2. Assign `observationNumber` 1, 2, 3, … in that order to any item lacking one.
3. Write back with a conditional `attribute_not_exists(observationNumber)` guard so it is idempotent and re-runnable.
4. After the scan completes, run the seed step: `SET trip:shared:seq <max assigned number>`, raising-only.

#### Rollout sequence (completed for dev)

1. ✅ Deployed `seq-maintenance` Lambda and invoked `action: "backfill"` — all existing records numbered and `trip:shared:seq` seeded.
2. ✅ Deployed numbering (write-path) Lambda. First production write: Ruddy-breasted Seedeater (observationNumber = 1).
3. ✅ Re-ran `backfill` for deploy-window stragglers.

#### Client handling of legacy/unnumbered records

Post-backfill the server holds no unnumbered records (except for the edge case of a failed `setObservationNumber`, handled by the noop repair path). A *client* can still hold one transiently: a record it created offline, or received via P2P, before its server sync assigned/delivered the number. Clients treat such records as "unordered" — include them in P2P payloads, but skip watermark logic until the number arrives (via `applied` for the origin device, or via the pull import for everyone else).

---

## Client State Management

### The two HWMs a client must track

A client may receive records via **server sync** and via **P2P**, and these two channels can produce a local observation-number space that has gaps. Example: a client receives records #1–50 from the server, then receives record #75 from a P2P peer (who had already synced with the server). The client's local max is 75, but it is missing #51–74.

Sending `localMax = 75` to the server as the pull HWM would cause the server to skip returning 51–74 (it pulls `observationNumber > 75`), permanently losing them on this client. For this reason, clients must maintain two distinct HWMs and use them in different contexts:

| Name | Updated by | Used for |
|---|---|---|
| `serverSyncedHWM` | Server sync only (pull response + `applied` entries) | Sent to server in `SyncRequest`; the highest `observationNumber` the client has pulled from the server |
| `localObservationNumberMax` | Any source (server or P2P) | Sent in P2P hello to tell peers what you have locally; may exceed `serverSyncedHWM` |

`serverSyncedHWM` advances only when records arrive via a server sync response (including numbers returned in `applied` for the client's own pushed records). It is never advanced by P2P receipt. This preserves the invariant that "the server has returned every write numbered ≤ this to me."

`localObservationNumberMax` is simply `max(observationNumber)` across all records in the local store, updated whenever a numbered record is received from any source.

### Advancement rules

Because the server paginates the pull in **`observationNumber` order** (HWM-primary pull via the GSI — see Protocol Changes), advancement is simple: the server returns every record with `observationNumber > serverSyncedHWM`, ascending. There is no interior gap to reason about — the server hands over the entire range in order, so the client has received *everything* up to the highest number it has drained.

> **Invariant.** `serverSyncedHWM = H` means *the client has received every server write with `observationNumber ≤ H`*. (Burned/abandoned numbers simply have no record; that's fine — the query returns all *records* with number > H.) This is what makes it safe to send `serverSyncedHWM` back to the server as the pull cursor. It must **never** be set from `localObservationNumberMax`, which can include higher P2P-only numbers whose intervening records the client has *not* pulled from the server.

**After a server sync response**:
1. For each record in `changes`: apply it, and set `localMax = max(localMax, observationNumber)`.
2. Advance `serverSyncedHWM` to the highest `observationNumber` drained from the ordered pull. Because pages arrive in number order, this is safe to do **per page** (receiving up to N in order means you have everything ≤ N); if you prefer, defer it until the final page (`hasMore == false`) — either is correct, page-wise just resumes better after a dropped session.
3. For each `applied` entry with an `observationNumber`: update the local record's number in place and feed `localMax`. An `applied` number is the client's *own* just-pushed write; it does **not** advance `serverSyncedHWM` (the pull stream, not the push echo, defines the server-confirmed range — the pull will re-deliver it in order if it isn't already ≤ HWM).

**After a P2P receive**:
1. For each received record with `observationNumber`: `localMax = max(localMax, observationNumber)`.
2. `serverSyncedHWM` is **not** updated — P2P delivery is not server confirmation. A P2P-received #75 while `serverSyncedHWM = 50` leaves the HWM at 50; the next server pull returns 51+ in order and the HWM advances cleanly, re-absorbing 75 idempotently.

### Unnumbered record promotion

A record may exist in the local store without an `observationNumber` (created offline, or received via P2P before the server assigned a number).

**For the origin device**: the number arrives via the `applied` array on the push response and is applied by `applyServerObservationNumbers` (which bypasses the LWW check). The normal LWW merge would skip the echoed record in `response.changes` as a duplicate (same `updatedAt`).

**For non-origin devices** that received the record via P2P (unnumbered): on their next server sync the record arrives in `response.changes` as a new import (they never pushed it, so it's not in their `applied`). Because it's new to them, `mergeDTOs` takes the import branch and captures `observationNumber` correctly. Their `localObservationNumberMax` and `serverSyncedHWM` advance normally.

**Do not** try to promote the number via the LWW merge path by checking `observationNumber != nil` as a secondary update condition. That would make the merge semantics inconsistent and silently resurrect otherwise-stale data. The `applied` path is the correct mechanism for the origin device; the import path is correct for all others.

The server returns the newly assigned `observationNumber` in the `applied` array entry for pushed records so the pushing client learns the number in the same response that accepted the push, without waiting for the pull phase of the same or a subsequent sync.

---

## Protocol Changes

### Cloud sync (POST /v1/sync)

#### Request: client sends `serverSyncedObservationNumberHWM` (primary pull cursor)

```json
"serverSyncedObservationNumberHWM": {
  "type": "integer",
  "minimum": 0,
  "description": "Highest observationNumber the client has pulled from the server (excludes P2P-only records). The server pulls all records with observationNumber greater than this, in ascending number order. 0 or absent = client has pulled nothing from the server."
}
```

This is `serverSyncedHWM` from the client state section — the server-confirmed value, **not** the local max. **HWM-primary pull:** when the client sends this field, the server queries the `(pk, observationNumber)` GSI for `observationNumber > serverSyncedObservationNumberHWM`, ordered ascending, and paginates in that order.

**Legacy fallback.** A client that does not send `serverSyncedObservationNumberHWM` (older build) falls back to the existing timestamp-`cursor` pull path unchanged. The server keeps both paths during the transition and picks per request based on which field the client sends.

**Cursor deprecation.** Once telemetry shows no active clients pulling by `cursor`, remove the timestamp-cursor pull path (keep the `serverUpdatedAt` GSI only if the deferred date-range feature needs it). Recommend a 3-release window.

#### Response: `observationNumber` in each returned record and in `applied`

The server stamps `observationNumber` on every outbound record (where it exists).

The `applied` array is extended:

```json
{
  "id": "<uuid>",
  "result": "applied",
  "observationNumber": 101
}
```

`observationNumber` is present in `applied` entries only when `result = "applied"` (not when stale or invalid).

**Why `applied` is required — the echo path does not work for the origin device.**

After a push is accepted, the just-written record gets a fresh high `observationNumber` (> the client's HWM), so the ordered pull returns it in `response.changes`. However, the iOS `mergeDTOs` LWW check is `dto.updatedAt > existingUpdatedAt` (strict). The echoed record's `updatedAt` is identical to the locally-stored value — the server never changes it. The echo is therefore counted as `duplicatesSkipped` and `$0.data = dto` is never called. Any `observationNumber` on the echoed DTO is silently dropped.

For **non-origin devices** the echo path works fine: the record is new to them, takes the import branch (`working.append(ObservationRecord(data: dto))`), and captures `observationNumber` directly.

For the **origin device**, `observationNumber` can only arrive via `applied`.

**iOS changes required for the `applied` path:**

1. `SyncAppliedResult` — add `observationNumber: Int?`.
2. `CloudSyncService.syncNow` — after `clearDirty`, pass the applied entries to the store:
   ```swift
   let numbers = response.applied.compactMap { e -> (UUID, Int)? in
       guard e.result == "applied", let n = e.observationNumber else { return nil }
       return (e.id, n)
   }
   store.applyServerObservationNumbers(numbers)
   ```
3. `ObservationStore.applyServerObservationNumbers` — a targeted in-place update that bypasses the LWW merge (since `updatedAt` has not changed, the normal merge would skip the record as a duplicate):
   ```swift
   func applyServerObservationNumbers(_ entries: [(id: UUID, number: Int)]) {
       // locate each record by id in the tree and set its observationNumber field
       // feed each number into localObservationNumberMax
       // do NOT advance serverSyncedHWM here — that advances from the ordered pull
       // stream, not the push echo (see Advancement rules)
   }
   ```
4. `ObservationRecordDTO` — add `observationNumber: Int?` (optional, `decodeIfPresent`). **Do not add it to `encode`/`CodingKeys` for the outbound direction** — clients must never upload it (see Backward Compatibility). The server's `toStored` already strips any client-supplied value as defense-in-depth.

#### Server pull logic (HWM-primary) — implemented

When the client sends `serverSyncedObservationNumberHWM`, the server queries the `(pk, observationNumber)` GSI with a **KeyConditionExpression** — no post-hoc filtering:

```typescript
const page = await ddb.query({
  IndexName: "gsi_observationNumber",
  KeyConditionExpression: "pk = :trip AND observationNumber > :hwm",
  ExpressionAttributeValues: { ":trip": trip, ":hwm": serverSyncedHWM },
  ScanIndexForward: true,          // ascending number order
  Limit: limit,
  ExclusiveStartKey: requestCursor // DynamoDB LastEvaluatedKey, opaque to client
});
// hasMore = page.LastEvaluatedKey != null; return page.Items in order.
```

Because `observationNumber > :hwm` is a **key condition** (not a `FilterExpression`), DynamoDB's `Limit` and `LastEvaluatedKey` apply to the *matched* rows — pagination is exact, and the truncation hazard of a post-`Limit` filter does not arise. The client advances `serverSyncedHWM` to the highest number in each page (see Advancement rules).

#### Sync response: `tripSequenceHighWater` — implemented

`tripSequenceHighWater` is included in the sync response (and in GET /v1/observations when the `hwm` parameter is present). Populated from `GET trip:shared:seq` in Valkey. Clients compare against their `serverSyncedHWM`: if `serverSyncedHWM >= tripSequenceHighWater` the client has pulled everything the server has and no further pull page is needed.

---

## P2P (Bonjour / Local Wi-Fi) Impact

### Current P2P protocol

P2P uses `SyncHelloMessage` (carries `sendSummary`: observation count, species count, date range) and `PayloadV1` (the full set of records to exchange). There is no cursor or sequence number in the P2P protocol.

### Proposed changes

#### Hello message: add `localObservationNumberMax`

```swift
struct SyncHelloMessage: Codable, Equatable {
    // existing fields ...
    var localObservationNumberMax: Int? = nil
}
```

Each device announces its `localObservationNumberMax` — the highest observationNumber in its local store, regardless of source. This value **may not be contiguous**: the peer should interpret it as "the highest number I have, but I may be missing some below it."

#### Payload: delta send (best-effort optimization)

The sending side filters its payload to records the peer likely lacks:

```swift
let peerMax = peerHello.localObservationNumberMax ?? 0
let delta = store.records.filter { record in
    guard let n = record.observationNumber else { return true }  // always send unnumbered
    return n > peerMax
}
```

**This is an optimization, not a correctness guarantee.** Because the peer's `localObservationNumberMax` may have gaps, the delta may omit records the peer actually needs (e.g., peer has #75 but not #51–74, announces max=75, sender skips 51–74). Correctness for the gap case is the server sync's responsibility: the peer's next HWM-primary server pull (`observationNumber > serverSyncedHWM`, which is still 50) returns 51+ in order and fills the gap.

Unnumbered records are always included in the payload because the peer may not have them and they carry no number signal.

#### HWM advancement after P2P receive

After a successful P2P receive, update `localObservationNumberMax` from `max(received observationNumbers)`. Do **not** update `serverSyncedHWM`.

#### No persistent per-peer sent-HWM needed

The sending device does not need to persistently track "what I sent to peer X last session." The peer's hello in each new session announces its current `localObservationNumberMax`, which is the correct input for computing the delta.

#### Backward compatibility

If `localObservationNumberMax` is absent in the peer's hello (legacy app version), fall back to the existing full-send behavior.

---

### Edge cases and interaction scenarios

#### Gap from mixed P2P sources

Device B gets records #1–50 from the server. Via P2P with device C, B receives record #75 (C had synced with server and had 51–100). B's local store: {1–50, 75}. `localMax = 75`, `serverSyncedHWM = 50`.

- B announces `localMax = 75` to P2P peer D. D sends B records above 75 (if any). B still has gap 51–74.
- B syncs with server, sending `serverSyncedHWM = 50`. The server pulls `observationNumber > 50` in ascending order: 51–74, 76+ (and 75, re-absorbed idempotently). B fills the gap and advances `serverSyncedHWM` to the highest number drained (say 100).

**Gap resolution is always guaranteed by the number-ordered server pull:** it returns *everything* above the HWM, so no P2P-induced gap can survive a server sync.

#### Unnumbered record spreading before server assignment

Device A creates an observation offline (no observationNumber). Via P2P, device B receives the unnumbered record. A then syncs with server: server accepts it, assigns #101, returns `{id: X, result: "applied", observationNumber: 101}`. A updates its local record with #101 (via the `applied` path); `serverSyncedHWM` advances from the ordered pull stream, which delivers #101 in its proper place.

B still has the unnumbered record. On B's next server sync, B's HWM pull (`observationNumber > B's HWM`) returns record #101 in the ordered changes. B's idempotent merge updates its local copy with the number. `localMax` and `serverSyncedHWM` advance as the ordered pages drain.

Between A's server sync and B's server sync, if C does P2P with B: B includes the unnumbered record in its payload (always included). C receives it unnumbered. C's next server sync fills in the number. This cascade is harmless.

#### Client's own record: number returned in `applied`

Device A pushes a new observation. Server assigns #102 and returns it in the `applied` array. A updates the local record immediately and sets `localMax = max(localMax, 102)`. It does **not** set `serverSyncedHWM = 102` from the `applied` number: if A's prior HWM was 99 and 100–101 exist on the server (written by others), jumping to 102 would skip them. `serverSyncedHWM` advances only from the ordered pull, which returns 100, 101, 102 in order — A's own #102 is already applied and re-absorbed idempotently when the pull reaches it.

#### P2P peer announces higher max than you have from server

Device A has `serverSyncedHWM = 80`, `localMax = 80`. P2P peer B announces `localMax = 100` (B synced with server more recently). A receives records 81–100 from B. A's `localMax = 100`, `serverSyncedHWM` still 80. A then syncs with server sending `serverSyncedHWM = 80`. The server pulls `observationNumber > 80` in order: 81–100 (all already present, absorbed idempotently). Sync completes; A advances `serverSyncedHWM = 100`.

This is slightly wasteful (A re-fetches 81–100 from server even though it got them via P2P) but correct. Once `serverSyncedHWM` catches up, subsequent server syncs will skip them.

---

## Infrastructure (Terraform) — Implemented

All infrastructure is deployed. Notes on what was actually built vs. the original plan:

- **VPC module**: private subnets + Lambda security group + DynamoDB/CloudWatch VPC endpoints. ✅
- **Valkey module**: ElastiCache Serverless (Valkey mode), `birdcount-{env}-seq`. ✅
- **API Lambda**: placed in VPC, same security group used by seq-maintenance. ✅
- **seq-maintenance Lambda**: own IAM role, in VPC, not on API Gateway. ✅
- **Lambda authorizer** (`birdcount-{env}-authorizer`): runs **outside the VPC** (needs internet access to fetch Cognito JWKS). Separate IAM role with basic execution only. ✅ (not in original plan — added to handle M2M auth)
- **Security groups**: `valkey` SG: inbound 6379 from Lambda SG. Lambda SG: outbound 6379 to Valkey, outbound 443 to VPC endpoints. ✅

Note: module wiring uses `module.vpc.lambda_security_group_id` (not `module.api.lambda_security_group_id` as the original plan sketch showed).

---

## Backward Compatibility & Rollout Safety

**Yes — the backend shipped ahead of any iOS client update, and existing clients keep working.** This holds because of three properties verified in the code:

1. **iOS ignores unknown response fields.** The client uses hand-written `Codable` with explicit `CodingKeys` (`bird-count-ios/BirdCount/Models/ObservationDTO.swift:74`). `observationNumber` is not in `CodingKeys`, so the server's field is silently dropped on decode. This is the correct behavior until the iOS changes land.
2. **The HWM pull is opt-in.** Old clients send only `cursor`; the server branches on presence of `serverSyncedObservationNumberHWM` and old clients get the unchanged `serverUpdatedAt` pull path.
3. **503 is within the existing failure contract.** iOS throws on any non-200 (`CloudAPIClient.swift:66`) and `CloudSyncService` turns it into a transient `.failure`, without advancing/persisting the cursor (saved only on success).

**Do not bump `schemaVersion`.** `observationNumber` is additive-optional, stays at 2.

### The one asymmetric hazard — inbound ajv validation

The server validates **incoming** `SyncRequest`s (including each `changes` item) with ajv, and every schema object is `additionalProperties: false`. Consequences:

- Adding optional `observationNumber` to the schema does **not** break old clients — they never send it.
- A **new** client that *re-encodes* `observationNumber` on upload would be 400-rejected. **Fix: `observationNumber` is decode-only** — add to `ObservationRecordDTO.init(from:)` and `decodeIfPresent`, but do **not** add it to `encode(to:)` or `CodingKeys` for the encoder direction. The server's `toStored` also strips any client-supplied value as defense-in-depth.
- Keep `serverSyncedObservationNumberHWM` **optional** in `SyncRequest` so a new iOS client also tolerates a not-yet-updated server.

### Rollout-order functional hazard — renumber storm (mitigated in implementation)

First-ever sync and recovery sync re-upload the entire ledger (`markAllDirty` when the cursor is nil, `CloudSyncService.swift:145`). The re-put is an equal-`updatedAt` no-op. The INCR is gated on `putResult === "written"` (genuine new/updated record), not on any successful conditional put — equal-`updatedAt` no-ops return the `{ kind: "noop" }` branch and preserve the stored `observationNumber`. This correctly prevents the renumber storm.

### Rollout checklist

1. ✅ Schema PR (additive, optional, no `schemaVersion` bump) — deployed.
2. ✅ Run `seq-maintenance backfill` before numbering Lambda live → deploy numbering Lambda → re-run `backfill` for stragglers — completed.
3. ⬜ Ship iOS: decode new fields, **omit `observationNumber` on upload**, send HWM. No coordinated backend release required.

---

## Implementation Order

Steps 1–5 are complete and deployed to dev. Steps 6–8 are the remaining iOS work.

1. ✅ **Schema** — `observationNumber` on observation, `serverSyncedObservationNumberHWM` + `observationNumber` in applied + `tripSequenceHighWater` on sync. Deployed.

2. ✅ **DynamoDB GSI** — `gsi_observationNumber (pk, observationNumber)`. Deployed.

3. ✅ **`seq-maintenance` Lambda** — `status` / `seed` / `backfill` with `dryRun`. Seeded in dev. First observation: Ruddy-breasted Seedeater (observationNumber = 1).

4. ✅ **Terraform** — VPC, Valkey, seq-maintenance Lambda, API Lambda in VPC, Lambda authorizer (replaces JWT authorizer).

5. ✅ **Backend** — guarded INCR on new writes, noop preserves number, repair path, HWM-primary pull via `queryByNumber`, `tripSequenceHighWater` from Valkey, 503 on absent key. E2E test suite: 37 checks (`make e2e`).

6. ⬜ **iOS client state** — `bird-count-ios/BirdCount/Models/ObservationDTO.swift`:
   - Add `observationNumber: Int?` to `ObservationRecordDTO`, decoded with `decodeIfPresent`. **Do not encode it** — add to `init(from:)` only, not to `encode(to:)` or the `CodingKeys` enum (the encoder direction must remain clean to avoid ajv 400 rejections).
   - `bird-count-ios/BirdCount/Stores/ObservationStore.swift`: persist `serverSyncedHWM: Int` + `localObservationNumberMax: Int` beside `cloudSyncCursor`.
   - Add `applyServerObservationNumbers(_ entries: [(id: UUID, number: Int)])` — in-place update that bypasses LWW merge (see Client State Management). The LWW skip that drops the echo is at `ObservationStore.swift:498-506`; this is why the `applied` path is the only route for the origin device.

7. ⬜ **iOS cloud sync** — `bird-count-ios/BirdCount/Cloud/CloudAPIClient.swift`:
   - Add `var serverSyncedObservationNumberHWM: Int?` to `SyncRequestBody` (`:5`).
   - Add `let observationNumber: Int?` to `SyncAppliedResult` (`:12`).
   - Add `let tripSequenceHighWater: Int?` to `SyncResponseBody` (`:17`) and `PullResponseBody` (`:25`).
   - Add `func observations(hwm: Int, limit: Int = 200)` variant using `?hwm=\(hwm)` (existing `since:` variant stays for legacy fallback).
   - `CloudSyncService.syncNow` (`CloudSyncService.swift:163`): send `serverSyncedObservationNumberHWM`, call `store.applyServerObservationNumbers` where applied is processed (`:166`), advance `serverSyncedHWM` per ordered page. This eventually retires the `cursorRewindMs` hack at `CloudSyncService.swift:38`/`:229`.

8. ⬜ **iOS P2P** — `bird-count-ios/BirdCount/Sync/SyncMessage.swift`:
   - Add `var localObservationNumberMax: Int? = nil` to `SyncHelloMessage` (`:30`), following the existing optional-with-default backward-compat pattern.
   - Delta-filter `PayloadV1.observations` (`bird-count-ios/BirdCount/Models/PayloadV1.swift:12`) best-effort: send records with `observationNumber > peerHello.localObservationNumberMax ?? 0`, always including unnumbered records.
   - After a P2P receive, update `localObservationNumberMax`; do not update `serverSyncedHWM`.
   - Full-send fallback when peer's hello omits the field.

9. ⬜ **iOS tests** — extend `bird-count-ios/TestsCore/ObservationStoreTests.swift` and `bird-count-ios/Tests/ObservationSyncTests.swift`:
   - HWM advancement (advance from ordered pull; P2P receipt does *not* advance `serverSyncedHWM`).
   - `applyServerObservationNumbers` sets number without LWW merge, doesn't advance `serverSyncedHWM`.
   - Decode-only: encoding a DTO with `observationNumber` set does not emit the field.
   - Delta-send P2P optimization: records above peer max are sent; records at or below are omitted; unnumbered always sent.

---

## Decisions

Settled — build to these.

- **`observationNumber` is a per-trip write sequence**, reassigned on every accepted write (append or edit), *not* a stable creation ordinal. → *Problem Statement*.
- **No deletes — append-only ledger.** Counts change only via appended negate entries; edits are additive and never change counts. Both appends and edits bump the watermark and sync back like new records. No tombstones needed. → *Problem Statement (Mutation model)*.
- **Counter = Valkey `INCR`**, one key per trip (`trip:<tripId>:seq`); ElastiCache Serverless. → *Valkey (Auto-Incrementor)*.
- **Guarded INCR** (incr-if-exists Lua); a bare `INCR` is never used. → *Sequence number assignment*.
- **503 on dependency-down, no graceful degradation — accepted, not provisional.** → *Resilience*.
- **Seeding/backfill/re-seed run via the operator-invoked `seq-maintenance` Lambda** (in-VPC, IAM-gated, not on API Gateway). → *Valkey Population*.
- **`maxmemory-policy noeviction`.** With the guarded INCR, failover/flush/eviction surface as 503 + alarm, never silent corruption.
- **Two client HWMs** (`serverSyncedHWM` = highest number pulled from server; `localObservationNumberMax` = any-source max). → *Client State Management*.
- **HWM-primary pull via the `(pk, observationNumber)` GSI**, paginated by number. Timestamp `cursor` kept as legacy fallback; deprecated over ~3-release window gated on telemetry. → *Data Model*, *Protocol Changes*.
- **Write trip-aware from day one.** Only `shared` exists in v1, but the key and param carry the trip through so multi-trip needs no rework later.
- **Lambda authorizer replaces JWT authorizer.** Cognito client_credentials tokens (version 2) have no `aud` claim, so API Gateway's built-in JWT authorizer cannot validate M2M tokens. A Lambda authorizer validates user tokens by `aud` and M2M tokens by `scope`; runs outside VPC to reach Cognito JWKS. → *Auth note*.

## Deferred features

Not in scope now; the design leaves room for them.

- **Date-range–scoped pull.** A future mode where a client requests "everything I haven't seen *within a date range*." The `serverUpdatedAt` GSI retained through the cursor transition can back this; note that a date `FilterExpression` layered on the number-ordered Query is post-`Limit`, so this feature needs its own paging design (a date-keyed GSI, or over-fetch-and-refill).
- **Dedicated Valkey/503-rate alarm.** Currently covered by the generic 5xx CloudWatch alarm. A specific alarm metric filter on "sequence counter not seeded" log lines would shorten the MTTR for a key-loss incident.

## Open Questions

- *(none blocking — all design decisions are settled. iOS implementation can proceed with steps 6–8 in order; P2P (step 8) can be deferred to a follow-up if needed, since the server and cloud-sync changes (steps 6–7) deliver the primary efficiency benefit.)*
