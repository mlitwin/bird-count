import SwiftUI

struct ObservationLogView: View {
    @Environment(ObservationStore.self) private var observationsStore
    @Environment(TaxonomyStore.self) private var taxonomy
    @Binding var show: Bool
    @State private var exportSheet: Bool = false

    struct DisplayObservation: Identifiable { let id: UUID; let taxon: Taxon?; let timestamp: Date }

    private var display: [DisplayObservation] {
        observationsStore.observations.sorted { $0.timestamp < $1.timestamp }.map { rec in
            let taxon = taxonomy.species.first { $0.id == rec.taxonId }
            return DisplayObservation(id: rec.id, taxon: taxon, timestamp: rec.timestamp)
        }
    }

    var body: some View {
        NavigationStack {
            List(display) { obs in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(obs.taxon?.commonName ?? obs.taxon?.id ?? obs.taxon?.scientificName ?? "Unknown")
                        Text(obs.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: obs))
            }
            .navigationTitle("Observation Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { show = false } }
                ToolbarItem(placement: .primaryAction) { Button("Export") { exportSheet = true }.disabled(display.isEmpty) }
            }
            .sheet(isPresented: $exportSheet) { ShareActivityView(items: [exportText()]) }
        }
    }

    private func exportText() -> String {
        var lines: [String] = ["Bird Count Observations"]
        let formatter = ISO8601DateFormatter()
        for o in display { lines.append("\(formatter.string(from: o.timestamp))\t\(o.taxon?.commonName ?? "Unknown")") }
        return lines.joined(separator: "\n")
    }

    private func accessibilityLabel(for o: DisplayObservation) -> String {
        let name = o.taxon?.commonName ?? "Unknown species"
        return "\(name) at \(DateFormatter.localizedString(from: o.timestamp, dateStyle: .none, timeStyle: .short))"
    }
}

#if DEBUG
#Preview { ObservationLogView(show: .constant(true)).environment(ObservationStore()).environment(TaxonomyStore()) }
#endif
