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

        // ScrollPosition.scrollTo(edge:) is instant by default (animation is opt-in),
        // so no animation keys should be active on the scroll view's layer.
        let animKeys = sv.layer.animationKeys() ?? []
        #expect(animKeys.isEmpty, "scrollTo must not animate")
    }

    @Test("Content set change scrolls to bottom after deferred layout (filter-clear path)")
    func contentChangeScrollsToBottomAfterDefer() async throws {
        let token1 = AnyHashable(Set(["a", "b", "c"]))
        let w = TestWindow(BottomAnchoredScrollView(scrollToBottomOnChange: token1) { tallContent })
        try await Task.sleep(for: .milliseconds(300))
        guard let sv = findScrollView(in: w.view) else {
            Issue.record("UIScrollView not found"); return
        }

        // Simulate filter active → list short → scroll back to top.
        sv.setContentOffset(.zero, animated: false)

        // Simulate filter cleared: new larger set of IDs.
        let token2 = AnyHashable(Set(["a", "b", "c", "d", "e"]))
        w.update(BottomAnchoredScrollView(scrollToBottomOnChange: token2) { tallContent })
        // onChange fires, which launches Task { @MainActor in scrollTo }.
        // Two sleeps: first lets onChange + Task enqueue happen, second lets the Task body execute.
        try await Task.sleep(for: .milliseconds(200))
        try await Task.sleep(for: .milliseconds(200))

        let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
        #expect(sv.contentOffset.y >= maxOffset - bottomScrollTolerance,
                "Should scroll to bottom after content set change (blank-list regression path)")
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
        #expect(view.recentlyUpdatedSpeciesId == nil)
        #expect(view.counts.isEmpty)
    }

    @Test("Renders with empty taxa list")
    func rendersEmpty() {
        let v = render(SpeciesListView(taxa: [], onSelect: { _ in }))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders a single species")
    func rendersSingleSpecies() {
        let v = render(SpeciesListView(taxa: makeTaxa(1), onSelect: { _ in }))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders many species (taller than screen)")
    func rendersManySpecies() {
        let taxa = makeTaxa(40)
        let counts = Dictionary(uniqueKeysWithValues: taxa.map { ($0.id, 3) })
        let v = render(SpeciesListView(taxa: taxa, counts: counts, onSelect: { _ in }))
        #expect(v.bounds.height > 0)
    }

    @Test("Starts scrolled to bottom with many species")
    func initialPositionIsAtBottomWithManySpecies() async throws {
        let taxa = makeTaxa(40)
        let w = TestWindow(SpeciesListView(taxa: taxa, onSelect: { _ in }))
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
        let v = render(SpeciesListView(taxa: makeTaxa(5), scrollToBottomSignal: 3, onSelect: { _ in }))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with recentlyUpdatedSpeciesId set")
    func rendersWithPulse() {
        let taxa = makeTaxa(5)
        let v = render(SpeciesListView(taxa: taxa, recentlyUpdatedSpeciesId: taxa[2].id, onSelect: { _ in }))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with counts provided for each species")
    func rendersWithCounts() {
        let taxa = makeTaxa(10)
        let counts = Dictionary(uniqueKeysWithValues: taxa.map { ($0.id, Int.random(in: 1...20)) })
        let v = render(SpeciesListView(taxa: taxa, counts: counts, onSelect: { _ in }))
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
        ))
        #expect(v.bounds.height > 0)
        _ = selectedId
        _ = quickAddId
    }
}
