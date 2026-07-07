import SwiftUI

/// A ScrollView anchored to the bottom: content grows upward and the view
/// starts scrolled to the bottom. Short lists are bottom-aligned within the
/// available space.
///
/// ## Two triggers
///
/// - **`scrollToBottomOnChange: AnyHashable?`** — when the *content set* changes
///   (e.g. filter applied/cleared, items added/removed). Applied as `.id(...)` to
///   the entire `ScrollView`, which tears down the underlying `UIScrollView`. The
///   fresh `UIScrollView` has no stale `contentSize`, and
///   `defaultScrollAnchor(.bottom, for: .initialOffset)` re-fires for the new
///   instance, landing the rebuilt content at the bottom.
///
///   This works around a known SwiftUI bug where `UIScrollView.contentSize` does
///   not refresh after a `LazyVStack`'s data set changes. SwiftUI's scroll-geometry
///   abstraction sees the new size, but the backing `UIScrollView` property stays
///   stale and clamps any scroll attempt to the old maximum. `.id` on the inner
///   content rebuilds the `LazyVStack` but does not reset the `UIScrollView`; only
///   `.id` on the `ScrollView` itself does. See docs/scroll-to-bottom.md.
///
/// - **`scrollToBottomTrigger: Int`** — increment for a one-shot scroll to the
///   bottom when the content *set* is unchanged (e.g. observation added without
///   active filter; row re-sorted to the bottom). Uses
///   `ScrollViewReader.proxy.scrollTo` against a zero-height sentinel anchored
///   after the content. Reliable on this path because the `LazyVStack` is stable
///   across the scroll.
struct BottomAnchoredScrollView<Content: View>: View {
    var scrollToBottomTrigger: Int = 0
    var scrollToBottomOnChange: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    @State private var sentinelID = UUID()

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    content()
                    Color.clear.frame(height: 0).id(sentinelID)
                }
                .onChange(of: scrollToBottomTrigger) { _, _ in
                    var t = Transaction(animation: .none)
                    t.disablesAnimations = true
                    withTransaction(t) {
                        proxy.scrollTo(sentinelID, anchor: .bottom)
                    }
                }
            }
        }
        .id(scrollToBottomOnChange)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
    }
}
