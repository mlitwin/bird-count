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
///   after the content.
///
///   This is not always a small re-sort: `TaxonomyStore.search()` always
///   returns the *full* checklist (species aren't filtered by observed
///   status), with species observed in the current range sorted to the
///   bottom. Observing a species for the first time in range can move its
///   row from anywhere in a several-thousand-row list to the very last
///   position — the `LazyVStack` has to realize and measure a swath of rows
///   it had never rendered before to know the true bottom, so the initial
///   `scrollTo` can land short by however much those newly-realized rows'
///   *estimated* heights differed from their *actual* heights (reported as a
///   persistent ~10px shortfall — see docs/live-sim-bug-findings.md #1). A
///   second, corrective `scrollTo` fires once `onScrollGeometryChange` below
///   reports the contentSize actually settling, the same "wait for the real
///   geometry, then correct" approach documented as working (for the other
///   scroll path) in docs/scroll-to-bottom.md's Attempt 3.
struct BottomAnchoredScrollView<Content: View>: View {
    var scrollToBottomTrigger: Int = 0
    var scrollToBottomOnChange: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    @State private var sentinelID = UUID()
    @State private var proxyHolder = ProxyHolder()
    @State private var pendingCorrectiveScroll = false

    /// Bridges the `ScrollViewProxy` out of `ScrollViewReader`'s scope so
    /// `onScrollGeometryChange` (attached to the outer `ScrollView`, since it
    /// never fires when nested inside `ScrollViewReader` — see
    /// docs/scroll-to-bottom.md Attempt 2) can trigger a corrective scroll.
    private final class ProxyHolder {
        var proxy: ScrollViewProxy?
    }

    private func scrollToSentinel(_ proxy: ScrollViewProxy) {
        var t = Transaction(animation: .none)
        t.disablesAnimations = true
        withTransaction(t) {
            proxy.scrollTo(sentinelID, anchor: .bottom)
        }
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    content()
                    Color.clear.frame(height: 0).id(sentinelID)
                }
                .onAppear { proxyHolder.proxy = proxy }
                .onChange(of: scrollToBottomTrigger) { _, _ in
                    DiagnosticsLog.log(.scroll, "trigger fired: scrollTo(sentinel) scheduled")
                    pendingCorrectiveScroll = true
                    // Defer by one run-loop tick so the LazyVStack can commit its
                    // updated layout (re-sorted rows) before the scroll resolves.
                    // Firing synchronously here targets stale estimated row heights
                    // and lands slightly above the true bottom. This alone isn't
                    // always enough (see the corrective scroll below), but it gets
                    // the common case right without waiting on a geometry signal.
                    Task { @MainActor in
                        scrollToSentinel(proxy)
                        DiagnosticsLog.log(.scroll, "trigger: scrollTo(sentinel) sent")
                        // If no contentSize change follows (the pre-emptive scroll
                        // already landed correctly, or the move was too small to
                        // change estimated layout), stop waiting after a bounded
                        // window rather than risk a corrective scroll firing later
                        // on some unrelated geometry change (e.g. a later filter).
                        try? await Task.sleep(for: .milliseconds(500))
                        pendingCorrectiveScroll = false
                    }
                }
            }
        }
        .id(scrollToBottomOnChange)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.height
        } action: { oldHeight, newHeight in
            guard oldHeight != newHeight else { return }
            DiagnosticsLog.log(.scroll, "SwiftUI contentSize.height: \(oldHeight) -> \(newHeight)")
            guard pendingCorrectiveScroll, let proxy = proxyHolder.proxy else { return }
            pendingCorrectiveScroll = false
            DiagnosticsLog.log(.scroll, "corrective scrollTo(sentinel) fired after contentSize settle")
            scrollToSentinel(proxy)
        }
        .onChange(of: scrollToBottomOnChange) { _, newValue in
            DiagnosticsLog.log(.scroll, "content-set changed (id: \(String(describing: newValue))) -> ScrollView teardown/rebuild")
        }
    }
}
