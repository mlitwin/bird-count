import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy
    @State private var filterText: String = ""
    @State private var useSystemKeyboard: Bool = false // debug toggle if needed

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
                        List(filtered) { taxon in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(taxon.commonName)
                                    .font(.headline)
                                Text(taxon.scientificName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !taxon.abbreviations.isEmpty {
                                    Text(taxon.abbreviations.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Future: open count adjust sheet
                            }
                        }
                        .listStyle(.plain)
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
        }
    }

    private var toggleKeyboardButton: some View {
        Button(action: { useSystemKeyboard.toggle() }) {
            Image(systemName: useSystemKeyboard ? "keyboard" : "rectangle.bottomthird.inset.filled")
        }
        .help("Toggle system keyboard (debug)")
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

struct OnScreenKeyboard: View {
    let onKey: (String) -> Void
    let onBackspace: () -> Void
    let onClear: () -> Void
    let onSpace: () -> Void

    private let rows: [[String]] = [
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.[0]) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
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
        @State private var pressed: Bool = false

        init(label: String? = nil, symbol: String? = nil, width: CGFloat? = nil, flex: Bool = false, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.label = label
            self.symbol = symbol
            self.width = width
            self.flex = flex
            self.role = role
            self.action = action
        }

        var body: some View {
            Button(role: role) {
                action()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Group {
                    if let label = label { Text(label).font(.callout.weight(.semibold)) }
                    else if let symbol = symbol { Image(systemName: symbol) }
                }
                .frame(width: width, height: 38)
                .frame(maxWidth: flex ? .infinity : nil)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .frame(height: 46)
            .frame(maxWidth: flex ? .infinity : (width ?? 34))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
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

#Preview("Home") {
    HomeView()
        .environment(TaxonomyStore.previewInstance)
}
