import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observations
    @Environment(SettingsStore.self) private var settings
    // Shared range (reserved for future use in Home)
    @Binding var preset: RangePreset
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var filterText: String = ""
    @State private var selectedTaxon: Taxon? = nil
    @State private var bottomControlsHeight: CGFloat = 0
    @State private var sheetContentHeight: CGFloat = 0

    private var filtered: [Taxon] { taxonomy.search(filterText, minCommonness: settings.selectedChecklistId != nil ? settings.minCommonness : nil, maxCommonness: settings.selectedChecklistId != nil ? settings.maxCommonness : nil) }

    // Range-filtered counts per species
    private var rangeCounts: [String:Int] {
        let (effStart, effEnd) = effectiveRange
    let filteredObs = observations.observations.filter { $0.end >= effStart && $0.begin <= effEnd }
        return filteredObs.reduce(into: [String:Int]()) { $0[$1.taxonId, default: 0] += max(0, $1.count) }
    }

    // Dynamic range: for relative presets, recompute against "now"
    private var effectiveRange: (Date, Date) {
        let now = Date()
        switch preset {
        case .today:
            return (Calendar.current.startOfDay(for: now), now)
        case .lastHour:
            let start = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
            return (start, now)
        case .last7Days:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .all:
            return (.distantPast, now)
        case .custom:
            return (startDate, endDate)
        }
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
                    FilterBar(text: filterText) { filterText = "" }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    Divider()
                    OnScreenKeyboard(onKey: { filterText.append($0) }, onBackspace: { if !filterText.isEmpty { _ = filterText.removeLast() } }, onClear: { filterText = "" })
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
            }
            
            // Hide the nav bar entirely so it doesn't reserve space at the top
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: settings.enableAbbreviationSearch) { _, newVal in
                taxonomy.enableAbbreviationSearch = newVal
            }
            .onChange(of: settings.selectedChecklistId) { _, newId in
                if let id = newId { taxonomy.loadChecklist(id: id) }
            }
            .task { taxonomy.enableAbbreviationSearch = settings.enableAbbreviationSearch; if let id = settings.selectedChecklistId { taxonomy.loadChecklist(id: id) } }
            // Present CountAdjustSheet as a custom bottom overlay, shifted up by the bottom controls height
            .overlay(alignment: .bottom) {
                if let taxon = selectedTaxon {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                                .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selectedTaxon = nil } }

                            VStack(spacing: 0) {
                                CountAdjustSheet(taxon: taxon) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selectedTaxon = nil }
                                }
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
                            .padding(.bottom, bottomControlsHeight)
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
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if !taxonomy.loaded {
            ProgressView("Loading taxonomy…")
                .task { taxonomy.load() }
        } else if taxonomy.species.isEmpty {
            ContentUnavailableView("No Species", systemImage: "bird", description: Text("Taxonomy file empty"))
        } else {
            speciesList
        }
    }

    private var speciesList: some View {
    GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { taxon in
                        let count = rangeCounts[taxon.id] ?? 0
                        VStack(spacing: 0) {
                            SpeciesRow(taxon: taxon, count: count)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedTaxon = taxon }
                                .contextMenu {
                                    if count > 0 {
                                        Button(role: .destructive) { observations.reset(taxon.id) } label: { Label("Reset", systemImage: "trash") }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                // Make stack at least as tall as available space and align its contents to bottom
                .frame(minHeight: proxy.size.height, alignment: .bottom)
            }
    }
    .padding(.bottom, 24)
    }

        // Removed keyboard toggle button
}

// PreferenceKey for measuring bottom controls height dynamically
private struct BottomControlsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// PreferenceKey for the sheet content height
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SpeciesRow: View {
    let taxon: Taxon
    let count: Int
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taxon.commonName)
                    .font(.title3.weight(.semibold))
                Text(taxon.scientificName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let c = taxon.commonness { Text(commonnessLabel(c)).font(.footnote).padding(4).background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))) }
            if count > 0 {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                    .accessibilityLabel("\(taxon.commonName) count \(count)")
            }
        }
    }
    private func commonnessLabel(_ c: Int) -> String { switch c { case 0: return "R"; case 1: return "S"; case 2: return "U"; case 3: return "C"; default: return "" } }
}

private struct FilterBar: View {
    let text: String
    let onClear: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "Filter species" : text)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear filter text")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
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
    HomeView(
        preset: .constant(.today),
        startDate: .constant(Calendar.current.startOfDay(for: Date())),
        endDate: .constant(Date())
    )
        .environment(TaxonomyStore.previewInstance)
        .environment(ObservationStore.previewInstance)
        .environment(SettingsStore())
}
#endif
