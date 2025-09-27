import SwiftUI

struct SpeciesRow: View {
    let taxon: Taxon
    let count: Int
    let onSelect: (Taxon) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                SpeciesRowBasic(taxon: taxon)
                if let c = taxon.commonness {
                    Text(commonnessLabel(c))
                        .font(.footnote)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)))
                }
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                        .accessibilityLabel(String(format: Strings.Accessibility.countLabel.string, taxon.commonName, count))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(taxon) }
            .padding(.horizontal)
            .padding(.vertical, 8)
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
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func commonnessLabel(_ c: Int) -> String {
    switch c { 
    case 0: return "R"
    case 1: return "S"
    case 2: return "U"
    case 3: return "C"
    default: return ""
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
        onSelect: { _ in }
    )
    .padding()
}
#endif