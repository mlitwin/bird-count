import SwiftUI

struct SummaryView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observations
    @Environment(SettingsStore.self) private var settings
    @Environment(DateRangeStore.self) private var dateRangeStore
    @Environment(AppNavigationState.self) private var navState
    @State private var selectedTaxon: Taxon? = nil
    @State private var speciesLogTaxon: Taxon? = nil
    @State private var pulseState = PulseAnimationState()

    private var filteredCounts: [String: Int] {
        ObservationStoreCache.countsInRange(dateRangeStore.dateRange, from: observations.observations)
    }

    private var taxonomicSpecies: [Taxon] {
        let counts = filteredCounts
        return taxonomy.search(
            "",
            minCommonness: settings.selectedChecklistId != nil ? settings.minCommonness : nil,
            maxCommonness: settings.selectedChecklistId != nil ? settings.maxCommonness : nil,
            dateRange: dateRangeStore.dateRange
        )
        .filter { (counts[$0.id] ?? 0) > 0 }
        .sorted { $0.order < $1.order }
    }

    private var syncAttributions: [String: ObserverAttribution] {
        ObservationStoreCache.observersByTaxon(
            in: dateRangeStore.dateRange,
            from: observations.observations
        ).compactMapValues { observers in
            let attribution = ObserverAttribution(observers: observers, currentObserver: settings.loginEmail)
            return attribution == .mine ? nil : attribution
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HeaderSpacingView()
                totalsBar
                Divider()
                speciesList
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $speciesLogTaxon) { taxon in
                VStack(spacing: 0) {
                    HeaderSpacingView()
                    ObservationLogContent(taxonId: taxon.id, bottomAnchored: true)
                }
            }
            .onChange(of: speciesLogTaxon) { _, newValue in
                if let taxon = newValue {
                    navState.push(title: taxon.commonName, backAction: { speciesLogTaxon = nil })
                } else {
                    Task { @MainActor in navState.pop() }
                }
            }
            .sheet(item: $selectedTaxon) { taxon in
                CountAdjustSheet(taxon: taxon, onDone: { selectedTaxon = nil })
            }
            .environment(pulseState)
        }
    }

    @ViewBuilder private var totalsBar: some View {
        let speciesCount = observations.totalSpeciesObserved(in: dateRangeStore.dateRange)
        let individualCount = observations.totalIndividuals(in: dateRangeStore.dateRange)
        HStack(spacing: 0) {
            TotalsCell(label: Strings.Species.observed.string, value: speciesCount)
            Divider().frame(height: 32)
            TotalsCell(label: Strings.Species.individuals.string, value: individualCount)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var speciesList: some View {
        let taxa = taxonomicSpecies
        if taxa.isEmpty {
            VStack(spacing: 12) {
                Text(Strings.Observation.none.string)
                    .foregroundStyle(.secondary)
                Text(Strings.Observation.noneInRange.string)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SpeciesListView(
                taxa: taxa,
                counts: filteredCounts,
                syncAttributions: syncAttributions,
                bottomAnchored: false,
                onBadgeTap: { taxon in selectedTaxon = taxon },
                onSelect: { taxon in speciesLogTaxon = taxon },
                onQuickAdd: { _ in }
            )
        }
    }
}

private struct TotalsCell: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Summary") {
    SummaryView()
        .environment(ObservationStore.previewInstance)
        .environment(TaxonomyStore())
        .environment(SettingsStore())
        .environment(DateRangeStore())
        .environment(AppNavigationState())
}
#endif
