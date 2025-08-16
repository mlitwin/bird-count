import SwiftUI

struct CountAdjustSheet: View, Identifiable {
    @Environment(ObservationStore.self) private var observations
    let taxon: Taxon
    let onDone: () -> Void
    var id: String { taxon.id }
    @State private var tempCount: Int = 1 // number of new observations to add
    // Numeric keypad removed; simple +/- controls only

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CountHeaderView(taxon: taxon)

                StepControlsView(value: tempCount, onMinus: { adjust(-1) }, onPlus: { adjust(+1) })

                ActionBarView(onCancel: onDone,
                               onDone: { commitAndClose() },
                               doneDisabled: tempCount < 1)
                    .padding(.bottom, 8)
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .onAppear(perform: initialize)
        }
    }

    private func initialize() {
    // Always default to 1 new observation regardless of existing total
    tempCount = 1
    }

    // MARK: Logic
    private func adjust(_ delta: Int) {
    let newVal = max(1, tempCount + delta)
    if newVal != tempCount { tempCount = newVal; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }
    private func commitAndClose() {
        guard tempCount >= 1 else { onDone(); return }
    observations.addObservation(taxon.id, begin: Date(), end: nil, count: tempCount)
        onDone()
    }
}

// MARK: - CountAdjust Components
private struct CountHeaderView: View {
    let taxon: Taxon
    var body: some View {
        VStack(spacing: 4) {
            Text(taxon.commonName)
                .font(.headline.weight(.semibold))
            Text(taxon.scientificName)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// Numeric keypad and toggle removed

// Count display is now integrated into StepControlsView

private struct StepControlsView: View {
    let value: Int
    let onMinus: () -> Void
    let onPlus: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            StepButton(symbol: "minus", action: onMinus)

            Text("\(value)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 72)
                .accessibilityLabel("Count")
                .accessibilityValue("\(value)")

            StepButton(symbol: "plus", action: onPlus)
        }
    }

    private struct StepButton: View {
        let symbol: String
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
            .font(.title.weight(.semibold))
            .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ActionBarView: View {
    let onCancel: () -> Void
    let onDone: () -> Void
    let doneDisabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Action buttons
            HStack(spacing: 12) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)

                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.regular)
                .disabled(doneDisabled)
            }
            .font(.headline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 4, y: 2)
    }
}
