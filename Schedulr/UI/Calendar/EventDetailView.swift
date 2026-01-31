import SwiftUI
import Supabase
import PostgREST

struct EventDetailView: View {
    let event: CalendarEventWithUser
    let member: (name: String, color: Color)?
    let currentUserId: UUID?
    @State private var displayEvent: CalendarEventWithUser?
    @State private var attendees: [Attendee] = []
    @State private var myStatus: String = "invited"
    @State private var resolvedCurrentUserId: UUID?
    @State private var isUpdatingResponse = false
    @State private var isProgrammaticStatusChange = false
    @State private var hasInitializedStatus = false
    @State private var isLoading = true
    @State private var showingEditor = false
    @State private var showingDeleteConfirm = false
    @State private var showingRecurringDeleteSheet = false
    @State private var showingRecurringEditSheet = false
    @State private var selectedDeleteScope: RecurringEditScope?
    @State private var selectedEditScope: RecurringEditScope = .allOccurrences
    @State private var isDeleting = false
    @State private var isCurrentUserInvited = false
    @State private var showingRainCheckRequest = false
    @State private var showingRainCheckApproval = false
    @State private var requesterName: String = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @EnvironmentObject private var themeManager: ThemeManager

    /// The event to display - uses displayEvent if available (after refresh), otherwise the original event
    private var currentEvent: CalendarEventWithUser {
        displayEvent ?? event
    }

    /// Whether this event is part of a recurring series
    private var isRecurringEvent: Bool {
        event.recurrenceRule != nil || event.parentEventId != nil
    }

    /// The parent event ID if this is an occurrence, otherwise the event's own ID
    private var parentEventId: UUID {
        event.parentEventId ?? event.id
    }
    
    private let responseOptions = [
        ("invited", "Not responded"),
        ("going", "Going"),
        ("maybe", "Maybe"),
        ("declined", "Decline")
    ]

    private let attendeeStatusOrder: [String] = ["going", "maybe", "invited"]
    
    private var canEdit: Bool {
        guard let userId = resolvedCurrentUserId ?? currentUserId else { return false }
        return event.user_id == userId
    }
    
    private var isPrivate: Bool {
        // Event is private if it's a personal event and current user didn't create it
        guard let userId = resolvedCurrentUserId ?? currentUserId else { return false }
        return event.event_type == "personal" && event.user_id != userId
    }

    private var hasPendingRainCheckRequest: Bool {
        currentEvent.rainCheckRequestedBy != nil
    }

    private var canRainCheck: Bool {
        // Only group events can be rain-checked
        // Must be either creator or an attendee
        guard let userId = resolvedCurrentUserId ?? currentUserId else { return false }
        if event.event_type != "group" { return false }
        return event.user_id == userId || isCurrentUserInvited
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Cover Image Hero Section
                    if !isPrivate, let coverImageURL = currentEvent.category?.cover_image_url, let url = URL(string: coverImageURL) {
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    Color(.systemGray5)
                                @unknown default:
                                    Color(.systemGray5)
                                }
                            }
                            .frame(height: 200)
                            .clipped()
                            
                            // Combined gradient: dark overlay for text + fade to background at bottom
                            ZStack {
                                // Top gradient for text readability
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                                
                                // Bottom fade to blend with content below
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        Color(.systemGroupedBackground).opacity(0.3),
                                        Color(.systemGroupedBackground)
                                    ],
                                    startPoint: UnitPoint(x: 0.5, y: 0.6),
                                    endPoint: .bottom
                                )
                            }
                            .frame(height: 200)
                            
                            // Title and emoji overlay
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    if let emoji = currentEvent.category?.emoji {
                                        Text(emoji)
                                            .font(.system(size: 40))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(isPrivate ? "Busy" : (currentEvent.title.isEmpty ? "Busy" : currentEvent.title))
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                        
                                        if let name = member?.name {
                                            HStack(spacing: 6) {
                                                Image(systemName: "person.circle.fill")
                                                Text(name)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.9))
                                        }
                                    }
                                    Spacer()
                                }
                                
                                if let catName = currentEvent.category?.name {
                                    Text(catName)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.2))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding()
                        }
                        .frame(height: 200)
                        .padding(.bottom, 32) // Add spacing between cover image and details
                    } else {
                        // Hero Section (no cover image)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        if let emoji = currentEvent.category?.emoji {
                                            Text(emoji)
                                                .font(.system(size: 40))
                                        }
                                        Text(isPrivate ? "Busy" : (currentEvent.title.isEmpty ? "Busy" : currentEvent.title))
                                            .font(.system(size: 34, weight: .bold, design: .rounded))
                                            .foregroundStyle(.primary)
                                    }
                                    
                                    if let name = member?.name {
                                        HStack(spacing: 6) {
                                            Image(systemName: "person.circle.fill")
                                            Text(name)
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Circle()
                                    .fill(eventColor)
                                    .frame(width: 44, height: 44)
                                    .shadow(color: eventColor.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            
                            if !isPrivate, let catName = currentEvent.category?.name {
                                Text(catName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(eventColor.opacity(0.1))
                                    .foregroundColor(eventColor)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                        .padding(.bottom, 8) // Add some bottom padding for consistency
                    }

                    // Rain Check Request Banner
                    if hasPendingRainCheckRequest, canEdit {
                        Button(action: showRainCheckApprovalSheet) {
                            HStack(spacing: 12) {
                                Image(systemName: "cloud.rain.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rain Check Request Pending")
                                        .font(.headline)
                                        .foregroundColor(.white)

                                    if let requesterId = currentEvent.rainCheckRequestedBy,
                                       let requesterName = attendees.first(where: { $0.userId == requesterId })?.displayName {
                                        Text("\(requesterName) wants to postpone this event")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.9))
                                    } else {
                                        Text("Tap to review and approve or deny")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding()
                            .background(themeManager.gradient)
                            .cornerRadius(12)
                            .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    VStack(spacing: 16) {
                        // When Card
                        DetailCard(title: "When", icon: "clock.fill", iconColor: .blue) {
                            Text(timeRange(currentEvent))
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }

                        // Location Card
                        if !isPrivate, let location = currentEvent.location, !location.isEmpty {
                            DetailCard(title: "Location", icon: "location.fill", iconColor: .red) {
                                Text(location)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }

                        // Notes Card
                        if !isPrivate, let notes = currentEvent.notes, !notes.isEmpty {
                            DetailCard(title: "Notes", icon: "note.text", iconColor: .orange) {
                                Text(notes)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }

                        // Calendar Card
                        if let calendar = currentEvent.calendar_name {
                            DetailCard(title: "Calendar", icon: "calendar", iconColor: .purple) {
                                Text(calendar)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }
                        
                        // Attendees Card
                        DetailCard(title: "Attendees", icon: "person.2.fill", iconColor: .green) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if attendees.isEmpty {
                                Text("No attendees")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(attendeeStatusOrder, id: \.self) { statusKey in
                                        let group = attendees.filter { $0.status.lowercased() == statusKey }
                                        if !group.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("\(statusDisplayName(statusKey)) (\(group.count))")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.secondary)
                                                    .padding(.top, 4)
                                                
                                                ForEach(group) { a in
                                                    HStack {
                                                        Circle()
                                                            .fill((a.color ?? .blue).opacity(0.8))
                                                            .frame(width: 8, height: 8)
                                                        Text(a.displayName)
                                                            .font(.subheadline)
                                                        Spacer()
                                                        AttendeeStatusBadge(status: a.status)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Response Section
                        if isCurrentUserInvited {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Response")
                                    .font(.headline)
                                    .padding(.horizontal, 4)
                                
                                HStack(spacing: 12) {
                                    ForEach(["going", "maybe", "declined"], id: \.self) { status in
                                        ResponseButton(
                                            status: status,
                                            isSelected: myStatus == status,
                                            isLoading: isUpdatingResponse && myStatus == status
                                        ) {
                                            if !isUpdatingResponse {
                                                let previous = myStatus
                                                isProgrammaticStatusChange = true
                                                myStatus = status
                                                isProgrammaticStatusChange = false
                                                respond(status, previousStatus: previous)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .tabBarSafeAreaInset()
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Show approval button if there's a pending rain check request
                        if hasPendingRainCheckRequest {
                            Button("Review Rain Check Request", systemImage: "cloud.rain") {
                                showRainCheckApprovalSheet()
                            }
                            Divider()
                        }

                        Button("Edit", systemImage: "pencil") {
                            if isRecurringEvent {
                                showingRecurringEditSheet = true
                            } else {
                                showingEditor = true
                            }
                        }

                        if canRainCheck {
                            Button("Rain Check Event", systemImage: "cloud.rain") {
                                showingRainCheckRequest = true
                            }
                        }

                        Button(role: .destructive) {
                            if isRecurringEvent {
                                showingRecurringDeleteSheet = true
                            } else {
                                showingDeleteConfirm = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            } else if canRainCheck {
                // Non-creators who are attendees can still request rain check
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingRainCheckRequest = true
                    } label: {
                        Image(systemName: "cloud.rain")
                    }
                }
            }
        }
        // Regular delete confirmation for non-recurring events
        .confirmationDialog("Delete this event?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteEvent(scope: .allOccurrences) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the event for everyone in the group if you created it.")
        }
        // Recurring event delete scope selection
        .sheet(isPresented: $showingRecurringDeleteSheet) {
            RecurringEventEditSheet(event: event, action: .delete) { scope in
                selectedDeleteScope = scope
                deleteEvent(scope: scope)
            }
        }
        // Recurring event edit scope selection
        .sheet(isPresented: $showingRecurringEditSheet) {
            RecurringEventEditSheet(event: event, action: .edit) { scope in
                handleRecurringEdit(scope: scope)
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            // Refresh event data after editing
            Task {
                await refreshEventData()
            }
        }) {
            EventEditorView(
                groupId: currentEvent.group_id,
                members: [],
                existingEvent: currentEvent,
                recurringEditScope: isRecurringEvent ? selectedEditScope : nil
            )
        }
        .sheet(isPresented: $showingRainCheckRequest) {
            RainCheckRequestSheet(
                event: currentEvent,
                isCreator: canEdit,
                onSubmit: { reason in
                    try await handleRainCheckRequest(reason: reason)
                }
            )
        }
        .sheet(isPresented: $showingRainCheckApproval) {
            RainCheckApprovalSheet(
                event: currentEvent,
                requesterName: requesterName,
                reason: currentEvent.rainCheckReason,
                onApprove: {
                    try await handleRainCheckApproval()
                },
                onDeny: {
                    try await handleRainCheckDenial()
                }
            )
        }
        .task {
            // Get current user ID first if not provided
            if resolvedCurrentUserId == nil {
                if let provided = currentUserId {
                    resolvedCurrentUserId = provided
                } else {
                    resolvedCurrentUserId = try? await SupabaseManager.shared.client.auth.session.user.id
                }
            }
            await loadAttendees()
        }
    }

    private var eventColor: Color {
        if let c = currentEvent.effectiveColor {
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }
        return member?.color ?? .blue
    }

    private func timeRange(_ e: CalendarEventWithUser) -> String {
        if e.is_all_day {
            if Calendar.current.isDate(e.start_date, inSameDayAs: e.end_date) {
                return "All day • " + day(e.start_date)
            } else {
                return "All day • \(day(e.start_date)) - \(day(e.end_date))"
            }
        }
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
            if let existing = resolvedCurrentUserId ?? currentUserId {
                uid = existing
            } else if let fetched = try? await SupabaseManager.shared.client.auth.session.user.id {
                uid = fetched
                await MainActor.run { resolvedCurrentUserId = fetched }
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
                
                // Auto-refresh the calendar view to reflect any changes
                try? await calendarSync.fetchGroupEvents(groupId: event.group_id)
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

    private func deleteEvent(scope: RecurringEditScope) {
        Task {
            guard !isDeleting else { return }
            isDeleting = true
            defer { isDeleting = false }
            do {
                guard let uid = try? await SupabaseManager.shared.client.auth.session.user.id else { return }

                switch scope {
                case .thisOccurrence:
                    // Delete only this single occurrence by creating a cancelled exception
                    // Use the occurrence's start date as the original occurrence date
                    try await CalendarEventService.shared.deleteRecurrenceOccurrence(
                        parentEventId: parentEventId,
                        occurrenceDate: event.start_date,
                        currentUserId: uid
                    )

                case .thisAndFuture:
                    // End the series at this occurrence by updating the parent's recurrence end date
                    let calendar = Calendar.current
                    let dayBefore = calendar.date(byAdding: .day, value: -1, to: event.start_date) ?? event.start_date

                    // Get Apple Calendar event ID for this user
                    struct AttendeeRow: Decodable {
                        let apple_calendar_event_id: String?
                    }
                    let attendeeRows: [AttendeeRow] = try await SupabaseManager.shared.client
                        .from("event_attendees")
                        .select("apple_calendar_event_id")
                        .eq("event_id", value: parentEventId)
                        .eq("user_id", value: uid)
                        .execute()
                        .value

                    // Update Apple Calendar to end recurrence at this date
                    if let appleEventId = attendeeRows.first?.apple_calendar_event_id {
                        try? await EventKitEventManager.shared.endRecurrenceAt(identifier: appleEventId, date: event.start_date)
                    }

                    struct UpdateEndDate: Encodable {
                        let recurrence_end_date: Date
                    }

                    _ = try await SupabaseManager.shared.client
                        .from("calendar_events")
                        .update(UpdateEndDate(recurrence_end_date: dayBefore))
                        .eq("id", value: parentEventId)
                        .execute()

                case .allOccurrences:
                    // Delete the entire recurring series
                    if isRecurringEvent {
                        try await CalendarEventService.shared.deleteRecurringSeries(
                            parentEventId: parentEventId,
                            currentUserId: uid
                        )
                    } else {
                        // Non-recurring event, use regular delete
                        try await CalendarEventService.shared.deleteEvent(
                            eventId: event.id,
                            currentUserId: uid,
                            originalEventId: event.original_event_id
                        )
                    }
                }

                // Refresh the calendar to remove the deleted event from the UI
                try? await calendarSync.fetchGroupEvents(groupId: event.group_id)
                dismiss()
            } catch {
                // Swallow error for now; could show toast/alert
                print("[EventDetailView] Failed to delete event: \(error.localizedDescription)")
            }
        }
    }

    private func handleRecurringEdit(scope: RecurringEditScope) {
        // Store the selected scope and show the editor
        selectedEditScope = scope
        showingEditor = true
    }

    /// Refresh the event data after editing
    /// For recurring events edited with "this occurrence", this finds the new exception event
    /// For other edits, it refreshes the current event from the database
    private func refreshEventData() async {
        // First refresh the calendar to get the latest data
        try? await calendarSync.fetchGroupEvents(groupId: event.group_id)

        // For "this occurrence" edits on recurring events, we need to find the exception event
        // that was created with the matching originalOccurrenceDate
        if selectedEditScope == .thisOccurrence && isRecurringEvent {
            // Look for an exception event that matches our occurrence date
            let matchingEvent = calendarSync.groupEvents.first { ev in
                ev.isRecurrenceException &&
                ev.parentEventId == parentEventId &&
                ev.originalOccurrenceDate != nil &&
                Calendar.current.isDate(ev.originalOccurrenceDate!, inSameDayAs: event.start_date)
            }

            if let matchingEvent {
                await MainActor.run {
                    displayEvent = matchingEvent
                }
                // Reload attendees for the new exception event
                await loadAttendeesForEvent(matchingEvent.id)
                return
            }
        }

        // For non-recurring events or "all occurrences" edits, try to fetch the updated event
        if let updatedEvent = try? await CalendarEventService.shared.fetchEventById(eventId: event.id) {
            await MainActor.run {
                displayEvent = updatedEvent
            }
        }

        // Reload attendees
        await loadAttendees()
    }

    // MARK: - Rain Check Handlers

    private func handleRainCheckRequest(reason: String?) async throws {
        guard let uid = try? await SupabaseManager.shared.client.auth.session.user.id else {
            throw NSError(domain: "EventDetailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get user ID"])
        }

        let wasApproved = try await CalendarEventService.shared.requestRainCheck(
            eventId: event.id,
            requesterId: uid,
            reason: reason,
            creatorId: event.user_id
        )

        if wasApproved {
            // Creator rain-checked directly - refresh and dismiss
            try? await calendarSync.fetchGroupEvents(groupId: event.group_id)
            dismiss()
        } else {
            // Attendee requested - refresh to show pending request badge
            await refreshEventData()
        }
    }

    private func handleRainCheckApproval() async throws {
        try await CalendarEventService.shared.approveRainCheck(eventId: event.id)
        try? await calendarSync.fetchGroupEvents(groupId: event.group_id)
        dismiss()
    }

    private func handleRainCheckDenial() async throws {
        try await CalendarEventService.shared.denyRainCheck(eventId: event.id)
        await refreshEventData()
    }

    private func showRainCheckApprovalSheet() {
        // Fetch the requester's name to display in the approval sheet
        Task {
            guard let requesterId = currentEvent.rainCheckRequestedBy else { return }

            do {
                struct UserRow: Decodable {
                    let display_name: String?
                }

                let user: UserRow = try await SupabaseManager.shared.client
                    .from("users")
                    .select("display_name")
                    .eq("id", value: requesterId)
                    .single()
                    .execute()
                    .value

                await MainActor.run {
                    requesterName = user.display_name ?? "Someone"
                    showingRainCheckApproval = true
                }
            } catch {
                // Fallback if we can't fetch the name
                await MainActor.run {
                    requesterName = "An attendee"
                    showingRainCheckApproval = true
                }
            }
        }
    }

    /// Load attendees for a specific event ID (used when switching to exception event)
    private func loadAttendeesForEvent(_ eventId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await CalendarEventService.shared.loadAttendees(eventId: eventId)

            let currentUserIdValue = resolvedCurrentUserId ?? currentUserId

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
                if let userId = currentUserIdValue {
                    isCurrentUserInvited = rows.contains(where: { $0.userId == userId })
                }
            }
        } catch {
            await MainActor.run { attendees = [] }
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
            if let existing = resolvedCurrentUserId ?? currentUserId {
                currentUserIdValue = existing
            } else {
                currentUserIdValue = try? await SupabaseManager.shared.client.auth.session.user.id
                if let fetched = currentUserIdValue {
                    await MainActor.run { resolvedCurrentUserId = fetched }
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
                // Check if current user is invited
                if let userId = currentUserIdValue {
                    isCurrentUserInvited = rows.contains(where: { $0.userId == userId })
                } else {
                    isCurrentUserInvited = false
                }
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

// MARK: - Helper UI Components

private struct DetailCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content
    
    init(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .imageScale(.small)
                    .font(.subheadline.bold())
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            VStack(alignment: .leading) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
        }
    }
}

private struct AttendeeStatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch status.lowercased() {
        case "going": return .green
        case "maybe": return .orange
        case "declined": return .red
        default: return .blue
        }
    }
}

private struct ResponseButton: View {
    let status: String
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(isSelected ? .white : .primary)
                        .controlSize(.small)
                } else {
                    Image(systemName: iconName)
                }
                Text(label)
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? statusColor : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
            .shadow(color: isSelected ? statusColor.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var label: String {
        switch status.lowercased() {
        case "going": return "Going"
        case "maybe": return "Maybe"
        case "declined": return "Decline"
        default: return status.capitalized
        }
    }
    
    private var iconName: String {
        switch status.lowercased() {
        case "going": return "checkmark.circle.fill"
        case "maybe": return "questionmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        default: return "circle"
        }
    }
    
    private var statusColor: Color {
        switch status.lowercased() {
        case "going": return .green
        case "maybe": return .orange
        case "declined": return .red
        default: return .blue
        }
    }
}

