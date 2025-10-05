import SwiftUI

private struct SpeciesListContent: View {
    let taxa: [Taxon]
    let counts: [String: Int]
    let recentlyUpdatedSpeciesId: String?
    let showPulseAnimation: Bool
    let onSelect: (Taxon) -> Void
    let minHeight: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            LazyVStack(spacing: 6) {
                ForEach(taxa) { taxon in
                    SpeciesRow(
                        taxon: taxon,
                        count: counts[taxon.id] ?? 0,
                        shouldPulse: recentlyUpdatedSpeciesId == taxon.id && showPulseAnimation,
                        onSelect: onSelect
                    )
                    .id(taxon.id)
                }
            }
            // Fallback anchor when list is empty
            Color.clear.frame(height: 1).id("__species_bottom_anchor__")
        }
        .frame(minHeight: minHeight, alignment: .bottom)
    }
}

struct SpeciesListView: View {
    let taxa: [Taxon]
    let counts: [String:Int]
    let onSelect: (Taxon) -> Void
    // External trigger: increment to request scrolling to the bottom
    let scrollToBottomSignal: Int
    // External trigger: species ID that was recently updated (for pulse animation)
    let recentlyUpdatedSpeciesId: String?
    
    @State private var showPulseAnimation = false
    @State private var scrolledToID: AnyHashable? = nil

    init(taxa: [Taxon], counts: [String:Int] = [:], scrollToBottomSignal: Int = 0, recentlyUpdatedSpeciesId: String? = nil, onSelect: @escaping (Taxon) -> Void) {
        self.taxa = taxa
        self.counts = counts
        self.scrollToBottomSignal = scrollToBottomSignal
        self.recentlyUpdatedSpeciesId = recentlyUpdatedSpeciesId
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView {
                    SpeciesListContent(
                        taxa: taxa,
                        counts: counts,
                        recentlyUpdatedSpeciesId: recentlyUpdatedSpeciesId,
                        showPulseAnimation: showPulseAnimation,
                        onSelect: onSelect,
                        minHeight: proxy.size.height
                    )
                }
                .defaultScrollAnchor(.bottom)
                .scrollPosition(id: $scrolledToID, anchor: .bottom)
                .onChange(of: scrollToBottomSignal) { _, newSignal in
                    let targetId: AnyHashable = taxa.last?.id ?? "__species_bottom_anchor__"
                    print("📊 SpeciesListView: Scroll signal changed to \(newSignal), targeting \(targetId)")
                    
                    // Immediate scroll (no animation)
                    reader.scrollTo(targetId, anchor: .bottom)
                }
                // Removed scroll completion detection - using immediate approach instead
                // Keep bottom alignment when the data set changes (e.g., clearing filters)
                .onChange(of: taxa.map { $0.id }) { _, newIds in
                    let targetId: AnyHashable = newIds.last ?? "__species_bottom_anchor__"
                    // Defer until after layout to ensure the last row exists
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.5)) {
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
                .onChange(of: recentlyUpdatedSpeciesId) { _, newValue in
                    if newValue != nil {
                        print("✨ SpeciesListView: Species \(newValue!) updated - starting pulse animation")
                        // Start the pulse animation immediately
                        showPulseAnimation = true
                        
                        // Auto-fade after a fixed duration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            print("🎭 SpeciesListView: Auto-fading pulse for species \(newValue!)")
                            showPulseAnimation = false
                        }
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }
}
