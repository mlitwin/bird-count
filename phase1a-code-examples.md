# Phase 1 Code Sketches (Revised Plan)

> Revision 2.0. The previous contents of this file (CloudSyncTransport
> wrapper, SyncCoordinator lock, tests subclassing a `final` class) were for
> a proposal that has been dropped — and would not have compiled. This file
> now sketches the revised Phase 1 from sync-unification-analysis.md.
> Filename kept for continuity.

These are sketches, not copy-paste code: verify property names against the
current source before implementing.

---

## 1a. Version-checked dirty clearing (fixes finding F1)

**Bug:** `CloudSyncService.syncNow` snapshots the push batch, awaits the
network, then clears dirty flags for every acked id — even if the record was
edited (user tap or P2P import) during the await. The newer version silently
never uploads.

### `ObservationStore.swift` — add a lookup helper

```swift
/// Current updatedAt for a record (top-level or child), or nil if absent.
public func updatedAt(for id: UUID) -> Date? {
    findRecord(by: id)?.updatedAt
}
```

### `CloudSyncService.swift` — modify `syncNow`

```swift
// After building toPush (unchanged):
let dirty = store.dirtyIds
let toPush = store.flatDTOs().filter { dirty.contains($0.id) }

// NEW: remember exactly which version of each record we are pushing.
let pushedVersion = Dictionary(uniqueKeysWithValues: toPush.map { ($0.id, $0.updatedAt) })
```

```swift
// In the chunk loop, replace the unconditional clear:
let acknowledged = response.applied
    .filter { $0.result == "applied" || $0.result == "stale" }
    .map(\.id)
    // NEW: don't clear a record that changed while this push was in flight;
    // it is dirty again with a newer updatedAt and must upload next session.
    .filter { store.updatedAt(for: $0) == pushedVersion[$0] }
store.clearDirty(acknowledged)
```

Notes:
- `updatedAt` is a `Date`; both sides come from the same stored value, so
  equality comparison is exact (no float-epsilon concern for unchanged
  records — any edit assigns a strictly newer Date).
- A record deleted mid-flight returns `nil` from `updatedAt(for:)`, fails the
  equality check, and keeps its dirty id; harmless either way.
- The skipped record is re-pushed by the follow-up sync that the mutation's
  `didMarkDirtyNotification` already schedules (30s debounce).

### Test sketch (`CloudSyncServiceTests` or store-level)

The interesting logic is the filter, which can be tested without networking:

```swift
@Test func editDuringPushKeepsRecordDirty() {
    let store = ObservationStore()
    let id = /* add a record */
    store.markDirty(id)

    // Simulate syncNow's snapshot:
    let pushedVersion = [id: store.updatedAt(for: id)!]

    // Simulate an edit landing while the push is in flight:
    /* mutate the record so updatedAt advances and it is re-marked dirty */

    // Simulate the ack arriving for the OLD version:
    let acked = [id].filter { store.updatedAt(for: $0) == pushedVersion[$0] }
    store.clearDirty(acked)

    #expect(store.dirtyIds.contains(id))   // still dirty → will re-upload
}
```

---

## 1b. Auto-sync courtesy guard (finding F3, optional)

Goal: when a P2P transfer is running, let a due auto cloud sync wait its turn
instead of running alongside it. Correctness does not require this — it only
avoids redundant work. **No user-facing errors.**

### `CloudSyncService.swift`

```swift
/// Injected by the app root: returns true while a P2P transfer is active.
/// Auto sync re-debounces instead of running concurrently. Manual syncNow
/// is NOT gated — an explicit user action proceeds.
public var isPeerSyncActive: () -> Bool = { false }
```

```swift
// In requestSync's fire-time guard, after the existing checks:
guard self.autoSyncEnabled, self.auth.isSignedIn, self.isOnWifi, !self.isSyncing else { return }
if self.isPeerSyncActive() {
    self.requestSync(after: Self.triggerDebounce)   // try again shortly
    return
}
```

### Wiring

`SyncViewModel` is created per `SyncSheet` presentation, so the signal must
live somewhere app-scoped. Smallest option: a shared observable flag set by
the P2P layer.

```swift
// App-scoped (e.g. injected via .environment alongside the stores):
@Observable final class SyncActivity {
    var p2pTransferring = false
}

// SyncViewModel.initiateSync / cancel / completion paths:
syncActivity.p2pTransferring = true   // entering .transferring
syncActivity.p2pTransferring = false  // on .completed / .error / cancel

// BirdCountApp:
cloudSync.isPeerSyncActive = { [weak syncActivity] in
    syncActivity?.p2pTransferring ?? false
}
```

If threading `SyncActivity` into `SyncViewModel` is more churn than it's
worth, skip 1b entirely — it is the least valuable item in the plan.

---

## Phase 2 sketch: drawer entry for cloud sync (finding F5)

The cloud sync UI already exists in `UserView` (header person icon). If
discoverability is the concern, add to `LeftDrawerView`'s menu:

```swift
@State private var showUserView = false

DrawerMenuItem(icon: "icloud", title: "Cloud Sync & Account") {
    isPresented = false
    showUserView = true
}
// ...
.sheet(isPresented: $showUserView) { UserView() }
```

`UserView` pulls everything it needs from the environment; no new plumbing.
