# Scroll-to-Bottom in SwiftUI: Problem, Current Solution, and Alternatives

## The problem

`BottomAnchoredScrollView` wraps `SpeciesListView` and `ObservationLogView`. Both views must:

1. **Start scrolled to the bottom** — newest content is at the bottom; the user should see it immediately without scrolling.
2. **Snap to the bottom when a new item is appended** — tapping a species increments its count. The row re-sorts to the bottom; the list should jump there instantly, with no visible animation.
3. **Re-anchor to the bottom when the content set expands** — the user clears a filter, causing the list to grow from a short filtered set back to a full list. The scroll position (a low offset) would now sit near the top of the taller list; the view should jump back to the bottom.

### Why `defaultScrollAnchor(.bottom)` alone isn't enough

`defaultScrollAnchor(.bottom)` (iOS 17) sets the *initial* content offset. It does not re-anchor when content size changes. When a filter narrows the list, the scroll offset is clamped to the smaller content range. When the filter is later cleared and content expands, that same low offset sits near the top of the new taller list — leaving the view appearing blank or showing stale content.

---

## Current solution (`BottomAnchoredScrollView`)

```
GeometryReader { proxy in
    ScrollViewReader { reader in
        ScrollView {
            VStack(spacing: 0) {
                content()
                Color.clear.frame(height: 1).id("__bottom_anchor__")
            }
            .frame(minHeight: proxy.size.height, alignment: .bottom)
        }
        .defaultScrollAnchor(.bottom)
        .onAppear { withAnimation(.none) { reader.scrollTo("__bottom_anchor__", anchor: .bottom) } }
        .onChange(of: scrollToBottomTrigger) { _, _ in
            withAnimation(.none) { reader.scrollTo("__bottom_anchor__", anchor: .bottom) }
        }
        .onChange(of: scrollToBottomOnChange) { _, _ in
            Task { @MainActor [reader] in
                withAnimation(.none) { reader.scrollTo("__bottom_anchor__", anchor: .bottom) }
            }
        }
    }
}
```

### Key elements

| Element | Purpose |
|---|---|
| `GeometryReader` at root | Captures available height so short lists stay bottom-aligned (via `frame(minHeight:alignment:)`) rather than top-aligned |
| Sentinel `Color.clear.id("__bottom_anchor__")` | Named target for `scrollTo` — a 1pt transparent view at the very end of content |
| `defaultScrollAnchor(.bottom)` | Sets initial scroll position to the bottom without a visible scroll |
| `onAppear` `scrollTo` | Belt-and-suspenders for initial position; `defaultScrollAnchor` can land slightly off due to safe-area insets |
| `scrollToBottomTrigger: Int` | Caller increments an `Int` to fire a one-shot jump (new observation appended) |
| `scrollToBottomOnChange: AnyHashable?` | Token that changes identity when the *content set* changes (filter cleared); uses `AnyHashable(Set(ids))` so re-sorting the same IDs doesn't trigger a spurious scroll |
| `withAnimation(.none)` | **iOS 26 regression fix.** `scrollTo` inherits the ambient SwiftUI transaction. When called from `onChange`, the ambient transaction is animated, causing a visible scroll instead of a snap. `withAnimation(.none)` explicitly clears the transaction. |
| `Task { @MainActor in }` in `scrollToBottomOnChange` | **Filter-expand fix.** `onChange` fires before the layout engine has processed the new content size. Calling `scrollTo` synchronously fires against the *old* layout and does nothing. Suspending via `Task` yields one actor turn, letting the layout pass complete before the scroll command fires. |

### Two-trigger design

`scrollToBottomTrigger` (Int) and `scrollToBottomOnChange` (AnyHashable?) are separate because they handle different timing:

- **Trigger** (`Int`): Fires immediately from `onChange`, no deferral needed. Used when the same content list gets a new item appended — layout has already happened.
- **OnChange** (`AnyHashable?`): Fires deferred via `Task`. Used when the entire content *set* changes (filter cleared) — layout must settle first.

The `AnyHashable(Set(ids))` token is order-independent: sorting the same species different ways does not change the set, so no spurious scroll. Adding or removing items changes the set, triggering re-anchor.

---

## Known weaknesses

### Test fragility
Tests that assert scroll position must:
- Use `async/await` + `Task.sleep` (not `RunLoop.main.run`) — the RunLoop-blocking approach starves concurrent `@MainActor` tasks, including `withObservationTracking` callbacks in other test suites.
- Accept a ~60pt tolerance on the "at bottom" position assertion — `defaultScrollAnchor(.bottom)` consistently lands ~54pt short of `contentSize − bounds.height` on iPhone 16, believed to be a safe-area inset offset that SwiftUI applies internally. The exact UIScrollView formula is not publicly documented.

### iOS 26 transaction inheritance (confirmed regression)
iOS 26 changed how SwiftUI propagates animation transactions: both `onChange` callbacks and `Task { @MainActor in }` bodies now inherit the ambient transaction. `withAnimation(.none)` must be applied at each call site where an instant snap is required, including inside deferred Tasks. Confirmed on iOS 26 device; not present on iOS 18.

### No user-scroll guard
The current implementation always re-anchors to the bottom on trigger/onChange. If a user has scrolled up to review history and a new item arrives, the view yanks them back to the bottom. A chat-style "new messages" badge with optional auto-scroll would be better UX for high-frequency updates.

---

## Alternative approaches (iOS 17–18+)

### iOS 17: `scrollPosition(id:)` + `.scrollTargetLayout()`

Apple introduced a declarative alternative at WWDC 2023:

```swift
@State var scrolledToID: Item.ID? = nil

ScrollView {
    LazyVStack {
        ForEach(items) { item in ItemView(item).id(item.id) }
    }
    .scrollTargetLayout()
}
.scrollPosition(id: $scrolledToID)
.onChange(of: items) {
    Task { @MainActor in scrolledToID = items.last?.id }
}
```

The binding is *bidirectional* — when the user scrolls manually, `scrolledToID` updates to reflect the visible item. This makes a user-scroll guard straightforward: check whether `scrolledToID == items.last?.id` before deciding to auto-scroll.

**Limitations:**
- Requires each item to have an `.id()` modifier and a `Hashable` identifier.
- Requires `.scrollTargetLayout()` on the content container.
- Does not work with `List` — `ScrollView` only.
- Setting the bound ID in `onChange` still fires before layout for content-expansion cases; the `Task { @MainActor in }` deferral is still needed.
- Animation suppression requires the same `withAnimation(.none)` wrapper (same transaction inheritance problem as `ScrollViewReader`).
- **Bug (iOS 17.0–17.3):** `LazyVStack + defaultScrollAnchor(.bottom)` renders blank on second+ view opens. Fixed in iOS 17.4.

### iOS 18: `ScrollPosition` struct + `scrollTo(edge: .bottom)`

The cleanest public API for this use case. Introduced at WWDC 2024:

```swift
@State private var position = ScrollPosition(edge: .bottom)

ScrollView {
    LazyVStack {
        ForEach(items) { item in ItemView(item) }
    }
}
.scrollPosition($position)
.defaultScrollAnchor(.bottom, for: .sizeChanges)   // stay-anchored on content growth
.onChange(of: items) {
    Task { @MainActor in position.scrollTo(edge: .bottom) }
}
```

Key advantages over the current approach:

| Current (`ScrollViewReader`) | iOS 18 (`ScrollPosition`) |
|---|---|
| No `.id()` sentinel needed | ✓ No `.id()` sentinel needed |
| `withAnimation(.none)` required (transaction inheritance) | `withAnimation(.none)` still required on iOS 26+ (see note below) |
| Sentinel `Color.clear` anchor view needed | ✓ No sentinel needed |
| Can't detect user's scroll position | ✓ Bidirectional: `.isPositionedByUser` tells you the user manually scrolled |

**Animation suppression on iOS 26+:** The WWDC 2024 documentation described `ScrollPosition.scrollTo(edge:)` as "animation opt-in — instant by default." This holds on iOS 18. On iOS 26, Apple changed SwiftUI transaction propagation so that `onChange` passes its animated context to `scrollTo`, producing a visible slide. The fix is the same `withAnimation(.none)` wrapper used with `ScrollViewReader`. This must also be applied *inside* `Task { @MainActor in }` on the deferred path, as iOS 26 propagates transactions across actor-boundary task hops.

**`defaultScrollAnchor(.bottom, for: .sizeChanges)` (iOS 18):** This role tells the scroll view to maintain bottom anchoring when the *content size* changes. For simple cases (a new item appended to the same list), this could eliminate the `onChange` handler entirely. **Caveat:** when the *entire item set* is replaced (filter cleared = wholly different collection), the behavior is less predictable — the `.sizeChanges` role may not re-anchor. The explicit `Task { @MainActor in position.scrollTo(edge: .bottom) }` call is still the reliable fallback.

**Layout timing:** `Task { @MainActor in }` deferral is still needed for the content-expansion case. This is a fundamental SwiftUI rendering pipeline constraint, not specific to the API.

### Not recommended: Inverted/flipped view

Applying `.rotationEffect(.radians(.pi)).scaleEffect(x: -1, y: 1)` to the ScrollView and each cell to reverse the coordinate system was a pre-iOS 17 workaround. As of iOS 18, it breaks accessibility hit testing (UIWindow behavior change). Do not use for new code.

---

## Migration path

The current `BottomAnchoredScrollView` works correctly on iOS 17+ with the `withAnimation(.none)` + `Task` fixes in place. If the app's minimum deployment target moves to iOS 18, it is worth migrating to `ScrollPosition` to:

1. Eliminate the `withAnimation(.none)` transaction suppression (and its iOS 26 brittleness).
2. Eliminate the sentinel `Color.clear` anchor view.
3. Gain bidirectional scroll position awareness for a future user-scroll guard.
4. Use `defaultScrollAnchor(.bottom, for: .sizeChanges)` to handle the simple-append case declaratively.

The `Task { @MainActor in }` deferral and the two-trigger design (immediate vs. deferred) remain valid regardless of which API is used.

---

## References

- [WWDC 2023 — Beyond scroll views (iOS 17 scroll APIs)](https://developer.apple.com/videos/play/wwdc2023/10159/)
- [WWDC 2024 — Scroll APIs (iOS 18 `ScrollPosition` struct)](https://developer.apple.com/videos/play/wwdc2024/)
- [Apple Developer Docs — `ScrollPosition`](https://developer.apple.com/documentation/swiftui/scrollposition)
- [Apple Developer Docs — `defaultScrollAnchor(_:for:)`](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:))
- [Fatbobman — The Evolution of SwiftUI Scroll Control APIs](https://fatbobman.com/en/posts/the-evolution-of-swiftui-scroll-control-apis/)
- [Swift with Majid — Mastering ScrollView: Scroll Position](https://swiftwithmajid.com/2023/06/27/mastering-scrollview-in-swiftui-scroll-position/)
- [Swift with Majid — Mastering ScrollView: Scroll Geometry](https://swiftwithmajid.com/2024/06/25/mastering-scrollview-in-swiftui-scroll-geometry/)
- [Use Your Loaf — SwiftUI Default Scroll Anchor](https://useyourloaf.com/blog/swiftui-default-scroll-anchor/)
- [Medium — SwiftUI: 2.5 Reliable Ways to Scroll to the Bottom](https://medium.com/@itsuki.enjoy/swiftui-2-5-reliable-ways-to-automatically-scroll-to-the-bottom-of-scrollview-1581711e957c)
- [iOS 26 animation regression with @MainActor / Swift 6.2](https://medium.com/@yagodemartin/ios-26-animation-regression-mainactor-swift-6-2-f93b27b7b2d4)
- [Apple Developer Forums — LazyVStack + scrollPosition race](https://developer.apple.com/forums/thread/741406)
