import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observations
    @Environment(SettingsStore.self) private var settings
    @State private var filterText: String = ""
    @State private var useSystemKeyboard: Bool = false // debug toggle if needed
    @State private var selectedTaxon: Taxon? = nil
    @State private var showSummary: Bool = false
    @State private var showSettings: Bool = false

    private var filtered: [Taxon] { taxonomy.search(filterText, minCommonness: settings.selectedChecklistId != nil ? settings.minCommonness : nil, maxCommonness: settings.selectedChecklistId != nil ? settings.maxCommonness : nil) }

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
                Divider()
                FilterBar(text: filterText) { filterText = "" }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
                OnScreenKeyboard(onKey: { filterText.append($0) }, onBackspace: { if !filterText.isEmpty { _ = filterText.removeLast() } }, onClear: { filterText = "" })
                    .padding(.bottom, 8)
                    .background(.thinMaterial)
            }
            .navigationTitle("Bird Count")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Summary") { showSummary = true } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    toggleKeyboardButton
                }
            }
            .sheet(item: $selectedTaxon) { taxon in
                CountAdjustSheet(taxon: taxon) { selectedTaxon = nil }
            }
            .sheet(isPresented: $showSummary) { SummaryView(show: $showSummary) }
            .sheet(isPresented: $showSettings) { SettingsView(show: $showSettings) }
            .onChange(of: settings.enableAbbreviationSearch) { _, newVal in
                taxonomy.enableAbbreviationSearch = newVal
            }
            .onChange(of: settings.selectedChecklistId) { _, newId in
                if let id = newId { taxonomy.loadChecklist(id: id) }
            }
            .task { taxonomy.enableAbbreviationSearch = settings.enableAbbreviationSearch; if let id = settings.selectedChecklistId { taxonomy.loadChecklist(id: id) } }
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
                        let count = observations.count(for: taxon.id)
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

    private var toggleKeyboardButton: some View {
        Button(action: { useSystemKeyboard.toggle() }) {
            Image(systemName: useSystemKeyboard ? "keyboard" : "rectangle.bottomthird.inset.filled")
        }
        .help("Toggle system keyboard (debug)")
    }
}

private struct SpeciesRow: View {
    let taxon: Taxon
    let count: Int
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taxon.commonName)
                    .font(.headline)
                Text(taxon.scientificName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let c = taxon.commonness { Text(commonnessLabel(c)).font(.caption2).padding(4).background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))) }
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
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

private struct CountAdjustSheet: View, Identifiable {
    @Environment(ObservationStore.self) private var observations
    let taxon: Taxon
    let onDone: () -> Void
    var id: String { taxon.id }
    @State private var tempCount: Int = 1 // number of new observations to add
    @State private var numberBuffer: String = "1"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                NumericPad(onDigit: { appendDigit($0) }, onBack: backspace, onClear: clearBuffer)
                    .frame(maxWidth: 400)
                countDisplay
                stepButtons
                Spacer()
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .onAppear(perform: initialize)
            .interactiveDismissDisabled()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    // Stats
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Observed species: \(observations.totalSpeciesObserved)")
                        Text("Total individuals: \(observations.totalIndividuals)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button(role: .cancel) { onDone() } label: {
                            Text("Cancel").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)

                        Button(action: { commitAndClose() }) {
                            Text("Done").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                        .disabled(tempCount < 1)
                    }
                    .font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: Subviews
    private var header: some View {
        VStack(spacing: 4) {
            Text(taxon.commonName)
                .font(.title2.weight(.semibold))
            Text(taxon.scientificName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var countDisplay: some View {
        Text("\(tempCount)")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.vertical, 8)
            .contentTransition(.numericText())
    }

    private var stepButtons: some View {
        HStack(spacing: 20) {
            StepButton(symbol: "minus") { adjust(-1) }
            StepButton(symbol: "plus") { adjust(+1) }
        }
    }

    private func initialize() {
        // Always default to 1 new observation regardless of existing total
        tempCount = 1
        numberBuffer = "1"
    }

    // MARK: Logic
    private func adjust(_ delta: Int) {
        let newVal = max(1, tempCount + delta)
        if newVal != tempCount { tempCount = newVal; numberBuffer = String(newVal); UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }
    private func appendDigit(_ d: Int) {
        if numberBuffer == "0" { numberBuffer = "" }
        numberBuffer.append(String(d))
        if let val = Int(numberBuffer) { tempCount = max(1, val) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func backspace() {
        guard !numberBuffer.isEmpty else { return }
        numberBuffer.removeLast()
        if numberBuffer.isEmpty { tempCount = 1; numberBuffer = "1" }
        else { tempCount = max(1, Int(numberBuffer) ?? 1) }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    private func clearBuffer() { tempCount = 1; numberBuffer = "1"; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    private func commitAndClose() {
        guard tempCount >= 1 else { onDone(); return }
        for _ in 0..<tempCount { observations.addObservation(taxon.id) }
        onDone()
    }

    // MARK: Components
    private struct StepButton: View { let symbol: String; let action: () -> Void; var body: some View { Button(action: action) { Image(systemName: symbol).font(.largeTitle.weight(.semibold)).frame(width: 88, height: 88).background(Circle().fill(Color.accentColor.opacity(0.15))) }.buttonStyle(.plain) } }
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
}
#endif
