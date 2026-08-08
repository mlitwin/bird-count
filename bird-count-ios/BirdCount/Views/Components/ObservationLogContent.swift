import SwiftUI

/// Reusable chronological list of ObservationRecords.
/// Tap: add a child observation. Swipe-right: immediate +1.
/// Swipe-left: reveal Delete (net-zero) and Details (observation detail screen).
/// taxonId: when set, filters live to records for that species only; nil = all records.
struct ObservationLogContent: View {
    var taxonId: String? = nil
    var bottomAnchored: Bool = false

    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(AppNavigationState.self) private var navState
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var selectedRecord: ObservationRecord? = nil
    @State private var adjustRecord: ObservationRecord? = nil

    private var effectiveRecords: [ObservationRecord] {
        let range = dateRangeStore.dateRange
        let base = observations.observations.filter { rec in
            guard taxonId == nil || rec.taxonId == taxonId else { return false }
            guard taxonId != nil else { return true }
            return rec.end >= range.begin && rec.begin <= range.end
        }
        return base.sorted { $0.begin < $1.begin }
    }

    var body: some View {
        ScrollViewReader { reader in
        List(effectiveRecords) { rec in
            ObservationRecordView(record: rec, onTap: { adjustRecord = rec })
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                // Swipe-right: immediate +1 child observation
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if taxonomy.taxon(id: rec.taxonId) != nil {
                        Button {
                            _ = observations.addChildObservationWithLocation(
                                parentId: rec.id,
                                taxonId: rec.taxonId,
                                begin: Date(),
                                end: nil,
                                count: 1
                            )
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Label("+1", systemImage: "plus.circle")
                        }
                        .tint(.accentColor)
                    }
                }
                // Swipe-left: Delete and Details
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { selectedRecord = rec } label: {
                        Label(Strings.Observation.details.string, systemImage: "info.circle")
                    }
                    .tint(.blue)
                    if rec.totalCount > 0 {
                        Button(role: .destructive) {
                            let total = rec.totalCount
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
