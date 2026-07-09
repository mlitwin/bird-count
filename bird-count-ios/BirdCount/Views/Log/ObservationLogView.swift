import SwiftUI

struct ObservationLogView: View {
    @Environment(ObservationStore.self) private var observationsStore
    @Environment(TaxonomyStore.self) private var taxonomy
    // Optional binding: if provided, shows a Close button (when used as a sheet); in Tab usage, omit it
    var show: Binding<Bool>? = nil
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var exportSheet: Bool = false
    @State private var adjustRecord: ObservationRecord? = nil

    // Flattened list of records (no date filtering here), preserving children so ObservationRecordView can compute recursive totals
    private var display: [ObservationRecord] { buildDisplay() }

    private func buildDisplay() -> [ObservationRecord] {
        let all = observationsStore.observations
        // Oldest first so the most recent entry sits at the bottom (bottom-anchored view)
        return all.sorted { $0.begin < $1.begin }
    }


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header spacing to account for floating AppHeaderView
                HeaderSpacingView()
                
                // List is used (not BottomAnchoredScrollView) to preserve native swipe actions.
                // The same bottom-anchor pattern is applied directly via defaultScrollAnchor.
                ScrollViewReader { reader in
                    List(display) { rec in
                        ObservationRecordView(record: rec)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if taxonomy.species.contains(where: { $0.id == rec.taxonId }) {
                                    Button {
                                        adjustRecord = rec
                                    } label: {
                                        Label(Strings.Observation.adjust.string, systemImage: "plus.circle")
                                    }
                                    .tint(.accentColor)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                let total = rec.totalCount
                                if total > 0 {
                                    Button(role: .destructive) {
                                        _ = observationsStore.addChildObservationWithLocation(
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
                    .defaultScrollAnchor(.bottom)
                    .onAppear {
                        if let last = display.last {
                            reader.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        
        .toolbar {
                if let show = show {
                    ToolbarItem(placement: .cancellationAction) { Button(Strings.General.close.string) { show.wrappedValue = false } }
                }
                ToolbarItem(placement: .primaryAction) { Button(Strings.Share.export.string) { exportSheet = true }.disabled(display.isEmpty) }
            }
        .sheet(isPresented: $exportSheet) { ShareActivityView(items: [exportText()]) }
        .sheet(item: $adjustRecord) { rec in
            if let taxon = taxonomy.species.first(where: { $0.id == rec.taxonId }) {
                CountAdjustSheet(taxon: taxon, parentId: rec.id, onDone: { adjustRecord = nil })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func exportText() -> String {
        var lines: [String] = [Strings.Summary.exportTitle.string]
        let formatter = ISO8601DateFormatter()
        // Build a quick lookup for species by id once
        let speciesById: [String: Taxon] = Dictionary(uniqueKeysWithValues: taxonomy.species.map { ($0.id, $0) })
        for r in display {
            let taxonName = speciesById[r.taxonId]?.commonName ?? Strings.Observation.unknown.string
            if r.begin == r.end {
                lines.append("\(formatter.string(from: r.begin))\t\(taxonName)\t×\(r.totalCount)")
            } else {
                lines.append("\(formatter.string(from: r.begin)) – \(formatter.string(from: r.end))\t\(taxonName)\t×\(r.totalCount)")
            }
        }
        return lines.joined(separator: "\n")
    }

}

#if DEBUG
#Preview("Sheet style") {
    ObservationLogView(show: .constant(true))
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
        .environment(SettingsStore())
}
#Preview("Tab style") {
    ObservationLogView()
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
        .environment(SettingsStore())
}
#endif
