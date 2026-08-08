import SwiftUI

private struct SpeciesListContent: View {
    let taxa: [Taxon]
    let counts: [String: Int]
    let syncAttributions: [String: ObserverAttribution]
    let undoableTaxonIds: Set<String>
    /// When non-nil, Details is only shown for taxa whose ID is in this set.
    let detailsTaxonIds: Set<String>?
    let onTap: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void
    var onDetails: ((Taxon) -> Void)? = nil
    var onUndo: ((Taxon) -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(taxa) { taxon in
                let detailsAllowed = detailsTaxonIds?.contains(taxon.id) ?? true
                SpeciesRow(
                    taxon: taxon,
                    count: counts[taxon.id] ?? 0,
                    attribution: syncAttributions[taxon.id],
                    onTap: onTap,
                    onQuickAdd: onQuickAdd,
                    onDetails: (detailsAllowed && onDetails != nil) ? onDetails : nil,
                    onUndo: (onUndo != nil && undoableTaxonIds.contains(taxon.id))
                        ? { onUndo!(taxon) }
                        : nil
                )
                .id(taxon.id)
            }
        }
    }
}

struct SpeciesListView: View {
    @State private var revealCoordinator = RevealCoordinator()

    let taxa: [Taxon]
    let counts: [String: Int]
    let syncAttributions: [String: ObserverAttribution]
    /// Taxon IDs for which the Undo button should be shown (computed by caller)
    let undoableTaxonIds: Set<String>
    /// When non-nil, Details is only shown for taxa whose ID is in this set.
    let detailsTaxonIds: Set<String>?
    let onTap: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void
    var onDetails: ((Taxon) -> Void)? = nil
    var onUndo: ((Taxon) -> Void)? = nil
    // Increment to programmatically scroll to the bottom (e.g. after adding an observation)
    let scrollToBottomSignal: Int
    // false for Taxonomic mode: plain top-anchored ScrollView instead of BottomAnchoredScrollView
    let bottomAnchored: Bool

    init(
        taxa: [Taxon],
        counts: [String: Int] = [:],
        syncAttributions: [String: ObserverAttribution] = [:],
        undoableTaxonIds: Set<String> = [],
        detailsTaxonIds: Set<String>? = nil,
        scrollToBottomSignal: Int = 0,
        bottomAnchored: Bool = true,
        onDetails: ((Taxon) -> Void)? = nil,
        onUndo: ((Taxon) -> Void)? = nil,
        onTap: @escaping (Taxon) -> Void,
        onQuickAdd: @escaping (Taxon) -> Void = { _ in }
    ) {
        self.taxa = taxa
        self.counts = counts
        self.syncAttributions = syncAttributions
        self.undoableTaxonIds = undoableTaxonIds
        self.detailsTaxonIds = detailsTaxonIds
        self.scrollToBottomSignal = scrollToBottomSignal
        self.bottomAnchored = bottomAnchored
        self.onDetails = onDetails
        self.onUndo = onUndo
        self.onTap = onTap
        self.onQuickAdd = onQuickAdd
    }

    var body: some View {
        if bottomAnchored {
            let visibleIdSet = AnyHashable(Set(taxa.map { $0.id }))
            BottomAnchoredScrollView(
                scrollToBottomTrigger: scrollToBottomSignal,
                scrollToBottomOnChange: visibleIdSet
            ) {
                SpeciesListContent(
                    taxa: taxa,
                    counts: counts,
                    syncAttributions: syncAttributions,
                    undoableTaxonIds: undoableTaxonIds,
                    detailsTaxonIds: detailsTaxonIds,
                    onTap: onTap,
                    onQuickAdd: onQuickAdd,
                    onDetails: onDetails,
                    onUndo: onUndo
                )
            }
            .environment(revealCoordinator)
            .padding(.bottom, 24)
        } else {
            ScrollView {
                SpeciesListContent(
                    taxa: taxa,
                    counts: counts,
                    syncAttributions: syncAttributions,
                    undoableTaxonIds: undoableTaxonIds,
                    detailsTaxonIds: detailsTaxonIds,
                    onTap: onTap,
                    onQuickAdd: onQuickAdd,
                    onDetails: onDetails,
                    onUndo: onUndo
                )
            }
            .environment(revealCoordinator)
            .padding(.bottom, 24)
        }
    }
}
