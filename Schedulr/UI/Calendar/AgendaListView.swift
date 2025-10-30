import SwiftUI

struct AgendaListView: View {
    let events: [DisplayEvent]
    let members: [UUID: (name: String, color: Color)]
    @Binding var selectedDate: Date

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(grouped.keys.sorted(), id: \.self) { day in
                    Section(header: dayHeader(day)) {
                        ForEach(grouped[day] ?? []) { devent in
                            NavigationLink(destination: EventDetailView(event: devent.base, member: members[devent.base.user_id])) {
                                AgendaRow(event: devent.base, member: members[devent.base.user_id], sharedCount: devent.sharedCount)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                // attempt to scroll to today
                if let todayKey = Calendar.current.startOfDay(for: Date()) as Date? {
                    proxy.scrollTo(todayKey, anchor: .top)
                }
            }
        }
    }

    private var grouped: [Date: [DisplayEvent]] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.base.start_date) }
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack {
            Text(headerTitle(for: date))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .id(date)
    }

    private func headerTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE — d MMM yyyy"
        return f.string(from: date)
    }
}

private struct AgendaRow: View {
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


