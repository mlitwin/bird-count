import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observations
    @Environment(AppNavigationState.self) private var navState
    @Environment(SettingsStore.self) private var settings
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var scrollToBottomSignal: Int = 0
    @State private var filterText: String = ""
    @State private var selectedTaxon: Taxon? = nil
    @State private var speciesLogTaxon: Taxon? = nil
    @State private var bottomControlsHeight: CGFloat = 0
    @State private var sheetContentHeight: CGFloat = 0
    @State private var filterFocused: Bool = false
    @State private var pulseState = PulseAnimationState()
    #if DEBUG
    @Environment(DebugTestHook.self) private var debugTestHook
    #endif
    private let speciesListBottomPadding: CGFloat = 48

    /// Shared by the real quick-add swipe and the DEBUG-only external test
    /// hook (see DebugTestHook) so both exercise the identical mutation +
    /// scroll + pulse path.
    private func performAdd(taxonId: String) {
        observations.addObservationWithLocation(taxonId, count: 1)
        didAddObservation(taxonId: taxonId)
    }

    /// The single post-add UI path (quick-add, count sheet, debug hook):
    /// clear the filter, pulse the row, and ask the list to show the bottom.
    /// The request is unconditional — with a filter active, clearing it also
    /// rebuilds the list (content-set change), and BottomAnchoredScrollView
    /// treats both signals the same way. Keeping one path matters: the
    /// filter-only path once skipped the scroll request and hid a bug.
    private func didAddObservation(taxonId: String) {
        filterText = ""
        pulseState.trigger(speciesId: taxonId)
        scrollToBottomSignal &+= 1
    }

    private var filtered: [Taxon] {
        taxonomy.search(
            filterText,
            minCommonness: settings.selectedChecklistId != nil ? settings.minCommonness : nil,
            maxCommonness: settings.selectedChecklistId != nil ? settings.maxCommonness : nil,
            dateRange: dateRangeStore.dateRange
        )
    }

    private var filteredCounts: [String: Int] {
        ObservationStoreCache.countsInRange(dateRangeStore.dateRange, from: observations.observations)
    }

    private var syncAttributions: [String: ObserverAttribution] {
        ObservationStoreCache.observersByTaxon(
            in: dateRangeStore.dateRange,
            from: observations.observations
        ).compactMapValues { observers in
            let attribution = ObserverAttribution(observers: observers, currentObserver: settings.loginEmail)
            return attribution == .mine ? nil : attribution
        }
    }

    private var taxaWithEntriesIds: Set<String> {
        let range = dateRangeStore.dateRange
        return Set(observations.observations.filter {
            $0.end >= range.begin && $0.begin <= range.end
        }.map { $0.taxonId })
    }

    private var undoableTaxonIds: Set<String> {
        let range = dateRangeStore.dateRange
        return Set(observations.observations.filter {
            $0.observer == settings.loginEmail &&
            $0.totalCount > 0 &&
            $0.end >= range.begin &&
            $0.begin <= range.end
        }.map { $0.taxonId })
    }

    private func undoTaxon(_ taxon: Taxon) {
        let range = dateRangeStore.dateRange
        guard let rec = observations.observations
            .filter({
                $0.taxonId == taxon.id &&
                $0.observer == settings.loginEmail &&
                $0.totalCount > 0 &&
                $0.end >= range.begin &&
                $0.begin <= range.end
            })
            .sorted(by: { $0.begin > $1.begin })
            .first
        else { return }
        _ = observations.addChildObservationWithLocation(parentId: rec.id, taxonId: rec.taxonId, begin: Date(), end: nil, count: -rec.totalCount)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                .onChange(of: filterText) { _, newValue in
                    if newValue.isEmpty { filterFocused = false }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            #if DEBUG
            .onChange(of: debugTestHook.pendingAddTaxonId) { _, newValue in
                guard let taxonId = newValue else { return }
                debugTestHook.pendingAddTaxonId = nil
                DiagnosticsLog.log(.sync, "Debug hook: performing addObservation for taxonId=\(taxonId)")
                performAdd(taxonId: taxonId)
            }
            #endif
            .onAppear { ObservationStoreProxy.shared.register(observations) }
            .onChange(of: settings.selectedChecklistId) { _, newId in
                if let id = newId { taxonomy.loadChecklist(id: id) }
            }
            .task {
                if let id = settings.selectedChecklistId { taxonomy.loadChecklist(id: id) }
            }
            .environment(pulseState)
            .navigationDestination(item: $speciesLogTaxon) { taxon in
                VStack(spacing: 0) {
                    HeaderSpacingView()
                    ObservationLogContent(taxonId: taxon.id, bottomAnchored: true)
                }
            }
            .onChange(of: speciesLogTaxon) { _, newValue in
                if let taxon = newValue {
                    navState.push(title: taxon.commonName, backAction: { speciesLogTaxon = nil })
                } else {
                    Task { @MainActor in navState.pop() }
                }
            }
            .overlay(alignment: .bottom) {
                if let taxon = selectedTaxon {
                    GeometryReader { _ in
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
                                        if didAdd { didAddObservation(taxonId: taxon.id) }
                                    }
                                )
                                .background(
                                    GeometryReader { sheetGeo in
                                        Color.clear
                                            .preference(key: SheetContentHeightKey.self, value: sheetGeo.size.height)
                                    }
                                )
                            }
                            .onPreferenceChange(SheetContentHeightKey.self) { sheetContentHeight = $0 }
                            .frame(maxWidth: .infinity)
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
                syncAttributions: syncAttributions,
                undoableTaxonIds: undoableTaxonIds,
                detailsTaxonIds: taxaWithEntriesIds,
                scrollToBottomSignal: scrollToBottomSignal,
                bottomAnchored: true,
                onDetails: { taxon in speciesLogTaxon = taxon },
                onUndo: { taxon in undoTaxon(taxon) },
                onTap: { taxon in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        selectedTaxon = taxon
                        filterFocused = false
                    }
                },
                onQuickAdd: { taxon in performAdd(taxonId: taxon.id) }
            )
        }
    }
}

private struct BottomControlsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = Swift.max(value, nextValue())
    }
}

private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

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
        .environment(AppNavigationState())
        .environment(PulseAnimationState())
}
#endif
