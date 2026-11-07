# HWM/GSI ordering race: analysis and fix plan

## Symptom

On a shared group count (multiple devices posting to the same `"shared"`
scope), observations that were briefly visible in the iOS app's Home/Log
views disappear permanently and never come back, with no user action
(delete, reset) involved. Pattern: a few observations logged right as
several devices start counting around the same time; some time later
those early observations are gone from the log while later ones remain.

This document is backend-focused: it explains why the *pull* path can
permanently skip a record that was written correctly and still exists in
DynamoDB, and proposes a fix. It does not implicate the iOS client's own
storage — `ObservationStore.mergeDTOs` is purely additive/update-only and
was independently verified not to remove records once merged locally.

## Component roles, as the design actually relies on them

Before proposing a fix it's worth being precise about which part of this
stack is *actually* strongly consistent, since the bug is exactly a case
of code silently borrowing a consistency guarantee that was never granted.

| Component | Consistency guarantee | What it's used for |
|---|---|---|
| DynamoDB **base table**, keyed by `pk`/`sk` | Strongly consistent per-item reads and conditional writes (`ConditionExpression`, `ReturnValuesOnConditionCheckFailure`) | `putObservation`'s LWW conditional put (`dynamo.ts:58`); the source of truth for "does this record exist / what's its `updatedAt`" |
| **DynamoDB seq table** `tripSeqKey` counter | Single-item conditional `ADD` — atomic and serialized, a true total order with no gaps in *assignment* | `guardedIncr` (`seq.ts`) hands out the next `observationNumber`; this is the one place in the system with a real, race-free sequence |
| DynamoDB **GSI** `gsi_observationNumber` | **Eventually consistent only** — AWS does not offer `ConsistentRead` on GSIs, and propagation order across concurrent writes to different items is not guaranteed to match write order | `queryByNumber` (`dynamo.ts:144`), the read path every client's incremental pull depends on |

The design already shows awareness that the base-table write and the
number stamp are two different operations that can fail independently:
`setObservationNumber`'s doc comment (`dynamo.ts:88-92`) explicitly says a
lost number is "a gap (not corruption)," and `seqMaintenance.ts` ships a
`backfill` action specifically to repair that failure mode. **That is the
one race the current design already defends against.** The race described
here is a different one: it's not about a number failing to get assigned,
it's about numbers that *are* assigned becoming visible to readers
**out of order**, which the "gap is fine" reasoning does not cover — a
gap in *assignment* is safe to skip; a gap in *read-side visibility* is not,
because the client uses "highest number seen" as a proxy for "everything
up to here has been seen," which only holds if visibility is ordered.

There's also direct evidence the original design anticipated needing a
safety net here and didn't finish wiring it up: `pull()` already fetches
`tripSequenceHighWater` from the seq counter and returns it on every response
(`sync.ts:84-91`), and the wire schema spells out the intent in plain
language:

> "Clients compare against their `serverSyncedObservationNumberHWM` to
> know when they are fully caught up." — `bird-count-schema/schemas/sync.schema.json:63`

Grepping the iOS client confirms `tripSequenceHighWater` is decoded
(it's in the generated wire types) but **never read anywhere in
`CloudSyncService` or `ObservationStore`** — the catch-up check the field
exists for was never implemented. This document's fix plan finishes that
half-built mechanism rather than inventing a new one.

## Root cause

Two independent issues compound into permanent record loss:

### 1. Number assignment is two separate writes

`sync.ts:127-155`:
1. `putObservation` — `PutCommand` with the record, **`observationNumber`
   explicitly stripped** (`toStored`, `sync.ts:39`)
2. `guardedIncr` — seq-table atomic `ADD`, then `setObservationNumber` — a
   **second**, independent `UpdateCommand` that stamps the number on

Between (1) and (2), and again between (2) landing on the base table and
it propagating to `gsi_observationNumber`, there is a window where the
item exists but is not yet visible *with its number* in the index that
every client's pull queries.

### 2. The pull advances past whatever the GSI happens to show, with no gap check

`sync.ts:78-97` / `dynamo.ts:144-164`:

```ts
const page = await queryByNumber(doc, SCOPE, hwm, limit); // observationNumber > hwm, ascending
let maxSeen = hwm;
for (const item of page.items) {
  if ((item.observationNumber ?? 0) > maxSeen) maxSeen = item.observationNumber!;
}
// ...
cursor: String(maxSeen)
```

`CloudSyncService.swift:184/205` then persists this as the client's new
floor (`store.advanceServerSyncedHWM`), and `serverSyncedHWM` is only ever
used as a **strict lower bound** for the *next* pull (`> hwm`). There is
no check anywhere that the numbers returned in a page are contiguous with
what the client already has.

### Concrete failure timeline

Three devices start a count within the same few seconds. Device A logs
observation X first.

```
t0    Device A calls sync(). guardedIncr → n=5 assigned to X.
t0+Δ1 setObservationNumber(X, 5) issued; not yet visible in gsi_observationNumber.
t1    Device B logs observation Y. guardedIncr → n=6 assigned to Y.
t1+Δ2 setObservationNumber(Y, 6) issued and happens to propagate to the
      GSI faster than X's update (Δ2 < remaining Δ1 — ordinary variance
      in DynamoDB's asynchronous GSI replication, nothing exotic).
t2    Device C calls sync() with hwm=4. queryByNumber(pk, hwm=4) hits the
      GSI: Y (n=6) is visible, X (n=5) is NOT yet visible.
      maxSeen = 6. Device C's cursor is now "6".
t3    X (n=5) finally propagates to the GSI.
t4..  Every future pull from any device that has already advanced past
      hwm=5 queries `observationNumber > hwm` with hwm >= 6 — X can never
      be returned again. It is not corrupted or deleted; it is simply
      unreachable from this read path for the rest of the count.
```

Device A's own local copy of X survives (it was created locally, not
received via pull) — which is exactly why this reads, from the reporting
device's perspective, as "records I saw briefly vanish": the records lost
this way are the ones a device *received from other participants*, not
the ones it authored itself. This matches a shared-count-only report and
is consistent with why a solo, single-device user would never see it.

## Why the existing mitigations don't cover this

- `cursorRewindMs` (`CloudSyncService.swift:39`, 5s rewind) only applies
  to the **legacy timestamp-cursor path** (`queryChanges`, no HWM sent).
  It does nothing for the HWM/number path, and even if applied there, a
  fixed rewind is a band-aid with the same fundamental flaw: it shrinks
  the race window, it doesn't close it.
- The `seqMaintenance.ts` backfill tool repairs records that never got an
  `observationNumber` at all (the "gap, not corruption" case). It has no
  visibility into records that *have* a number but were skipped by a
  client's advancing cursor — from Dynamo's perspective those records are
  completely normal, numbered, queryable rows.

## Fix plan

The guiding constraint: keep leaning on the parts that are actually
strongly consistent (base-table conditional writes, seq-table atomic `ADD`), and
stop treating the GSI's query result as proof of "nothing lower remains."
Ship in three stages, independently deployable.

### Stage 1 — Close the two-phase write window (cheap, immediate)

Assign the number **before** the conditional put and write it in the
same `PutCommand`, instead of a separate follow-up `UpdateCommand`:

```ts
const n = await guardedIncr(doc, seqKey);           // still the single atomic authority
if (n === -1) throw new SeqUnavailableError(...);
const stored = toStored(change, observerSub, stamp, request.schemaVersion, n);
const putResult = await putObservation(doc, stored);    // observationNumber included from the start
```

This collapses two propagation-lag windows into one and removes the
"item visible without its number" state entirely. It does **not** fully
close the race (concurrent single-phase writes for n=5 and n=6 can still
propagate to the GSI out of order), but it shrinks the exposure
significantly and simplifies away one of the two independent races.
Note this changes the LWW semantics slightly: today a stale/equal-`updatedAt`
retry re-reads the previously-assigned number via `ALL_OLD`
(`putObservation`'s `noop`/`stale` branches); with the number decided
up front, a retried request that turns out to be `stale` has burned a
sequence number for nothing — acceptable, since burned numbers are
already an accepted category ("gap, not corruption").

### Stage 2 — Gap-aware client catch-up (finishes the half-built mechanism)

This is the real fix, and it's the one the schema already documents but
the client never implemented.

**Server**: no change needed beyond Stage 1 — `tripSequenceHighWater` is
already returned on every response.

**Client** (`CloudSyncService.swift`, in the HWM drain loop around
`sync.ts` response handling, `CloudSyncService.swift:194-209`):

1. When advancing `serverSyncedHWM`, only advance it past a **contiguous**
   run starting at the old value — i.e. verify `page.changes` sorted by
   `observationNumber` has no gap between `oldHWM+1` and whatever it
   raises to. If element `n` is missing where `oldHWM < n <= maxSeenInPage`,
   advance only up to the last contiguous number before the gap, not to
   `maxSeenInPage`.
2. After a drain loop finishes (`hasMore == false`), compare
   `store.serverSyncedHWM` against the response's `tripSequenceHighWater`.
   If `tripSequenceHighWater > serverSyncedHWM`, the client knows there
   are still unseen numbers out there (exactly the case this bug
   produces) — don't mark the sync fully caught up; schedule a short
   retry (a few seconds, mirroring the existing `triggerDebounce`/
   `mutationDebounce` pattern already used elsewhere in this file) instead
   of silently accepting the gap as "nothing more to pull."
3. Cap retries with a backoff and a ceiling (e.g. stop escalating after a
   minute of retrying and surface it in `DiagnosticsLog` rather than
   looping forever) — a record that never resolves points at a genuinely
   stuck `setObservationNumber` (the *other* known failure mode), which
   `seqMaintenance.ts backfill` already exists to repair operationally.

This is intentionally conservative and purely additive to the wire
protocol — `tripSequenceHighWater` is already being sent and decoded, so
this is a client-only change plus the small server change in Stage 1.

### Stage 3 — Optional: server-side gapless low-watermark (only if Stage 2's retry latency is a problem in practice)

If retry-driven catch-up (Stage 2) proves too slow or chatty in the field,
move the gap logic server-side so clients only ever see a hwm that's
provably safe to trust immediately:

- Track a second seq-table value, `tripSeqSettled`, representing the highest
  `n` such that every number `1..n` is confirmed present in DynamoDB.
- After a successful single-phase write of number `n`
  (post Stage 1), attempt to advance `tripSeqSettled`: if `n ==
  tripSeqSettled + 1`, bump it and keep walking forward through any
  higher numbers already durably written (a small seq-table set of
  "written but not yet folded into the settled watermark" makes this
  O(1) amortized).
- `queryByNumber` truncates its returned page (and the `cursor`/hwm it
  reports) at `tripSeqSettled`, never at "whatever the GSI query
  happened to return."

This is more machinery than Stage 2 and should only be built if
measurement shows Stage 2's retry loop isn't good enough — most
DynamoDB GSI propagation delay is sub-second, so a short bounded retry
should resolve the vast majority of cases invisibly to the user.

## Verification plan

- **Unit (backend)**: extend `sync.test.ts` with a test that stubs
  `queryByNumber` to return a page with a gap (e.g. hwm=4, page returns
  only n=6) and asserts the fix path's expected behavior at whichever
  stage is implemented (Stage 1: number present at write time; Stage 2
  is client-side, so this is really an iOS test — see below).
- **Unit (iOS)**: add a test to `TestsCore` feeding `CloudSyncService`/
  `ObservationStore` a mocked sync response sequence: page 1 has a gap
  (`tripSequenceHighWater` ahead of the returned max), assert
  `serverSyncedHWM` does **not** advance past the gap and a retry is
  scheduled; page 2 (after the gap fills) completes the catch-up and HWM
  advances fully.
- **E2E** (`bird-count-backend/api/test/e2e/run.ts` already exercises
  sync round-trips): add a concurrency scenario — two simulated clients
  racing `sync()` calls for two different records — to catch a
  regression of the two-phase write window reappearing.
- **Field verification**: land Stage 1+2 behind normal deploy, then
  spot-check `seqMaintenance status` on a live shared trip during/after a
  busy group count to confirm `dynamoMax` and `counterValue` stay aligned
  and no growing permanent gap appears in practice.

## Rollout notes

- Stage 1 is a backend-only change; no client version dependency, no
  data migration (existing records already have `observationNumber` set
  via the same eventual path, just via two writes instead of one).
- Stage 2 requires an iOS client update to take effect; **older clients
  will continue to exhibit the bug** until they update, since they
  already ignore `tripSequenceHighWater`. That's acceptable — it's the
  status quo — but worth noting if there's a decision about forcing a
  minimum app version for the next shared count.
- No backfill or historical repair is needed for records already lost
  to this race in past counts: they are fully intact and numbered in
  DynamoDB (nothing was corrupted), so a one-off `seqMaintenance`
  "status" check plus a manual re-pull (`resyncAll` on affected devices,
  which resets `cloudSyncCursor`/HWMs to zero and re-walks the entire
  numbered stream from scratch) recovers them retroactively without any
  server-side changes.
