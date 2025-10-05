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
                                .stroke(Color.green.opacity(0.8), lineWidth: isPulsing ? 2 : 0)
                                .animation(.easeOut(duration: 0.5), value: isPulsing)
                        )
                        .accessibilityLabel(String(format: Strings.Accessibility.countLabel.string, taxon.commonName, count))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(taxon) }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(isPulsing ? 0.15 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.8), lineWidth: isPulsing ? 2 : 0)
            )
                    .onChange(of: shouldPulse) { _, newValue in
            if newValue {
                // Quick fade-in (0.3 seconds)
                withAnimation(.easeIn(duration: 0.3)) {
                    isPulsing = true
                }
                
                // Slow fade-out after delay (1.7 seconds after fade-in completes)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 1.7)) {
                        isPulsing = false
                    }
                }
            } else {
                isPulsing = false
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