import SwiftUI

struct ObservationRecordView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(SettingsStore.self) private var settings
    let record: ObservationRecord
    var onTap: (() -> Void)? = nil
    var onBadgeTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(taxon?.commonName ?? record.taxonId)
                        .font(.title3.weight(.semibold))
                    Text(dateRangeString)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.8))
                }
                Spacer()
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
                Button {
                    onBadgeTap?()
                } label: {
                    CountBadge(count: totalCount)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Count \(totalCount), tap to adjust")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }

            Divider()
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
