import SwiftUI

public struct ObservationsSelectorView: View {
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var showCustomSheet: Bool = false
    @State private var previousPreset: DateRangePreset? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: { shiftRangeByDays(-1); dateRangeStore.setPreset(.custom) }) {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Previous day")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Today") { applyRangePreset(.today); dateRangeStore.setPreset(.today) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(dateRangeStore.dateRangePreset == .today ? .accentColor : .primary)
                    .fontWeight(dateRangeStore.dateRangePreset == .today ? .semibold : .regular)

                Button(action: { shiftRangeByDays(1); dateRangeStore.setPreset(.custom) }) {
                    Image(systemName: "chevron.right")
                        .accessibilityLabel("Next day")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("All") { applyRangePreset(.all); dateRangeStore.setPreset(.all) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()
            }
            Button(action: {
                previousPreset = dateRangeStore.dateRangePreset
                dateRangeStore.setPreset(.custom)
                showCustomSheet = true
            }) {
                Text(rangeSummary)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.2))
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom range")
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomRangeSheet(
                startDate: .constant(dateRangeStore.dateRange.begin),
                endDate: .constant(dateRangeStore.dateRange.end),
                onCancel: {
                    if let prev = previousPreset { dateRangeStore.setPreset(prev) }
                    previousPreset = nil
                },
                onDone: {
                    dateRangeStore.setPreset(.custom)
                    previousPreset = nil
                }
            )
            .onAppear {
                if previousPreset == nil {
                    previousPreset = dateRangeStore.dateRangePreset
                }
            }
        }
        // Keep preset in sync if range equals the Today preset values (via chevrons or custom sheet)
        .onChange(of: dateRangeStore.dateRange.begin) { _, _ in syncPresetWithCurrentRange() }
        .onChange(of: dateRangeStore.dateRange.end) { _, _ in syncPresetWithCurrentRange() }
        // Auto-update when the calendar day changes while the app is active
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if dateRangeStore.dateRangePreset == .today {
                dateRangeStore.applyPreset(.today)
            }
        }
        .onAppear { syncPresetWithCurrentRange() }
    }

    private func applyRangePreset(_ p: DateRangePreset) {
        dateRangeStore.applyPreset(p)
    }

    private func shiftRangeByDays(_ days: Int) {
        dateRangeStore.shiftRangeByDays(days)
    }

    // Summary string for the currently selected range (compact, likely to fit one line)
    private var rangeSummary: String {
        let preset = dateRangeStore.dateRangePreset
        let startDate = dateRangeStore.dateRange.begin
        let endDate = dateRangeStore.dateRange.end
        if preset == .all {
            return "All time – Now"
        }
        let cal = Calendar.current
        let sameDay = cal.isDate(startDate, inSameDayAs: endDate)
        let sameYear = cal.component(.year, from: startDate) == cal.component(.year, from: endDate)
        let sameMonth = sameYear && cal.component(.month, from: startDate) == cal.component(.month, from: endDate)

        let startHM = Formatters.hm.string(from: startDate)
        let endHM = Formatters.hm.string(from: endDate)

        if sameDay {
            return "\(Formatters.mdy.string(from: startDate)) \(startHM) – \(endHM)"
        } else if sameMonth {
            let startMD = Formatters.md.string(from: startDate)
            let endD = String(cal.component(.day, from: endDate))
            return "\(startMD) \(startHM) – \(endD) \(endHM)"
        } else if sameYear {
            let startMD = Formatters.md.string(from: startDate)
            let endMD = Formatters.md.string(from: endDate)
            return "\(startMD) \(startHM) – \(endMD) \(endHM)"
        } else {
            let startMDY = Formatters.mdy.string(from: startDate)
            let endMDY = Formatters.mdy.string(from: endDate)
            return "\(startMDY) \(startHM) – \(endMDY) \(endHM)"
        }
    }

    private enum Formatters {
        static let hm: DateFormatter = {
            let df = DateFormatter()
            df.timeStyle = .short
            df.dateStyle = .none
            return df
        }()
        static let md: DateFormatter = {
            let df = DateFormatter()
            df.setLocalizedDateFormatFromTemplate("MMMd") // e.g., Aug 14
            return df
        }()
        static let mdy: DateFormatter = {
            let df = DateFormatter()
            df.setLocalizedDateFormatFromTemplate("MMMdyyyy") // e.g., Aug 14, 2025
            return df
        }()
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
            // If the range no longer equals today's boundaries, deselect Today
            dateRangeStore.setPreset(.custom)
        }
    }
}

// MARK: - Custom Range Sheet
private struct CustomRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("From")) {
                    DatePicker("", selection: $startDate, in: ...endDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Section(header: Text("To")) {
                    DatePicker("", selection: $endDate, in: startDate... , displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            .navigationTitle("Custom Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.5), .large])
    }
}
