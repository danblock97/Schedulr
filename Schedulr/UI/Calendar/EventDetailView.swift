import SwiftUI
import Supabase
import PostgREST

struct EventDetailView: View {
    let event: CalendarEventWithUser
    let member: (name: String, color: Color)?
    @State private var attendees: [Attendee] = []
    @State private var myStatus: String = "invited"
    @State private var currentUserId: UUID?
    @State private var isUpdatingResponse = false
    @State private var isProgrammaticStatusChange = false
    @State private var hasInitializedStatus = false
    @State private var isLoading = true
    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    
    private let responseOptions = [
        ("invited", "Not responded"),
        ("going", "Going"),
        ("maybe", "Maybe"),
        ("declined", "Decline")
    ]

    private let attendeeStatusOrder: [String] = ["going", "maybe", "invited"]

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(eventColor.opacity(0.9)).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title.isEmpty ? "Busy" : event.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        if let name = member?.name {
                            Text(name).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        if let catName = event.category?.name {
                            HStack(spacing: 6) {
                                Circle().fill(eventColor).frame(width: 8, height: 8)
                                Text(catName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                            }
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
                // Group by status and render in a stable order
                ForEach(attendeeStatusOrder, id: \.self) { statusKey in
                    let group = attendees.filter { $0.status.lowercased() == statusKey }
                    if !group.isEmpty {
                        Section("\(statusDisplayName(statusKey)) (\(group.count))") {
                            ForEach(group) { a in
                                HStack {
                                    Circle().fill((a.color ?? .blue).opacity(0.9)).frame(width: 8, height: 8)
                                    Text(a.displayName)
                                    Spacer()
                                    Text(statusDisplayName(a.status))
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            Section("Your response") {
                Menu {
                    // Going
                    Button(action: {
                        if isUpdatingResponse { return }
                        let previous = myStatus
                        isProgrammaticStatusChange = true
                        myStatus = "going"
                        isProgrammaticStatusChange = false
                        respond("going", previousStatus: previous)
                    }) {
                        Label("Going", systemImage: myStatus == "going" ? "checkmark.circle.fill" : "circle")
                    }

                    // Maybe
                    Button(action: {
                        if isUpdatingResponse { return }
                        let previous = myStatus
                        isProgrammaticStatusChange = true
                        myStatus = "maybe"
                        isProgrammaticStatusChange = false
                        respond("maybe", previousStatus: previous)
                    }) {
                        Label("Maybe", systemImage: myStatus == "maybe" ? "checkmark.circle.fill" : "circle")
                    }

                    // Decline
                    Button(role: .destructive, action: {
                        if isUpdatingResponse { return }
                        let previous = myStatus
                        isProgrammaticStatusChange = true
                        myStatus = "declined"
                        isProgrammaticStatusChange = false
                        respond("declined", previousStatus: previous)
                    }) {
                        Label("Decline", systemImage: myStatus == "declined" ? "checkmark.circle.fill" : "circle")
                    }
                } label: {
                    HStack {
                        Text("Response")
                        Spacer()
                        Text(statusDisplayName(myStatus))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isUpdatingResponse)
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { showingEditor = true }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this event?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteEvent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the event for everyone in the group if you created it.")
        }
        .sheet(isPresented: $showingEditor) {
            EventEditorView(groupId: event.group_id, members: [], existingEvent: event)
        }
        .task {
            // Get current user ID first
            currentUserId = try? await SupabaseManager.shared.client.auth.session.user.id
            await loadAttendees()
        }
    }

    private var eventColor: Color {
        if let c = event.effectiveColor {
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }
        return member?.color ?? .blue
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
    
    private func statusDisplayName(_ status: String) -> String {
        switch status.lowercased() {
        case "going": return "Going"
        case "maybe": return "Maybe"
        case "declined": return "Declined"
        case "invited": return "Invited"
        default: return status.capitalized
        }
    }
}

extension EventDetailView {
    private func respond(_ status: String, previousStatus: String) {
        // Status is already updated optimistically via the picker binding
        Task {
            await MainActor.run { isUpdatingResponse = true }
            let uid: UUID
            if let existing = currentUserId {
                uid = existing
            } else if let fetched = try? await SupabaseManager.shared.client.auth.session.user.id {
                uid = fetched
                await MainActor.run { currentUserId = fetched }
            } else {
                // Revert if we can't get user ID
                await MainActor.run {
                    isProgrammaticStatusChange = true
                    myStatus = previousStatus
                    isProgrammaticStatusChange = false
                }
                await MainActor.run { isUpdatingResponse = false }
                return
            }
            
            do {
                try await CalendarEventService.shared.updateMyStatus(eventId: event.id, status: status, currentUserId: uid)
                await loadAttendees()
            } catch {
                // Revert status on error
                await MainActor.run {
                    isProgrammaticStatusChange = true
                    myStatus = previousStatus
                    isProgrammaticStatusChange = false
                }
            }
            await MainActor.run { isUpdatingResponse = false }
        }
    }

    private func deleteEvent() {
        Task {
            guard !isDeleting else { return }
            isDeleting = true
            defer { isDeleting = false }
            do {
                if let uid = try? await SupabaseManager.shared.client.auth.session.user.id {
                    try await CalendarEventService.shared.deleteEvent(eventId: event.id, currentUserId: uid, originalEventId: event.original_event_id)
                    // Refresh the calendar to remove the deleted event from the UI
                    try? await calendarSync.fetchGroupEvents(groupId: event.group_id)
                    dismiss()
                }
            } catch {
                // Swallow error for now; could show toast/alert
            }
        }
    }
}

private struct Attendee: Identifiable {
    let id: UUID
    let userId: UUID?
    let displayName: String
    let status: String
    let color: Color?
}

extension EventDetailView {
    private func loadAttendees() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await CalendarEventService.shared.loadAttendees(eventId: event.id)

            let currentUserIdValue: UUID?
            if let existing = currentUserId {
                currentUserIdValue = existing
            } else {
                currentUserIdValue = try? await SupabaseManager.shared.client.auth.session.user.id
                if let fetched = currentUserIdValue {
                    await MainActor.run { currentUserId = fetched }
                }
            }

            // Filter out declined attendees and map to Attendee struct
            let mappedAttendees = rows
                .filter { $0.status.lowercased() != "declined" }
                .map { r in
                    let name = r.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolved = name.isEmpty ? (r.userId != nil ? "Member" : "Guest") : name
                    let color = r.userId.map { _ in Color.blue }
                    return Attendee(
                        id: UUID(),
                        userId: r.userId,
                        displayName: resolved,
                        status: r.status,
                        color: color
                    )
                }

            await MainActor.run {
                attendees = mappedAttendees
                // Initialize myStatus only once from server to avoid flicker
                if !hasInitializedStatus {
                    isProgrammaticStatusChange = true
                    defer { isProgrammaticStatusChange = false }
                    if let userId = currentUserIdValue,
                       let myAttendee = rows.first(where: { $0.userId == userId }) {
                        myStatus = myAttendee.status.lowercased()
                    } else {
                        myStatus = "invited"
                    }
                    hasInitializedStatus = true
                }
            }
        } catch {
            await MainActor.run { attendees = [] }
        }
    }
}


