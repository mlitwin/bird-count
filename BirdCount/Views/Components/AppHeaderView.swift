import SwiftUI

/// App header containing the title, settings button, share button, and global observations selector
struct AppHeaderView: View {
    @Binding var showSettings: Bool
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    @Environment(SyncSessionManager.self) private var syncManager
    @State private var shareSheet: Bool = false
    @State private var showSyncSheet: Bool = false
    @State private var syncMode: SyncMode = .sender
    @State private var showShareOptions: Bool = false
    @State private var includeCounts: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: centered title with trailing Settings and Share buttons
            ZStack {
                Text(Strings.Home.title.string)
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button(action: { showShareOptions = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .padding(8)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .disabled(observations.totalIndividuals(in: dateRangeStore.dateRange) == 0)
                .accessibilityLabel(Strings.Share.Accessibility.label.string)
            }
            .overlay(alignment: .trailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.headline)
                        .padding(8)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel(Strings.Share.Accessibility.settings.string)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Global observations selector
            ObservationsSelectorView()
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .background(
            // Gradient background that transitions from opaque to transparent
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(.systemGroupedBackground), location: 0.95),
                    .init(color: Color(.systemGroupedBackground).opacity(0.5), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .confirmationDialog(Strings.Share.title.string, isPresented: $showShareOptions) {
            Button(Strings.Share.export.string) { shareSheet = true }
            Button(Strings.Share.sendNearby.string) { 
                syncMode = .sender
                showSyncSheet = true 
            }
            Button(Strings.Share.receiveNearby.string) { 
                syncMode = .receiver
                showSyncSheet = true 
            }
            Button(Strings.General.cancel.string, role: .cancel) { }
        }
        .sheet(isPresented: $shareSheet) {
            VStack(spacing: 16) {
                Toggle(isOn: $includeCounts) {
                    Text(Strings.Share.includeCounts.string)
                }
                .padding(.horizontal)
                ShareActivityView(items: [exportText(includeCounts: includeCounts)])
            }
            .padding()
        }
        .sheet(isPresented: $showSyncSheet) {
            SyncSheet(initialMode: syncMode)
        }
    }
    
    // MARK: - Helper Methods
    
    // Lightweight model to simplify ForEach and type inference
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

    private func exportText(includeCounts: Bool = false) -> String {
        let species = speciesInRange
        var lines: [String] = []
        lines.append("\(Strings.Species.observed.string): \(species.count)")
        if includeCounts {
            lines.append("\(Strings.Species.individuals.string): \(species.reduce(0) { $0 + $1.count })")
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
