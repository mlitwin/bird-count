import SwiftUI

struct SummaryView: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Binding var show: Bool
    @State private var shareSheet: Bool = false
    @State private var showLog: Bool = false

    private var observedSpecies: [(Taxon, Int)] {
        taxonomy.species
            .compactMap { t in
                let c = observations.count(for: t.id)
                return c > 0 ? (t, c) : nil
            }
            .sorted { $0.0.commonName < $1.0.commonName }
    }

    private var recentEntries: [(Taxon, Int, Date)] {
        observations.recent.compactMap { r in
            guard let taxon = taxonomy.species.first(where: { $0.id == r.id }) else { return nil }
            return (taxon, observations.count(for: r.id), r.lastUpdated)
        }
        .filter { $0.1 > 0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Totals") {
                    HStack { Text("Species observed"); Spacer(); Text("\(observations.totalSpeciesObserved)") }
                    HStack { Text("Total individuals"); Spacer(); Text("\(observations.totalIndividuals)") }
                }
                if !recentEntries.isEmpty {
                    Section("Recent") {
                        ForEach(recentEntries, id: \.0.id) { (taxon, count, date) in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(taxon.commonName)
                                    Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(count)").monospacedDigit()
                            }
                        }
                    }
                }
                if !observedSpecies.isEmpty {
                    Section("All Observed Species") {
                        ForEach(observedSpecies, id: \.0.id) { (taxon, count) in
                            HStack { Text(taxon.commonName); Spacer(); Text("\(count)").monospacedDigit() }
                        }
                    }
                } else {
                    Section { Text("No observations yet.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { show = false } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Log") { showLog = true }.disabled(observations.observations.isEmpty)
                    Button("Share") { shareSheet = true }.disabled(observedSpecies.isEmpty)
                }
            }
            .sheet(isPresented: $shareSheet) { ShareActivityView(items: [exportText()]) }
            .sheet(isPresented: $showLog) { ObservationLogView(show: $showLog) }
        }
    }

    private func exportText() -> String {
        var lines: [String] = []
        lines.append("Bird Count Summary")
        lines.append("Species observed: \(observations.totalSpeciesObserved)")
        lines.append("Total individuals: \(observations.totalIndividuals)")
        lines.append("")
        for (taxon, count) in observedSpecies { lines.append("\(taxon.commonName)\t\(count)") }
        return lines.joined(separator: "\n")
    }
}

#if DEBUG
#Preview("Summary Empty") { SummaryView(show: .constant(true)).environment(ObservationStore()).environment(TaxonomyStore()) }
#endif
