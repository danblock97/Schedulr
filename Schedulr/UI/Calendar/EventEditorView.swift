import SwiftUI
import Supabase
import Auth

struct EventEditorView: View {
    let groupId: UUID
    let members: [DashboardViewModel.MemberSummary]
    var existingEvent: CalendarEventWithUser? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var isAllDay: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var guestNamesText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveToAppleCalendar: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    Toggle("All day", isOn: $isAllDay)
                    DatePicker("Start", selection: $date, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    TextField("Location", text: $location)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }

                Section("Invite group members") {
                    ForEach(members) { member in
                        Toggle(isOn: Binding(
                            get: { selectedMemberIds.contains(member.id) },
                            set: { newVal in
                                if newVal { selectedMemberIds.insert(member.id) } else { selectedMemberIds.remove(member.id) }
                            }
                        )) {
                            Text(member.displayName)
                        }
                    }
                }

                Section("Guests not in group") {
                    TextField("Add names separated by commas", text: $guestNamesText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Calendar") {
                    Toggle("Save to Apple Calendar", isOn: $saveToAppleCalendar)
                        .accessibilityHint("Also creates/updates an Apple Calendar event")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(existingEvent == nil ? "New Event" : "Edit Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .task { prefillIfEditing() }
    }

    private func save() {
        Task {
            guard !isSaving else { return }
            isSaving = true
            defer { isSaving = false }
            do {
                let uid = try await SupabaseManager.shared.client.auth.session.user.id
                var ekId: String? = existingEvent?.original_event_id
                if saveToAppleCalendar {
                    if let existingId = ekId {
                        try await EventKitEventManager.shared.updateEvent(identifier: existingId, title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: date, end: endDate, isAllDay: isAllDay, location: location.isEmpty ? nil : location, notes: notes.isEmpty ? nil : notes)
                    } else {
                        ekId = try? await EventKitEventManager.shared.createEvent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: date, end: endDate, isAllDay: isAllDay, location: location.isEmpty ? nil : location, notes: notes.isEmpty ? nil : notes)
                    }
                }

                let input = NewEventInput(
                    groupId: groupId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: date,
                    end: endDate,
                    isAllDay: isAllDay,
                    location: location.isEmpty ? nil : location,
                    notes: notes.isEmpty ? nil : notes,
                    attendeeUserIds: Array(selectedMemberIds),
                    guestNames: guestNamesText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) },
                    originalEventId: ekId
                )
                if let existingEvent {
                    try await CalendarEventService.shared.updateEvent(eventId: existingEvent.id, input: input, currentUserId: uid)
                } else {
                    _ = try await CalendarEventService.shared.createEvent(input: input, currentUserId: uid)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prefillIfEditing() {
        guard let ev = existingEvent else { return }
        title = ev.title
        date = ev.start_date
        endDate = ev.end_date
        isAllDay = ev.is_all_day
        location = ev.location ?? ""
        notes = ev.notes ?? ""
        // Load attendees preselection
        Task {
            if let rows = try? await CalendarEventService.shared.loadAttendees(eventId: ev.id) {
                var ids = Set<UUID>()
                var guests: [String] = []
                for row in rows {
                    if let uid = row.userId { ids.insert(uid) } else { guests.append(row.displayName) }
                }
                selectedMemberIds = ids
                guestNamesText = guests.joined(separator: ", ")
            }
        }
    }
}


