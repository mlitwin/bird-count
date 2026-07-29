import SwiftUI

private struct SpeciesListContent: View {
    let taxa: [Taxon]
    let counts: [String: Int]
    let syncAttributions: [String: ObserverAttribution]
    let onSelect: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void
    var onBadgeTap: ((Taxon) -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(taxa) { taxon in
                SpeciesRow(
                    taxon: taxon,
                    count: counts[taxon.id] ?? 0,
                    attribution: syncAttributions[taxon.id],
                    onSelect: onSelect,
                    onQuickAdd: onQuickAdd,
                    onBadgeTap: onBadgeTap.map { cb in { cb(taxon) } }
                )
                .id(taxon.id)
            }
        }
    }
}

struct SpeciesListView: View {
    let taxa: [Taxon]
    let counts: [String: Int]
    let syncAttributions: [String: ObserverAttribution]
    let onSelect: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void
    var onBadgeTap: ((Taxon) -> Void)? = nil
    // Increment to programmatically scroll to the bottom (e.g. after adding an observation)
    let scrollToBottomSignal: Int
    // false for Taxonomic mode: plain top-anchored ScrollView instead of BottomAnchoredScrollView
    let bottomAnchored: Bool

    init(
        taxa: [Taxon],
        counts: [String: Int] = [:],
        syncAttributions: [String: ObserverAttribution] = [:],
        scrollToBottomSignal: Int = 0,
        bottomAnchored: Bool = true,
        onBadgeTap: ((Taxon) -> Void)? = nil,
        onSelect: @escaping (Taxon) -> Void,
        onQuickAdd: @escaping (Taxon) -> Void = { _ in }
    ) {
        self.taxa = taxa
        self.counts = counts
        self.syncAttributions = syncAttributions
        self.scrollToBottomSignal = scrollToBottomSignal
        self.bottomAnchored = bottomAnchored
        self.onBadgeTap = onBadgeTap
        self.onSelect = onSelect
        self.onQuickAdd = onQuickAdd
    }

    var body: some View {
        if bottomAnchored {
            // scrollToBottomOnChange uses a Set (not an Array) so that sort-order
            // changes — same species, different bucket positions — do not trigger
            // a content rebuild, while filter changes that add or remove species do.
            let visibleIdSet = AnyHashable(Set(taxa.map { $0.id }))
            BottomAnchoredScrollView(
                scrollToBottomTrigger: scrollToBottomSignal,
                scrollToBottomOnChange: visibleIdSet
            ) {
                SpeciesListContent(
                    taxa: taxa,
                    counts: counts,
                    syncAttributions: syncAttributions,
                    onSelect: onSelect,
                    onQuickAdd: onQuickAdd,
                    onBadgeTap: onBadgeTap
                )
            }
            .padding(.bottom, 24)
        } else {
            ScrollView {
                SpeciesListContent(
                    taxa: taxa,
                    counts: counts,
                    syncAttributions: syncAttributions,
                    onSelect: onSelect,
                    onQuickAdd: onQuickAdd,
                    onBadgeTap: onBadgeTap
                )
            }
            .padding(.bottom, 24)
        }
    }
}
