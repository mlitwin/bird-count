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
/// ## Sticky bottom
///
/// Both paths position the list using the `LazyVStack`'s *estimated* row
/// heights. Rows measured afterwards (a long name wrapping, e.g. next to an
/// attribution icon at larger Dynamic Type) change the content height without
/// moving the offset, leaving the list short by exactly the difference (seen
/// on device: 28pt after a filter-typed swipe-add; reproduced by
/// `SwipeScrollReproTests.testFilterSwipeReplay`). So whenever the list
/// *should* be at the bottom — initially, after either trigger, or after a
/// user scroll that ends there — a content-height change schedules a
/// deferred, bounded re-pin (see `scheduleRepin`). A user scroll that ends
/// elsewhere clears that intent, so a scrolled-up list is never yanked.
struct BottomAnchoredScrollView<Content: View>: View {
    var scrollToBottomTrigger: Int = 0
    var scrollToBottomOnChange: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    @State private var sentinelID = UUID()
    @State private var pin = PinState()

    /// Sticky-bottom bookkeeping. A plain reference type on purpose: it is
    /// written from scroll-geometry/phase callbacks, and any view
    /// invalidation from inside those callbacks (a `@State` write, or an
    /// `@Observable` read the body ends up depending on) is itself enough to
    /// break bottom pinning (see BottomAnchoredScrollViewRowGrowthTests).
    /// Also bridges the `ScrollViewProxy` out of `ScrollViewReader`'s scope,
    /// since `onScrollGeometryChange` never fires when nested inside it
    /// (docs/scroll-to-bottom.md Attempt 2).
    private final class PinState {
        var proxy: ScrollViewProxy?
        /// The list should rest at the bottom: true initially, after a
        /// content-set rebuild or trigger, and after a user scroll that ends
        /// at the bottom; false after a user scroll that ends elsewhere.
        var wantsBottom = true
        var userScrolling = false
        /// Distance short of the true bottom at the last geometry sample.
        var gap: CGFloat = 0
        /// Coalesces bursts of contentSize changes into one deferred re-pin.
        var repinGeneration = 0
    }

    private struct Geometry: Equatable {
        var contentHeight: CGFloat
        var gap: CGFloat
    }

    private func scrollToSentinel(_ proxy: ScrollViewProxy) {
        var t = Transaction(animation: .none)
        t.disablesAnimations = true
        withTransaction(t) {
            proxy.scrollTo(sentinelID, anchor: .bottom)
        }
    }

    /// Re-pins to the bottom once content height has settled.
    ///
    /// Deferred and coalesced because (a) LazyVStack's estimate can flap
    /// within a few ms of a rebuild (seen: 813607 → 852587 → 813607), and
    /// (b) SwiftUI reports a new content height before the backing
    /// UIScrollView's contentSize catches up, so a scroll issued in the same
    /// moment is clamped to the old maximum (docs/scroll-to-bottom.md). When
    /// the height change lands inside an animated transaction, the
    /// UIScrollView's contentSize itself animates toward the new value, so
    /// keep following (bounded) until the list actually reaches the bottom.
    private func scheduleRepin(_ reason: String) {
        pin.repinGeneration &+= 1
        let generation = pin.repinGeneration
        Task { @MainActor in
            for attempt in 1...Self.repinAttempts {
                try? await Task.sleep(for: Self.repinSettle)
                guard generation == pin.repinGeneration,
                      pin.wantsBottom, !pin.userScrolling,
                      pin.gap > Self.bottomTolerance,
                      let proxy = pin.proxy
                else { return }
                DiagnosticsLog.log(.scroll, "\(reason): re-pin attempt \(attempt) (gap=\(pin.gap))")
                scrollToSentinel(proxy)
            }
        }
    }

    private static var repinSettle: Duration { .milliseconds(50) }
    private static var repinAttempts: Int { 20 }
    private static var bottomTolerance: CGFloat { 0.5 }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    content()
                    Color.clear.frame(height: 0).id(sentinelID)
                }
                .onAppear { pin.proxy = proxy }
            }
        }
        .id(scrollToBottomOnChange)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .onScrollGeometryChange(for: Geometry.self) { g in
            Geometry(contentHeight: g.contentSize.height,
                     gap: g.contentSize.height - g.visibleRect.maxY)
        } action: { old, new in
            pin.gap = new.gap
            guard old.contentHeight != new.contentHeight else { return }
            DiagnosticsLog.log(.scroll, "SwiftUI contentSize.height: \(old.contentHeight) -> \(new.contentHeight) gap=\(new.gap)")
            // Rows measured after the list settled (LazyVStack estimates →
            // real heights, e.g. a name wrapping) change the content height
            // without moving the offset, leaving the list short by exactly the
            // difference. Follow the bottom unless the user has scrolled away.
            guard pin.wantsBottom, !pin.userScrolling else { return }
            scheduleRepin("contentSize change")
        }
        .onScrollPhaseChange { old, new in
            switch new {
            case .tracking, .interacting, .decelerating:
                pin.userScrolling = true
            case .idle:
                if pin.userScrolling {
                    pin.userScrolling = false
                    pin.wantsBottom = pin.gap <= 1
                }
            case .animating:
                break
            @unknown default:
                break
            }
            DiagnosticsLog.log(.scroll, "phase \(old) -> \(new) wantsBottom=\(pin.wantsBottom) gap=\(pin.gap)")
        }
        // Both bottom requests live outside the `.id`-rebuilt subtree so they
        // fire even when they arrive in the same update as a rebuild.
        .onChange(of: scrollToBottomTrigger) { _, _ in
            // Defer by one run-loop tick so the LazyVStack can commit its
            // updated layout (re-sorted rows) before the scroll resolves.
            // Rows measured after that are handled by the sticky-bottom
            // re-pin in onScrollGeometryChange.
            pin.userScrolling = false
            pin.wantsBottom = true
            Task { @MainActor in
                if let proxy = pin.proxy { scrollToSentinel(proxy) }
                DiagnosticsLog.log(.scroll, "trigger: scrollTo(sentinel) sent")
            }
            scheduleRepin("trigger")
        }
        .onChange(of: scrollToBottomOnChange) { _, newValue in
            DiagnosticsLog.log(.scroll, "content-set changed (id: \(String(describing: newValue))) -> ScrollView teardown/rebuild")
            // The rebuilt ScrollView starts at the bottom (initialOffset);
            // keep it there as its rows get measured.
            pin.userScrolling = false
            pin.wantsBottom = true
            scheduleRepin("content-set rebuild")
        }
        #if DEBUG
        .onScrollGeometryChange(for: BottomGapProbe.Sample.self) { g in
            BottomGapProbe.Sample(g)
        } action: { _, new in
            gapProbe.sample = new
        }
        // Never read gapProbe from the phase/geometry callbacks above: the
        // body would start depending on per-frame geometry, and that
        // re-render alone breaks bottom pinning.
        .overlay(alignment: .topLeading) { BottomGapProbeView(probe: gapProbe) }
        #endif
    }

    #if DEBUG
    @State private var gapProbe = BottomGapProbe()
    #endif
}

#if DEBUG
/// Diagnostics for the "lands a few points short of bottom" bug: exposes the
/// live distance from the true bottom (per SwiftUI's ScrollGeometry) as an
/// accessibility value so UI tests can assert on it. Held as a reference so
/// per-frame updates only re-render `BottomGapProbeView`, not the scroll view.
@Observable final class BottomGapProbe {
    struct Sample: Equatable, CustomDebugStringConvertible {
        var offsetY: CGFloat = 0
        var contentHeight: CGFloat = 0
        var containerHeight: CGFloat = 0
        var insetTop: CGFloat = 0
        var insetBottom: CGFloat = 0
        var visibleMaxY: CGFloat = 0

        init() {}
        init(_ g: ScrollGeometry) {
            offsetY = g.contentOffset.y
            contentHeight = g.contentSize.height
            containerHeight = g.containerSize.height
            insetTop = g.contentInsets.top
            insetBottom = g.contentInsets.bottom
            visibleMaxY = g.visibleRect.maxY
        }

        /// Positive = scrolled short of the bottom by this many points.
        var gap: CGFloat { contentHeight - visibleMaxY }

        var debugDescription: String {
            String(format: "gap=%.2f visibleMaxY=%.2f offsetY=%.2f content=%.2f container=%.2f insets=(%.2f,%.2f)",
                   gap, visibleMaxY, offsetY, contentHeight, containerHeight, insetTop, insetBottom)
        }
    }
    var sample = Sample()
}

private struct BottomGapProbeView: View {
    let probe: BottomGapProbe
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("debug.scrollGap")
            .accessibilityValue(String(format: "%.2f", probe.sample.gap))
            .allowsHitTesting(false)
    }
}
#endif
