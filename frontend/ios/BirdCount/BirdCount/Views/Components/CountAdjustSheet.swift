import SwiftUI

struct CountAdjustSheet: View, Identifiable {
    @Environment(ObservationStore.self) private var observations
    let taxon: Taxon
    let onDone: () -> Void
    var id: String { taxon.id }
    @State private var tempCount: Int = 1 // number of new observations to add
    @State private var numberBuffer: String = "1"
    @State private var showPad: Bool = false // keypad is hidden initially

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                CountHeaderView(taxon: taxon)

                KeypadToggleView(showPad: $showPad)

                NumericPadContainer(showPad: showPad,
                                    onDigit: { appendDigit($0) },
                                    onBack: backspace,
                                    onClear: clearBuffer)

                // Push display and step buttons to the bottom
                Spacer(minLength: 0)

                CountDisplayView(value: tempCount)

                StepControlsView(onMinus: { adjust(-1) }, onPlus: { adjust(+1) })

                ActionBarView(observedSpecies: observations.totalSpeciesObserved,
                               totalIndividuals: observations.totalIndividuals,
                               onCancel: onDone,
                               onDone: { commitAndClose() },
                               doneDisabled: tempCount < 1)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .onAppear(perform: initialize)
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
}

// MARK: - CountAdjust Components
private struct CountHeaderView: View {
    let taxon: Taxon
    var body: some View {
        VStack(spacing: 4) {
            Text(taxon.commonName)
                .font(.title2.weight(.semibold))
            Text(taxon.scientificName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeypadToggleView: View {
    @Binding var showPad: Bool
    var body: some View {
        HStack {
            Button(action: { withAnimation(.easeInOut) { showPad.toggle() } }) {
                Label(showPad ? "Hide keypad" : "Show keypad",
                      systemImage: showPad ? "keyboard.chevron.compact.down" : "keyboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Spacer()
        }
    }
}

private struct NumericPadContainer: View {
    let showPad: Bool
    let onDigit: (Int) -> Void
    let onBack: () -> Void
    let onClear: () -> Void
    var body: some View {
        Group {
            if showPad {
                NumericPad(onDigit: { onDigit($0) }, onBack: onBack, onClear: onClear)
                    .frame(maxWidth: 400)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private struct CountDisplayView: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.vertical, 8)
            .contentTransition(.numericText())
    }
}

private struct StepControlsView: View {
    let onMinus: () -> Void
    let onPlus: () -> Void
    var body: some View {
        HStack(spacing: 20) {
            StepButton(symbol: "minus", action: onMinus)
            StepButton(symbol: "plus", action: onPlus)
        }
    }

    private struct StepButton: View {
        let symbol: String
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.largeTitle.weight(.semibold))
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ActionBarView: View {
    let observedSpecies: Int
    let totalIndividuals: Int
    let onCancel: () -> Void
    let onDone: () -> Void
    let doneDisabled: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Stats
            VStack(alignment: .leading, spacing: 2) {
                Text("Observed species: \(observedSpecies)")
                Text("Total individuals: \(totalIndividuals)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            // Action buttons
            HStack(spacing: 12) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)

                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(doneDisabled)
            }
            .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 4, y: 2)
    }
}
