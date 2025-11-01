import SwiftUI

struct MonthGridView: View {
    let events: [DisplayEvent]
    let members: [UUID: (name: String, color: Color)]
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let viewMode: MonthViewMode
    var onDateSelected: ((Date) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(minimum: 36, maximum: .infinity)), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: viewMode == .compact ? 4 : 6) {
                ForEach(daysInMonthGrid, id: \.self) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            
            // Event details for selected day (only in Details mode)
            if viewMode == .details {
                if let selectedDay = Calendar.current.startOfDay(for: selectedDate) as Date? {
                    let dayEvents = eventsForDay(selectedDay)
                    if !dayEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(inlineHeader(for: selectedDay))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            
                            ForEach(dayEvents) { e in
                                NavigationLink(destination: EventDetailView(event: e.base, member: members[e.base.user_id])) {
                                    MiniAgendaRow(event: e.base, member: members[e.base.user_id], sharedCount: e.sharedCount)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
            }
        }
    }


    private func dayCell(_ day: Date) -> some View {
        let isCurrentMonth = Calendar.current.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = Calendar.current.isDateInToday(day)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let dayEvents = eventsForDay(day)
        let dayNumber = Calendar.current.component(.day, from: day)
        
        return ZStack(alignment: .top) {
            // Date number - centered horizontally
            HStack {
                Spacer()
                Text("\(dayNumber)")
                    .font(.system(size: viewMode == .compact ? 15 : 17, weight: .regular))
                    .foregroundColor(isSelected ? .red : (isCurrentMonth ? .primary : .secondary))
                    .frame(width: 36, height: 36, alignment: .center)
                Spacer()
            }
            .padding(.top, viewMode == .compact ? 4 : 6)
            
            VStack(alignment: .leading, spacing: viewMode == .compact ? 2 : 4) {
                // Spacer to align content below day number
                Spacer()
                    .frame(height: viewMode == .compact ? 32 : 34)
            
            // Event indicators based on view mode
            if viewMode == .compact {
                // Compact: Single centered dot indicator
                if !dayEvents.isEmpty {
                    let eventColor = dayEvents.first?.base.effectiveColor != nil ? Color(
                        red: dayEvents.first!.base.effectiveColor!.red,
                        green: dayEvents.first!.base.effectiveColor!.green,
                        blue: dayEvents.first!.base.effectiveColor!.blue,
                        opacity: dayEvents.first!.base.effectiveColor!.alpha
                    ) : Color(red: 0.58, green: 0.41, blue: 0.87)
                    HStack {
                        Spacer()
                        Circle()
                            .fill(eventColor)
                            .frame(width: 7, height: 7)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
            } else if viewMode == .stacked {
                // Stacked: Event titles stacked
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(dayEvents.prefix(2)) { event in
                        Text(event.base.title.isEmpty ? "Busy" : event.base.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(event.base.effectiveColor != nil ? Color(
                                red: event.base.effectiveColor!.red,
                                green: event.base.effectiveColor!.green,
                                blue: event.base.effectiveColor!.blue,
                                opacity: event.base.effectiveColor!.alpha
                            ) : Color(red: 0.58, green: 0.41, blue: 0.87))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill((event.base.effectiveColor != nil ? Color(
                                        red: event.base.effectiveColor!.red,
                                        green: event.base.effectiveColor!.green,
                                        blue: event.base.effectiveColor!.blue,
                                        opacity: event.base.effectiveColor!.alpha
                                    ) : Color(red: 0.58, green: 0.41, blue: 0.87)).opacity(0.15))
                            )
                    }
                    if dayEvents.count > 2 {
                        Text("+\(dayEvents.count - 2)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            } else {
                // Details: Single centered dot indicator
                if !dayEvents.isEmpty {
                    let eventColor = dayEvents.first?.base.effectiveColor != nil ? Color(
                        red: dayEvents.first!.base.effectiveColor!.red,
                        green: dayEvents.first!.base.effectiveColor!.green,
                        blue: dayEvents.first!.base.effectiveColor!.blue,
                        opacity: dayEvents.first!.base.effectiveColor!.alpha
                    ) : Color(red: 0.58, green: 0.41, blue: 0.87)
                    HStack {
                        Spacer()
                        Circle()
                            .fill(eventColor)
                            .frame(width: 7, height: 7)
                        Spacer()
                    }
                    .padding(.bottom, 6)
                }
            }
                
                Spacer(minLength: 0)
            }
            
            // Red circle for selected/today - perfectly aligned with day number
            if isSelected || isToday {
                HStack {
                    Spacer()
                    Circle()
                        .stroke(Color.red, lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                    Spacer()
                }
                .padding(.top, viewMode == .compact ? 4 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: viewMode == .compact ? 44 : (viewMode == .stacked ? 60 : 50))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                selectedDate = day
                // Update displayedMonth if tapping a date from different month
                if !Calendar.current.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
                    displayedMonth = startOfMonth(for: day)
                }
                
                // Notify parent that a date was selected (to switch to Details mode if needed)
                if let onDateSelected = onDateSelected {
                    onDateSelected(day)
                }
            }
        }
    }


    private var daysInMonthGrid: [Date] {
        let start = startOfMonth(for: displayedMonth)
        let range = Calendar.current.range(of: .day, in: .month, for: start) ?? 1..<31
        var days: [Date] = range.compactMap { day -> Date? in
            Calendar.current.date(byAdding: .day, value: day - 1, to: start)
        }
        // prepend previous month days to align first weekday (Sunday = 1)
        let firstWeekday = Calendar.current.component(.weekday, from: start)
        let prefix = firstWeekday - 1 // Sunday = 1, so if Monday (2), prefix = 1
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
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        return events.filter { event in
            if event.base.is_all_day {
                // For all-day events, check if the day falls within the inclusive date range
                let eventStart = Calendar.current.startOfDay(for: event.base.start_date)
                let eventEnd = Calendar.current.startOfDay(for: event.base.end_date)
                // Day must be >= event start AND <= event end (inclusive)
                return dayStart >= eventStart && dayStart <= eventEnd
            } else {
                // For timed events, use overlap logic
                let eventStart = Calendar.current.startOfDay(for: event.base.start_date)
                let eventEnd = event.base.end_date
                
                // Event overlaps with the day if:
                // - Event starts before or on the day AND
                // - Event ends after the day starts
                return eventStart <= dayEnd && eventEnd > dayStart
            }
        }
    }

    private func startOfMonth(for date: Date) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: comps) ?? date
    }
    
    private func inlineHeader(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: date)
    }
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


