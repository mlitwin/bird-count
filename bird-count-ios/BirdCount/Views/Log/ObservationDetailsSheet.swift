import SwiftUI
import MapKit

struct ObservationDetailsSheet: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observationStore
    let record: ObservationRecord
    @Environment(\.dismiss) private var dismiss
    @State private var showCountAdjust: Bool = false
    
    // Get the current version of the record from the store to reflect updates
    private var currentRecord: ObservationRecord {
        observationStore.findRecord(by: record.id) ?? record
    }
    
    private var taxon: Taxon? { 
        taxonomy.species.first { $0.id == currentRecord.taxonId }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main Species Information
                    SpeciesHeader(taxon: taxon, record: currentRecord)
                    
                    Divider()
                    
                    // Observation Details
                    ObservationDetailsSection(record: currentRecord, onEditCount: { showCountAdjust = true })
                    
                    Divider()
                    
                    // Location Information
                    LocationDetailsSection(record: currentRecord, onSearchStateChanged: nil)
                    
                    Divider()
                    
                    // Child Observations
                    ChildObservationsSection(record: currentRecord, taxonomy: taxonomy)
                    
                    Divider()
                    
                    // Summary Statistics
                    SummarySection(record: currentRecord)
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
        .sheet(isPresented: $showCountAdjust) {
            if let taxon = taxon {
                CountAdjustSheet(taxon: taxon, parentId: record.id, onDone: { showCountAdjust = false })
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
                Text("×\(record.totalCount)")
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
    let onEditCount: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observation Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            DetailRow(label: "Date & Time", value: formattedDateTime)
            DetailRow(label: "Duration", value: formattedDuration)
            
            // Total Count with edit button
            DetailRowWithAction(
                label: "Total Count",
                value: "\(record.totalCount)",
                actionIcon: "pencil",
                action: onEditCount
            )
            
            // Status
            DetailRow(label: Strings.Observation.status.string, value: statusText, valueColor: statusColor)
            
            // Observer field - show only if not empty
            if !record.observer.isEmpty {
                DetailRow(label: Strings.Observation.observer.string, value: record.observer)
            }
            
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
    
    private var statusText: String {
        switch record.status {
        case .pending:
            return Strings.Observation.Status.pending.string
        case .completed:
            return Strings.Observation.Status.completed.string
        }
    }
    
    private var statusColor: Color {
        switch record.status {
        case .pending:
            return .orange
        case .completed:
            return .green
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
            
            // Direct count (non-editable)
            DetailRow(label: "Direct Count", value: "\(record.count)")
            
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
            
            let totalCount = record.totalCount
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

private struct LocationMapView: View {
    let location: ObservationLocation
    
    @State private var cameraPosition: MapCameraPosition
    
    init(location: ObservationLocation) {
        self.location = location
        
        // Initialize camera position centered on the location
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        
        // Set zoom level based on accuracy - less accurate locations get zoomed out more
        let span: MKCoordinateSpan
        if location.horizontalAccuracy <= 50 {
            span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Close zoom for accurate locations
        } else if location.horizontalAccuracy <= 200 {
            span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) // Medium zoom
        } else {
            span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05) // Wider zoom for less accurate locations
        }
        
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            // Location pin
            Annotation("Observation Location", coordinate: coordinate) {
                LocationPin()
            }
            
            // Accuracy circle if accuracy is reasonable to show
            if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 1000 {
                MapCircle(center: coordinate, radius: location.horizontalAccuracy)
                    .foregroundStyle(.blue.opacity(0.2))
                    .stroke(.blue.opacity(0.5), lineWidth: 1)
            }
        }
        .mapStyle(.standard)
        .mapControlVisibility(.hidden) // Hide default controls for cleaner look in details view
    }
    
    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
}

private struct LocationPin: View {
    var body: some View {
        ZStack {
            // Pin shadow
            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: 20, height: 20)
                .offset(x: 1, y: 1)
            
            // Pin background
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(.gray.opacity(0.3), lineWidth: 1)
                )
            
            // Pin center (bird icon color)
            Circle()
                .fill(.blue)
                .frame(width: 12, height: 12)
        }
    }
}

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

private struct DetailRowWithAction: View {
    let label: String
    let value: String
    let actionIcon: String
    let action: () -> Void
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(value)
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
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

// MARK: - Preview

#if DEBUG
#Preview {
    let mockLocation = ObservationLocation(
        latitude: 37.7749,
        longitude: -122.4194,
        horizontalAccuracy: 5.0,
        timestamp: Date().addingTimeInterval(-300),
        altitude: 100,
        verticalAccuracy: 3.0,
        name: "Golden Gate Park",
        notes: "Near the Japanese Tea Garden"
    )
    
    let mockRecord = ObservationRecord(
        id: UUID(),
        taxonId: "amecro",
        begin: Date().addingTimeInterval(-3600),
        end: Date(),
        count: 3,
        location: mockLocation
    )
    
    ObservationDetailsSheet(record: mockRecord)
        .environment(TaxonomyStore())
        .environment(ObservationStore())
}
#endif
