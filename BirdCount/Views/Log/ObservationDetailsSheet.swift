import SwiftUI

struct ObservationDetailsSheet: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    let record: ObservationRecord
    @Environment(\.dismiss) private var dismiss
    
    private var taxon: Taxon? { 
        taxonomy.species.first { $0.id == record.taxonId }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main Species Information
                    SpeciesHeader(taxon: taxon, record: record)
                    
                    Divider()
                    
                    // Observation Details
                    ObservationDetailsSection(record: record)
                    
                    Divider()
                    
                    // Location Information
                    LocationDetailsSection(record: record)
                    
                    Divider()
                    
                    // Child Observations
                    ChildObservationsSection(record: record, taxonomy: taxonomy)
                    
                    Divider()
                    
                    // Summary Statistics
                    SummarySection(record: record)
                }
                .padding()
            }
            .navigationTitle(Strings.Observation.details.string)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.close.string) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct SpeciesHeader: View {
    let taxon: Taxon?
    let record: ObservationRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(taxon?.commonName ?? record.taxonId)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let taxon = taxon {
                        Text(taxon.scientificName)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Total count badge
                Text("×\(recursiveCount(record))")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2))
            }
            
            if let taxon = taxon, let commonness = taxon.commonness {
                CommonnessLabel(commonness: commonness)
            }
        }
    }
}

private struct ObservationDetailsSection: View {
    let record: ObservationRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observation Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            DetailRow(label: "Date & Time", value: formattedDateTime)
            DetailRow(label: "Duration", value: formattedDuration)
            DetailRow(label: "Direct Count", value: "\(record.count)")
            DetailRow(label: "Record ID", value: record.id.uuidString.prefix(8) + "...")
        }
    }
    
    private var formattedDateTime: String {
        if record.begin == record.end {
            return record.begin.formatted(date: .abbreviated, time: .standard)
        } else {
            let start = record.begin.formatted(date: .abbreviated, time: .shortened)
            let end = record.end.formatted(date: .abbreviated, time: .shortened)
            return "\(start) – \(end)"
        }
    }
    
    private var formattedDuration: String {
        if record.begin == record.end {
            return "Instant"
        } else {
            let duration = record.end.timeIntervalSince(record.begin)
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }
}

private struct LocationDetailsSection: View {
    let record: ObservationRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let location = record.location, location.isValid {
                DetailRow(label: "Name", value: location.displayName)
                DetailRow(label: "Coordinates", value: location.formattedCoordinates())
                DetailRow(label: "Accuracy", value: "\(location.accuracyDescription) (±\(Int(location.horizontalAccuracy))m)")
                
                if let altitude = location.altitude {
                    DetailRow(label: "Altitude", value: "\(Int(altitude))m")
                }
                
                DetailRow(label: "Recorded", value: location.timestamp.formatted(date: .omitted, time: .standard))
                
                if let notes = location.notes, !notes.isEmpty {
                    DetailRow(label: "Notes", value: notes)
                }
            } else {
                Text("No location data available")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}

private struct ChildObservationsSection: View {
    let record: ObservationRecord
    let taxonomy: TaxonomyStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Child Observations")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(record.children.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))
            }
            
            if record.children.isEmpty {
                Text("No child observations")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(record.children) { child in
                    ChildObservationRow(child: child, taxonomy: taxonomy)
                }
            }
        }
    }
}

private struct ChildObservationRow: View {
    let child: ObservationRecord
    let taxonomy: TaxonomyStore
    
    private var taxon: Taxon? {
        taxonomy.species.first { $0.id == child.taxonId }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(taxon?.commonName ?? child.taxonId)
                    .font(.subheadline)
                
                Text(child.begin.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(child.count > 0 ? "+" : "")\(child.count)")
                .font(.subheadline.monospacedDigit())
                .fontWeight(.medium)
                                            .foregroundStyle(child.count >= 0 ? .primary : Color.red)
        }
        .padding(.vertical, 4)
    }
}

private struct SummarySection: View {
    let record: ObservationRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            let totalCount = recursiveCount(record)
            let childCount = record.children.count
            let adjustments = record.children.filter { $0.count != 0 }.count
            
            DetailRow(label: "Total Count", value: "\(totalCount)")
            DetailRow(label: "Child Records", value: "\(childCount)")
            DetailRow(label: "Count Adjustments", value: "\(adjustments)")
            
            if childCount > 0 {
                let positiveAdjustments = record.children.filter { $0.count > 0 }.reduce(0) { $0 + $1.count }
                let negativeAdjustments = record.children.filter { $0.count < 0 }.reduce(0) { $0 + $1.count }
                
                if positiveAdjustments > 0 {
                    DetailRow(label: "Added", value: "+\(positiveAdjustments)", valueColor: .green)
                }
                
                if negativeAdjustments < 0 {
                    DetailRow(label: "Removed", value: "\(negativeAdjustments)", valueColor: .red)
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct CommonnessLabel: View {
    let commonness: Int
    
    var body: some View {
        Text(commonnessDescription)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(commonnessColor.opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(commonnessColor, lineWidth: 1))
    }
    
    private var commonnessDescription: String {
        switch commonness {
        case 0: return "Very Rare"
        case 1: return "Rare"
        case 2: return "Uncommon"
        case 3: return "Common"
        case 4: return "Very Common"
        default: return "Unknown"
        }
    }
    
    private var commonnessColor: Color {
        switch commonness {
        case 0: return .purple
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        default: return .gray
        }
    }
}

// MARK: - Helper Functions

private func recursiveCount(_ record: ObservationRecord) -> Int {
    record.count + record.children.map { recursiveCount($0) }.reduce(0, +)
}

// MARK: - Preview

#if DEBUG
#Preview {
    let mockRecord = ObservationRecord(
        id: UUID(),
        taxonId: "amecro",
        begin: Date().addingTimeInterval(-3600),
        end: Date(),
        count: 3,
        location: ObservationLocation.mock()
    )
    
    ObservationDetailsSheet(record: mockRecord)
        .environment(TaxonomyStore())
}
#endif
