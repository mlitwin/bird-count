import Testing
import SwiftUI
import UIKit
@testable import BirdCount

// MARK: - Helpers

/// A UIWindow kept alive for the duration of a test so GeometryReader gets real geometry.
/// Without a window, GeometryReader reports zero size and the scroll view is never rendered.
@MainActor
private final class TestWindow {
    let window: UIWindow
    let hostingController: UIHostingController<AnyView>

    init(_ view: some View) {
        let vc = UIHostingController(rootView: AnyView(view))
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w
        hostingController = vc
        vc.view.layoutIfNeeded()
    }

    var view: UIView { hostingController.view }

    func update(_ newView: some View) {
        hostingController.rootView = AnyView(newView)
        hostingController.view.layoutIfNeeded()
    }

    deinit {
        window.isHidden = true
    }
}

/// Render a SwiftUI view into a window and force a full layout pass.
@MainActor
private func render<V: View>(_ view: V) -> UIView {
    let vc = UIHostingController(rootView: view)
    let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    w.rootViewController = vc
    w.makeKeyAndVisible()
    vc.view.layoutIfNeeded()
    return vc.view
}

/// Find the first UIScrollView in the view hierarchy (recursive).
private func findScrollView(in view: UIView) -> UIScrollView? {
    if let sv = view as? UIScrollView { return sv }
    for sub in view.subviews {
        if let found = findScrollView(in: sub) { return found }
    }
    return nil
}

/// Wait until a UIScrollView other than `previous` appears in the view tree with
/// content sized to overflow its bounds (so scroll-to-bottom assertions are meaningful).
///
/// Tests that update a `BottomAnchoredScrollView` with a new `scrollToBottomOnChange`
/// token cause `.id(...)` to tear down and rebuild the underlying `UIScrollView`. The
/// old `UIScrollView` may remain in the hierarchy briefly during the swap, so polling
/// blindly for *any* laid-out scroll view returns the stale one. Pass the pre-update
/// reference as `previous` so the wait keeps polling until the new instance arrives.
///
/// Under parallel test execution (xcodebuild test across multiple suites) the simulator
/// is heavily loaded and SwiftUI's update→commit pipeline runs more slowly. The polling
/// loop forces a layout pass each iteration so we don't wait on the runloop's natural
/// schedule.
@MainActor
private func waitForNewScrollView(in view: UIView, replacing previous: UIScrollView?, timeoutMs: Int = 8000, intervalMs: Int = 25) async -> UIScrollView? {
    var elapsedMs = 0
    while elapsedMs < timeoutMs {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        if let sv = findScrollView(in: view),
           sv !== previous,
           sv.bounds.height > 0,
           sv.contentSize.height > sv.bounds.height {
            return sv
        }
        try? await Task.sleep(for: .milliseconds(intervalMs))
        elapsedMs += intervalMs
    }
    return findScrollView(in: view)
}

/// Tolerance for bottom-scroll assertions (pt). `defaultScrollAnchor(.bottom)` and
/// `scrollTo(anchor:.bottom)` both land slightly short of `contentSize − bounds` on
/// devices with safe-area insets; 60 pt covers observed real-device/simulator gaps
/// while still catching "completely failed to scroll" cases (offset near 0).
private let bottomScrollTolerance: CGFloat = 60

private func makeTaxa(_ count: Int) -> [Taxon] {
    (1...max(1, count)).map { i in
        Taxon(
            id: "species-\(i)",
            commonName: "Species \(i)",
            scientificName: "Specius exemplaris \(i)",
            order: i,
            rank: "species",
            commonness: i % 4
        )
    }
}

/// Tall content that always overflows a standard iPhone screen.
private var tallContent: some View {
    VStack(spacing: 0) {
        ForEach(0..<50, id: \.self) { i in
            Color.clear.frame(height: 44)
        }
    }
}

/// Short content that fits on a standard iPhone screen (no overflow).
/// Represents the species list when a filter is active and narrows to a few results.
private var shortContent: some View {
    VStack(spacing: 0) {
        ForEach(0..<5, id: \.self) { i in
            Color.clear.frame(height: 44)
        }
    }
}

/// Tall content using LazyVStack — mirrors SpeciesListContent in the real app.
/// LazyVStack measures row heights lazily; the first onGeometryChange firing may
/// see an intermediate (underestimated) content height rather than the final height.
private var tallLazyContent: some View {
    LazyVStack(spacing: 6) {
        ForEach(0..<50, id: \.self) { i in
            Color.clear.frame(height: 44).id(i)
        }
    }
}

/// Short lazy content — a handful of rows that fit on screen.
private var shortLazyContent: some View {
    LazyVStack(spacing: 6) {
        ForEach(0..<5, id: \.self) { i in
            Color.clear.frame(height: 44).id(i)
        }
    }
}

// MARK: - BottomAnchoredScrollView — Init & Token Logic

@MainActor
@Suite("BottomAnchoredScrollView — init and token logic")
struct BottomAnchoredScrollViewInitTests {

    @Test("Default scrollToBottomTrigger is 0")
    func defaultTrigger() {
        let view = BottomAnchoredScrollView { EmptyView() }
        #expect(view.scrollToBottomTrigger == 0)
    }

    @Test("Custom scrollToBottomTrigger is preserved at init")
    func customTrigger() {
        let view = BottomAnchoredScrollView(scrollToBottomTrigger: 7) { EmptyView() }
        #expect(view.scrollToBottomTrigger == 7)
    }

    @Test("Default scrollToBottomOnChange is nil")
    func defaultOnChange() {
        let view = BottomAnchoredScrollView { EmptyView() }
        #expect(view.scrollToBottomOnChange == nil)
    }

    @Test("scrollToBottomOnChange is preserved at init")
    func customOnChange() {
        let token = AnyHashable(Set(["a", "b"]))
        let view = BottomAnchoredScrollView(scrollToBottomOnChange: token) { EmptyView() }
        #expect(view.scrollToBottomOnChange == token)
    }

    @Test("Set-based token: same IDs different order produce equal tokens (no scroll on re-sort)")
    func setTokenIsOrderIndependent() {
        let ids1 = ["amecro", "norbla", "blujay"]
        let ids2 = ["blujay", "amecro", "norbla"]
        #expect(AnyHashable(Set(ids1)) == AnyHashable(Set(ids2)))
    }

    @Test("Set-based token: different IDs produce different tokens (filter change triggers scroll)")
    func setTokenDiffersOnFilterChange() {
        let ids1 = ["amecro", "norbla", "blujay"]
        let ids2 = ["amecro"]
        #expect(AnyHashable(Set(ids1)) != AnyHashable(Set(ids2)))
    }
}

// MARK: - BottomAnchoredScrollView — Scroll Behavior

@MainActor
@Suite("BottomAnchoredScrollView — scroll behavior")
struct BottomAnchoredScrollViewBehaviorTests {

    @Test("Starts at bottom with tall content")
    func initialPositionIsAtBottom() async throws {
        let w = TestWindow(BottomAnchoredScrollView { tallContent })
        // Yield the main actor so SwiftUI's display-link-driven render and onAppear fire.
        try await Task.sleep(for: .milliseconds(300))
        guard let sv = findScrollView(in: w.view) else {
            Issue.record("UIScrollView not found in view hierarchy"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "Content must overflow screen for this test to be meaningful")
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Should start scrolled to bottom (defaultScrollAnchor + onAppear)")
    }

    @Test("Trigger increment snaps to bottom without animation")
    func triggerScrollsToBottomWithoutAnimation() async throws {
        let w = TestWindow(BottomAnchoredScrollView(scrollToBottomTrigger: 0) { tallContent })
        try await Task.sleep(for: .milliseconds(300))
        guard let sv = findScrollView(in: w.view) else {
            Issue.record("UIScrollView not found"); return
        }

        // Manually scroll to top to simulate the state before an observation is added.
        sv.setContentOffset(.zero, animated: false)
        #expect(sv.contentOffset.y < 10, "Precondition: should be near top")

        // Fire the trigger (mirrors HomeView incrementing scrollToBottomSignal).
        w.update(BottomAnchoredScrollView(scrollToBottomTrigger: 1) { tallContent })
        // Yield so SwiftUI's onChange fires and scrollTo executes.
        try await Task.sleep(for: .milliseconds(300))

        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Should snap to bottom after trigger")

        // withAnimation(.none) must suppress the onChange transaction so no animation runs.
        // On iOS 26+ ScrollPosition.scrollTo inherits the ambient onChange animation;
        // withAnimation(.none) is the explicit suppression.
        let animKeys = sv.layer.animationKeys() ?? []
        #expect(animKeys.isEmpty, "scrollTo must not animate")
    }

    @Test("Content set change scrolls to bottom after deferred layout (filter-clear path)")
    func contentChangeScrollsToBottomAfterDefer() async throws {
        let token1 = AnyHashable(Set(["a", "b", "c"]))
        let w = TestWindow(BottomAnchoredScrollView(scrollToBottomOnChange: token1) { tallContent })
        try await Task.sleep(for: .milliseconds(300))
        let oldSV = findScrollView(in: w.view)

        // Token change → .id rebuild → fresh UIScrollView. Poll for new instance.
        let token2 = AnyHashable(Set(["a", "b", "c", "d", "e"]))
        w.update(BottomAnchoredScrollView(scrollToBottomOnChange: token2) { tallContent })

        guard let sv = await waitForNewScrollView(in: w.view, replacing: oldSV) else {
            Issue.record("New UIScrollView not laid out after update"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "Tall content must overflow screen")
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Should scroll to bottom after content set change (blank-list regression path)")
    }

    // MARK: Filter-clear regression tests
    //
    // Scenario (Images 1→3 from bug report):
    //   1. Full list visible, scrolled to bottom.
    //   2. User types a filter → list narrows to a few rows that fit on screen (scroll ≈ 0).
    //   3. User picks a species via CountAdjustSheet → observation recorded → filter cleared.
    //   4. HomeView sets filterText="" (hadFilter=true) so scrollToBottomSignal is NOT
    //      incremented. Only scrollToBottomOnChange fires (visibleIdSet changes).
    //   5. List expands from short (fits on screen) back to full tall list.
    //   Expected: view snaps to bottom of the tall list.
    //
    // The critical difference from contentChangeScrollsToBottomAfterDefer:
    //   • Content HEIGHT changes (short → tall), not just the token.
    //   • scrollToBottomTrigger does NOT change (hadFilter path).

    @Test("Filter-clear: short-to-tall expansion scrolls to bottom without trigger")
    func filterClearShortToTallScrollsToBottom() async throws {
        // Phase 1: start with short content (filter active).
        let token1 = AnyHashable(Set(["a", "b", "c"]))
        let w = TestWindow(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token1) {
                shortContent
            }
        )
        try await Task.sleep(for: .milliseconds(300))
        let oldSV = findScrollView(in: w.view)
        if let initialSV = oldSV {
            let shortMax = max(0, initialSV.contentSize.height - initialSV.bounds.height)
            #expect(shortMax == 0, "Precondition: short content must fit on screen")
        }

        // Phase 2: filter clears → tall content + new token.
        // scrollToBottomTrigger stays at 0 (hadFilter path: HomeView doesn't increment it).
        // .id(token2) rebuilds the ScrollView; poll for the new UIScrollView to lay out.
        let token2 = AnyHashable(Set(["a", "b", "c", "d", "e"]))
        w.update(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token2) {
                tallContent
            }
        )
        guard let sv = await waitForNewScrollView(in: w.view, replacing: oldSV) else {
            Issue.record("New UIScrollView not laid out after update"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "Tall content must overflow screen")
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Should scroll to bottom after filter-clear content expansion (scrollToBottomTrigger unchanged)")
    }

    @Test("Filter-clear: short-to-tall expansion does not leave view near top")
    func filterClearDoesNotLeaveViewNearTop() async throws {
        // Complementary assertion: after filter-clear, offset must NOT be near 0
        // (which would mean the view is stuck at the top of the expanded list).
        let token1 = AnyHashable(Set(["x"]))
        let w = TestWindow(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token1) {
                shortContent
            }
        )
        try await Task.sleep(for: .milliseconds(300))
        let oldSV = findScrollView(in: w.view)

        let token2 = AnyHashable(Set(["x", "y", "z"]))
        w.update(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token2) {
                tallContent
            }
        )
        guard let sv = await waitForNewScrollView(in: w.view, replacing: oldSV) else {
            Issue.record("New UIScrollView not laid out after update"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "Tall content must overflow screen")
        // The bug: scroll left at 0.0 (top of tall list). Assert we're not near top.
        #expect(sv.contentOffset.y > maxOffset / 2,
                "View must not be stuck near top after filter-clear expansion")
    }

    // MARK: Two-pass render regression
    //
    // In the real-app async rendering pipeline, SwiftUI may increment scrollEpoch
    // (from onChange) in one render pass, then expand the content height in a
    // subsequent pass. The epoch guard alone fires the scroll against the pre-expansion
    // height (0 offset for short content), then blocks the corrective scroll when
    // height later grows (same epoch). Result: view stuck at top of expanded list.
    //
    // This test simulates the two-pass scenario directly: first change only the token
    // (epoch increments, same short height), then separately expand the content height
    // (epoch unchanged, height grows). The second update should trigger a re-scroll.

    @Test("Two-pass: epoch fires with short height, then content expands — must re-scroll")
    func twoPassEpochThenHeightExpansion() async throws {
        let token1 = AnyHashable(Set(["a"]))
        let w = TestWindow(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token1) {
                shortContent
            }
        )
        try await Task.sleep(for: .milliseconds(300))
        let oldSV = findScrollView(in: w.view)
        if let initialSV = oldSV {
            #expect(max(0, initialSV.contentSize.height - initialSV.bounds.height) == 0,
                    "Precondition: short content fits on screen")
        }

        // Pass 1: token changes but content height stays short.
        // .id(token2) rebuilds the ScrollView at this point.
        let token2 = AnyHashable(Set(["a", "b", "c", "d", "e"]))
        w.update(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token2) {
                shortContent
            }
        )
        // Wait for the .id rebuild to settle before triggering pass 2.
        _ = await waitForNewScrollView(in: w.view, replacing: oldSV, timeoutMs: 1000)
        let afterPass1SV = findScrollView(in: w.view)

        // Pass 2: height now expands (same token, no further rebuild from .id;
        // same UIScrollView grows its content).
        w.update(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token2) {
                tallContent
            }
        )
        // Same UIScrollView (afterPass1SV), just bigger content — poll until contentSize grows.
        var sv: UIScrollView? = afterPass1SV
        var elapsedMs = 0
        while elapsedMs < 8000 {
            w.view.setNeedsLayout()
            w.view.layoutIfNeeded()
            if let s = findScrollView(in: w.view), s.bounds.height > 0, s.contentSize.height > s.bounds.height {
                sv = s
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
            elapsedMs += 25
        }
        guard let sv else {
            Issue.record("UIScrollView not laid out after updates"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "Tall content must overflow screen")
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Must re-scroll to bottom when height grows after epoch-only pass")
    }

    // MARK: LazyVStack progressive-height regression
    //
    // The real app's SpeciesListContent uses LazyVStack(spacing:6). Unlike VStack,
    // LazyVStack may report a smaller initial height (only visible rows measured),
    // then grow as more rows come into view. The epoch-based guard
    //   `guard old.epoch != new.epoch else { return }`
    // fires the scroll once (against the underestimated height) and then ignores
    // subsequent height-growth notifications because the epoch is unchanged.
    // Result: view stuck near the top of the expanded list (shows "Penguins" bug).
    //
    // These tests use LazyVStack content so they reproduce the bug before the fix
    // and verify the fix handles progressive height refinement.

    @Test("Filter-clear: LazyVStack short-to-tall expansion scrolls to bottom (real-app content type)")
    func filterClearLazyVStackScrollsToBottom() async throws {
        let token1 = AnyHashable(Set(["a", "b", "c"]))
        let w = TestWindow(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token1) {
                shortLazyContent
            }
        )
        try await Task.sleep(for: .milliseconds(300))
        let oldSV = findScrollView(in: w.view)
        if let initialSV = oldSV {
            let shortMax = max(0, initialSV.contentSize.height - initialSV.bounds.height)
            #expect(shortMax == 0, "Precondition: short LazyVStack content must fit on screen")
        }

        // Filter clears → tall LazyVStack + new token. Trigger unchanged (hadFilter path).
        // .id(token2) rebuilds the ScrollView; poll for the new UIScrollView to lay out.
        let token2 = AnyHashable(Set(["a", "b", "c", "d", "e"]))
        w.update(
            BottomAnchoredScrollView(scrollToBottomTrigger: 0, scrollToBottomOnChange: token2) {
                tallLazyContent
            }
        )
        guard let sv = await waitForNewScrollView(in: w.view, replacing: oldSV) else {
            Issue.record("New UIScrollView not laid out after update"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "Tall LazyVStack content must overflow screen")
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Should scroll to bottom after filter-clear expansion with LazyVStack content")
    }

    @Test("Renders empty content without crash")
    func rendersEmpty() {
        let v = render(BottomAnchoredScrollView { EmptyView() })
        #expect(v.bounds.height > 0)
    }

    @Test("Renders content shorter than screen without crash")
    func rendersShortContent() {
        let v = render(BottomAnchoredScrollView { Text("One row").frame(height: 44) })
        #expect(v.bounds.height > 0)
    }

    @Test("Renders tall content without crash")
    func rendersTallContent() {
        let v = render(BottomAnchoredScrollView { tallContent })
        #expect(v.bounds.height > 0)
    }

    @Test("Renders nested identifiable content without crash")
    func rendersNestedIdentifiableContent() {
        let items = (1...5).map { "Item \($0)" }
        let v = render(BottomAnchoredScrollView {
            LazyVStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item).frame(height: 44).id(item)
                }
            }
        })
        #expect(v.bounds.height > 0)
    }
}

// MARK: - SpeciesListView

@MainActor
@Suite("SpeciesListView")
struct SpeciesListViewTests {

    @Test("Default parameter values")
    func defaultParameters() {
        let view = SpeciesListView(taxa: [], onSelect: { _ in })
        #expect(view.scrollToBottomSignal == 0)
        #expect(view.counts.isEmpty)
    }

    @Test("Renders with empty taxa list")
    func rendersEmpty() {
        let v = render(SpeciesListView(taxa: [], onSelect: { _ in }).environment(PulseAnimationState()))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders a single species")
    func rendersSingleSpecies() {
        let v = render(SpeciesListView(taxa: makeTaxa(1), onSelect: { _ in }).environment(PulseAnimationState()))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders many species (taller than screen)")
    func rendersManySpecies() {
        let taxa = makeTaxa(40)
        let counts = Dictionary(uniqueKeysWithValues: taxa.map { ($0.id, 3) })
        let v = render(SpeciesListView(taxa: taxa, counts: counts, onSelect: { _ in }).environment(PulseAnimationState()))
        #expect(v.bounds.height > 0)
    }

    @Test("Starts scrolled to bottom with many species")
    func initialPositionIsAtBottomWithManySpecies() async throws {
        let taxa = makeTaxa(40)
        let w = TestWindow(SpeciesListView(taxa: taxa, onSelect: { _ in }).environment(PulseAnimationState()))
        try await Task.sleep(for: .milliseconds(300))
        guard let sv = findScrollView(in: w.view) else {
            Issue.record("UIScrollView not found"); return
        }
        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(maxOffset > 0, "40 species rows must overflow screen")
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Species list should start at bottom on first render")
    }

    @Test("Renders with non-zero scrollToBottomSignal")
    func rendersWithScrollSignal() {
        let v = render(SpeciesListView(taxa: makeTaxa(5), scrollToBottomSignal: 3, onSelect: { _ in }).environment(PulseAnimationState()))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with pulse animation state in environment")
    func rendersWithPulse() {
        let taxa = makeTaxa(5)
        let pulse = PulseAnimationState()
        pulse.trigger(speciesId: taxa[2].id)
        let v = render(SpeciesListView(taxa: taxa, onSelect: { _ in }).environment(pulse))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with counts provided for each species")
    func rendersWithCounts() {
        let taxa = makeTaxa(10)
        let counts = Dictionary(uniqueKeysWithValues: taxa.map { ($0.id, Int.random(in: 1...20)) })
        let v = render(SpeciesListView(taxa: taxa, counts: counts, onSelect: { _ in }).environment(PulseAnimationState()))
        #expect(v.bounds.height > 0)
    }

    @Test("onSelect and onQuickAdd closures accepted without crash")
    func closuresAccepted() {
        var selectedId: String?
        var quickAddId: String?
        let taxa = makeTaxa(3)
        let v = render(SpeciesListView(
            taxa: taxa,
            onSelect: { selectedId = $0.id },
            onQuickAdd: { quickAddId = $0.id }
        ).environment(PulseAnimationState()))
        #expect(v.bounds.height > 0)
        _ = selectedId
        _ = quickAddId
    }
}
