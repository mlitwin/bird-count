# Bird Count iOS: Sync Review (Revised)

## Overview

This folder contains a review of the iOS app's observation sync functionality
(P2P Bonjour and Cloud) and a plan for the small set of changes that are
actually warranted.

**Revision note:** This is a corrected version. The original analysis proposed
a large unification effort (transport abstraction, sync lock, new cloud UI,
role model for cloud). Verification against the code showed that most of its
premises were wrong — in particular, the manual cloud sync UI it proposed to
build **already exists** (`UserView.swift`), and the concurrency race it
described is not real — while it missed a genuine (small) race in dirty-flag
clearing. See "What the original analysis got wrong" below.

## Documents

1. **sync-unification-analysis.md** — the corrected analysis: verified current
   architecture, real vs. imagined deficiencies, and the revised plan.
2. **sync-unification-diagrams.md** — corrected diagrams: current state, the
   dirty-clear race timeline, and why a local lock can't fix cross-device
   re-uploads.
3. **phase1a-code-examples.md** — code sketches for the revised Phase 1
   (filename kept from the earlier revision; contents replaced).

## Key findings (verified against code)

| Claim in original analysis | Reality |
|---|---|
| "No manual Sync Now UI, no last-sync display, no auto-sync toggle" | **False.** `UserView.swift` (person icon in `AppHeaderView`) has all of it: Sync now button with progress, failure text, last-sync date, "Auto sync on Wi-Fi" toggle, sign in/out. |
| "P2P can transfer over cellular" | **False.** P2P is Bonjour on the `local.` domain (`_birdcount._tcp`, `includePeerToPeer`). It runs over LAN / peer-to-peer Wi-Fi only; there is no cellular path. Traffic between two devices on the same hotspot is subnet-local and does not consume cellular data. |
| "Race: a record could be missed if cloud's cursor was taken before P2P marked it dirty" | **Wrong mechanics.** The cursor governs *pull*, not push, and `mergeDTOs(markDirty: true)` posts `didMarkDirtyNotification`, which schedules a follow-up sync. Nothing is missed. |
| (not mentioned) | **Real race missed:** `syncNow` snapshots `toPush`, then awaits the network. An edit to a pushed record during that await (user tap or P2P import) re-dirties it with a newer `updatedAt` — but the server ack for the *old* version unconditionally clears the dirty flag (`clearDirty(acknowledged)`, CloudSyncService.swift:159). The newer version silently never uploads until the record is edited again. |
| "SyncCoordinator lock prevents the duplicate-upload scenario" | **No.** The headline scenario (A and B both re-upload after a P2P exchange) is *cross-device*; a per-device lock cannot affect it. It is also harmless: uploads are idempotent, and the redundancy is inherent to P2P dirty-marking. |
| "Cloud should get send-only / receive-only roles like P2P" | **Doesn't fit the protocol.** `POST /v1/sync` atomically pushes *and* returns a pulled delta page, advancing the cursor. A true "send only" would either discard pulled changes while advancing the cursor (permanent data loss until a cursor reset) or require a backend change. "Receive only" for device restore is already served by a normal bidirectional sync on an empty device (nothing dirty to push). |
| Phase 1a code examples "ready to implement" | **Won't compile.** `MockCloudSyncService` subclasses a `final` class; `do/catch` wraps a non-throwing call; `objc_setAssociatedObject` exposes the *debounce* task (cancelling it doesn't cancel an in-flight sync); `SyncReadyInfo` initializer misused; `#expect(case …)` is not valid Swift Testing syntax. |

## Revised plan

### Phase 1 — correctness (small, real)
- **1a. Fix the dirty-clear race:** record each pushed DTO's `updatedAt`; on
  server ack, clear the dirty flag only if the local record's `updatedAt`
  still matches what was pushed. ~15 lines. See phase1a-code-examples.md.
- **1b. Courtesy guard between transports (optional, low value):** have the
  auto cloud sync's fire-time guard also check "P2P transfer in progress" and
  re-debounce instead of running. Do **not** surface errors to the user for
  this — concurrent operation is safe; this only avoids redundant work.

### Phase 2 — UX polish (product decisions, optional)
- Add a "Cloud Sync / Account" drawer item that opens the existing `UserView`,
  if discoverability via the header person icon is deemed insufficient.
- Decide whether manual "Sync now" over cellular is intended (it currently is
  allowed; only *auto* sync gates on Wi-Fi). If intended, optionally add a
  "may use cellular data" caption; do not silently block it.

### Dropped from the original plan (with reasons)
- **CloudSyncTransport / unified `SyncTransport` abstraction** — the protocol
  is shaped around peer discovery (`startDiscovery(localHello:)`,
  `peerInitiatedSync`, hello/negotiate). Cloud sync has no discovery phase and
  no shared consumer with P2P; wrapping it produces fake states and adapter
  code with no caller. YAGNI.
- **SyncCoordinator mutual-exclusion lock** — solves a non-problem (see
  table), adds a user-facing failure mode, and its pseudocode released the
  lock before the async transfer even started.
- **P2P Wi-Fi-only toggle** — premised on a cellular transfer path that
  doesn't exist.
- **Cloud send/receive roles** — see table; revisit only alongside a backend
  protocol change, e.g. as part of trip scoping.

### Phase P — persistent pairing & offline ongoing sync (the real goal)
The investigation's actual intent: pair two phones once, then sync ongoing
with no Wi-Fi network and no cell service. Key clarification: the current
transport is peer-to-peer Wi-Fi (AWDL), not Bluetooth, and it **already works
fully offline** — no router or internet needed, only the Wi-Fi radio on. What
is missing is persistence and automation. Plan (full detail in
sync-unification-analysis.md, "Phase P"):
- **P1 — IMPLEMENTED (July 2026):** stable device identity (Curve25519 key in
  Keychain, peerID = key fingerprint), signature-verified sessions, one-time
  pairing in the SyncSheet peer card, per-peer outbound queues (chosen over
  `updatedAt` watermarks — a watermark misses records that arrive via cloud
  or a third peer with older timestamps), and `PeerAutoSyncService` for
  zero-tap delta sync while the app is foregrounded. Manual sheet flow is
  unchanged and suspends the auto service while open. New:
  `Sync/PeerIdentity.swift`, `Sync/PeerAutoSyncService.swift`,
  `Stores/PairedPeersStore.swift`, `TestsCore/PairedPeersStoreTests.swift`.
- **P2:** Core Bluetooth *presence* detection in the background → local
  notification "device nearby — tap to sync" → fast AWDL transfer on open.
- **P3 (only if needed):** full background BLE data channel — slow (tens of
  KB/s, fine for deltas), heavily throttled by iOS, dead after force-quit.
- **Not possible:** silent always-on AirDrop-style background sync; that
  needs private Apple entitlements.

### Future (unchanged in spirit)
- **Trip scoping** (`SCOPE = "trip#<uuid>"`): backend partition key is
  designed for it (`bird-count-backend/api/src/sync.ts:9`). Real work items
  when it happens: per-scope sync cursors on the client, migration of the
  existing `shared` partition, and authorization (who may read/write a trip).

## Code references

```
P2P:    bird-count-ios/BirdCount/Sync/{SyncTransport,NetworkSyncTransport,SyncViewModel,SyncMessage}.swift
        bird-count-ios/BirdCount/Views/Sync/SyncSheet.swift
Cloud:  bird-count-ios/BirdCount/Cloud/{CloudSyncService,CloudAuthService,CloudAPIClient}.swift
        bird-count-ios/BirdCount/Views/Components/UserView.swift   ← existing cloud sync UI
Merge:  bird-count-ios/BirdCount/Stores/ObservationStore.swift (mergeDTOs, dirty tracking)
        bird-count-ios/BirdCount/Models/ObservationImportService.swift (P2P import → mergeDTOs)
Server: bird-count-backend/api/src/sync.ts (SCOPE = "shared"; push+pull atomic)
```

---

**Document Version:** 2.0 (corrected) | **Last Updated:** July 2026
