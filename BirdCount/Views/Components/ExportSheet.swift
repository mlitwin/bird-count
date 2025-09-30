import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(DateRangeStore.self) private var dateRangeStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var showShareActivityView: Bool = false
    @State private var includeCounts: Bool = false
    @State private var exportFormat: ExportFormat = .summary
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding()
                
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
                
                // Export button
                Button(action: {
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
            .navigationTitle(Strings.Export.format.string)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Strings.General.cancel.string) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareActivityView, onDismiss: {
            // Auto-dismiss the export sheet when share sheet closes
            dismiss()
        }) {
            ShareActivityView(items: shareItems(format: exportFormat, includeCounts: includeCounts))
        }
    }
    
    // MARK: - Export Logic
    
    // Lightweight model to simplify ForEach and type inference
    private struct SpeciesCountItem: Identifiable {
        let id: String // taxon.id
        let taxon: Taxon
        let count: Int
    }
    
    private var speciesInRange: [SpeciesCountItem] {
        // Filter parent observations by range overlap, then use totalCount for each
        let (effStart, effEnd) = effectiveRange
        let filtered = observations.observations.filter { $0.end >= effStart && $0.begin <= effEnd }
        
        // Use totalCount method to handle parent-child hierarchies
        let counts = filtered.reduce(into: [String:Int]()) { acc, r in
            acc[r.taxonId, default: 0] += r.totalCount
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
        let filtered = observations.observations.filter { $0.end >= effStart && $0.begin <= effEnd }
        
        // Flatten to individual observation entries with proper parentId references
        var allObservations: [[String: Any]] = []
        
        func addObservation(_ record: ObservationRecord, parentId: UUID? = nil) {
            var observation: [String: Any] = [
                "id": record.id.uuidString,
                "taxonId": record.taxonId,
                "count": record.count,
                "begin": ISO8601DateFormatter().string(from: record.begin),
                "end": ISO8601DateFormatter().string(from: record.end)
            ]
            
            // Add parentId if this is a child observation
            if let parentId = parentId {
                observation["parentId"] = parentId.uuidString
            }
            
            // Add location if present
            if let location = record.location {
                observation["location"] = [
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                    "horizontalAccuracy": location.horizontalAccuracy,
                    "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
                    "altitude": location.altitude as Any,
                    "verticalAccuracy": location.verticalAccuracy as Any,
                    "name": location.name as Any,
                    "notes": location.notes as Any
                ]
            }
            
            allObservations.append(observation)
            
            // Recursively add children
            for child in record.children {
                addObservation(child, parentId: record.id)
            }
        }
        
        // Process all filtered parent observations
        for record in filtered {
            addObservation(record)
        }
        
        // Create JSON structure suitable for importing
        let exportData: [String: Any] = [
            "metadata": [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "dateRange": [
                    "begin": ISO8601DateFormatter().string(from: effStart),
                    "end": ISO8601DateFormatter().string(from: effEnd)
                ],
                "totalObservations": allObservations.count
            ],
            "observations": allObservations
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            // Log JSON to console for debugging
            print("📄 JSON Export:")
            print(jsonString)
            print("📄 End JSON Export")
            
            return jsonString
        } catch {
            print("❌ JSON Export Error: \(error.localizedDescription)")
            return "{\"error\": \"Failed to serialize JSON: \(error.localizedDescription)\"}"
        }
    }
    
    private func shareItems(format: ExportFormat, includeCounts: Bool = false) -> [Any] {
        let content = exportContent(format: format, includeCounts: includeCounts)
        
        switch format {
        case .summary:
            // For summary text, use simple string sharing
            return [content]
        case .json:
            // For JSON, create a temporary file with proper .json extension
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let filename = "bird-observations-\(dateString).json"
            
            return [TemporaryFileItem(
                content: content,
                filename: filename,
                utType: .json
            )]
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

#if DEBUG
#Preview {
    ExportSheet()
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(DateRangeStore())
}
#endif