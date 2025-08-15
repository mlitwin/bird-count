import SwiftUI

public enum RangePreset: String, CaseIterable, Identifiable {
    case lastHour = "Last Hour"
    case today = "Today"
    case last7Days = "7 Days"
    case all = "All"
    case custom = "Custom"
    public var id: String { rawValue }
}

public struct RangeSelectorView: View {
    @Binding var preset: RangePreset
    @Binding var startDate: Date
    @Binding var endDate: Date

    public init(preset: Binding<RangePreset>, startDate: Binding<Date>, endDate: Binding<Date>) {
        self._preset = preset
        self._startDate = startDate
        self._endDate = endDate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Range").font(.headline)
            Picker("Preset", selection: $preset) {
                ForEach(RangePreset.allCases) { p in Text(p.rawValue).tag(p) }
            }
            .pickerStyle(.segmented)
            .onChange(of: preset) { _, newVal in applyRangePreset(newVal) }

            DatePicker("From", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
            DatePicker("To", selection: $endDate, in: startDate... , displayedComponents: [.date, .hourAndMinute])
                .onChange(of: startDate) { _, _ in preset = .custom }
                .onChange(of: endDate) { _, _ in preset = .custom }
        }
    }

    private func applyRangePreset(_ p: RangePreset) {
        let now = Date()
        switch p {
        case .lastHour:
            startDate = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
            endDate = now
        case .today:
            let cal = Calendar.current
            startDate = cal.startOfDay(for: now)
            endDate = now
        case .last7Days:
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            endDate = now
        case .all:
            startDate = .distantPast
            endDate = now
        case .custom:
            break
        }
    }
}
