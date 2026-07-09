# iOS Sync Analysis (Corrected)

> Revision 2.0. The original version of this document proposed a broad
> "unification" (transport abstraction, sync lock, new cloud UI, cloud role
> model). Checking each claim against the code invalidated most of the
> premises. This version keeps what was verified, corrects what was wrong,
> and replaces the proposal with the much smaller set of changes that the
> code actually needs. SyncR.md has the summary table of corrections.

## Executive Summary

Bird Count iOS has two sync pathways — **P2P (Bonjour/WebSocket)** and
**Cloud (HTTPS/Cognito)** — that share one merge path
(`ObservationStore.mergeDTOs`, idempotent LWW on `updatedAt`). Both are
sound. Concurrent operation is *safe for correctness* with one exception:

- **Real bug (small window):** during a cloud push, a local edit to a record
  already in the in-flight batch is silently un-dirtied when the server acks
  the *older* version. The newer version doesn't upload until the record is
  edited again. Fix in Phase 1a below.

Everything else the original analysis flagged is either already implemented
(manual cloud sync UI), not a real risk (cross-device re-uploads are
idempotent and unpreventable by a local lock), or based on a wrong premise
(P2P cannot use cellular).

---

## Current Architecture (verified)

### P2P sync
- `NetworkSyncTransport` (`Sync/NetworkSyncTransport.swift`): Bonjour
  `_birdcount._tcp` on `local.` with `includePeerToPeer = true`; WebSocket
  over TCP; UUID tiebreaker picks the connecting side; single connection.
- Roles negotiated via `SyncReadyInfo.negotiate` (`Sync/SyncMessage.swift`):
  `sendAndReceive` / `sendOnly` / `receiveOnly`, incompatible pairs rejected.
- Payload is date-windowed by the user in `SyncSheet` (drawer → "Sync with
  Nearby Phones"); export keeps ledger integrity (in-range parents bring all
  children).
- Received records import via `ObservationImportService.importFromSync` →
  `mergeDTOs(_, markDirty: true)`, so P2P-received data later flows to the
  cloud from whichever device syncs first.
- **Network scope:** local network / peer-to-peer Wi-Fi only. There is no
  cellular path for Bonjour `local.` discovery, and traffic between two
  devices on the same hotspot stays on the local subnet (no cellular data
  consumed). The original "P2P can transfer over cellular" concern was wrong.

### Cloud sync
- `CloudSyncService` (`Cloud/CloudSyncService.swift`), `@MainActor`.
- **Auto triggers**, debounced through `requestSync`: Wi-Fi restored (3s),
  app foregrounded (3s), local mutation via `didMarkDirtyNotification` (30s).
  The fire-time guard requires `autoSyncEnabled && isSignedIn && isOnWifi &&
  !isSyncing`, where `isOnWifi = path.satisfied && !path.isExpensive`.
- **Manual sync exists**: `UserView.swift` (person icon in `AppHeaderView`)
  has "Sync now" with progress, error text, last-sync date, an "Auto sync on
  Wi-Fi" toggle, and sign in/out. Manual `syncNow` deliberately does *not*
  gate on Wi-Fi — only the auto path does.
- **Protocol:** chunked `POST /v1/sync` (≤100 records) — each round trip both
  pushes a chunk *and* returns a pulled delta page — then drains remaining
  pages via `GET /v1/observations?since=`. Cursor is strictly-after on the
  server; the client rewinds 5s at session start for clock skew; re-delivery
  is absorbed by idempotent merge.
- **Dirty tracking:** first sync (`cursor == nil`) does `markAllDirty()`;
  dirty ids clear only on server ack (`applied` or `stale`).

### Shared merge path
`ObservationStore.mergeDTOs` — put-if-absent by UUID; whole-record LWW on
`updatedAt` for existing records; orphan children held until the parent
arrives; `markDirty: true` only for P2P imports. All merges run on the main
actor (cloud service is `@MainActor`; the P2P transport dispatches to main),
so interleaving happens only at suspension points — no data races, but see
the dirty-clear hazard below.

### Backend scoping
`bird-count-backend/api/src/sync.ts:9` — `SCOPE = "shared"`, one pool for all
observations. `pk = "trip#<uuid>"` is anticipated by the key design but not
implemented anywhere else.

---

## Findings

### F1 (bug): ack clears dirty flags for records edited mid-push

`syncNow` snapshots `dirtyIds` and `toPush` up front, then awaits network
calls. If a record in the in-flight batch is edited during an await — a user
tap, or a P2P import applying a newer LWW version — the edit bumps
`updatedAt` and re-inserts the id into `dirtyIds`. When the ack for the *old*
DTO arrives, `store.clearDirty(acknowledged)`
(`CloudSyncService.swift:159`) removes the id unconditionally. Result: the
newer local version is no longer dirty and never uploads until the record is
edited again or a fresh install re-runs `markAllDirty`.

No data is lost locally, and the 30s mutation debounce makes overlap
uncommon — but a manual "Sync now" during active counting hits the window
easily. Fix: clear only ids whose current `updatedAt` still equals the value
that was pushed (Phase 1a; sketch in phase1a-code-examples.md).

The race the original analysis described instead ("cloud's cursor taken
before P2P marked it dirty") does not exist: the cursor governs pull, not
push, and a P2P import posts `didMarkDirtyNotification`, scheduling a
follow-up sync that picks up anything the current session missed.

### F2 (inherent, harmless): cross-device re-uploads after P2P exchange

After A and B sync P2P, both hold each other's records marked dirty; whichever
reaches Wi-Fi first uploads both sets, and the second device re-uploads
records the server already has (acked `stale`, dirty cleared). Final state is
correct; the cost is redundant bandwidth. **A local lock cannot prevent
this** — the two uploads happen on different devices at different times. The
only real optimization would be propagating server-acknowledged state through
the P2P payload, which is not worth the protocol complexity today.

### F3 (minor): same-device concurrent P2P + cloud sync is possible

Safe for correctness (main-actor serialized, idempotent merge, F1 fix closes
the only hazard), but simultaneously running both does redundant work and
shows two spinners. A courtesy guard — auto-sync's fire-time check also
requiring "no P2P transfer in progress", re-debouncing otherwise — is cheap
(Phase 1b). It should never surface an error: there is nothing wrong to
report.

### F4 (product question): manual sync over cellular

Manual "Sync now" runs on any network; only auto sync gates on Wi-Fi. This
reads as intentional (explicit user action = user intent). If confirmed,
optionally add a "may use cellular data" caption in `UserView`; blocking it
would be a regression for users who want exactly that.

### F5 (product question): cloud sync discoverability

Cloud sync controls live in `UserView`, reached from the header person icon.
The drawer's Share section has P2P sync but no cloud entry. If users don't
find it, add a drawer item that opens `UserView` — a 10-line change to
`LeftDrawerView.swift`. This is the *entire* remaining substance of the
original "Phase 1c".

---

## Proposals evaluated and rejected

### CloudSyncTransport / unified `SyncTransport` abstraction — rejected
`SyncTransport` is shaped around peer discovery: `startDiscovery(localHello:
SyncHelloMessage)`, `peerInitiatedSync`, hello negotiation, a `readyToSync`
handshake state. Cloud sync has none of these; an adapter must fabricate a
`SyncReadyInfo` with a fake peer, ignore the `payload:` parameter, and map
states approximately. Crucially there is **no shared consumer**: `SyncSheet`/
`SyncViewModel` are built around discovery UX, and cloud sync already has its
own UI. An abstraction with one real implementation and zero shared callers
is pure carrying cost. Revisit only if a third transport or a genuinely
unified sync screen materializes.

### SyncCoordinator mutual-exclusion lock — rejected
Motivated by F2, which it cannot affect (cross-device), and by a race that
doesn't exist (see F1 discussion). Its cost is real: an auto cloud sync
firing mid-P2P would either error out a user-initiated action or be reported
as a failure for a situation that is actually fine. The lock pseudocode in
the original documents was also broken — `defer { releaseLock() }` in the
synchronous `initiateSync` while the transfer ran in a detached `Task`, so
the lock released before the transfer began. F3's courtesy re-debounce
achieves the useful 10% at none of the cost.

### P2P Wi-Fi-only toggle — rejected
Premised on P2P transferring over cellular/hotspot at data cost. It can't
(cellular) and doesn't (hotspot traffic is subnet-local). A toggle would add
a setting that protects against nothing.

### Cloud send/receive roles — rejected as specified
The wire protocol makes push and pull one atomic exchange: every
`POST /v1/sync` response carries a pulled delta page and an advanced cursor.
A client-side "send only" must either merge those changes anyway (so it isn't
send-only) or discard them while persisting the advanced cursor — which skips
them **permanently**. "Receive only" for device restore is already served by
ordinary bidirectional sync on an empty device: `markAllDirty()` over nothing
pushes nothing. A real role model needs backend support (e.g. a `pullLimit:0`
/ push-only mode) and a use case; fold it into trip-scoping design if one
appears.

---

## Revised roadmap

### Phase 1 — correctness (do now, ~1 hour total)
1. **1a. Version-checked dirty clearing** (fixes F1).
   `CloudSyncService.syncNow`: capture `updatedAt` per pushed DTO; filter the
   acknowledged ids to those whose store record still has that `updatedAt`
   before `clearDirty`. Needs a small `ObservationStore.updatedAt(for:)`
   helper. Unit-testable without network by simulating an edit between
   snapshot and ack.
2. **1b. Auto-sync courtesy guard** (addresses F3; optional).
   Inject a `() -> Bool` ("is a P2P transfer active") into
   `CloudSyncService`; the fire-time guard re-debounces when it returns true.
   Wire it from the app root where both objects exist. No user-facing errors.

### Phase 2 — UX (pending product decisions F4/F5, ~1 hour)
- Drawer item "Cloud Sync" opening `UserView` (F5).
- Cellular caption on manual sync, if F4 is confirmed intentional.

### Phase P — persistent pairing & offline ongoing sync (the investigation's actual goal)

Intent: pair two phones once, then phone-to-phone sync happens on an ongoing
basis, working with no Wi-Fi network and no cell service.

**Clarification:** the current transport already works fully offline. It is
not Bluetooth — it is Bonjour over peer-to-peer Wi-Fi (AWDL), which needs no
router and no internet, only the Wi-Fi radio enabled on both phones. What is
missing is persistence and automation: `peerID` is regenerated per session,
there is no authentication or memory of past peers, and both users must open
the sheet and tap.

**P1 — persistent pairing + zero-tap foreground sync — IMPLEMENTED (July 2026)**

What landed (deviations from the sketch below noted):
- `Sync/PeerIdentity.swift`: Curve25519 signing key in the Keychain; the
  stable peerID is the key's SHA256 fingerprint, stamped into the Bonjour TXT
  record and hello by the transport.
- Session auth in `NetworkSyncTransport`: hellos carry publicKey + a fresh
  nonce; each side proves possession with a signature over both nonces before
  `readyToSync`. Legacy (pre-pairing) peers negotiate as before, unverified.
- `Stores/PairedPeersStore.swift`: paired devices + **per-peer outbound
  queues** instead of the sketched `updatedAt` watermark — a watermark misses
  records that arrive via cloud pull or a third peer with older timestamps.
  Pairing queues everything (the P2P analog of first-sync `markAllDirty`);
  every subsequent create/update from any source queues for all peers via a
  new `ObservationStore.didChangeRecordsNotification`. Delivery clearing is
  version-checked (a record edited mid-transfer stays queued — the same fix
  Phase 1a prescribes for the cloud path).
- `Sync/PeerAutoSyncService.swift`: while the app is foregrounded and a
  paired peer is near, discovers, verifies the pairing key, and runs the
  delta exchange with no taps; idle sessions stay connected and quiet;
  local changes refresh the session after a 10s quiet period.
- SyncSheet: pair/unpair in the peer card (verified peers only), paired-
  devices list, and the sheet suspends the auto service while open so one
  transport advertises per device. Manual one-off sync is unchanged.
- Known limits: auto-sync drops connections from unpaired devices (pairing
  still requires the sheet open on both phones, as before); an unpaired
  manual session that reaches a device with its sheet closed gets a
  connection error rather than a hang; the cloud dirty-clear race (F1) is
  still open on the cloud path.

Original P1 sketch (for reference):
1. *Stable identity:* per-install identity keypair (Keychain); advertise the
   stable public-key fingerprint in the Bonjour TXT record instead of a
   throwaway UUID.
2. *Pairing ceremony:* one-time confirm-on-first-connect (or QR code) stores
   the peer's key in a paired-devices list. Connections from paired peers are
   authenticated and auto-accepted; unknown peers keep today's manual flow.
   This also closes a latent gap: today any device on the LAN running the
   app can connect.
3. *Per-peer deltas:* for paired peers, replace the per-session date window
   with a per-peer `updatedAt` high-water mark (rewound a few seconds for
   clock skew) — the same design as the cloud cursor; the idempotent LWW
   merge absorbs overlap. No schema change.
4. *Auto-sync:* while the app is foregrounded, discover paired peer →
   connect → exchange deltas → idle. The transport's existing
   `peerInitiatedSync` auto-start path extends naturally. Covers the field
   scenario whenever both users have the app open.

**P2 — BLE presence nudge** (adds "works without opening the app first"):
Network.framework/Bonjour is suspended when the app is backgrounded, and
there is no third-party entitlement for continuous background AWDL (AirDrop /
Find My use private Apple frameworks). The sanctioned background channel is
Core Bluetooth (`bluetooth-central` / `bluetooth-peripheral` background
modes). Use it for *presence only*: advertise a service UUID; on a background
BLE encounter with a paired peer, fire a local notification ("Bird Count
device nearby — tap to sync") that foregrounds the app and runs the fast
AWDL transfer. Background BLE discovery latency is minutes, not seconds.

**P3 — full background BLE transfer** (largest effort; evaluate after P1/P2):
a Core Bluetooth GATT data channel with OS-level BLE bonding (encrypted,
persistent pairing) and state restoration. Throughput is tens of KB/s — too
slow for bulk, adequate for incremental observation deltas. Caveats: iOS
throttles background BLE aggressively, and a force-quit app is not restored
for peripheral events. Only build this if P2's tap-to-sync proves
insufficient in practice.

**Not possible on iOS:** silent, always-on, high-bandwidth background sync
(AirDrop-style) — that requires private entitlements third-party apps cannot
get.

### Phase 3 — trip scoping (future, unchanged)
Backend `SCOPE = "trip#<uuid>"` plus: per-scope client cursors (the single
`cloudSyncCursor` assumes one scope), migration of the existing `shared`
partition into a default trip, per-trip authorization, and trip UI. Design
the cloud role question (if still wanted) into the same protocol revision.
Effort: days, not hours; defer until trips exist as a product concept.
