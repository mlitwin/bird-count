import SwiftUI

struct ObservationLogView: View {
    @Environment(ObservationStore.self) private var observationsStore
    @Environment(TaxonomyStore.self) private var taxonomy
    // Optional binding: if provided, shows a Close button (when used as a sheet); in Tab usage, omit it
    var show: Binding<Bool>? = nil
    // Shared date range
    @Binding var preset: RangePreset
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var exportSheet: Bool = false

    struct DisplayObservation: Identifiable { let id: UUID; let taxon: Taxon?; let timestamp: Date }

    private var display: [DisplayObservation] {
        let filtered = observationsStore.observations.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        return filtered.sorted { $0.timestamp < $1.timestamp }.map { rec in
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
                        // Show both date and time
                        Text(obs.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: obs))
            }
            .navigationTitle("Observation Log")
            .toolbar {
                if let show = show {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { show.wrappedValue = false } }
                }
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
        let dt = DateFormatter.localizedString(from: o.timestamp, dateStyle: .medium, timeStyle: .short)
        return "\(name) at \(dt)"
    }
}

#if DEBUG
#Preview("Sheet style") {
    ObservationLogView(show: .constant(true), preset: .constant(.custom), startDate: .constant(Date().addingTimeInterval(-3600)), endDate: .constant(Date()))
        .environment(ObservationStore())
        .environment(TaxonomyStore())
}
#Preview("Tab style") {
    ObservationLogView(preset: .constant(.custom), startDate: .constant(Date().addingTimeInterval(-3600)), endDate: .constant(Date()))
        .environment(ObservationStore())
        .environment(TaxonomyStore())
}
#endif
