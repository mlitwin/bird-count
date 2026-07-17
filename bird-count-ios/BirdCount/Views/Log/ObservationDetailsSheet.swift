import SwiftUI

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
        taxonomy.taxon(id: record.taxonId)
    }

    var body: some View {
        // Resolve once per render: findRecord walks the whole observation tree
        // and copies the record's subtree, so don't repeat it per section.
        let current = currentRecord
        let taxon = self.taxon
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main Species Information
                    SpeciesHeader(taxon: taxon, record: current)

                    Divider()

                    // Observation Details
                    ObservationDetailsSection(record: current, onEditCount: { showCountAdjust = true })

                    Divider()

                    // Location Information
                    LocationDetailsSection(record: current, onSearchStateChanged: nil)

                    Divider()

                    // Child Observations
                    ChildObservationsSection(record: current, taxonomy: taxonomy)

                    Divider()

                    // Summary Statistics
                    SummarySection(record: current)
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
        taxonomy.taxon(id: child.taxonId)
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

    // Single pass over children instead of separate filter/reduce passes
    private var stats: (adjustments: Int, added: Int, removed: Int) {
        record.children.reduce(into: (adjustments: 0, added: 0, removed: 0)) { acc, child in
            if child.count != 0 { acc.adjustments += 1 }
            if child.count > 0 { acc.added += child.count }
            if child.count < 0 { acc.removed += child.count }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)
                .fontWeight(.semibold)

            let childCount = record.children.count
            let stats = self.stats

            DetailRow(label: "Total Count", value: "\(record.totalCount)")
            DetailRow(label: "Child Records", value: "\(childCount)")
            DetailRow(label: "Count Adjustments", value: "\(stats.adjustments)")

            if childCount > 0 {
                if stats.added > 0 {
                    DetailRow(label: "Added", value: "+\(stats.added)", valueColor: .green)
                }

                if stats.removed < 0 {
                    DetailRow(label: "Removed", value: "\(stats.removed)", valueColor: .red)
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
