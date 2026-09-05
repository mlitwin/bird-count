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

/// Coordinates which row (if any) has its left reveal open, so that
/// interacting with any other row automatically closes the open reveal.
@Observable final class RevealCoordinator {
    var openRowId: String? = nil

    func open(_ id: String) { openRowId = id }
    func closeAll() { openRowId = nil }
}

struct SpeciesRow: View {
    let taxon: Taxon
    let count: Int
    /// Who contributed to this count, when synced users are involved
    /// (nil = only the current user's observations — no badge).
    var attribution: ObserverAttribution? = nil
    /// Tap: add a new observation for this species
    let onTap: (Taxon) -> Void
    /// Swipe-right: immediate +1
    let onQuickAdd: (Taxon) -> Void
    /// Swipe-left reveal: Details — navigate to species log; nil = left swipe disabled
    var onDetails: ((Taxon) -> Void)? = nil
    /// Swipe-left reveal: Undo — remove most recent user record; nil = button hidden
    var onUndo: (() -> Void)? = nil

    @Environment(PulseAnimationState.self) private var pulseState
    @Environment(RevealCoordinator.self) private var revealCoordinator
    @State private var isPulsing = false

    @State private var rightSwipeOffset: CGFloat = 0
    @State private var leftDragOffset: CGFloat = 0
    @State private var leftRevealOpen: Bool = false

    private let rightSwipeThreshold: CGFloat = 72
    private var leftRevealWidth: CGFloat { onUndo != nil ? 160 : 80 }

    private var shouldPulse: Bool {
        pulseState.recentlyUpdatedSpeciesId == taxon.id && pulseState.showPulseAnimation
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Swipe-right reveal: + icon anchored to leading edge
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.mix(with: .white, by: 0.4)))
                .opacity(min(Double(rightSwipeOffset / rightSwipeThreshold), 1.0))

                // Swipe-left reveal: action buttons anchored to trailing edge
                if onDetails != nil {
                    HStack(spacing: 0) {
                        Spacer()
                        if let undo = onUndo {
                            Button {
                                closeLeftReveal()
                                undo()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward").font(.headline)
                                    Text("Undo").font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 80)
                                .frame(maxHeight: .infinity)
                                .background(Color.orange)
                            }
                            .buttonStyle(.plain)
                        }
                        if let details = onDetails {
                            Button {
                                resetGestureState()
                                details(taxon)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "info.circle").font(.headline)
                                    Text("Details").font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 80)
                                .frame(maxHeight: .infinity)
                                .background(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(leftRevealOpen ? 1 : min(Double(leftDragOffset / (leftRevealWidth * 0.5)), 1.0))
                    .allowsHitTesting(leftRevealOpen)
                }

                // Row content — slides based on active gesture
                rowContent
                    .offset(x: rightSwipeOffset - (leftRevealOpen ? leftRevealWidth : leftDragOffset))
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if leftRevealOpen {
                    closeLeftReveal()
                } else {
                    revealCoordinator.closeAll()
                    onTap(taxon)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        guard !leftRevealOpen else { return }
                        if value.translation.width > 0 {
                            // Right swipe: close any other open reveal first
                            if revealCoordinator.openRowId != nil {
                                revealCoordinator.closeAll()
                            }
                            rightSwipeOffset = min(value.translation.width, rightSwipeThreshold + 20)
                        } else if onDetails != nil {
                            // Left swipe: only allowed when there are reveal actions
                            leftDragOffset = min(-value.translation.width, leftRevealWidth + 20)
                        }
                    }
                    .onEnded { value in
                        DiagnosticsLog.log(.gesture, "[\(taxon.id)] drag ended: translation=\(value.translation.width) leftRevealOpen=\(leftRevealOpen)")
                        if leftRevealOpen {
                            // While reveal is open, any rightward swipe closes it; ignore quick-add
                            if value.translation.width > 0 { closeLeftReveal() }
                            return
                        }
                        if value.translation.width > 0 {
                            let triggered = value.translation.width >= rightSwipeThreshold
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { rightSwipeOffset = 0 }
                            if triggered {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onQuickAdd(taxon)
                            }
                        } else if value.translation.width < 0 && onDetails != nil {
                            let shouldOpen = -value.translation.width >= leftRevealWidth * 0.5
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                leftDragOffset = 0
                                leftRevealOpen = shouldOpen
                            }
                            DiagnosticsLog.log(.gesture, "[\(taxon.id)] leftRevealOpen -> \(shouldOpen)")
                            if shouldOpen {
                                revealCoordinator.open(taxon.id)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
            )
            .onChange(of: revealCoordinator.openRowId) { _, newId in
                // Another row opened its reveal — close ours
                if newId != taxon.id && leftRevealOpen {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        leftRevealOpen = false
                    }
                }
            }
            .onChange(of: shouldPulse) { _, newValue in
                DiagnosticsLog.log(.animation, "[\(taxon.id)] shouldPulse -> \(newValue)")
                if newValue {
                    withAnimation(.easeIn(duration: 0.3)) { isPulsing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        DiagnosticsLog.log(.animation, "[\(taxon.id)] pulse fade-out begin")
                        withAnimation(.easeOut(duration: 1.7)) { isPulsing = false }
                    }
                } else {
                    isPulsing = false
                }
            }

            Divider()
        }
    }

    private func closeLeftReveal() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { leftRevealOpen = false }
        revealCoordinator.closeAll()
    }

    /// Immediate (no animation) full reset — use before navigation so the push
    /// doesn't race with an in-flight close animation and leave residual offset.
    private func resetGestureState() {
        leftRevealOpen = false
        leftDragOffset = 0
        rightSwipeOffset = 0
        revealCoordinator.closeAll()
    }

    @ViewBuilder private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            SpeciesRowBasic(taxon: taxon)
            Spacer()
            if count > 0 {
                if let symbol = attribution?.symbolName {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            attribution?.includesCurrentUser == true
                                ? Strings.Sync.includesSynced.string
                                : Strings.Sync.fromSyncedUsers.string
                        )
                }
                CountBadge(count: count)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
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
        count: 5,
        onTap: { _ in },
        onQuickAdd: { _ in },
        onDetails: { _ in },
        onUndo: {}
    ).padding().environment(PulseAnimationState()).environment(RevealCoordinator())
}

#Preview("Species Row without count") {
    SpeciesRow(
        taxon: Taxon(id: "sample-id-2", commonName: "Rare Warbler", scientificName: "Setophaga rara", order: 2, rank: "species", commonness: 0),
        count: 0,
        onTap: { _ in },
        onQuickAdd: { _ in },
        onDetails: { _ in }
    ).padding().environment(PulseAnimationState()).environment(RevealCoordinator())
}

#Preview("Species Row with pulse") {
    let pulse = PulseAnimationState()
    SpeciesRow(
        taxon: Taxon(id: "sample-id-3", commonName: "Pulsing Warbler", scientificName: "Setophaga pulsans", order: 3, rank: "species", commonness: 1),
        count: 2,
        onTap: { _ in },
        onQuickAdd: { _ in },
        onDetails: { _ in }
    ).padding().environment(pulse).environment(RevealCoordinator())
}
#endif
