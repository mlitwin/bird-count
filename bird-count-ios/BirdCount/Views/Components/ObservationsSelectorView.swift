import SwiftUI
import Combine

public struct ObservationsSelectorView: View {
    @Environment(DateRangeStore.self) private var dateRangeStore
    @Environment(ObservationStore.self) private var observations
    @State private var showCustomSheet: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                 // Species count badge
                HStack(spacing: 6) {
                    Text("\(observations.totalSpeciesObserved(in: dateRangeStore.dateRange))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.tint))
                        .accessibilityLabel(String(format: Strings.Accessibility.speciesObserved.string, observations.totalSpeciesObserved(in: dateRangeStore.dateRange)))

                    Text(Strings.Species.species.string)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(dateRangeStore.dateRange.formattedSummary(preset: dateRangeStore.dateRangePreset))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)

                Button(action: { showCustomSheet = true }) {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .padding(8)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel(Strings.Share.Accessibility.editRange.string)
                Spacer()
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            DateRangePickerSheet(
                range: Binding(
                    get: { dateRangeStore.dateRange },
                    set: { dateRangeStore.update($0) }
                ),
                preset: Binding(
                    get: { dateRangeStore.dateRangePreset },
                    set: { dateRangeStore.dateRangePreset = $0 }
                )
            )
        }
        // Keep preset in sync if range equals the Today preset values (via chevrons or custom sheet)
        .onChange(of: dateRangeStore.dateRange.begin) { _, _ in syncPresetWithCurrentRange() }
        .onChange(of: dateRangeStore.dateRange.end) { _, _ in syncPresetWithCurrentRange() }
        // Auto-update when the calendar day changes while the app is active
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            if dateRangeStore.dateRangePreset == .today {
                dateRangeStore.applyPreset(.today)
            }
        }
        .onAppear { syncPresetWithCurrentRange() }
    }
}

// MARK: - Preset sync helpers
private extension ObservationsSelectorView {
    func syncPresetWithCurrentRange() {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let startDate = dateRangeStore.dateRange.begin
        let endDate = dateRangeStore.dateRange.end
        let preset = dateRangeStore.dateRangePreset
        if startDate == todayStart && endDate == todayEnd {
            if preset != .today { dateRangeStore.setPreset(.today) }
        } else if preset == .today {
            dateRangeStore.setPreset(.custom)
        }
    }
}
