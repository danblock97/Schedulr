import SwiftUI
import Supabase
import PostgREST

struct EventDetailView: View {
    let event: CalendarEventWithUser
    let member: (name: String, color: Color)?
    @State private var attendees: [Attendee] = []
    @State private var isLoading = true
    @State private var showingEditor = false

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

            if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if !attendees.isEmpty {
                Section("Attendees") {
                    ForEach(attendees) { a in
                        HStack {
                            Circle().fill((a.color ?? .blue).opacity(0.9)).frame(width: 8, height: 8)
                            Text(a.displayName)
                            Spacer()
                            Text(a.status.capitalized).foregroundStyle(.secondary).font(.footnote)
                        }
                    }
                }
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            EventEditorView(groupId: event.group_id, members: [], existingEvent: event)
        }
        .task { await loadAttendees() }
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

private struct Attendee: Identifiable { let id = UUID(); let displayName: String; let status: String; let color: Color? }

extension EventDetailView {
    private func loadAttendees() async {
        isLoading = true
        defer { isLoading = false }
        do {
            struct Row: Decodable {
                let user_id: UUID?
                let display_name: String?
                let status: String
                let users: UserInfo?
                struct UserInfo: Decodable { let display_name: String? }
            }
            let rows: [Row] = try await SupabaseManager.shared.client
                .from("event_attendees")
                .select("user_id, display_name, status, users(display_name)")
                .eq("event_id", value: event.id)
                .execute()
                .value

            attendees = rows.map { r in
                let explicit = r.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let nameFromUser = r.users?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolved = (explicit?.isEmpty == false ? explicit : nil)
                    ?? (nameFromUser?.isEmpty == false ? nameFromUser : nil)
                    ?? (r.user_id != nil ? "Member" : "Guest")
                let color = r.user_id.map { _ in Color.blue }
                return Attendee(displayName: resolved ?? "Guest", status: r.status, color: color)
            }
        } catch {
            attendees = []
        }
    }
}


