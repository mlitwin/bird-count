import Testing
import SwiftUI
import UIKit
@testable import BirdCount

// MARK: - Helpers

/// Render a SwiftUI view at iPhone 16 Pro dimensions and force a full layout pass.
@MainActor
private func render<V: View>(_ view: V) -> UIView {
    let vc = UIHostingController(rootView: view)
    vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
    vc.view.layoutIfNeeded()
    return vc.view
}

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

// MARK: - BottomAnchoredScrollView Tests

@MainActor
@Suite("BottomAnchoredScrollView")
struct BottomAnchoredScrollViewTests {

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

    @Test("Set-based token: same IDs different order produce equal tokens (no scroll snap on re-sort)")
    func setTokenIsOrderIndependent() {
        // A re-sort produces the same Set — should NOT trigger scrollToBottomOnChange
        let ids1 = ["amecro", "norbla", "blujay"]
        let ids2 = ["blujay", "amecro", "norbla"] // same IDs, different order
        let token1 = AnyHashable(Set(ids1))
        let token2 = AnyHashable(Set(ids2))
        #expect(token1 == token2)
    }

    @Test("Set-based token: different IDs produce different tokens (filter change triggers scroll)")
    func setTokenDiffersOnFilterChange() {
        // A filter change produces a different Set — SHOULD trigger scrollToBottomOnChange
        let ids1 = ["amecro", "norbla", "blujay"]
        let ids2 = ["amecro"] // filtered
        let token1 = AnyHashable(Set(ids1))
        let token2 = AnyHashable(Set(ids2))
        #expect(token1 != token2)
    }

    @Test("Renders with scrollToBottomOnChange set without crash")
    func rendersWithOnChange() {
        let token = AnyHashable(Set(["species-1", "species-2"]))
        let v = render(BottomAnchoredScrollView(scrollToBottomOnChange: token) {
            Text("Content")
        })
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with no content without crash")
    func rendersEmpty() {
        let v = render(BottomAnchoredScrollView { EmptyView() })
        #expect(v.bounds.height > 0)
    }

    @Test("Renders a single short row (content shorter than screen)")
    func rendersShortContent() {
        let v = render(BottomAnchoredScrollView {
            Text("One row").frame(height: 44)
        })
        #expect(v.bounds.height > 0)
    }

    @Test("Renders many rows (content taller than screen)")
    func rendersTallContent() {
        let v = render(BottomAnchoredScrollView {
            VStack(spacing: 0) {
                ForEach(0..<100, id: \.self) { i in
                    Text("Row \(i)").frame(height: 44)
                }
            }
        })
        #expect(v.bounds.height > 0)
    }

    @Test("Different positive trigger values all render without crash")
    func variousTriggerValues() {
        for trigger in [0, 1, 2, 10, 99] {
            let v = render(BottomAnchoredScrollView(scrollToBottomTrigger: trigger) {
                Text("Item")
            })
            #expect(v.bounds.height > 0)
        }
    }

    @Test("Renders nested content with IDs (mirrors SpeciesListView usage)")
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

// MARK: - SpeciesListView Tests

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

    @Test("Renders with non-zero scrollToBottomSignal")
    func rendersWithScrollSignal() {
        let v = render(SpeciesListView(
            taxa: makeTaxa(5),
            scrollToBottomSignal: 3,
            onSelect: { _ in }
        ))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with recentlyUpdatedSpeciesId set (pulse state)")
    func rendersWithPulse() {
        let taxa = makeTaxa(5)
        let v = render(SpeciesListView(
            taxa: taxa,
            recentlyUpdatedSpeciesId: taxa[2].id,
            onSelect: { _ in }
        ))
        #expect(v.bounds.height > 0)
    }

    @Test("Renders with counts provided for each species")
    func rendersWithCounts() {
        let taxa = makeTaxa(10)
        let counts = Dictionary(uniqueKeysWithValues: taxa.map { ($0.id, Int.random(in: 1...20)) })
        let v = render(SpeciesListView(taxa: taxa, counts: counts, onSelect: { _ in }))
        #expect(v.bounds.height > 0)
    }

    @Test("onSelect and onQuickAdd closures are accepted without crash")
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
        // Closures are captured but not invoked during layout; verify no crash
        _ = selectedId
        _ = quickAddId
    }
}
