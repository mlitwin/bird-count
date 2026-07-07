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

    struct DisplayObservation: Identifiable { let id: UUID; let taxonId: String; let taxon: Taxon?; let begin: Date; let end: Date; let count: Int }

    private var display: [DisplayObservation] { buildDisplay() }

    private func buildDisplay() -> [DisplayObservation] {
        let (effStart, effEnd) = effectiveRange
        let filtered = observationsStore.observations.filter { $0.end >= effStart && $0.begin <= effEnd }
        // Build a quick lookup for species by id to avoid repeated searches
        let speciesById: [String: Taxon] = Dictionary(uniqueKeysWithValues: taxonomy.species.map { ($0.id, $0) })
        return filtered
            .sorted { $0.begin < $1.begin }
            .map { rec in
                let taxon = speciesById[rec.taxonId]
                return DisplayObservation(id: rec.id, taxonId: rec.taxonId, taxon: taxon, begin: rec.begin, end: rec.end, count: rec.count)
            }
    }

    private var effectiveRange: (Date, Date) {
        let now = Date()
        switch preset {
        case .today:
            return (Calendar.current.startOfDay(for: now), now)
        case .lastHour:
            let start = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
            return (start, now)
        case .last7Days:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .all:
            return (.distantPast, now)
        case .custom:
            return (startDate, endDate)
        }
    }

    var body: some View {
        NavigationStack {
            List(display) { obs in
                ObservationRecordView(record: ObservationRecord(id: obs.id, taxonId: obs.taxonId, begin: obs.begin, end: obs.end, count: obs.count))
            }
        
        .toolbar {
                if let show = show {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { show.wrappedValue = false } }
                }
                ToolbarItem(placement: .primaryAction) { Button("Export") { exportSheet = true }.disabled(display.isEmpty) }
            }
        .sheet(isPresented: $exportSheet) { ShareActivityView(items: [exportText()]) }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func exportText() -> String {
        var lines: [String] = ["Bird Count Observations"]
        let formatter = ISO8601DateFormatter()
        for o in display {
            if o.begin == o.end {
                lines.append("\(formatter.string(from: o.begin))\t\(o.taxon?.commonName ?? "Unknown")")
            } else {
                lines.append("\(formatter.string(from: o.begin)) – \(formatter.string(from: o.end))\t\(o.taxon?.commonName ?? "Unknown")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func accessibilityLabel(for o: DisplayObservation) -> String {
        let name = o.taxon?.commonName ?? "Unknown species"
        if o.begin == o.end {
            let dt = DateFormatter.localizedString(from: o.begin, dateStyle: .medium, timeStyle: .short)
            return "\(name) at \(dt)"
        } else {
            let start = DateFormatter.localizedString(from: o.begin, dateStyle: .medium, timeStyle: .short)
            let end = DateFormatter.localizedString(from: o.end, dateStyle: .medium, timeStyle: .short)
            return "\(name) from \(start) to \(end)"
        }
    }

    private func displayName(for taxon: Taxon?) -> String {
        if let t = taxon { return t.commonName }
        return "Unknown"
    }

    private func dateRangeString(for obs: DisplayObservation) -> String {
        if obs.begin == obs.end {
            return obs.begin.formatted(date: .abbreviated, time: .shortened)
        } else {
            let start = obs.begin.formatted(date: .abbreviated, time: .shortened)
            let end = obs.end.formatted(date: .abbreviated, time: .shortened)
            return "\(start) – \(end)"
        }
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
