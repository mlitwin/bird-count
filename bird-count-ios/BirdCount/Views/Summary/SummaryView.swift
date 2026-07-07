import SwiftUI

struct SummaryView: View {
    // Lightweight models to simplify ForEach and type inference
    private struct SpeciesCountItem: Identifiable {
        let id: String // taxon.id
        let taxon: Taxon
        let count: Int
    }

    private var speciesInRange: [SpeciesCountItem] {
        // Use the common filtering logic from ObservationStoreCache
        let counts = ObservationStoreCache.countsInRange(dateRangeStore.dateRange, from: observations.observations)
        
        return taxonomy.species.compactMap { t in
            if let c = counts[t.id], c > 0 {
                return SpeciesCountItem(id: t.id, taxon: t, count: c)
            } else {
                return nil
            }
        }
        .sorted { $0.taxon.order < $1.taxon.order }
    }

    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var showLog: Bool = false

    var body: some View {
        // Break up inference with local constants
        let species = speciesInRange
        let totalSpeciesInRange = observations.totalSpeciesObserved(in: dateRangeStore.dateRange)
        let totalIndividualsInRange = observations.totalIndividuals(in: dateRangeStore.dateRange)
        
        return NavigationStack {
            VStack(spacing: 0) {
                // Header spacing to account for floating AppHeaderView
                HeaderSpacingView()
                
                // Totals (range is selected globally at the top of the app)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { 
                        Text(Strings.Species.observed.string)
                        Spacer()
                        Text("\(totalSpeciesInRange)").monospacedDigit() 
                    }
                    HStack { 
                        Text(Strings.Species.individuals.string)
                        Spacer()
                        Text("\(totalIndividualsInRange)").monospacedDigit() 
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()

                // Species list with counts from date range
                if species.isEmpty {
                    VStack(spacing: 16) {
                        Text(Strings.Observation.none.string)
                            .foregroundStyle(.secondary)
                        
                        Text(Strings.Observation.noneInRange.string)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(species) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.taxon.commonName)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        Text(item.taxon.scientificName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(item.count)")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                
                                if item.id != species.last?.id {
                                    Divider()
                                        .padding(.leading)
                                }
                            }
                        }
                    }
                }
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
}
#endif
