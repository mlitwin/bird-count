import SwiftUI

// MARK: - Shared formatters (file-private)

private enum DateRangeFormatters {
    static let hm: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()
    static let md: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMd")
        return df
    }()
    static let mdy: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return df
    }()
}

// MARK: - DateRange display extension

extension DateRange {
    /// Compact display string for a date range, respecting the given preset label when provided.
    func formattedSummary(preset: DateRangePreset? = nil) -> String {
        if preset == .all { return Strings.DateRange.allTime.string }
        if preset == .today { return Strings.DateRange.today.string }

        let cal = Calendar.current
        let isCompleteDay = cal.isDate(begin, equalTo: cal.startOfDay(for: begin), toGranularity: .second) &&
                            cal.isDate(end, equalTo: cal.startOfDay(for: end), toGranularity: .second) &&
                            cal.dateInterval(of: .day, for: begin)?.end == end
        if isCompleteDay {
            return DateRangeFormatters.mdy.string(from: begin)
        }

        let sameDay = cal.isDate(begin, inSameDayAs: end)
        let sameYear = cal.component(.year, from: begin) == cal.component(.year, from: end)
        let sameMonth = sameYear && cal.component(.month, from: begin) == cal.component(.month, from: end)
        let startHM = DateRangeFormatters.hm.string(from: begin)
        let endHM = DateRangeFormatters.hm.string(from: end)

        if sameDay {
            return "\(DateRangeFormatters.mdy.string(from: begin)) \(startHM) – \(endHM)"
        } else if sameMonth {
            let endD = String(cal.component(.day, from: end))
            return "\(DateRangeFormatters.md.string(from: begin)) \(startHM) – \(endD) \(endHM)"
        } else if sameYear {
            return "\(DateRangeFormatters.md.string(from: begin)) \(startHM) – \(DateRangeFormatters.md.string(from: end)) \(endHM)"
        } else {
            return "\(DateRangeFormatters.mdy.string(from: begin)) \(startHM) – \(DateRangeFormatters.mdy.string(from: end)) \(endHM)"
        }
    }
}

// MARK: - DateRangePickerSheet

/// A half-sheet date range picker with Today/All presets and day-navigation arrows.
/// Works with a local working copy — changes are applied only when the user taps Done.
struct DateRangePickerSheet: View {
    @Binding var range: DateRange
    private var presetBinding: Binding<DateRangePreset>?

    @Environment(\.dismiss) private var dismiss
    @State private var workingRange: DateRange
    @State private var workingPreset: DateRangePreset
    @State private var refreshTrigger = false

    init(range: Binding<DateRange>, preset: Binding<DateRangePreset>? = nil) {
        _range = range
        presetBinding = preset
        let initial = range.wrappedValue
        _workingRange = State(initialValue: initial)
        _workingPreset = State(initialValue: preset?.wrappedValue ?? Self.detectPreset(from: initial))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Button(action: { shiftByDays(-1) }) {
                            Image(systemName: "chevron.left")
                                .accessibilityLabel(Strings.DateRange.previous.string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(Strings.DateRange.today.string) { applyPreset(.today) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(workingPreset == .today ? .accentColor : .primary)
                            .fontWeight(workingPreset == .today ? .semibold : .regular)

                        Button(action: { shiftByDays(1) }) {
                            Image(systemName: "chevron.right")
                                .accessibilityLabel(Strings.DateRange.next.string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(Strings.DateRange.all.string) { applyPreset(.all) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(workingPreset == .all ? .accentColor : .primary)
                            .fontWeight(workingPreset == .all ? .semibold : .regular)

                        Spacer()
                    }
                }
                Section(header: Text(Strings.DateRange.from.string)) {
                    DatePicker("", selection: Binding(
                        get: { workingRange.begin },
                        set: {
                            workingRange = DateRange(begin: $0, end: max($0, workingRange.end))
                            workingPreset = .custom
                            refreshTrigger.toggle()
                        }
                    ), in: ...workingRange.end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Section(header: Text(Strings.DateRange.to.string)) {
                    DatePicker("", selection: Binding(
                        get: { workingRange.end },
                        set: {
                            workingRange = DateRange(begin: min(workingRange.begin, $0), end: $0)
                            workingPreset = .custom
                            refreshTrigger.toggle()
                        }
                    ), in: workingRange.begin..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            .id(refreshTrigger)
            .navigationTitle(Strings.DateRange.custom.string)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.cancel.string) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.General.done.string) { commit() }
                }
            }
        }
        .presentationDetents([.fraction(0.5), .large])
    }

    private func applyPreset(_ preset: DateRangePreset) {
        workingPreset = preset
        let cal = Calendar.current
        switch preset {
        case .today:
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            workingRange = DateRange(begin: start, end: end)
        case .all:
            workingRange = DateRange(begin: .distantPast, end: .distantFuture)
        default:
            break
        }
        refreshTrigger.toggle()
    }

    private func shiftByDays(_ days: Int) {
        let cal = Calendar.current
        let newStart = cal.date(byAdding: .day, value: days, to: workingRange.begin) ?? workingRange.begin
        let newEnd = cal.date(byAdding: .day, value: days, to: workingRange.end) ?? workingRange.end
        workingRange = DateRange(begin: newStart, end: max(newStart, newEnd))
        workingPreset = .custom
        refreshTrigger.toggle()
    }

    private func commit() {
        range = workingRange
        presetBinding?.wrappedValue = workingPreset
        dismiss()
    }

    private static func detectPreset(from range: DateRange) -> DateRangePreset {
        if range.begin == .distantPast && range.end == .distantFuture { return .all }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return .custom }
        if range.begin == todayStart && range.end == todayEnd { return .today }
        return .custom
    }
}

#if DEBUG
#Preview {
    DateRangePickerSheet(range: .constant(DateRange.defaultRange()))
}
#endif
