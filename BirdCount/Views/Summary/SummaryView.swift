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
        let range = dateRangeStore.dateRange
        return (range.begin, range.end)
    }
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var showLog: Bool = false

    var body: some View {
        // Break up inference with local constants
    let species = speciesInRange
    let totalSpeciesInRange = species.count
    let totalIndividualsInRange = species.reduce(0) { $0 + $1.count }
        return NavigationStack {
            VStack(spacing: 0) {
                // Header spacing to account for floating AppHeaderView
                HeaderSpacingView()
                
                // Totals (range is selected globally at the top of the app)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(Strings.Species.observed.string); Spacer(); Text("\(totalSpeciesInRange)").monospacedDigit() }
                    HStack { Text(Strings.Species.individuals.string); Spacer(); Text("\(totalIndividualsInRange)").monospacedDigit() }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()

                // Scrollable content: Species in Range
                List {
                    if !species.isEmpty {
                        Section(Strings.Species.inRange.string) {
                            ForEach(species) { item in
                                HStack { Text(item.taxon.commonName); Spacer(); Text("\(item.count)").monospacedDigit() }
                            }
                        }
                    }
                    if species.isEmpty {
                        Section { Text(Strings.Observation.none.string).foregroundStyle(.secondary) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollBounceBehavior(.basedOnSize)
            }
            .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

//
#if DEBUG
#Preview("Summary Empty") {
    SummaryView()
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
        .environment(SyncSessionManager())
}
#endif

// iOS 18.5+ target assumed: using scrollBounceBehavior(.never) directly above
