import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observations
    @State private var scrollToBottomSignal: Int = 0
    @Environment(SettingsStore.self) private var settings
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var filterText: String = ""
    @State private var selectedTaxon: Taxon? = nil
    @State private var bottomControlsHeight: CGFloat = 0
    @State private var sheetContentHeight: CGFloat = 0
    @State private var filterFocused: Bool = false
    // Keep CountAdjustSheet aligned with SpeciesListView bottom
    private let speciesListBottomPadding: CGFloat = 48

    private var filtered: [Taxon] { taxonomy.search(filterText, minCommonness: settings.selectedChecklistId != nil ? settings.minCommonness : nil, maxCommonness: settings.selectedChecklistId != nil ? settings.maxCommonness : nil, dateRange: dateRangeStore.dateRange) }

    private var filteredCounts: [String: Int] {
        ObservationStoreCache.countsInRange(dateRangeStore.dateRange, from: observations.observations)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let checklistErr = taxonomy.checklistError {
                    Text(checklistErr)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                }
                Group { content }
                // Bottom controls (FilterBar + Keyboard) measured dynamically for sheet positioning
                VStack(spacing: 0) {
                    Divider()
                    FilterBar(
                        text: filterText,
                        onClear: { filterText = ""; filterFocused = false },
                        active: (filterFocused || !filterText.isEmpty)
                    )
                        .onTapGesture { filterFocused = true }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    Divider()
                    OnScreenKeyboard(
                        onKey: { filterText.append($0); filterFocused = true },
                        onBackspace: {
                            if !filterText.isEmpty { _ = filterText.removeLast() }
                            filterFocused = !filterText.isEmpty
                        },
                        onClear: { filterText = ""; filterFocused = false },
                        active: (filterFocused || !filterText.isEmpty)
                    )
                        .padding(.bottom, 8)
                        .background(.thinMaterial)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: BottomControlsHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(BottomControlsHeightKey.self) { bottomControlsHeight = $0 }
                // If the filter text becomes empty (via clear or programmatic), deactivate the visual focus state
                .onChange(of: filterText) { _, newValue in
                    if newValue.isEmpty { filterFocused = false }
                }
            }
            
            // Hide the nav bar entirely so it doesn't reserve space at the top
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear { ObservationStoreProxy.shared.register(observations) }
            .onChange(of: settings.selectedChecklistId) { _, newId in
                if let id = newId { taxonomy.loadChecklist(id: id) }
            }
            .task {
                if let id = settings.selectedChecklistId { taxonomy.loadChecklist(id: id) }
            }
            // No range-based recompute here
            // Present CountAdjustSheet as a custom bottom overlay, shifted up by the bottom controls height
            .overlay(alignment: .bottom) {
                if let taxon = selectedTaxon {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        selectedTaxon = nil
                                        filterFocused = false
                                    }
                                }

                            VStack(spacing: 0) {
                                CountAdjustSheet(
                                    taxon: taxon,
                                    onDone: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selectedTaxon = nil }
                                    },
                                    onCommitted: { didAdd in
                                        if didAdd {
                                            filterText = ""
                                            // Trigger scroll to bottom so newest/recent species are visible
                                            scrollToBottomSignal &+= 1
                                        }
                                    }
                                )
                                // Measure intrinsic height of the sheet's content
                                .background(
                                    GeometryReader { sheetGeo in
                                        Color.clear
                                            .preference(key: SheetContentHeightKey.self, value: sheetGeo.size.height)
                                    }
                                )
                            }
                            .onPreferenceChange(SheetContentHeightKey.self) { sheetContentHeight = $0 }
                            .frame(maxWidth: .infinity)
                            // Height equals content height
                            .frame(height: max(sheetContentHeight, 1))
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(radius: 10)
                            .padding(.horizontal, 12)
                            .padding(.bottom, bottomControlsHeight + speciesListBottomPadding)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .ignoresSafeArea()
                    }
                }
            }
            .zIndex(selectedTaxon != nil ? 1 : 0)
        }
    }

    @ViewBuilder private var content: some View {
        if let error = taxonomy.error {
            VStack(spacing: 0) {
                HeaderSpacingView()
                ContentUnavailableView(Strings.General.error.string, systemImage: "exclamationmark.triangle", description: Text(error))
            }
        } else if !taxonomy.loaded {
            VStack(spacing: 0) {
                HeaderSpacingView()
                ProgressView(Strings.Home.loading.string)
                    .task { taxonomy.load() }
            }
        } else if taxonomy.species.isEmpty {
            VStack(spacing: 0) {
                HeaderSpacingView()
                ContentUnavailableView(Strings.Species.List.empty.string, systemImage: "bird", description: Text(Strings.Species.List.emptyDescription.string))
            }
        } else {
            SpeciesListView(
                taxa: filtered, 
                counts: filteredCounts,
                scrollToBottomSignal: scrollToBottomSignal
            ) { taxon in
                selectedTaxon = taxon
            }
        }
    }
}

// PreferenceKey for measuring bottom controls height dynamically
private struct BottomControlsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = Swift.max(value, nextValue())
    }
}

// PreferenceKey for the sheet content height
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

    

// MARK: - Filter Bar

private struct FilterBar: View {
    let text: String
    let onClear: () -> Void
    var active: Bool = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? Strings.Home.Filter.placeholder.string : text)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel(Strings.Home.Filter.clear.string)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(active ? 0.16 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(active ? 0.6 : 0.3), lineWidth: 1)
        )
    }
}


#if DEBUG
private extension TaxonomyStore {
    static var previewInstance: TaxonomyStore {
        let store = TaxonomyStore()
        store.loadPreview(species: [
            Taxon(id: "amecro", commonName: "American Crow", scientificName: "Corvus brachyrhynchos", order: 1, rank: "species", commonness: 3),
            Taxon(id: "norbla", commonName: "Northern Blackbird", scientificName: "Inventus fictus", order: 2, rank: "species", commonness: 1),
            Taxon(id: "bkhawk", commonName: "Black Hawk", scientificName: "Buteogallus anthracinus", order: 3, rank: "species", commonness: 0)
        ])
        return store
    }
}
#endif

#if DEBUG
#Preview("Home") {
    HomeView()
        .environment(TaxonomyStore.previewInstance)
        .environment(ObservationStore.previewInstance)
        .environment(SettingsStore())
        .environment(DateRangeStore())
        .environment(SyncSessionManager())
}
#endif
