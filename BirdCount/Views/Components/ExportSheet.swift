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

    /// Returns a display string for the active date range, with first letter lowercased for presets
    private var rangeSummaryForExport: String {
        let preset = dateRangeStore.dateRangePreset
        let startDate = dateRangeStore.dateRange.begin
        let endDate = dateRangeStore.dateRange.end

        // For presets, return the preset name with first letter lowercased
        switch preset {
        case .all:
            return Strings.DateRange.allTime.string.lowercasingFirst
        case .today:
            return Strings.DateRange.today.string.lowercasingFirst
        case .lastHour, .last7Days:
            return preset.rawValue.lowercased()
        case .custom:
            break
        }

        // Custom range: format the date range
        let cal = Calendar.current
        let sameDay = cal.isDate(startDate, inSameDayAs: endDate)

        // Check if this is a complete day (starts at midnight, ends at midnight next day)
        let isCompleteDay = cal.isDate(startDate, equalTo: cal.startOfDay(for: startDate), toGranularity: .second) &&
                           cal.isDate(endDate, equalTo: cal.startOfDay(for: endDate), toGranularity: .second) &&
                           cal.dateInterval(of: .day, for: startDate)?.end == endDate

        if isCompleteDay {
            return ExportFormatters.mdy.string(from: startDate)
        }

        let sameYear = cal.component(.year, from: startDate) == cal.component(.year, from: endDate)
        let sameMonth = sameYear && cal.component(.month, from: startDate) == cal.component(.month, from: endDate)

        let startHM = ExportFormatters.hm.string(from: startDate)
        let endHM = ExportFormatters.hm.string(from: endDate)

        if sameDay {
            return "\(ExportFormatters.mdy.string(from: startDate)) \(startHM) – \(endHM)"
        } else if sameMonth {
            let startMD = ExportFormatters.md.string(from: startDate)
            let endD = String(cal.component(.day, from: endDate))
            return "\(startMD) \(startHM) – \(endD) \(endHM)"
        } else if sameYear {
            let startMD = ExportFormatters.md.string(from: startDate)
            let endMD = ExportFormatters.md.string(from: endDate)
            return "\(startMD) \(startHM) – \(endMD) \(endHM)"
        } else {
            let startMDY = ExportFormatters.mdy.string(from: startDate)
            let endMDY = ExportFormatters.mdy.string(from: endDate)
            return "\(startMDY) \(startHM) – \(endMDY) \(endHM)"
        }
    }

    private func exportText(includeCounts: Bool = false) -> String {
        let species = speciesInRange
        var lines: [String] = []
        lines.append("\(species.count) \(Strings.Species.species.string) \(rangeSummaryForExport)")
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
    
    private var exportSubject: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: Date())
        return String(format: Strings.Export.subject.string, dateString)
    }

    private func shareItems(format: ExportFormat, includeCounts: Bool = false) -> [Any] {
        let content = exportContent(format: format, includeCounts: includeCounts)
        let subject = exportSubject

        switch format {
        case .summary:
            // For summary text, use TextShareItem to support subject line (e.g., email)
            return [TextShareItem(content: content, subject: subject)]
        case .json:
            // For JSON, create a temporary file with proper .json extension
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            let filename = "bird-observations-\(dateString).json"

            return [TemporaryFileItem(
                content: content,
                filename: filename,
                utType: .json,
                subject: subject
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

// MARK: - Date Formatters for Export

private enum ExportFormatters {
    static let hm: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()
    static let md: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMd")
        return df
    }()
    static let mdy: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return df
    }()
}

// MARK: - String Extension for Lowercasing First Character

private extension String {
    var lowercasingFirst: String {
        guard let first = self.first else { return self }
        return first.lowercased() + self.dropFirst()
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