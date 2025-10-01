import SwiftUI

struct SpeciesRow: View {
    let taxon: Taxon
    let count: Int
    let shouldPulse: Bool
    let onSelect: (Taxon) -> Void
    
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                SpeciesRowBasic(taxon: taxon)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    Color.green,
                                    lineWidth: isPulsing ? 2 : 0
                                )
                                .opacity(isPulsing ? 1 : 0)
                                .animation(.easeInOut(duration: 1.0), value: isPulsing)
                        )
                        .accessibilityLabel(String(format: Strings.Accessibility.countLabel.string, taxon.commonName, count))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(taxon) }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onChange(of: shouldPulse) { _, newValue in
                if newValue {
                    isPulsing = true
                    // Stop pulsing after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Single 1.0s ease cycle
                        isPulsing = false
                    }
                }
            }
            Divider()
        }
    }
}

private struct SpeciesRowBasic: View {
    let taxon: Taxon
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(taxon.commonName)
                    .font(.title3.weight(.semibold))
                Text(taxon.scientificName)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
            }
        }
    }
}

#if DEBUG
#Preview("Species Row with count") {
    SpeciesRow(
        taxon: Taxon(
            id: "sample-id",
            commonName: "American Robin",
            scientificName: "Turdus migratorius",
            order: 1,
            rank: "species",
            commonness: 3
        ),
        count: 5,
        shouldPulse: false,
        onSelect: { _ in }
    )
    .padding()
}

#Preview("Species Row without count") {
    SpeciesRow(
        taxon: Taxon(
            id: "sample-id-2",
            commonName: "Rare Warbler",
            scientificName: "Setophaga rara",
            order: 2,
            rank: "species",
            commonness: 0
        ),
        count: 0,
        shouldPulse: false,
        onSelect: { _ in }
    )
    .padding()
}

#Preview("Species Row with pulse") {
    SpeciesRow(
        taxon: Taxon(
            id: "sample-id-3",
            commonName: "Pulsing Warbler",
            scientificName: "Setophaga pulsans",
            order: 3,
            rank: "species",
            commonness: 1
        ),
        count: 2,
        shouldPulse: true,
        onSelect: { _ in }
    )
    .padding()
}
#endif