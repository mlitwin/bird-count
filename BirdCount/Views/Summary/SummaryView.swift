import SwiftUI

struct SummaryView: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var showLog: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header spacing to account for floating AppHeaderView
                HeaderSpacingView()
                
                // Total individuals in range
                VStack(alignment: .leading, spacing: 8) {
                    HStack { 
                        Text(Strings.Species.individuals.string)
                        Spacer()
                        Text("\(observations.totalIndividuals(in: dateRangeStore.dateRange))").monospacedDigit() 
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()

                // Future content can go here
                Text(Strings.Observation.none.string)
                    .foregroundStyle(.secondary)
                    .padding()
                
                Spacer()
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
