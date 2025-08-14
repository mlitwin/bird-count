import SwiftUI

struct SummaryView: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @State private var shareSheet: Bool = false
    @State private var showLog: Bool = false
    // Range filter
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var preset: RangePreset = .custom

    private enum RangePreset: String, CaseIterable, Identifiable {
        case lastHour = "Last Hour"
        case today = "Today"
        case last7Days = "7 Days"
        case all = "All"
        case custom = "Custom"
        var id: String { rawValue }
    }

    // Lightweight models to simplify ForEach and type inference
    private struct UpdateItem: Identifiable {
        let id: String // taxon.id
        let taxon: Taxon
        let count: Int
        let date: Date
    }

    private struct SpeciesCountItem: Identifiable {
        let id: String // taxon.id
        let taxon: Taxon
        let count: Int
    }

    private func applyRangePreset(_ p: RangePreset) {
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

    private var speciesInRange: [SpeciesCountItem] {
        // Aggregate counts within the selected range
        let filtered = observations.observations.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        let counts = filtered.reduce(into: [String:Int]()) { $0[$1.taxonId, default: 0] += 1 }
        return taxonomy.species.compactMap { t in
            if let c = counts[t.id], c > 0 {
                return SpeciesCountItem(id: t.id, taxon: t, count: c)
            } else {
                return nil
            }
        }
        .sorted { $0.taxon.commonName < $1.taxon.commonName }
    }

    var body: some View {
        // Break up inference with local constants
    let species = speciesInRange
    let totalSpeciesInRange = species.count
    let totalIndividualsInRange = species.reduce(0) { $0 + $1.count }
        return NavigationStack {
            VStack(spacing: 0) {
                // Compact header row: Title + Share
                HStack(spacing: 12) {
                    Text("Summary")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(action: { shareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(observations.totalIndividuals == 0)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Fixed header: Range + Totals
                VStack(alignment: .leading, spacing: 12) {
                    Text("Range").font(.headline)
                    Picker("Preset", selection: $preset) {
                        ForEach(RangePreset.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preset) { _, newVal in applyRangePreset(newVal) }
                    DatePicker("From", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("To", selection: $endDate, in: startDate... , displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startDate) { _, _ in preset = .custom }
                        .onChange(of: endDate) { _, _ in preset = .custom }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Totals").font(.headline)
                        HStack { Text("Species observed"); Spacer(); Text("\(totalSpeciesInRange)").monospacedDigit() }
                        HStack { Text("Total individuals"); Spacer(); Text("\(totalIndividualsInRange)").monospacedDigit() }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()

                // Scrollable content: Species in Range
                List {
                    if !species.isEmpty {
                        Section("Species in Range") {
                            ForEach(species) { item in
                                HStack { Text(item.taxon.commonName); Spacer(); Text("\(item.count)").monospacedDigit() }
                            }
                        }
                    }
                    if species.isEmpty {
                        Section { Text("No observations yet.").foregroundStyle(.secondary) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollBounceBehavior(.basedOnSize)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $shareSheet) { ShareActivityView(items: [exportText()]) }
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
#Preview("Summary Empty") { SummaryView().environment(ObservationStore()).environment(TaxonomyStore()) }
#endif

// iOS 18.5+ target assumed: using scrollBounceBehavior(.never) directly above
