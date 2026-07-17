import SwiftUI

struct ObservationRecordView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(SettingsStore.self) private var settings
    let record: ObservationRecord
    @State private var showDetails: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taxon?.commonName ?? taxon?.id ?? "Unknown")
                HStack(spacing: 4) {
                    Text(dateRangeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Trails into free space on the caption line: showing or
                    // hiding it never shifts the rest of the row. Filled =
                    // includes the current user's observations; outline =
                    // entirely from synced users.
                    if let symbol = attribution.symbolName {
                        Image(systemName: symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                attribution.includesCurrentUser
                                    ? Strings.Sync.includesSynced.string
                                    : Strings.Sync.fromSyncedUsers.string
                            )
                    }
                }
                if let location = record.location, location.isValid {
                    Text(location.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // Always show count; use recursive total including children
            Text("×\(totalCount)")
                .font(.subheadline.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
                .accessibilityLabel("Count \(totalCount)")
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetails = true }
        .sheet(isPresented: $showDetails) {
            ObservationDetailsSheet(record: record)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var taxon: Taxon? { taxonomy.taxon(id: record.taxonId) }

    /// Who contributed to this record (including adjustment children).
    private var attribution: ObserverAttribution {
        ObserverAttribution(observers: record.observers(), currentObserver: settings.loginEmail)
    }

    private var dateRangeString: String {
        if record.begin == record.end {
            return record.begin.formatted(date: .abbreviated, time: .shortened)
        } else {
            let start = record.begin.formatted(date: .abbreviated, time: .shortened)
            let end = record.end.formatted(date: .abbreviated, time: .shortened)
            return "\(start) – \(end)"
        }
    }

    private var accessibilityLabel: String {
        let name = taxon?.commonName ?? "Unknown species"
        if record.begin == record.end {
            let dt = DateFormatter.localizedString(from: record.begin, dateStyle: .medium, timeStyle: .short)
            return "\(name) at \(dt)"
        } else {
            let start = DateFormatter.localizedString(from: record.begin, dateStyle: .medium, timeStyle: .short)
            let end = DateFormatter.localizedString(from: record.end, dateStyle: .medium, timeStyle: .short)
            return "\(name) from \(start) to \(end)"
        }
    }

    // MARK: - Totals
    private var totalCount: Int { record.totalCount }
}
