import SwiftUI
import Observation

/// Shared observable state for the species-row pulse animation.
/// Injected via environment so only SpeciesRow re-renders on animation changes,
/// not SpeciesListView, SpeciesListContent, or BottomAnchoredScrollView.
@Observable final class PulseAnimationState {
    private(set) var recentlyUpdatedSpeciesId: String? = nil
    private(set) var showPulseAnimation: Bool = false
    private var clearTask: Task<Void, Never>? = nil

    @MainActor func trigger(speciesId: String) {
        clearTask?.cancel()
        recentlyUpdatedSpeciesId = speciesId
        showPulseAnimation = true
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showPulseAnimation = false
            recentlyUpdatedSpeciesId = nil
        }
    }
}

struct SpeciesRow: View {
    let taxon: Taxon
    let count: Int
    /// Count includes observations received from synced users.
    var hasSyncedObservations: Bool = false
    let onSelect: (Taxon) -> Void
    let onQuickAdd: (Taxon) -> Void

    @Environment(PulseAnimationState.self) private var pulseState
    @State private var isPulsing = false

    private var shouldPulse: Bool {
        pulseState.recentlyUpdatedSpeciesId == taxon.id && pulseState.showPulseAnimation
    }
    @State private var swipeOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Swipe-right reveal: stays fixed while content slides over it
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.mix(with: .white, by: 0.4)))
                .opacity(min(Double(swipeOffset / swipeThreshold), 1.0))

                // Row content — slides right during swipe
                HStack(alignment: .center, spacing: 12) {
                    SpeciesRowBasic(taxon: taxon)
                    Spacer()
                    if count > 0 {
                        // Sits in space the Spacer already absorbs, so its
                        // presence never shifts the name or the count badge.
                        if hasSyncedObservations {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Strings.Sync.includesSynced.string)
                        }
                        Text("\(count)")
                            .font(.headline.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.green.opacity(0.8), lineWidth: isPulsing ? 2 : 0)
                            )
                            .accessibilityLabel(String(format: Strings.Accessibility.countLabel.string, taxon.commonName, count))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(isPulsing ? 0.15 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.8), lineWidth: isPulsing ? 2 : 0)
                )
                .offset(x: swipeOffset)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(taxon) }
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        guard value.translation.width > 0 else { return }
                        swipeOffset = min(value.translation.width, swipeThreshold + 20)
                    }
                    .onEnded { value in
                        let triggered = value.translation.width >= swipeThreshold
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            swipeOffset = 0
                        }
                        if triggered {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onQuickAdd(taxon)
                        }
                    }
            )
            .onChange(of: shouldPulse) { _, newValue in
                if newValue {
                    withAnimation(.easeIn(duration: 0.3)) { isPulsing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 1.7)) { isPulsing = false }
                    }
                } else {
                    isPulsing = false
                }
            }

            Divider()
        }
    }
}

private struct SpeciesRowBasic: View {
    let taxon: Taxon

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(taxon.commonName)
                    .font(.title3.weight(.semibold))
                Text(taxon.scientificName)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
            }
        }
    }
}

#if DEBUG
#Preview("Species Row with count") {
    SpeciesRow(
        taxon: Taxon(id: "sample-id", commonName: "American Robin", scientificName: "Turdus migratorius", order: 1, rank: "species", commonness: 3),
        count: 5, onSelect: { _ in }, onQuickAdd: { _ in }
    ).padding().environment(PulseAnimationState())
}

#Preview("Species Row without count") {
    SpeciesRow(
        taxon: Taxon(id: "sample-id-2", commonName: "Rare Warbler", scientificName: "Setophaga rara", order: 2, rank: "species", commonness: 0),
        count: 0, onSelect: { _ in }, onQuickAdd: { _ in }
    ).padding().environment(PulseAnimationState())
}

#Preview("Species Row with pulse") {
    let pulse = PulseAnimationState()
    SpeciesRow(
        taxon: Taxon(id: "sample-id-3", commonName: "Pulsing Warbler", scientificName: "Setophaga pulsans", order: 3, rank: "species", commonness: 1),
        count: 2, onSelect: { _ in }, onQuickAdd: { _ in }
    ).padding().environment(pulse)
}
#endif
