import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(ObservationStore.self) private var observations
    @State private var filterText: String = ""
    @State private var useSystemKeyboard: Bool = false // debug toggle if needed
    @State private var selectedTaxon: Taxon? = nil

    private var filtered: [Taxon] { taxonomy.search(filterText) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FilterBar(text: filterText) { filterText = "" }
                    .padding(.horizontal)
                    .padding(.top, 8)
                Divider()
                Group {
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
                Divider()
                OnScreenKeyboard(onKey: { ch in
                    filterText.append(ch)
                }, onBackspace: {
                    if !filterText.isEmpty { _ = filterText.removeLast() }
                }, onClear: {
                    filterText = ""
                }, onSpace: {
                    filterText.append(" ")
                })
                .padding(.bottom, 8)
                .background(.thinMaterial)
            }
            .navigationTitle("Bird Count")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { toggleKeyboardButton } }
            .sheet(item: $selectedTaxon) { taxon in
                CountAdjustSheet(taxon: taxon) { selectedTaxon = nil }
            }
        }
    }

    private var speciesList: some View {
        List(filtered) { taxon in
            SpeciesRow(taxon: taxon, count: observations.count(for: taxon.id))
                .contentShape(Rectangle())
                .onTapGesture { selectedTaxon = taxon }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { observations.reset(taxon.id) } label: { Label("Reset", systemImage: "trash") }
                }
        }
        .listStyle(.plain)
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
    @State private var tempCount: Int = 0
    @State private var numberBuffer: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                countDisplay
                stepButtons
                NumericPad(onDigit: { appendDigit($0) }, onBack: backspace, onClear: clearBuffer)
                    .frame(maxWidth: 400)
                Spacer()
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commitAndClose() }.disabled(tempCount < 0) }
                ToolbarItem(placement: .bottomBar) {
                    VStack(alignment: .leading) {
                        Text("Observed species: \(observations.totalSpeciesObserved)")
                        Text("Total individuals: \(observations.totalIndividuals)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear(perform: initialize)
            .interactiveDismissDisabled()
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
        let current = observations.count(for: taxon.id)
        tempCount = current
        numberBuffer = current > 0 ? String(current) : ""
    }

    // MARK: Logic
    private func adjust(_ delta: Int) { let new = max(0, tempCount + delta); tempCount = new; numberBuffer = String(new); UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    private func appendDigit(_ d: Int) { numberBuffer.append(String(d)); if let val = Int(numberBuffer) { tempCount = val }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func backspace() { guard !numberBuffer.isEmpty else { return }; numberBuffer.removeLast(); tempCount = Int(numberBuffer) ?? 0; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    private func clearBuffer() { numberBuffer = ""; tempCount = 0; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    private func commitAndClose() { observations.set(taxon.id, to: tempCount); onDone() }

    // MARK: Components
    private struct StepButton: View { let symbol: String; let action: () -> Void; var body: some View { Button(action: action) { Image(systemName: symbol).font(.largeTitle.weight(.semibold)).frame(width: 88, height: 88).background(Circle().fill(Color.accentColor.opacity(0.15))) }.buttonStyle(.plain) } }

    private struct NumericPad: View {
        let onDigit: (Int) -> Void
        let onBack: () -> Void
        let onClear: () -> Void
        private let layout: [[Int?]] = [[1,2,3],[4,5,6],[7,8,9],[nil,0,nil]]
        var body: some View {
            VStack(spacing: 12) {
                ForEach(layout.indices, id: \.self) { r in
                    HStack(spacing: 12) {
                        ForEach(layout[r].indices, id: \.self) { c in
                            if let val = layout[r][c] { NumButton(label: String(val)) { onDigit(val) } }
                            else if r == 3 && c == 0 { NumButton(symbol: "delete.left") { onBack() } }
                            else if r == 3 && c == 2 { NumButton(symbol: "xmark") { onClear() } }
                            else { Spacer().frame(width: 64, height: 64) }
                        }
                    }
                }
            }
        }
        private struct NumButton: View { var label: String? = nil; var symbol: String? = nil; let action: () -> Void; var body: some View { Button(action: action) { Group { if let label = label { Text(label).font(.title2.bold()) } else if let symbol = symbol { Image(systemName: symbol).font(.title2) } }.frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 16).fill(Color(.tertiarySystemFill))) }.buttonStyle(.plain) } }
    }
}

struct OnScreenKeyboard: View {
    let onKey: (String) -> Void
    let onBackspace: () -> Void
    let onClear: () -> Void
    let onSpace: () -> Void

    private let rows: [[String]] = [["Q","W","E","R","T","Y","U","I","O","P"],["A","S","D","F","G","H","J","K","L"],["Z","X","C","V","B","N","M"]]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key) { onKey(key.lowercased()) }
                    }
                }
            }
            HStack(spacing: 6) {
                KeyButton(symbol: "delete.left.fill", width: 60, role: .destructive) { onBackspace() }
                    .accessibilityLabel("Backspace")
                KeyButton(label: "SPACE", flex: true) { onSpace() }
                    .accessibilityLabel("Space")
                KeyButton(symbol: "xmark.circle", width: 60) { onClear() }
                    .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 10)
    }

    private struct KeyButton: View {
        var label: String? = nil
        var symbol: String? = nil
        var width: CGFloat? = nil
        var flex: Bool = false
        var role: ButtonRole? = nil
        let action: () -> Void
        var body: some View {
            Button(role: role) { action(); UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                Group { if let label = label { Text(label).font(.callout.weight(.semibold)) } else if let symbol = symbol { Image(systemName: symbol) } }
                .frame(width: width, height: 38)
                .frame(maxWidth: flex ? .infinity : nil)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .frame(height: 46)
            .frame(maxWidth: flex ? .infinity : (width ?? 34))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
        }
    }
}

#if DEBUG
private extension TaxonomyStore {
    static var previewInstance: TaxonomyStore {
        let store = TaxonomyStore()
        store.loadPreview(species: [
            Taxon(id: "amecro", commonName: "American Crow", scientificName: "Corvus brachyrhynchos", order: 1, rank: "species"),
            Taxon(id: "norbla", commonName: "Northern Blackbird", scientificName: "Inventus fictus", order: 2, rank: "species"),
            Taxon(id: "bkhawk", commonName: "Black Hawk", scientificName: "Buteogallus anthracinus", order: 3, rank: "species")
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
}
#endif
