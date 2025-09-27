import SwiftUI

struct SpeciesListView: View {
    let taxa: [Taxon]
    let counts: [String:Int]
    let onSelect: (Taxon) -> Void
    // External trigger: increment to request scrolling to the bottom
    let scrollToBottomSignal: Int

    init(taxa: [Taxon], counts: [String:Int] = [:], scrollToBottomSignal: Int = 0, onSelect: @escaping (Taxon) -> Void) {
        self.taxa = taxa
        self.counts = counts
        self.scrollToBottomSignal = scrollToBottomSignal
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 6) {
                            ForEach(taxa) { taxon in
                                SpeciesRow(
                                    taxon: taxon,
                                    count: counts[taxon.id] ?? 0,
                                    onSelect: onSelect
                                )
                                .id(taxon.id)
                            }
                        }
                        // Fallback anchor when list is empty
                        Color.clear.frame(height: 1).id("__species_bottom_anchor__")
                    }
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: scrollToBottomSignal) { _, _ in
                    let targetId: AnyHashable = taxa.last?.id ?? "__species_bottom_anchor__"
                    withAnimation(.easeOut(duration: 0.2)) {
                        reader.scrollTo(targetId, anchor: .bottom)
                    }
                }
                // Keep bottom alignment when the data set changes (e.g., clearing filters)
                .onChange(of: taxa.map { $0.id }) { _, newIds in
                    let targetId: AnyHashable = newIds.last ?? "__species_bottom_anchor__"
                    // Defer until after layout to ensure the last row exists
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            reader.scrollTo(targetId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Ensure initial positioning at bottom
                    DispatchQueue.main.async {
                        let targetId: AnyHashable = taxa.last?.id ?? "__species_bottom_anchor__"
                        reader.scrollTo(targetId, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }
}
