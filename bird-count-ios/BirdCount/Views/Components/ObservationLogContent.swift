import SwiftUI

/// Reusable list of ObservationRecords with swipe-to-adjust/delete and
/// NavigationStack push to ObservationDetailsView on tap.
/// Manages AppNavigationState push/pop for the details level.
/// Can be scoped to any pre-filtered/sorted record array by the caller.
struct ObservationLogContent: View {
    let records: [ObservationRecord]
    var bottomAnchored: Bool = false

    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(AppNavigationState.self) private var navState
    @State private var selectedRecord: ObservationRecord? = nil
    @State private var adjustRecord: ObservationRecord? = nil

    var body: some View {
        ScrollViewReader { reader in
        List(records) { rec in
            ObservationRecordView(record: rec, onTap: { selectedRecord = rec })
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
            if bottomAnchored, let last = records.last {
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
