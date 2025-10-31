import SwiftUI

struct DayTimelineView: View {
    let events: [CalendarEventWithUser]
    let members: [UUID: (name: String, color: Color)]
    @Binding var date: Date

    private let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            // All-day events bar
            allDayEventsBar
            dayGrid
        }
    }
    
    @ViewBuilder
    private var allDayEventsBar: some View {
        let allDayEvents = allDayEventsForDate(date)
        if !allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("all-day")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: timeColumnWidth - 8)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(allDayEvents, id: \.id) { event in
                                NavigationLink(destination: EventDetailView(event: event, member: members[event.user_id])) {
                                    HStack(spacing: 4) {
                                        Text(event.title.isEmpty ? "Busy" : event.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        if let name = members[event.user_id]?.name {
                                            Text("• \(name)")
                                                .font(.system(size: 10, weight: .regular))
                                                .lineLimit(1)
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(eventColor(event))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 8)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var dayGrid: some View {
        ScrollView {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    timeBackground
                    eventsOverlay(in: geometry)
                }
                .frame(height: hourHeight * 24)
            }
            .frame(minHeight: 600)
        }
    }

    private var timeBackground: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(label(for: hour))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: timeColumnWidth, height: hourHeight, alignment: .top)
                        .padding(.top, -8)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(Color.secondary.opacity(0.1)).frame(height: 1)
                    Spacer().frame(height: hourHeight - 1)
                }
            }
        }
    }

    private func eventsOverlay(in geometry: GeometryProxy) -> some View {
        let dayWidth = geometry.size.width - timeColumnWidth
        let dayEvents = eventsForDay(date)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dayEvents.enumerated()), id: \.element.id) { idx, e in
                let y = CGFloat(minutes(fromStart: e.start_date)) / 60.0 * hourHeight
                let h = CGFloat(max(30, minutesDuration(e))) / 60.0 * hourHeight
                NavigationLink(destination: EventDetailView(event: e, member: members[e.user_id])) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if let name = members[e.user_id]?.name { Text(name).font(.system(size: 10)) }
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(width: dayWidth - 8, height: max(40, h), alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(eventColor(e).opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(eventColor(e), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .offset(x: timeColumnWidth + 4, y: y + 1)
            }
        }
    }

    private func eventsForDay(_ day: Date) -> [CalendarEventWithUser] {
        // Only return timed events (not all-day)
        events.filter { 
            !$0.is_all_day && (Calendar.current.isDate($0.start_date, inSameDayAs: day) || ($0.start_date < day && $0.end_date > day))
        }
    }
    
    private func allDayEventsForDate(_ day: Date) -> [CalendarEventWithUser] {
        events.filter { 
            $0.is_all_day && Calendar.current.isDate($0.start_date, inSameDayAs: day)
        }
    }

    private func label(for hour: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "ha"
        let d = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return f.string(from: d).lowercased()
    }


    private func minutes(fromStart d: Date) -> Int {
        let h = Calendar.current.component(.hour, from: d)
        let m = Calendar.current.component(.minute, from: d)
        return h * 60 + m
    }
    private func minutesDuration(_ e: CalendarEventWithUser) -> Int { max(30, Int(e.end_date.timeIntervalSince(e.start_date) / 60)) }
    
    private func eventColor(_ e: CalendarEventWithUser) -> Color {
        if let color = e.effectiveColor {
            return Color(
                red: color.red,
                green: color.green,
                blue: color.blue,
                opacity: color.alpha
            )
        }
        return members[e.user_id]?.color ?? .blue
    }
}


