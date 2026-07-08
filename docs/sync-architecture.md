# Sync Architecture

How bird observations move between devices: the ledger data model, the cloud
sync protocol (client and server halves), and how peer-to-peer sync coexists
with the cloud. For the operational view (deploys, endpoints, alarms) see
[bird-count-backend/README.md](../bird-count-backend/README.md).

```
 iPhone A                    AWS (per env: dev / prod)              iPhone B
┌───────────────┐   HTTPS   ┌──────────────────────────┐   HTTPS  ┌───────────────┐
│ObservationStore│◄────────►│ API Gateway (JWT auth)   │◄────────►│ObservationStore│
│CloudSyncService│          │  └─ Lambda (ajv validate)│          │CloudSyncService│
│CloudAuthService│          │      └─ DynamoDB ledger  │          │CloudAuthService│
└───────┬───────┘           │ Cognito ◄─ Sign in w/    │          └───────┬───────┘
        │  Bonjour/TCP P2P  │           Apple          │                  │
        └──────────────────►│                          │◄─────────────────┘
                            └──────────────────────────┘
```

## The ledger data model

An observation is an **immutable event**: species (`taxonId`), time interval
(`begin`/`end`), `count`, optional `location`, `observer`, `status`, and a
UUID `id`. Records form a hierarchy via `parentId`.

**Nothing is ever edited or deleted.** A count change is a new *adjustment
child* whose `count` is the delta (negative allowed); a "delete" is a child
whose negative count zeroes the parent's recursive total. The UI hides
records whose total is ≤ 0. Consequences:

- No tombstones, no deleted flags, no resurrection bugs — a zero-out child
  syncs like any other record.
- Sync reduces to *set union by UUID*. Two devices that exchange all records
  converge, regardless of order or repetition.
- **One exception to immutability**: the location backfill. A record is
  created `status: pending` and updated once on the *originating device*
  when CoreLocation resolves (`location` set, `status: completed`,
  `updatedAt` bumped). This is the only case where two copies of the same
  UUID can differ, and it is resolved by whole-record last-writer-wins on
  `updatedAt`.
- **Ledger integrity**: an adjustment child must never be counted without
  its parent chain. Cloud sync is full-fidelity so this holds automatically;
  the P2P date-window export includes *all descendants* of in-range parents
  for the same reason.

### Two timestamps, two jobs

| Field | Set by | Purpose |
|---|---|---|
| `updatedAt` (ms epoch) | client | LWW conflict resolution for the location backfill. Legacy (v1) records lack it; every consumer backfills `updatedAt = end` — the same deterministic rule everywhere, so all devices converge. |
| `serverUpdatedAt` (ms epoch) | Lambda at write | The delta cursor. Immune to client clock skew; never leaves the server except as the opaque `cursor` string. |

The wire format is defined once in [`bird-count-schema/`](../bird-count-schema/)
(JSON Schema + golden fixtures). The backend generates TypeScript types from
it and ajv-validates every request against it; the iOS app proves conformance
by decoding/encoding the same fixtures in `SchemaConformanceTests`. On the
wire, `updatedAt` is an integer (ms); all other dates are ISO8601 strings.

## Client side (iOS)

Code: `bird-count-ios/BirdCount/Cloud/` (app target only) plus sync state in
`ObservationStore` (platform-neutral core).

### What is synced

Everything. All records — top-level and children — are flattened to wire
DTOs. There is no date filtering on the cloud path (unlike P2P, which is
scoped to a date window). Upload is driven by the **dirty set**; download by
the **cursor**.

**Dirty tracking** (`ObservationStore.dirtyIds`, persisted): a record id
enters the dirty set when it is
- created (`addObservation`, `addChildObservation`, and the WithLocation variants),
- mutated (`updateRecord` / `updateChildRecord` — in practice only the
  location backfill),
- received via **P2P import** (so peer records flow up to the cloud from
  whichever device syncs next), or
- everything at once on first sync (`cloudSyncCursor == nil` → `markAllDirty`),
  which is how pre-cloud legacy data gets uploaded.

Ids leave the dirty set only when the server acknowledges them (`applied` or
`stale`). The set is persisted, so offline changes queue across relaunches.

**Cursor** (`ObservationStore.cloudSyncCursor`, persisted): the max
`serverUpdatedAt` this device has seen, as an opaque decimal string. `nil`
means never synced.

`clearAll` (Settings → "Clear all counts") is a **local device reset, not a
ledger operation**: it wipes observations, the dirty set, and the cursor —
nothing propagates, and the next sync re-pulls the shared pool from zero.

### When sync runs

- **Manually**: Settings → Sync now.
- **Automatically** (all triggers funnel into a debounced `requestSync`,
  which fires only when signed in, the *Auto sync on Wi-Fi* toggle is on,
  and the network path is wifi — `NWPathMonitor` satisfied and not
  expensive):
  - wifi restored → 3 s debounce
  - app foregrounded (`scenePhase == .active`) → 3 s debounce
  - local mutation (store posts `didMarkDirtyNotification`) → 30 s debounce,
    so a counting session settles before uploading
  A shorter-delay request supersedes a pending longer one; nothing runs
  while a sync is already in flight.

### How a sync session works (`CloudSyncService.syncNow`)

1. **Auth**: `CloudAuthService.validAccessToken()` — Keychain-stored Cognito
   JWTs from the hosted-UI + Sign in with Apple PKCE flow; silent refresh
   when < 60 s of validity remain. A failed refresh signs the user out and
   sync surfaces "Session expired — sign in again".
2. **Cursor rewind**: the session cursor = stored cursor minus 5 s. The
   server's pull is strictly-after-cursor (see below); this client-side
   overlap absorbs near-simultaneous writes and clock jitter between Lambda
   instances. Re-delivered records are harmless because apply is idempotent.
3. **Push**: dirty records are gathered in `flatDTOs()` order — **parents
   before children** — and pushed in chunks of ≤ 100 (the schema's
   `maxItems`) via `POST /v1/sync`. Each response's `applied` array clears
   acknowledged ids from the dirty set (`applied` and `stale` both count:
   `stale` means the server already has a newer copy, which arrives in the
   pull half).
4. **Pull**: every `/v1/sync` round trip also returns changes after the
   request cursor. After the last chunk, remaining pages are drained via
   `GET /v1/observations?since=<cursor>` while `hasMore`.
5. **Apply**: pulled DTOs go through `ObservationStore.mergeDTOs` —
   put-if-absent by UUID; whole-record LWW on `updatedAt` for existing ids;
   **orphaned children** (a child paginating in before its parent) are held
   in a persisted stash and reattached when the parent arrives.
   Cloud applies do *not* mark records dirty (unlike P2P imports).
6. **Advance**: the stored cursor becomes the final response cursor and the
   last-sync time is recorded. Only ids the server acknowledged were cleared,
   so a session that dies mid-way just re-pushes the remainder next time
   (server-side put-if-absent makes the retry a no-op).

## Server side (Lambda + DynamoDB)

Code: `bird-count-backend/api/src/` (`handler` → `validate` → `sync`/`pull` →
`dynamo`).

### Request handling

- API Gateway's **JWT authorizer** (Cognito issuer/audience) rejects
  unauthenticated calls before the Lambda runs; the JWT `sub` claim is the
  identity and is stored on each record as `observerSub`.
- The body is **ajv-validated** against the shared schemas (compiled into
  the bundle at build time). Schema violations → 400. `additionalProperties:
  false` means unknown fields are rejected at the boundary, not silently
  dropped.
- `schemaVersion` above what the server supports → 400 with an
  "update the app" message.

### Storage

One table `birdcount-data-<env>`:

| Key | Value |
|---|---|
| `pk` | scope — `"shared"` for everything today; `"trip#<uuid>"` / `"user#<sub>"` are the planned extension, addable with zero migration |
| `sk` | `obs#<uuid>` |
| GSI `changes` | `pk` + `serverUpdatedAt` — the delta query |

Item attributes are the wire DTO plus server bookkeeping (`observerSub`,
`serverUpdatedAt`, `createdAt`, `schemaVersion`). PITR is on; nothing is
ever deleted (prod additionally has deletion protection).

### Push (`sync.ts`)

For each incoming record:

- `updatedAt` is backfilled from `end` if absent (legacy v1 clients — same
  rule as the iOS decoder).
- `serverUpdatedAt` stamps are **unique and increasing within the batch**
  (`max(now, prev+1)`), so a page boundary can never split records sharing
  a millisecond.
- Conditional put: `attribute_not_exists(sk) OR updatedAt <= :incoming` —
  new records insert; the location backfill overwrites; anything older than
  the stored copy fails the condition and is reported `stale` (never
  written). This is the entire conflict-resolution surface.

### Pull (`sync.ts` / `dynamo.ts`)

Query the `changes` GSI for `serverUpdatedAt > cursor`, ascending, limited
(200 by default), `hasMore` from `LastEvaluatedKey`. Two invariants:

- **Strictly exclusive cursor.** The original design had the *server* apply
  a 5 s overlap window, but that breaks pagination: if more records fall
  inside the overlap than the page limit, the client re-receives the same
  page forever (guaranteed during a bulk first upload). So the server is
  strict — pagination always advances — and the overlap is the client's
  one-time rewind at session start.
- The response `cursor` is `max(request cursor, max serverUpdatedAt pulled,
  max stamp pushed this call)`, so a client that pushed but had nothing to
  pull still advances past its own writes.

### Failure and abuse handling

- Throttling at the API Gateway stage (burst 20 / rate 10).
- CloudWatch alarms on Lambda errors and API 5xx (email on prod).
- Idempotency everywhere: re-pushing acknowledged records is a conditional
  no-op; re-pulling overlapped pages is absorbed by client LWW merge.

## P2P and cloud coexistence

P2P sync (Bonjour/TCP, `Sync/`) and cloud sync share the same merge
machinery (`mergeDTOs`) and the same wire observation shape (`payload`
schema, v2 = DTOs carry `updatedAt`; v1 peers still accepted via the
backfill rule). The differences:

| | P2P | Cloud |
|---|---|---|
| Scope | date-windowed (plus all descendants of in-range parents) | everything |
| Transport | symmetric peer session (hello/negotiate) | authenticated request/response |
| Dedup/conflict | same: put-if-absent + LWW on `updatedAt` | same |
| Dirty marking | **yes** — received records upload on next cloud sync | no |

That last row is what makes the two compose: sync A↔B over P2P in the
field, and whichever device reaches wifi first uploads both devices'
records.
