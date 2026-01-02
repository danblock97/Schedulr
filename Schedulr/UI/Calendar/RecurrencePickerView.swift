import SwiftUI

struct RecurrencePickerView: View {
    @Binding var recurrenceRule: RecurrenceRule?
    @Binding var isRecurring: Bool
    let eventStartDate: Date
    /// Optional initial rule to use for initialization (pass the parent event's rule when editing)
    var initialRule: RecurrenceRule? = nil

    @State private var frequency: RecurrenceFrequency = .weekly
    @State private var interval: Int = 1
    @State private var selectedDays: Set<Int> = []
    @State private var dayOfMonth: Int = 1
    @State private var endType: RecurrenceEndType = .never
    @State private var occurrenceCount: Int = 10
    @State private var endDate: Date = Date().addingTimeInterval(30 * 24 * 3600)
    @State private var hasInitialized = false

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 16) {
            CustomToggle(label: "Repeat", isOn: $isRecurring)

            if isRecurring {
                // Frequency picker
                CustomPicker(label: "Frequency", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }

                // Interval stepper
                HStack {
                    Text("Every")
                        .font(.subheadline)
                    Stepper(value: $interval, in: 1...30) {
                        Text("\(interval) \(interval == 1 ? singularUnit : frequency.pluralUnit)")
                            .font(.subheadline)
                    }
                }

                // Weekly: Day selection
                if frequency == .weekly {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        WeekdaySelector(selectedDays: $selectedDays)
                    }
                }

                // Monthly: Day of month
                if frequency == .monthly {
                    HStack {
                        Text("On day")
                            .font(.subheadline)
                        Stepper(value: $dayOfMonth, in: 1...31) {
                            Text("\(dayOfMonth)")
                                .font(.subheadline)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                // End type
                CustomPicker(label: "Ends", selection: $endType) {
                    ForEach(RecurrenceEndType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                switch endType {
                case .never:
                    EmptyView()
                case .afterCount:
                    HStack {
                        Text("After")
                            .font(.subheadline)
                        Stepper(value: $occurrenceCount, in: 1...365) {
                            Text("\(occurrenceCount) occurrences")
                                .font(.subheadline)
                        }
                    }
                case .onDate:
                    CustomDatePicker(
                        label: "End Date",
                        selection: $endDate,
                        displayedComponents: [.date]
                    )
                }

                // Preview description
                if let rule = buildRecurrenceRule() {
                    Text(RecurrenceService.shared.describeRecurrence(rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
        .onChange(of: isRecurring) { _, _ in updateRecurrenceRule() }
        .onChange(of: frequency) { _, newFreq in
            // Set default days for weekly
            if newFreq == .weekly && selectedDays.isEmpty {
                let weekday = Calendar.current.component(.weekday, from: eventStartDate) - 1
                selectedDays = [weekday]
            }
            // Set default day for monthly
            if newFreq == .monthly {
                dayOfMonth = Calendar.current.component(.day, from: eventStartDate)
            }
            updateRecurrenceRule()
        }
        .onChange(of: interval) { _, _ in updateRecurrenceRule() }
        .onChange(of: selectedDays) { _, _ in updateRecurrenceRule() }
        .onChange(of: dayOfMonth) { _, _ in updateRecurrenceRule() }
        .onChange(of: endType) { _, _ in updateRecurrenceRule() }
        .onChange(of: occurrenceCount) { _, _ in updateRecurrenceRule() }
        .onChange(of: endDate) { _, _ in updateRecurrenceRule() }
        .onAppear {
            initializeFromRule()
        }
        .onChange(of: recurrenceRule) { oldValue, newValue in
            // Re-initialize when the rule changes externally (e.g., when editing existing event)
            // Only if we haven't initialized yet or if the rule is significantly different
            if !hasInitialized || (newValue != nil && oldValue == nil) {
                initializeFromRule()
            }
        }
    }

    private func initializeFromRule() {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Use initialRule if provided (for editing), otherwise use recurrenceRule binding
        let ruleToUse = initialRule ?? recurrenceRule

        // Initialize from existing rule if editing
        if let rule = ruleToUse {
            isRecurring = true
            frequency = rule.frequency
            interval = rule.interval
            // Ensure we capture the days correctly
            if let days = rule.daysOfWeek, !days.isEmpty {
                selectedDays = Set(days)
            } else if frequency == .weekly {
                // Default to current weekday if no days specified
                let weekday = Calendar.current.component(.weekday, from: eventStartDate) - 1
                selectedDays = [weekday]
            }
            dayOfMonth = rule.dayOfMonth ?? Calendar.current.component(.day, from: eventStartDate)
            if let count = rule.count {
                endType = .afterCount
                occurrenceCount = count
            } else if let end = rule.endDate {
                endType = .onDate
                endDate = end
            } else {
                endType = .never
            }
        } else {
            // Set defaults based on event start date
            let weekday = Calendar.current.component(.weekday, from: eventStartDate) - 1
            selectedDays = [weekday]
            dayOfMonth = Calendar.current.component(.day, from: eventStartDate)
        }
    }

    private var singularUnit: String {
        switch frequency {
        case .daily: return "day"
        case .weekly: return "week"
        case .monthly: return "month"
        case .yearly: return "year"
        }
    }

    private func buildRecurrenceRule() -> RecurrenceRule? {
        guard isRecurring else { return nil }

        let count: Int? = endType == .afterCount ? occurrenceCount : nil
        let end: Date? = endType == .onDate ? endDate : nil

        switch frequency {
        case .daily:
            return .daily(interval: interval, count: count, endDate: end)
        case .weekly:
            let days = selectedDays.isEmpty ? [Calendar.current.component(.weekday, from: eventStartDate) - 1] : Array(selectedDays).sorted()
            return .weekly(interval: interval, daysOfWeek: days, count: count, endDate: end)
        case .monthly:
            return .monthly(interval: interval, dayOfMonth: dayOfMonth, count: count, endDate: end)
        case .yearly:
            let month = Calendar.current.component(.month, from: eventStartDate)
            let day = Calendar.current.component(.day, from: eventStartDate)
            return .yearly(interval: interval, monthOfYear: month, dayOfMonth: day, count: count, endDate: end)
        }
    }

    private func updateRecurrenceRule() {
        recurrenceRule = buildRecurrenceRule()
    }
}

struct WeekdaySelector: View {
    @Binding var selectedDays: Set<Int>
    @EnvironmentObject var themeManager: ThemeManager

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                Button {
                    if selectedDays.contains(index) {
                        // Don't allow deselecting if it's the only one
                        if selectedDays.count > 1 {
                            selectedDays.remove(index)
                        }
                    } else {
                        selectedDays.insert(index)
                    }
                } label: {
                    Text(weekdays[index])
                        .font(.caption.bold())
                        .frame(width: 36, height: 36)
                        .background(selectedDays.contains(index) ? themeManager.primaryColor : Color(.secondarySystemBackground))
                        .foregroundColor(selectedDays.contains(index) ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var recurrenceRule: RecurrenceRule? = nil
        @State private var isRecurring = false

        var body: some View {
            Form {
                RecurrencePickerView(
                    recurrenceRule: $recurrenceRule,
                    isRecurring: $isRecurring,
                    eventStartDate: Date()
                )
                .environmentObject(ThemeManager.shared)
            }
        }
    }

    return PreviewWrapper()
}
