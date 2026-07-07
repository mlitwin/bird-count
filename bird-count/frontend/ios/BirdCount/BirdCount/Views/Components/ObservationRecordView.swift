import SwiftUI

struct ObservationRecordView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    let record: ObservationRecord
    @State private var showAdjust: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taxon?.commonName ?? taxon?.id ?? "Unknown")
                Text(dateRangeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if record.count > 1 {
                Text("×\(record.count)")
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
                    .accessibilityLabel("Count \(record.count)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showAdjust = true }
        .sheet(isPresented: $showAdjust) {
            if let taxon = taxon {
                CountAdjustSheet(taxon: taxon) { showAdjust = false }
            } else {
                // Fallback: dismiss if taxon not found
                Color.clear.onAppear { showAdjust = false }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var taxon: Taxon? { taxonomy.species.first { $0.id == record.taxonId } }

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
}
