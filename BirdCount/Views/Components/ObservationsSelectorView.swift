import SwiftUI

public struct ObservationsSelectorView: View {
    @Environment(DateRangeStore.self) private var dateRangeStore
    @State private var showCustomSheet: Bool = false
    @State private var previousPreset: DateRangePreset? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(rangeSummary)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                
                Spacer()
                
                Button(action: {
                    previousPreset = dateRangeStore.dateRangePreset
                    // Don't change the preset when opening the sheet - let it stay as is
                    showCustomSheet = true
                }) {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .padding(8)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel("Edit range")
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomRangeSheet(
                onCancel: {
                    if let prev = previousPreset { dateRangeStore.setPreset(prev) }
                    previousPreset = nil
                },
                onDone: {
                    // Don't override the preset - let it remain as set by the buttons
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
            return "All time"
        }
        if preset == .today {
            return "Today"
        }
        let cal = Calendar.current
        let sameDay = cal.isDate(startDate, inSameDayAs: endDate)
        
        // Check if this is a complete day (starts at midnight, ends at midnight next day)
        let isCompleteDay = cal.isDate(startDate, equalTo: cal.startOfDay(for: startDate), toGranularity: .second) &&
                           cal.isDate(endDate, equalTo: cal.startOfDay(for: endDate), toGranularity: .second) &&
                           cal.dateInterval(of: .day, for: startDate)?.end == endDate
        
        if isCompleteDay {
            return Formatters.mdy.string(from: startDate)
        }
        
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
    @Environment(DateRangeStore.self) private var dateRangeStore
    let onCancel: () -> Void
    let onDone: () -> Void
    
    @State private var refreshTrigger = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Button(action: { 
                            shiftRangeByDays(-1) 
                            dateRangeStore.setPreset(.custom)
                            refreshTrigger.toggle()
                        }) {
                            Image(systemName: "chevron.left")
                                .accessibilityLabel("Previous day")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Today") { 
                            dateRangeStore.setPreset(.today)
                            refreshTrigger.toggle()
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(dateRangeStore.dateRangePreset == .today ? .accentColor : .primary)
                            .fontWeight(dateRangeStore.dateRangePreset == .today ? .semibold : .regular)

                        Button(action: { 
                            shiftRangeByDays(1) 
                            dateRangeStore.setPreset(.custom)
                            refreshTrigger.toggle()
                        }) {
                            Image(systemName: "chevron.right")
                                .accessibilityLabel("Next day")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("All") { 
                            dateRangeStore.setPreset(.all)
                            refreshTrigger.toggle()
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(dateRangeStore.dateRangePreset == .all ? .accentColor : .primary)
                            .fontWeight(dateRangeStore.dateRangePreset == .all ? .semibold : .regular)

                        Spacer()
                    }
                }
                Section(header: Text("From")) {
                    DatePicker("", selection: Binding(
                        get: { dateRangeStore.dateRange.begin },
                        set: { newStart in
                            dateRangeStore.update(DateRange(begin: newStart, end: dateRangeStore.dateRange.end))
                            dateRangeStore.dateRangePreset = .custom
                            refreshTrigger.toggle()
                        }
                    ), in: ...dateRangeStore.dateRange.end, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Section(header: Text("To")) {
                    DatePicker("", selection: Binding(
                        get: { dateRangeStore.dateRange.end },
                        set: { newEnd in
                            dateRangeStore.update(DateRange(begin: dateRangeStore.dateRange.begin, end: newEnd))
                            dateRangeStore.dateRangePreset = .custom
                            refreshTrigger.toggle()
                        }
                    ), in: dateRangeStore.dateRange.begin... , displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
            .id(refreshTrigger) // Force refresh when refreshTrigger changes
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
    
    private func shiftRangeByDays(_ days: Int) {
        dateRangeStore.shiftRangeByDays(days)
    }
}
