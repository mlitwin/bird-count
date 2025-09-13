import SwiftUI

struct SummaryView: View {
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

    private var speciesInRange: [SpeciesCountItem] {
        // Aggregate counts within the selected range (dynamic for relative presets)
        // Respect child observations by flattening the tree and summing each node that overlaps the range.
        let (effStart, effEnd) = effectiveRange
        let all: [ObservationRecord] = flatten(observations.observations)
        let filtered = all.filter { $0.end >= effStart && $0.begin <= effEnd }
        // Sum raw counts (children may be negative to zero-out a parent)
        let counts = filtered.reduce(into: [String:Int]()) { acc, r in
            acc[r.taxonId, default: 0] += r.count
        }
        return taxonomy.species.compactMap { t in
            if let c = counts[t.id], c > 0 {
                return SpeciesCountItem(id: t.id, taxon: t, count: c)
            } else {
                return nil
            }
        }
        .sorted { $0.taxon.order < $1.taxon.order }
    }

    // Flatten nested observations so filtering happens per node (parent and children)
    private func flatten(_ records: [ObservationRecord]) -> [ObservationRecord] {
        var result: [ObservationRecord] = []
        result.reserveCapacity(records.count)
        func walk(_ r: ObservationRecord) {
            result.append(r)
            if !r.children.isEmpty { r.children.forEach(walk) }
        }
        records.forEach(walk)
        return result
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
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @State private var shareSheet: Bool = false
    @State private var includeCounts: Bool = false
    @State private var showLog: Bool = false
    // Range filter (provided from parent/top-level)
    @Binding var preset: DateRangePreset
    @Binding var startDate: Date
    @Binding var endDate: Date
    // ...existing code...

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

                // Date range selector (only in Summary)
                DateRangeSelectorView(preset: $preset, startDate: $startDate, endDate: $endDate)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                // Totals (range is selected globally at the top of the app)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Species observed"); Spacer(); Text("\(totalSpeciesInRange)").monospacedDigit() }
                    HStack { Text("Total individuals"); Spacer(); Text("\(totalIndividualsInRange)").monospacedDigit() }
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
                .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $shareSheet) {
                VStack(spacing: 16) {
                    Toggle(isOn: $includeCounts) {
                        Text("Include counts")
                    }
                    .padding(.horizontal)
                    ShareActivityView(items: [exportText(includeCounts: includeCounts)])
                }
                .padding()
            }
        }
    }

    private func exportText(includeCounts: Bool = false) -> String {
        let species = speciesInRange
        var lines: [String] = []
        lines.append("Species observed: \(species.count)")
        if includeCounts {
            lines.append("Total individuals: \(species.reduce(0) { $0 + $1.count })")
        }
        lines.append("")
        for item in species {
            if includeCounts {
                lines.append("\(item.taxon.commonName)\t\(item.count)")
            } else {
                lines.append("\(item.taxon.commonName)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

#if DEBUG
#Preview("Summary Empty") {
    SummaryView(preset: .constant(.custom), startDate: .constant(Date()), endDate: .constant(Date()))
        .environment(ObservationStore())
        .environment(TaxonomyStore())
}
#endif

// iOS 18.5+ target assumed: using scrollBounceBehavior(.never) directly above
