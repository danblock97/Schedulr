import SwiftUI

struct MonthGridView: View {
    let events: [DisplayEvent]
    let members: [UUID: (name: String, color: Color)]
    @Binding var selectedDate: Date

    @State private var displayedMonth: Date = Date()

    private let columns = Array(repeating: GridItem(.flexible(minimum: 36, maximum: .infinity)), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdayHeaders, id: \.self) { header in
                    Text(header)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(daysInMonthGrid, id: \.self) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal)

            // Inline agenda for selected day
            if let selectedDay = Calendar.current.startOfDay(for: selectedDate) as Date? {
                let dayEvents = eventsForDay(selectedDay)
                if !dayEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(inlineHeader(for: selectedDay))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal)
                        ForEach(dayEvents) { e in
                            NavigationLink(destination: EventDetailView(event: e.base, member: members[e.base.user_id])) {
                                MiniAgendaRow(event: e.base, member: members[e.base.user_id], sharedCount: e.sharedCount)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { displayedMonth = startOfMonth(for: selectedDate) }
    }

    private var monthHeader: some View {
        HStack {
            Button(action: { displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth }) {
                Image(systemName: "chevron.left.circle.fill").font(.title2)
                    .foregroundStyle(LinearGradient(colors: [
                        Color(red: 0.98, green: 0.29, blue: 0.55),
                        Color(red: 0.58, green: 0.41, blue: 0.87)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Spacer()
            Text(monthTitle(displayedMonth))
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
            Button(action: { displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth }) {
                Image(systemName: "chevron.right.circle.fill").font(.title2)
                    .foregroundStyle(LinearGradient(colors: [
                        Color(red: 0.98, green: 0.29, blue: 0.55),
                        Color(red: 0.58, green: 0.41, blue: 0.87)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .padding(.horizontal)
    }

    private func dayCell(_ day: Date) -> some View {
        let isCurrentMonth = Calendar.current.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let badgeCount = eventsForDay(day).count
        return VStack(spacing: 6) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected || isToday ? .white : (isCurrentMonth ? Color.primary : Color.secondary))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(isToday && !isSelected ? Color.blue : Color.clear)
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .opacity(isSelected ? 1 : 0)
                )
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
            } else {
                Spacer(minLength: 0)
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { selectedDate = day }
    }

    private var weekdayHeaders: [String] {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEEEE"
        return (0..<7).map { i in
            let d = Calendar.current.date(byAdding: .day, value: i, to: startOfWeek(for: Date())) ?? Date()
            return f.string(from: d)
        }
    }

    private var daysInMonthGrid: [Date] {
        let start = startOfMonth(for: displayedMonth)
        let range = Calendar.current.range(of: .day, in: .month, for: start) ?? 1..<31
        var days: [Date] = range.compactMap { day -> Date? in
            Calendar.current.date(byAdding: .day, value: day - 1, to: start)
        }
        // prepend previous month days to align first weekday
        let firstWeekday = Calendar.current.component(.weekday, from: start)
        let prefix = (firstWeekday + 6) % 7
        if prefix > 0 {
            for i in 1...prefix {
                if let d = Calendar.current.date(byAdding: .day, value: -i, to: start) { days.insert(d, at: 0) }
            }
        }
        // append next month days to fill rows
        while days.count % 7 != 0 { days.append(Calendar.current.date(byAdding: .day, value: 1, to: days.last ?? start)!) }
        return days
    }

    private func eventsForDay(_ day: Date) -> [DisplayEvent] {
        events.filter { Calendar.current.isDate($0.base.start_date, inSameDayAs: day) }
    }

    private func monthTitle(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: date) }
    private func startOfWeek(for date: Date) -> Date { Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date }
    private func startOfMonth(for date: Date) -> Date { let comps = Calendar.current.dateComponents([.year, .month], from: date); return Calendar.current.date(from: comps) ?? date }
    private func inlineHeader(for date: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f.string(from: date) }
}

private struct MiniAgendaRow: View {
    let event: CalendarEventWithUser
    let member: (name: String, color: Color)?
    var sharedCount: Int = 1

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(eventColor.opacity(0.9))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Busy" : event.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if sharedCount > 1 {
                    Text("shared by \(sharedCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock.fill").font(.system(size: 11)).foregroundColor(.secondary)
                    Text(timeSummary(event))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(location).font(.system(size: 12)).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func timeSummary(_ e: CalendarEventWithUser) -> String {
        if e.is_all_day { return "All day" }
        let t = DateFormatter(); t.dateStyle = .none; t.timeStyle = .short
        if Calendar.current.isDate(e.start_date, inSameDayAs: e.end_date) {
            return "\(t.string(from: e.start_date)) – \(t.string(from: e.end_date))"
        }
        let d = DateFormatter(); d.dateStyle = .medium; d.timeStyle = .none
        return "\(d.string(from: e.start_date)) \(t.string(from: e.start_date)) → \(d.string(from: e.end_date)) \(t.string(from: e.end_date))"
    }
    
    private var eventColor: Color {
        if let color = event.effectiveColor {
            return Color(
                red: color.red,
                green: color.green,
                blue: color.blue,
                opacity: color.alpha
            )
        }
        return member?.color ?? .blue
    }
}


