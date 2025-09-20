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
                Text("Bird Count")
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                HStack(spacing: 12) {
                    Button(action: { showShareOptions = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                            .padding(8)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .disabled(observations.totalIndividuals == 0)
                    .accessibilityLabel("Share")
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.headline)
                            .padding(8)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Global observations selector
            ObservationsSelectorView()
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog("Share Options", isPresented: $showShareOptions) {
            Button("Export") { shareSheet = true }
            Button("Send to Nearby iPhone") { 
                syncMode = .sender
                showSyncSheet = true 
            }
            Button("Receive from Nearby iPhone") { 
                syncMode = .receiver
                showSyncSheet = true 
            }
            Button("Cancel", role: .cancel) { }
        }
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
