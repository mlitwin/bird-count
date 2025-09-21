import SwiftUI

struct CountAdjustSheet: View, Identifiable {
    @Environment(ObservationStore.self) private var observations
    let taxon: Taxon
    // Optional parent record id; when present, new observations will be attached as children of this parent
    var parentId: UUID? = nil
    let onDone: () -> Void
    // Optional callback fired after pressing Done; indicates if a root observation was actually added (true)
    // Used by callers like HomeView to clear the filter when a new observation is created from a taxon.
    var onCommitted: ((Bool) -> Void)? = nil
    var id: String { taxon.id }
    @State private var tempCount: Int = 1 // desired total count when adjusting existing record

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
        // If we're adjusting from a record context (parentId present), start with current recursive total for that record
        if let pid = parentId, let parent = observations.findRecord(by: pid) {
            tempCount = recursiveCount(parent)
        } else {
            // Default for new root additions
            tempCount = 1
        }
    }

    // MARK: Logic
    private func adjust(_ delta: Int) {
        // Allow adjusting down to 0
        let newVal = max(0, tempCount + delta)
        if newVal != tempCount { tempCount = newVal; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }
    private func commitAndClose() {
        var didAddRootObservation = false
        if let pid = parentId, let parent = observations.findRecord(by: pid) {
            // Compute delta from current recursive total to desired total and add as a child (can be negative)
            let currentTotal = recursiveCount(parent)
            let delta = tempCount - currentTotal
            if delta != 0 {
                _ = observations.addChildObservation(parentId: pid, taxonId: taxon.id, begin: Date(), end: nil, count: delta)
            }
        } else {
            // For new root additions, treat tempCount as the count to add; allow 0 => no-op
            if tempCount > 0 {
                observations.addObservation(taxon.id, begin: Date(), end: nil, count: tempCount)
                didAddRootObservation = true
            }
        }
        // Notify caller whether a root observation was added (HomeView may clear filter)
        onCommitted?(didAddRootObservation)
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

// MARK: - Step Controls

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
                .accessibilityLabel(Strings.Observation.count.string)
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

// MARK: - Local helpers
private func recursiveCount(_ r: ObservationRecord) -> Int {
    r.count + r.children.map { recursiveCount($0) }.reduce(0, +)
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
                    Text(Strings.General.cancel.string).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)

                Button(action: onDone) {
                    Text(Strings.General.done.string).frame(maxWidth: .infinity)
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
