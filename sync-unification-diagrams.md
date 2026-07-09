# Sync Diagrams (Corrected)

> Revision 2.0. Diagrams updated to match the verified code. The original
> "proposed unified transport" diagram is gone along with the proposal
> (see sync-unification-analysis.md, "Proposals evaluated and rejected").

## Current state: two transports, one merge path

```
┌───────────────────────────────────────────────────────────────┐
│  ObservationStore  (main actor in practice)                   │
│  ├─ observations, dirtyIds, cloudSyncCursor                   │
│  └─ mergeDTOs(markDirty:)  ← idempotent LWW, shared by both   │
└──────────────┬──────────────────────────────────┬─────────────┘
               │ markDirty: false (cloud pulls)   │ markDirty: true (P2P imports,
               │                                  │ via ObservationImportService)
      ┌────────┴──────────┐              ┌────────┴───────────────┐
      │ CloudSyncService  │              │ SyncViewModel +        │
      │ @MainActor        │              │ NetworkSyncTransport   │
      ├─ auto: wifi/fg/   │              ├─ Bonjour local. +      │
      │  mutation debounce│              │  peer-to-peer Wi-Fi    │
      ├─ manual: UserView │              │  (NO cellular path)    │
      │  "Sync now" ✅     │              ├─ role negotiation      │
      ├─ everything scope │              ├─ date-windowed payload │
      └────────┬──────────┘              └────────┬───────────────┘
               │ POST /v1/sync                    │ WebSocket/TCP
               │ (push chunk + pull page,         │
               │  one atomic exchange)            │
               ▼                                  ▼
      AWS backend (SCOPE="shared")        Nearby iPhone

UI entry points (both already exist):
  header person icon → UserView  → cloud: Sync now / status / last sync / auto toggle
  drawer → "Sync with Nearby Phones" → SyncSheet → P2P
```

## F1: the real race — dirty flag cleared for an edit made mid-push

```
main actor timeline, one device:

t0  syncNow snapshots:  dirty = {X}, toPush = [X@updatedAt=100]
t1  await POST /v1/sync ─────────────┐  (suspension point)
t2    user edits X  →  X@updatedAt=150, dirtyIds.insert(X)
t3  ◄──────── ack {X: applied} ──────┘
t4  clearDirty([X])            ← unconditional! wipes the t2 dirty mark
t5  30s mutation debounce fires → syncNow → dirty = {} → X@150 NOT pushed

Result: server holds X@100; local X@150 never uploads until X is
edited again. Fix: at t4, clear X only if store.updatedAt(X) == 100.
```

## F2: why a local lock can't stop cross-device re-uploads

```
T0  A ↔ B sync P2P            A: 150 recs (50 dirty from B)
                              B: 150 recs (100 dirty from A)
T1  A hits Wi-Fi, uploads 150      server: 150   A.dirty = {}
T2  B hits Wi-Fi, uploads 150      100 acked "stale" (already there)
                                   B.dirty = {}

The redundant upload at T2 happens on a DIFFERENT DEVICE, LATER.
No lock on either device changes it. It is the price of "P2P imports
are marked dirty so data reaches the cloud from whichever device
syncs first" — a feature, and idempotent on the server.
```

## Cloud protocol: push and pull are one exchange

```
POST /v1/sync {cursor, changes[≤100]}
        │
        ▼  server (sync.ts):
   put each change (LWW)  → applied[] (applied|stale)
   pull(cursor)           → changes[] + new cursor + hasMore
        │
        ▼
response {applied, changes, cursor, hasMore}

⇒ a client-side "send only" role would have to discard response.changes
  while persisting the advanced cursor — permanently skipping them.
  This is why cloud roles were rejected without a backend change.
```

## Phase 1a fix, shape of the change

```
syncNow:
  toPush = flatDTOs().filter { dirty.contains($0.id) }
  pushedVersion = [id: updatedAt]  for toPush          ← NEW
  ...per chunk:
  acked = response.applied.filter(applied|stale).map(\.id)
  acked = acked.filter { store.updatedAt(for: $0) == pushedVersion[$0] }  ← NEW
  store.clearDirty(acked)
```

## Future: trip scoping (unchanged sketch)

```
backend:  pk = "trip#<uuid>"      (today: "shared", sync.ts:9)
client:   cursor PER SCOPE        (today: single cloudSyncCursor)
migrate:  "shared" partition → default trip
authz:    who may read/write a trip (today: any signed-in user)
ui:       trip selector; counts/exports/sync scoped to active trip
```
