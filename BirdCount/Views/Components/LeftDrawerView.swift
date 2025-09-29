import SwiftUI

enum ExportFormat: String, CaseIterable, Identifiable {
    case summary = "summary"
    case json = "json"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .summary:
            return Strings.Export.formatSummary.string
        case .json:
            return Strings.Export.formatJSON.string
        }
    }
}

struct LeftDrawerView: View {
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @Binding var showShareOptions: Bool
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    
    // Internal state for sync functionality
    @State private var showSyncSheet: Bool = false
    @State private var syncMode: SyncMode = .sender
    @State private var shareSheet: Bool = false
    @State private var showShareActivityView: Bool = false
    @State private var includeCounts: Bool = false
    @State private var exportFormat: ExportFormat = .summary
    
    var body: some View {
        ZStack {
            // Background overlay
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
            }
            
            // Drawer content
            HStack {
                if isPresented {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Text(Strings.General.menu.string)
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        
                        Divider()
                        
                        // Menu items
                        VStack(spacing: 0) {
                            // Share section
                            DrawerMenuSection(title: Strings.Share.title.string) {
                                DrawerMenuItem(
                                    icon: "square.and.arrow.up",
                                    title: Strings.Share.export.string,
                                    disabled: observations.totalIndividuals(in: dateRangeStore.dateRange) == 0
                                ) {
                                    isPresented = false
                                    shareSheet = true
                                }
                                
                                DrawerMenuItem(
                                    icon: "iphone.radiowaves.left.and.right",
                                    title: Strings.Share.sendNearby.string,
                                    disabled: observations.totalIndividuals(in: dateRangeStore.dateRange) == 0
                                ) {
                                    isPresented = false
                                    syncMode = .sender
                                    showSyncSheet = true
                                }
                                
                                DrawerMenuItem(
                                    icon: "wave.3.right",
                                    title: Strings.Share.receiveNearby.string
                                ) {
                                    isPresented = false
                                    syncMode = .receiver
                                    showSyncSheet = true
                                }
                            }
                            
                            Divider()
                                .padding(.horizontal)
                            
                            // Settings section
                            DrawerMenuSection(title: Strings.Settings.title.string) {
                                DrawerMenuItem(
                                    icon: "gearshape",
                                    title: Strings.Settings.title.string
                                ) {
                                    isPresented = false
                                    showSettings = true
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        
                        Spacer()
                    }
                    .frame(width: 280)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .shadow(radius: 10)
                    .transition(.move(edge: .leading))
                }
                
                Spacer()
            }
        }
        .sheet(isPresented: $shareSheet) {
            VStack(spacing: 20) {
                // Header
                Text(Strings.Export.format.string)
                    .font(.headline)
                    .padding(.top)
                
                // Export format picker
                Picker(Strings.Export.format.string, selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName)
                            .tag(format)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Include counts toggle (only shown for summary format)
                if exportFormat == .summary {
                    Toggle(isOn: $includeCounts) {
                        Text(Strings.Share.includeCounts.string)
                    }
                    .padding(.horizontal)
                }
                
                // Share button
                Button(action: {
                    shareSheet = false
                    showShareActivityView = true
                }) {
                    Text(Strings.Share.export.string)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showShareActivityView) {
            ShareActivityView(items: [exportContent(format: exportFormat, includeCounts: includeCounts)])
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
    
    private func exportJSON() -> String {
        let (effStart, effEnd) = effectiveRange
        let all: [ObservationRecord] = flatten(observations.observations)
        let filtered = all.filter { $0.end >= effStart && $0.begin <= effEnd }
        
        // Create JSON structure suitable for importing
        let exportData: [String: Any] = [
            "metadata": [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "dateRange": [
                    "begin": ISO8601DateFormatter().string(from: effStart),
                    "end": ISO8601DateFormatter().string(from: effEnd)
                ],
                "totalObservations": filtered.count
            ],
            "observations": filtered.map { record in
                [
                    "id": record.id.uuidString,
                    "taxonId": record.taxonId,
                    "count": record.count,
                    "begin": ISO8601DateFormatter().string(from: record.begin),
                    "end": ISO8601DateFormatter().string(from: record.end),
                    "location": record.location.map { location in
                        [
                            "latitude": location.latitude,
                            "longitude": location.longitude,
                            "horizontalAccuracy": location.horizontalAccuracy,
                            "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
                            "altitude": location.altitude as Any,
                            "verticalAccuracy": location.verticalAccuracy as Any,
                            "name": location.name as Any,
                            "notes": location.notes as Any
                        ]
                    } as Any,
                    "children": record.children.map { child in
                        [
                            "id": child.id.uuidString,
                            "taxonId": child.taxonId,
                            "count": child.count,
                            "begin": ISO8601DateFormatter().string(from: child.begin),
                            "end": ISO8601DateFormatter().string(from: child.end)
                        ]
                    }
                ]
            }
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to serialize JSON: \(error.localizedDescription)\"}"
        }
    }
    
    private func exportContent(format: ExportFormat, includeCounts: Bool = false) -> String {
        switch format {
        case .summary:
            return exportText(includeCounts: includeCounts)
        case .json:
            return exportJSON()
        }
    }
}

// MARK: - Supporting Components

private struct DrawerMenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 16)
            
            content
        }
    }
}

private struct DrawerMenuItem: View {
    let icon: String
    let title: String
    let disabled: Bool
    let action: () -> Void
    
    init(icon: String, title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.disabled = disabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(disabled ? .secondary : .accentColor)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(disabled ? .secondary : .primary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .disabled(disabled)
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        LeftDrawerView(
            isPresented: .constant(true),
            showSettings: .constant(false),
            showShareOptions: .constant(false)
        )
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
    }
}
#endif
