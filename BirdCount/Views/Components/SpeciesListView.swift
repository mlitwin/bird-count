import SwiftUI

private struct SpeciesListContent: View {
    let taxa: [Taxon]
    let counts: [String: Int]
    let recentlyUpdatedSpeciesId: String?
    let showPulseAnimation: Bool
    let onSelect: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void

    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(taxa) { taxon in
                SpeciesRow(
                    taxon: taxon,
                    count: counts[taxon.id] ?? 0,
                    shouldPulse: recentlyUpdatedSpeciesId == taxon.id && showPulseAnimation,
                    onSelect: onSelect,
                    onQuickAdd: onQuickAdd
                )
                .id(taxon.id)
            }
        }
    }
}

struct SpeciesListView: View {
    let taxa: [Taxon]
    let counts: [String: Int]
    let onSelect: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void
    // Increment to programmatically scroll to the bottom (e.g. after adding an observation)
    let scrollToBottomSignal: Int
    // Species ID that was recently updated, used to trigger the pulse animation
    let recentlyUpdatedSpeciesId: String?

    @State private var showPulseAnimation = false

    init(
        taxa: [Taxon],
        counts: [String: Int] = [:],
        scrollToBottomSignal: Int = 0,
        recentlyUpdatedSpeciesId: String? = nil,
        onSelect: @escaping (Taxon) -> Void,
        onQuickAdd: @escaping (Taxon) -> Void = { _ in }
    ) {
        self.taxa = taxa
        self.counts = counts
        self.scrollToBottomSignal = scrollToBottomSignal
        self.recentlyUpdatedSpeciesId = recentlyUpdatedSpeciesId
        self.onSelect = onSelect
        self.onQuickAdd = onQuickAdd
    }

    var body: some View {
        // scrollToBottomOnChange uses a Set (not an Array) so that sort-order
        // changes — same species, different bucket positions — do not trigger
        // a scroll, while filter changes that add or remove species do.
        let visibleIdSet = AnyHashable(Set(taxa.map { $0.id }))
        return BottomAnchoredScrollView(
            scrollToBottomTrigger: scrollToBottomSignal,
            scrollToBottomOnChange: visibleIdSet
        ) {
            SpeciesListContent(
                taxa: taxa,
                counts: counts,
                recentlyUpdatedSpeciesId: recentlyUpdatedSpeciesId,
                showPulseAnimation: showPulseAnimation,
                onSelect: onSelect,
                onQuickAdd: onQuickAdd
            )
        }
        .padding(.bottom, 24)
        .onChange(of: recentlyUpdatedSpeciesId) { _, newValue in
            if newValue != nil {
                showPulseAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showPulseAnimation = false
                }
            }
        }
    }
}
