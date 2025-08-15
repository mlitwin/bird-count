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
    @State private var showCustomSheet: Bool = false
    @State private var previousPreset: RangePreset? = nil

    public init(preset: Binding<RangePreset>, startDate: Binding<Date>, endDate: Binding<Date>) {
        self._preset = preset
        self._startDate = startDate
        self._endDate = endDate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Range").font(.headline)
            HStack(spacing: 8) {
                // Shift range one day back
                Button(action: { shiftRangeByDays(-1); preset = .custom }) {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Previous day")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Today preset
                Button("Today") { applyRangePreset(.today); preset = .today }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                // Shift range one day forward
                Button(action: { shiftRangeByDays(1); preset = .custom }) {
                    Image(systemName: "chevron.right")
                        .accessibilityLabel("Next day")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // All preset
                Button("All") { applyRangePreset(.all); preset = .all }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                // Custom opens sheet
                Button("Custom") {
                    previousPreset = preset
                    preset = .custom
                    showCustomSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Text representation of the current date range
            Text(rangeSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomRangeSheet(startDate: $startDate, endDate: $endDate, onCancel: {
                // Revert to previous preset if cancel
                if let prev = previousPreset { preset = prev }
            }, onDone: {
                // Ensure Custom is selected when done
                preset = .custom
            })
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

    private func shiftRangeByDays(_ days: Int) {
        let cal = Calendar.current
        let newStart = cal.date(byAdding: .day, value: days, to: startDate) ?? startDate
        let newEnd = cal.date(byAdding: .day, value: days, to: endDate) ?? endDate
        startDate = newStart
        endDate = max(newStart, newEnd)
    }

    // Summary string for the currently selected range
    private var rangeSummary: String {
        let style = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .year()
            .hour()
            .minute()
        return "\(startDate.formatted(style)) – \(endDate.formatted(style))"
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
