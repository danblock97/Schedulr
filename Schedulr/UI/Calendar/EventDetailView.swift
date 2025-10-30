import SwiftUI

struct EventDetailView: View {
    let event: CalendarEventWithUser
    let member: (name: String, color: Color)?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill((member?.color ?? .blue).opacity(0.9)).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title.isEmpty ? "Busy" : event.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        if let name = member?.name {
                            Text(name).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("When") {
                Label(timeRange(event), systemImage: "clock")
            }

            if let location = event.location, !location.isEmpty {
                Section("Location") {
                    Label(location, systemImage: "location")
                }
            }

            if let calendar = event.calendar_name {
                Section("Calendar") {
                    Label(calendar, systemImage: "calendar")
                }
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeRange(_ e: CalendarEventWithUser) -> String {
        if e.is_all_day { return "All day • " + day(e.start_date) }
        let t = DateFormatter(); t.timeStyle = .short; t.dateStyle = .none
        if Calendar.current.isDate(e.start_date, inSameDayAs: e.end_date) {
            return "\(day(e.start_date)) • \(t.string(from: e.start_date)) – \(t.string(from: e.end_date))"
        }
        return "\(day(e.start_date)) \(t.string(from: e.start_date)) → \(day(e.end_date)) \(t.string(from: e.end_date))"
    }
    private func day(_ d: Date) -> String { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f.string(from: d) }
}


