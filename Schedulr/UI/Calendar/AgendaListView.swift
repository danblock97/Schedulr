import SwiftUI

struct AgendaListView: View {
    let events: [DisplayEvent]
    let members: [UUID: (name: String, color: Color)]
    @Binding var selectedDate: Date

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped.keys.sorted(), id: \.self) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            // Date header
                            Text(headerTitle(for: day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isTodayOrFirst(day) ? .red : .primary)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                                .id(day)
                            
                            // Events for this day
                            ForEach(grouped[day] ?? []) { devent in
                                NavigationLink(destination: EventDetailView(event: devent.base, member: members[devent.base.user_id])) {
                                    AgendaRow(event: devent.base, member: members[devent.base.user_id], sharedCount: devent.sharedCount)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .onAppear {
                // attempt to scroll to today
                if let todayKey = Calendar.current.startOfDay(for: Date()) as Date? {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(todayKey, anchor: .top)
                    }
                }
            }
        }
    }

    private var grouped: [Date: [DisplayEvent]] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.base.start_date) }
    }
    
    private func isTodayOrFirst(_ date: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let dayStart = Calendar.current.startOfDay(for: date)
        
        // First date in list or today
        if let firstDate = grouped.keys.sorted().first, dayStart == firstDate {
            return true
        }
        return Calendar.current.isDate(dayStart, inSameDayAs: today)
    }

    private func headerTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE — d MMM"
        return formatter.string(from: date)
    }
}

private struct AgendaRow: View {
    let event: CalendarEventWithUser
    let member: (name: String, color: Color)?
    var sharedCount: Int = 1

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Purple star icon (Apple Calendar style)
            Image(systemName: "star.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0.58, green: 0.41, blue: 0.87))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // Event title
                Text(event.title.isEmpty ? "Busy" : event.title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.primary)

                // Time and "all-day" indicator
                HStack(spacing: 4) {
                    if event.is_all_day {
                        Text("all-day")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                    } else {
                        Text(timeSummary(event))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
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


