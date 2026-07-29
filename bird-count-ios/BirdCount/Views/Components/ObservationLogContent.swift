import SwiftUI

/// Reusable chronological list of ObservationRecords with swipe-to-adjust/delete
/// and NavigationStack push to ObservationDetailsView on tap.
/// taxonId: when set, filters live to records for that species only; nil = all records.
struct ObservationLogContent: View {
    var taxonId: String? = nil
    var bottomAnchored: Bool = false

    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(AppNavigationState.self) private var navState
    @State private var selectedRecord: ObservationRecord? = nil
    @State private var adjustRecord: ObservationRecord? = nil

    private var effectiveRecords: [ObservationRecord] {
        let base = taxonId.map { id in observations.observations.filter { $0.taxonId == id } }
            ?? observations.observations
        return base.sorted { $0.begin < $1.begin }
    }

    var body: some View {
        ScrollViewReader { reader in
        List(effectiveRecords) { rec in
            ObservationRecordView(record: rec, onTap: { selectedRecord = rec }, onBadgeTap: { adjustRecord = rec })
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if taxonomy.taxon(id: rec.taxonId) != nil {
                        Button { adjustRecord = rec } label: {
                            Label(Strings.Observation.adjust.string, systemImage: "plus.circle")
                        }
                        .tint(.accentColor)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if rec.totalCount > 0 {
                        Button(role: .destructive) {
                            let total = rec.totalCount
                            guard total > 0 else { return }
                            _ = observations.addChildObservationWithLocation(
                                parentId: rec.id,
                                taxonId: rec.taxonId,
                                begin: Date(),
                                end: nil,
                                count: -total
                            )
                        } label: {
                            Label(Strings.Observation.delete.string, systemImage: "trash")
                        }
                    }
                }
        }
        .defaultScrollAnchor(bottomAnchored ? .bottom : .top)
        .onAppear {
            if bottomAnchored, let last = effectiveRecords.last {
                reader.scrollTo(last.id, anchor: .bottom)
            }
        }
        } // ScrollViewReader
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedRecord) { rec in
            ObservationDetailsView(record: rec)
        }
        .onChange(of: selectedRecord) { _, newValue in
            if newValue != nil {
                navState.push(
                    title: Strings.Observation.details.string,
                    backAction: { selectedRecord = nil }
                )
            } else {
                // Defer so the NavigationStack pop animation starts before the
                // header reverts, preventing a title flash on swipe-back.
                Task { @MainActor in navState.pop() }
            }
        }
        .sheet(item: $adjustRecord) { rec in
            if let taxon = taxonomy.taxon(id: rec.taxonId) {
                CountAdjustSheet(taxon: taxon, parentId: rec.id, onDone: { adjustRecord = nil })
            }
        }
    }
}
