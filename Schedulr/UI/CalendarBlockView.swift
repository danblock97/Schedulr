import SwiftUI

enum CalendarViewType: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { self.rawValue }
}

struct CalendarBlockView: View {
    let events: [CalendarEventWithUser]
    let members: [UUID: (name: String, color: Color)]
    @State private var currentWeekStart: Date = Date().startOfWeek()
    @State private var selectedDate: Date = Date()
    @State private var viewType: CalendarViewType = .week

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 50

    var body: some View {
        VStack(spacing: 12) {
            // View type picker
            Picker("View Type", selection: $viewType) {
                ForEach(CalendarViewType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            switch viewType {
            case .day:
                dayView
            case .week:
                weekView
            case .month:
                MonthlyCalendarView()
            }
        }
    }

    private var dayView: some View {
        VStack {
            dayNavigationHeader
            dayHeaders()
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        timeGridBackground
                        eventsOverlay(in: geometry)
                    }
                    .frame(height: hourHeight * 24)
                }
                .frame(minHeight: 500)
            }
        }
    }

    private var dayNavigationHeader: some View {
        HStack {
            Button(action: previousDay) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Spacer()

            Text(dayViewDateText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Spacer()

            Button(action: nextDay) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .padding(.horizontal)
    }

    private var dayViewDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: selectedDate)
    }

    private func previousDay() {
        if let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = newDate
        }
    }

    private func nextDay() {
        if let newDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = newDate
        }
    }

    private var weekView: some View {
        VStack {
            // Week navigation header
            weekNavigationHeader

            // Day of week headers
            dayHeaders()

            // Calendar grid
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        // Time labels and grid lines
                        timeGridBackground

                        // Events
                        eventsOverlay(in: geometry)
                    }
                    .frame(height: hourHeight * 24)
                }
                .frame(minHeight: 500)
            }

            // Legend
            if !members.isEmpty {
                legendView
            }
        }
    }

    // MARK: - Week Navigation Header

    private var weekNavigationHeader: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Spacer()

            VStack(spacing: 2) {
                Text(weekRangeText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                if isCurrentWeek {
                    Text("This Week")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: next) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .padding(.horizontal)
    }



    // MARK: - Day Headers

    private func dayHeaders(for day: Date? = nil) -> some View {
        HStack(spacing: 0) {
            // Empty space for time column
            Color.clear
                .frame(width: timeColumnWidth)

            if let day = day {
                dayHeaderCell(for: day)
            } else {
                ForEach(weekDays, id: \.self) { date in
                    dayHeaderCell(for: date)
                }
            }
        }
    }

    private func dayHeaderCell(for date: Date) -> some View {
        VStack(spacing: 4) {
            Text(dayOfWeek(date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(isToday(date) ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(
                            isToday(date) ?
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                (calendar.isDate(date, inSameDayAs: selectedDate) && !isToday(date)) ?
                                LinearGradient(
                                    colors: [.gray.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                )
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {
            selectedDate = date
        }
    }

    // MARK: - Time Grid Background

    private var timeGridBackground: some View {
        HStack(spacing: 0) {
            // Time labels
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(timeLabel(for: hour))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: timeColumnWidth, height: hourHeight, alignment: .top)
                        .padding(.top, -8)
                }
            }

            // Grid for each day
            ForEach(weekDays, id: \.self) { _ in
                dayGrid
            }
        }
    }

    private var dayGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)

                Spacer()
                    .frame(height: hourHeight - 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Events Overlay

    private func eventsOverlay(in geometry: GeometryProxy) -> some View {
        let dayWidth = (geometry.size.width - timeColumnWidth) / 7

        return ZStack {
            ForEach(Array(weekDays.enumerated()), id: \.element) { index, date in
                if calendar.isDate(date, inSameDayAs: selectedDate) {
                    let dayEvents = eventsForDay(date)

                    ForEach(Array(dayEvents.enumerated()), id: \.element.id) { eventIndex, event in
                        eventBlock(
                            event: event,
                            dayIndex: index,
                            dayWidth: dayWidth,
                            totalEventsInSlot: dayEvents.count,
                            eventIndexInSlot: eventIndex
                        )
                    }
                }
            }
        }
    }

    private func eventBlock(
        event: CalendarEventWithUser,
        dayIndex: Int,
        dayWidth: CGFloat,
        totalEventsInSlot: Int,
        eventIndexInSlot: Int
    ) -> some View {
        let startMinutes = minutesFromMidnight(event.start_date)
        let endMinutes = minutesFromMidnight(event.end_date)
        let durationMinutes = max(endMinutes - startMinutes, 30) // Minimum 30 minutes

        let yOffset = (CGFloat(startMinutes) / 60.0) * hourHeight
        let height = (CGFloat(durationMinutes) / 60.0) * hourHeight

        // Calculate horizontal position for overlapping events
        let eventWidth = dayWidth / CGFloat(max(totalEventsInSlot, 1))
        let xOffset = timeColumnWidth + (CGFloat(dayIndex) * dayWidth) + (CGFloat(eventIndexInSlot) * eventWidth)

        let userColor = members[event.user_id]?.color ?? .gray

        return VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if let userName = members[event.user_id]?.name {
                Text(userName)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }

            if let location = event.location {
                Text(location)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(width: eventWidth - 4, height: max(height - 2, 40), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(userColor.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(userColor, lineWidth: 2)
        )
        .offset(x: xOffset + 2, y: yOffset + 1)
    }

    // MARK: - Legend

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group Members")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120), spacing: 12)
            ], spacing: 8) {
                ForEach(Array(members.keys.sorted(by: { members[$0]?.name ?? "" < members[$1]?.name ?? "" })), id: \.self) { userId in
                    if let member = members[userId] {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(member.color)
                                .frame(width: 12, height: 12)

                            Text(member.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Helper Methods

    private var isCurrentWeek: Bool {
        let today = Date()
        return calendar.isDate(today, equalTo: currentWeekStart, toGranularity: .weekOfYear)
    }

    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func timeLabel(for hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }

    private func eventsForDay(_ date: Date) -> [CalendarEventWithUser] {
        events.filter { event in
            calendar.isDate(event.start_date, inSameDayAs: date) ||
            (event.start_date < date && event.end_date > date)
        }
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: currentWeekStart)
        }
    }

    private var weekRangeText: String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let startMonth = calendar.component(.month, from: currentWeekStart)
        let endMonth = calendar.component(.month, from: weekEnd)

        if startMonth == endMonth {
            return "\(formatter.string(from: currentWeekStart)) - \(calendar.component(.day, from: weekEnd))"
        } else {
            return "\(formatter.string(from: currentWeekStart)) - \(formatter.string(from: weekEnd))"
        }
    }

    private func previous() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }

    private func next() {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }
}

// MARK: - Date Extension

extension Date {
    func startOfWeek(using calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
}

// MARK: - Preview

#Preview {
    let sampleEvents: [CalendarEventWithUser] = [
        CalendarEventWithUser(
            id: UUID(),
            user_id: UUID(),
            group_id: UUID(),
            title: "Team Meeting",
            start_date: Date().addingTimeInterval(3600 * 2),
            end_date: Date().addingTimeInterval(3600 * 3),
            is_all_day: false,
            location: "Conference Room A",
            is_public: true,
            original_event_id: "1",
            calendar_name: "Work",
            calendar_color: nil,
            created_at: Date(),
            updated_at: Date(),
            synced_at: Date(),
            notes: nil,
            category_id: nil,
            user: DBUser(id: UUID(), display_name: "John Doe", avatar_url: nil, created_at: Date(), updated_at: Date()),
            category: nil,
            hasAttendees: true
        )
    ]

    let sampleMembers: [UUID: (name: String, color: Color)] = [
        sampleEvents[0].user_id: ("John Doe", .blue)
    ]

    CalendarBlockView(events: sampleEvents, members: sampleMembers)
        .padding()
}
