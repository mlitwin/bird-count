import SwiftUI

struct SummaryView: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Binding var show: Bool
    @State private var shareSheet: Bool = false
    @State private var showLog: Bool = false
    // Recent filter range
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var preset: RecentPreset = .custom

    private enum RecentPreset: String, CaseIterable, Identifiable {
        case lastHour = "Last Hour"
        case today = "Today"
        case last7Days = "7 Days"
        case all = "All"
        case custom = "Custom"
        var id: String { rawValue }
    }

    private func applyPreset(_ p: RecentPreset) {
        let now = Date()
        switch p {
        case .lastHour:
            startDate = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
            endDate = now
        case .today:
            let cal = Calendar.current
            startDate = cal.startOfDay(for: now)
            endDate = now
        case .last7Days:
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            endDate = now
        case .all:
            startDate = .distantPast
            endDate = now
        case .custom:
            break
        }
    }

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
        .filter { $0.1 > 0 && $0.2 >= startDate && $0.2 <= endDate }
    }

    private var speciesInRange: [(Taxon, Int)] {
        // Aggregate counts within the selected range
        let filtered = observations.observations.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        let counts = filtered.reduce(into: [String:Int]()) { $0[$1.taxonId, default: 0] += 1 }
        return taxonomy.species.compactMap { t in
            if let c = counts[t.id], c > 0 { return (t, c) } else { return nil }
        }
        .sorted { $0.0.commonName < $1.0.commonName }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Totals") {
                    HStack { Text("Species observed"); Spacer(); Text("\(observations.totalSpeciesObserved)") }
                    HStack { Text("Total individuals"); Spacer(); Text("\(observations.totalIndividuals)") }
                }
                Section("Recent Range") {
                    Picker("Preset", selection: $preset) {
                        ForEach(RecentPreset.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preset) { _, newVal in applyPreset(newVal) }
                    DatePicker("From", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("To", selection: $endDate, in: startDate... , displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startDate) { _, _ in preset = .custom }
                        .onChange(of: endDate) { _, _ in preset = .custom }
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
                if !speciesInRange.isEmpty {
                    Section("Species in Range") {
                        ForEach(speciesInRange, id: \.0.id) { (taxon, count) in
                            HStack { Text(taxon.commonName); Spacer(); Text("\(count)").monospacedDigit() }
                        }
                    }
                }
                if observedSpecies.isEmpty {
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
