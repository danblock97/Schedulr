import SwiftUI
import Supabase
import Auth
import UIKit
import PhotosUI

struct EventEditorView: View {
    let groupId: UUID
    @State private var members: [DashboardViewModel.MemberSummary]
    var existingEvent: CalendarEventWithUser? = nil
    var initialDate: Date? = nil
    var recurringEditScope: RecurringEditScope? = nil
    var isRescheduling: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarSync: CalendarSyncManager

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var isAllDay: Bool = false
    @State private var eventType: String = "personal"
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var guestNamesText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveToAppleCalendar: Bool = true
    @State private var categories: [EventCategory] = []
    @State private var selectedCategoryId: UUID? = nil
    @State private var showingCategoryCreator = false
    @State private var isLoadingCategories = false
    @State private var currentAttendees: [(userId: UUID?, displayName: String, status: String)] = []
    @State private var isLoadingAttendees = false
    @State private var selectedGroupId: UUID
    @State private var availableGroups: [DashboardViewModel.GroupSummary] = []
    @State private var isLoadingGroups = false
    @State private var loadedDraftFollowupId: UUID?
    @State private var didSave: Bool = false
    @State private var availableDraftPayload: [String: String]?
    // Recurrence state
    @State private var isRecurring: Bool = false
    @State private var recurrenceRule: RecurrenceRule? = nil
    // Validation state
    @State private var showingMissingAttendeesAlert = false
    @State private var currentUserId: UUID? = nil

    init(groupId: UUID, members: [DashboardViewModel.MemberSummary], existingEvent: CalendarEventWithUser? = nil, initialDate: Date? = nil, recurringEditScope: RecurringEditScope? = nil, isRescheduling: Bool = false) {
        self.groupId = groupId
        self.members = members
        self.existingEvent = existingEvent
        self.initialDate = initialDate
        self.recurringEditScope = recurringEditScope
        self.isRescheduling = isRescheduling
        _selectedGroupId = State(initialValue: groupId)

        // If creating a new event with an initial date, set the start and end dates
        if existingEvent == nil, let initialDate = initialDate {
            _date = State(initialValue: initialDate)
            _endDate = State(initialValue: Calendar.current.date(byAdding: .hour, value: 1, to: initialDate) ?? initialDate)
        }
    }

    @EnvironmentObject var themeManager: ThemeManager

    private var navigationTitle: String {
        if isRescheduling {
            return "Reschedule Event"
        }
        if existingEvent == nil {
            return "New Event"
        }
        guard let scope = recurringEditScope else {
            return "Edit Event"
        }
        switch scope {
        case .thisOccurrence:
            return "Edit This Event"
        case .thisAndFuture:
            return "Edit Future Events"
        case .allOccurrences:
            return "Edit All Events"
        }
    }
    
    private var hasValidAttendees: Bool {
        if eventType != "group" { return true }
        // Exclude the creator from selected members count
        // Group events need at least 2 people total: creator (auto-added) + at least 1 other
        let otherMembers: Set<UUID>
        if let creatorId = currentUserId {
            otherMembers = selectedMemberIds.filter { $0 != creatorId }
        } else {
            otherMembers = selectedMemberIds
        }
        let hasOtherMembers = !otherMembers.isEmpty
        let hasGuests = !guestNamesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasOtherMembers || hasGuests
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Recurring event edit scope banner
                        if let scope = recurringEditScope {
                            HStack(spacing: 12) {
                                Image(systemName: "repeat")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Editing Recurring Event")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text(scope.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                Spacer()
                            }
                            .padding()
                            .background(themeManager.primaryColor)
                            .cornerRadius(12)
                        }

                        if let _ = availableDraftPayload {
                            SectionCard(title: "Draft available", icon: "doc.text") {
                                HStack {
                                    Spacer()
                                    Button("Discard") {
                                        Task {
                                            await discardAvailableDraft()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    
                                    Button("Resume") {
                                        applyAvailableDraft()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(themeManager.primaryColor)
                                }
                            }
                        }
                        
                        // Details Section
                        SectionCard(title: "Details", icon: "pencil.and.outline") {
                            VStack(spacing: 16) {
                                CustomTextField(label: "Title", text: $title, placeholder: "Event Title")
                                
                                CustomToggle(label: "All day", isOn: $isAllDay)
                                
                                CustomPicker(label: "Event Type", selection: $eventType) {
                                    Text("Personal").tag("personal")
                                    Text("Group").tag("group")
                                }
                                .onChange(of: eventType) { oldValue, newValue in
                                    if newValue == "personal" {
                                        selectedMemberIds.removeAll()
                                        guestNamesText = ""
                                    } else if newValue == "group" {
                                        saveToAppleCalendar = false
                                    }
                                }
                                
                                CustomDatePicker(label: "Start", selection: $date, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                CustomDatePicker(label: "End", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                
                                CustomTextField(label: "Location", text: $location, placeholder: "Add location", icon: "location")
                                
                                CustomTextField(label: "Notes", text: $notes, placeholder: "Add notes (optional)", icon: "note.text", axis: .vertical)
                            }
                        }
                        
                        // Group Section
                        SectionCard(title: "Group", icon: "person.3") {
                            VStack(spacing: 12) {
                                if isLoadingGroups {
                                    HStack {
                                        ProgressView()
                                        Text("Loading groups...")
                                            .foregroundStyle(.secondary)
                                    }
                                } else if availableGroups.isEmpty {
                                    Text("No groups available")
                                        .foregroundStyle(.secondary)
                                } else {
                                    CustomPicker(label: "Select Group", selection: $selectedGroupId) {
                                        ForEach(availableGroups) { group in
                                            Text(group.name).tag(group.id)
                                        }
                                    }
                                    .disabled(eventType == "personal")
                                    .onChange(of: selectedGroupId) { oldValue, newValue in
                                        Task {
                                            await loadMembersForGroup(newValue)
                                            await loadCategoriesForGroup(newValue)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Category Section
                        SectionCard(title: "Category", icon: "tag") {
                            VStack(spacing: 16) {
                                CustomPicker(label: "Select Category", selection: $selectedCategoryId) {
                                    Text("None").tag(nil as UUID?)
                                    ForEach(categories) { category in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(Color(
                                                    red: category.color.red,
                                                    green: category.color.green,
                                                    blue: category.color.blue,
                                                    opacity: category.color.alpha
                                                ))
                                                .frame(width: 10, height: 10)
                                            Text(category.name)
                                        }
                                        .tag(category.id as UUID?)
                                    }
                                }
                                
                                Button(action: { showingCategoryCreator = true }) {
                                    Label("Create New Category", systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .tint(themeManager.primaryColor)
                            }
                        }

                        // Recurrence Section (hide when editing single occurrence)
                        if recurringEditScope != .thisOccurrence {
                            SectionCard(title: "Repeat", icon: "repeat") {
                                RecurrencePickerView(
                                    recurrenceRule: $recurrenceRule,
                                    isRecurring: $isRecurring,
                                    eventStartDate: date,
                                    initialRule: existingEvent?.recurrenceRule
                                )
                            }
                        }

                        if eventType == "group" {
                            SectionCard(title: "Invite group members", icon: "person.badge.plus") {
                                VStack(alignment: .leading, spacing: 12) {
                                    if members.isEmpty {
                                        Text("No members to invite")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(members) { member in
                                                    MemberInviteChip(member: member, isSelected: selectedMemberIds.contains(member.id)) {
                                                        if selectedMemberIds.contains(member.id) {
                                                            selectedMemberIds.remove(member.id)
                                                        } else {
                                                            selectedMemberIds.insert(member.id)
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                        }
                                    }
                                    
                                    Divider()
                                        .padding(.vertical, 4)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Guests not in group")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        
                                        TextField("Names (comma separated)", text: $guestNamesText)
                                            .padding(12)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                            )
                                    }
                                    
                                    if !hasValidAttendees {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text("Please invite at least one member or guest")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                        
                        if existingEvent != nil && !currentAttendees.isEmpty {
                            SectionCard(title: "Current Attendees", icon: "person.2") {
                                VStack(spacing: 12) {
                                    ForEach(currentAttendees.indices, id: \.self) { index in
                                        HStack {
                                            Circle()
                                                .fill(themeManager.primaryColor.opacity(0.8))
                                                .frame(width: 8, height: 8)
                                            Text(currentAttendees[index].displayName)
                                                .font(.subheadline)
                                            Spacer()
                                            ParticipantStatusBadge(status: currentAttendees[index].status)
                                        }
                                        if index < currentAttendees.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }

                        SectionCard(title: "Apple Calendar Sync", icon: "calendar.badge.plus") {
                            VStack(alignment: .leading, spacing: 8) {
                                if eventType == "personal" {
                                    CustomToggle(label: "Save to Apple Calendar", isOn: $saveToAppleCalendar)
                                        .accessibilityHint("Also creates/updates an Apple Calendar event")
                                } else {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title3)
                                        Text("Group events automatically sync to Apple Calendar")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        if let errorMessage {
                            SectionCard(title: "Error", icon: "exclamationmark.triangle", color: .red) {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.callout)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .task {
            // Load current user ID for validation
            if currentUserId == nil {
                currentUserId = try? await SupabaseManager.shared.client.auth.session.user.id
            }
            
            await loadAvailableGroups()
            // If editing, set group from existing event after groups are loaded
            if let ev = existingEvent {
                selectedGroupId = ev.group_id
                // Ensure the group is in available groups
                if !availableGroups.contains(where: { $0.id == ev.group_id }) {
                    // If event's group not in available groups, use first available or keep original
                    if let firstGroup = availableGroups.first {
                        selectedGroupId = firstGroup.id
                    }
                }
            }
            await loadCategoriesForGroup(selectedGroupId)
            await loadMembersForGroup(selectedGroupId)
            prefillIfEditing()
            if existingEvent != nil {
                await loadCurrentAttendees()
            } else {
                await loadLatestDraftIfAvailable()
            }
        }
        .sheet(isPresented: $showingCategoryCreator) {
            CategoryCreatorView(groupId: selectedGroupId) { category in
                categories.append(category)
                selectedCategoryId = category.id
            }
        }
        .alert("Add Attendees", isPresented: $showingMissingAttendeesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Group events must include at least one other member or guest. Please invite at least one person to the event.")
        }
        .onDisappear {
            Task { await saveDraftIfNeeded() }
        }
    }
    
    private func loadCategories() async {
        await loadCategoriesForGroup(selectedGroupId)
    }
    
    private func loadCategoriesForGroup(_ groupId: UUID) async {
        guard !isLoadingCategories else { return }
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            let uid = try await SupabaseManager.shared.client.auth.session.user.id
            categories = try await CalendarEventService.shared.fetchCategories(userId: uid, groupId: groupId)
        } catch {
            errorMessage = "Failed to load categories: \(error.localizedDescription)"
        }
    }
    
    private func loadAvailableGroups() async {
        guard !isLoadingGroups else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        do {
            guard let client = SupabaseManager.shared.client else {
                errorMessage = "Service unavailable"
                return
            }
            let uid = try await client.auth.session.user.id
            
            struct GroupMembershipRow: Decodable {
                let group_id: UUID
                let role: String?
                let joined_at: Date?
                let groups: DBGroup?
            }
            
            let rows: [GroupMembershipRow] = try await client.database
                .from("group_members")
                .select("group_id, role, joined_at, groups(id,name,invite_slug,created_at,created_by)")
                .eq("user_id", value: uid)
                .order("joined_at", ascending: true)
                .execute()
                .value
            
            availableGroups = rows.compactMap { row -> DashboardViewModel.GroupSummary? in
                guard let group = row.groups else { return nil }
                return DashboardViewModel.GroupSummary(
                    id: group.id,
                    name: group.name,
                    role: row.role ?? "member",
                    inviteSlug: group.invite_slug,
                    createdAt: group.created_at,
                    joinedAt: row.joined_at
                )
            }
            
            // Ensure selectedGroupId is valid, if not, select first group
            if !availableGroups.contains(where: { $0.id == selectedGroupId }) {
                if let firstGroup = availableGroups.first {
                    selectedGroupId = firstGroup.id
                }
            }
        } catch {
            errorMessage = "Failed to load groups: \(error.localizedDescription)"
        }
    }
    
    private func loadMembersForGroup(_ groupId: UUID) async {
        do {
            guard let client = SupabaseManager.shared.client else {
                return
            }
            
            struct GroupMemberRow: Decodable {
                let user_id: UUID
                let role: String?
                let joined_at: Date?
                let users: DBUser?
            }
            
            let rows: [GroupMemberRow] = try await client.database
                .from("group_members")
                .select("user_id, role, joined_at, users(id,display_name,avatar_url)")
                .eq("group_id", value: groupId)
                .order("joined_at", ascending: true)
                .execute()
                .value
            
            members = rows.map { row in
                DashboardViewModel.MemberSummary(
                    id: row.user_id,
                    displayName: row.users?.display_name ?? "Member",
                    role: row.role ?? "member",
                    avatarURL: row.users?.avatar_url.flatMap(URL.init(string:)),
                    joinedAt: row.joined_at
                )
            }
            
            // Clear selected members when group changes (they're no longer valid)
            selectedMemberIds.removeAll()
        } catch {
            // Silently fail - members will just be empty
            members = []
        }
    }

    private func save() {
        Task {
            guard !isSaving else { return }
            isSaving = true
            defer { isSaving = false }
            
            // Validate group events have at least one attendee
            if eventType == "group" && !hasValidAttendees {
                showingMissingAttendeesAlert = true
                return
            }
            
            // Validate that end date is not before start date
            if endDate < date {
                errorMessage = "End date cannot be before start date"
                return
            }
            
            do {
                let uid = try await SupabaseManager.shared.client.auth.session.user.id
                var ekId: String? = existingEvent?.original_event_id
                
                // Get category color if category is selected
                var categoryColor: ColorComponents? = nil
                if let categoryId = selectedCategoryId {
                    if let category = categories.first(where: { $0.id == categoryId }) {
                        categoryColor = category.color
                    }
                }
                
                // Only save to Apple Calendar if it's a personal event AND the user enabled the toggle
                if saveToAppleCalendar && eventType == "personal" {
                    if let existingId = ekId {
                        try await EventKitEventManager.shared.updateEvent(identifier: existingId, title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: date, end: endDate, isAllDay: isAllDay, location: location.isEmpty ? nil : location, notes: notes.isEmpty ? nil : notes, categoryColor: categoryColor)
                    } else {
                        ekId = try? await EventKitEventManager.shared.createEvent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: date, end: endDate, isAllDay: isAllDay, location: location.isEmpty ? nil : location, notes: notes.isEmpty ? nil : notes, categoryColor: categoryColor, recurrenceRule: recurrenceRule)
                    }
                } else if eventType == "group" {
                    // Don't save group events to Apple Calendar directly - they're synced via CalendarEventService
                    // Delete if converting from personal to group
                    if let existingId = ekId {
                        try? await EventKitEventManager.shared.deleteEvent(identifier: existingId)
                    }
                    ekId = nil
                }

                // Ensure personal events have no attendees
                let attendeeIds = eventType == "personal" ? [] : Array(selectedMemberIds)
                let guestNames = eventType == "personal" ? [] : guestNamesText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                
                let input = NewEventInput(
                    groupId: selectedGroupId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: date,
                    end: endDate,
                    isAllDay: isAllDay,
                    location: location.isEmpty ? nil : location,
                    notes: notes.isEmpty ? nil : notes,
                    attendeeUserIds: attendeeIds,
                    guestNames: guestNames,
                    originalEventId: ekId,
                    categoryId: selectedCategoryId,
                    eventType: eventType,
                    recurrenceRule: isRecurring ? recurrenceRule : nil,
                    recurrenceEndDate: isRecurring ? recurrenceRule?.endDate : nil
                )

                // Special handling for rescheduling rain-checked events
                if isRescheduling, let rainCheckedEvent = existingEvent {
                    _ = try await CalendarEventService.shared.rescheduleRainCheckedEvent(
                        rainCheckedEventId: rainCheckedEvent.id,
                        newInput: input,
                        currentUserId: uid
                    )
                } else if let existingEvent {
                    // Handle recurring event edit scopes
                    if let scope = recurringEditScope {
                        switch scope {
                        case .thisOccurrence:
                            // Create an exception event for this occurrence only
                            _ = try await CalendarEventService.shared.createRecurrenceException(
                                parentEventId: existingEvent.parentEventId ?? existingEvent.id,
                                originalOccurrenceDate: existingEvent.start_date,
                                exception: .modified(input),
                                currentUserId: uid
                            )
                        case .thisAndFuture:
                            // End current series and create new series starting from this date
                            _ = try await CalendarEventService.shared.updateFutureOccurrences(
                                parentEventId: existingEvent.parentEventId ?? existingEvent.id,
                                fromDate: existingEvent.start_date,
                                newInput: input,
                                currentUserId: uid
                            )
                        case .allOccurrences:
                            // Update the parent event (all occurrences)
                            let parentId = existingEvent.parentEventId ?? existingEvent.id
                            
                            // FIX: When updating "all occurrences", preserve the parent's original start DATE
                            // but apply the new TIME from the edited occurrence.
                            // This is needed because when editing from a virtual occurrence (expanded from recurrence),
                            // the form shows the occurrence's date, not the parent's original start date.
                            var fixedInput = input
                            
                            // ALWAYS fetch the parent event to get its original start date
                            if let parentEvent = try? await CalendarEventService.shared.fetchEventById(eventId: parentId) {
                                let calendar = Calendar.current
                                
                                // Check if the occurrence date differs from the parent's start date
                                let occurrenceDate = calendar.startOfDay(for: existingEvent.start_date)
                                let parentDate = calendar.startOfDay(for: parentEvent.start_date)
                                
                                if occurrenceDate != parentDate {
                                    // We're editing from a different occurrence, preserve parent's date
                                    // Get time components from the edited occurrence's new times
                                    let newStartTime = calendar.dateComponents([.hour, .minute, .second], from: input.start)
                                    let newEndTime = calendar.dateComponents([.hour, .minute, .second], from: input.end)
                                    // Get date components from the PARENT's original start date
                                    var parentStartComponents = calendar.dateComponents([.year, .month, .day], from: parentEvent.start_date)
                                    var parentEndComponents = calendar.dateComponents([.year, .month, .day], from: parentEvent.start_date)
                                    // Combine: parent's date + new time
                                    parentStartComponents.hour = newStartTime.hour
                                    parentStartComponents.minute = newStartTime.minute
                                    parentStartComponents.second = newStartTime.second
                                    parentEndComponents.hour = newEndTime.hour
                                    parentEndComponents.minute = newEndTime.minute
                                    parentEndComponents.second = newEndTime.second
                                    
                                    if let correctedStart = calendar.date(from: parentStartComponents),
                                       let correctedEnd = calendar.date(from: parentEndComponents) {
                                        fixedInput = NewEventInput(
                                            groupId: input.groupId,
                                            title: input.title,
                                            start: correctedStart,
                                            end: correctedEnd,
                                            isAllDay: input.isAllDay,
                                            location: input.location,
                                            notes: input.notes,
                                            attendeeUserIds: input.attendeeUserIds,
                                            guestNames: input.guestNames,
                                            originalEventId: input.originalEventId,
                                            categoryId: input.categoryId,
                                            eventType: input.eventType,
                                            recurrenceRule: input.recurrenceRule
                                        )
                                    }
                                }
                            }
                            
                            try await CalendarEventService.shared.updateEvent(eventId: parentId, input: fixedInput, currentUserId: uid, updateAllOccurrences: true)
                        }
                    } else {
                        // Non-recurring event, update normally
                        try await CalendarEventService.shared.updateEvent(eventId: existingEvent.id, input: input, currentUserId: uid)
                    }
                } else {
                    _ = try await CalendarEventService.shared.createEvent(input: input, currentUserId: uid)
                }
                
                // Auto-refresh the calendar view to show the new/updated event
                try? await calendarSync.fetchGroupEvents(groupId: selectedGroupId)
                
                // Record significant action for rating prompt (only for new events)
                if existingEvent == nil {
                    RatingManager.shared.recordSignificantAction()
                    // Check if we should show rating prompt
                    _ = RatingManager.shared.requestReviewIfAppropriate()
                }

                didSave = true
                // Clear drafts upon successful save
                if let draftId = loadedDraftFollowupId {
                    await resolveSpecificDraftFollowUp(id: draftId)
                } else {
                    await resolveAllDraftFollowUps()
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
        selectedCategoryId = ev.category_id
        eventType = ev.event_type
        // Load recurrence if present
        if let rule = ev.recurrenceRule {
            isRecurring = true
            recurrenceRule = rule
        }
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
    
    private func loadCurrentAttendees() async {
        guard let ev = existingEvent else { return }
        isLoadingAttendees = true
        defer { isLoadingAttendees = false }
        do {
            currentAttendees = try await CalendarEventService.shared.loadAttendees(eventId: ev.id)
        } catch {
            // Silently fail - attendees list is informational only
            currentAttendees = []
        }
    }

    // MARK: - Draft handling
    private func saveDraftIfNeeded() async {
        guard existingEvent == nil, !didSave else { return }
        let hasContent = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedMemberIds.isEmpty
            || !guestNamesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else { return }
        await recordDraftFollowUp()
    }
    
    private func recordDraftFollowUp(expiresInHours: Double = 24) async {
        guard let client = SupabaseManager.shared.client else { return }
        do {
            let session = try await client.auth.session
            let userId = session.user.id
            let expiresAt = Date().addingTimeInterval(expiresInHours * 3600)
            
            struct InsertRow: Encodable {
                let user_id: UUID
                let conversation_id: UUID?
                let expires_at: Date
                let reason: String
                let draft_payload: [String: String]
            }
            
            let payload = buildDraftPayload()
            let row = InsertRow(
                user_id: userId,
                conversation_id: nil,
                expires_at: expiresAt,
                reason: "event_editor_draft",
                draft_payload: payload
            )
            
            // Upsert latest draft for this user/reason to avoid multiple entries
            struct DraftParams: Encodable {
                let p_user_id: UUID
                let p_reason: String
                let p_expires_at: Date
                let p_draft_payload: [String: String]
            }
            let params = DraftParams(
                p_user_id: userId,
                p_reason: "event_editor_draft",
                p_expires_at: expiresAt,
                p_draft_payload: payload
            )
            
            _ = try await client
                .database
                .rpc("upsert_ai_followup_draft", params: params)
        } catch {
            #if DEBUG
            print("[EventEditorView] Failed to record draft follow-up: \(error)")
            #endif
        }
    }
    
    private func loadLatestDraftIfAvailable() async {
        guard let client = SupabaseManager.shared.client else { return }
        do {
            let session = try await client.auth.session
            let userId = session.user.id
            let now = Date()
            
            struct Row: Decodable {
                let id: UUID
                let draft_payload: [String: String]?
                let expires_at: Date
                let resolved_at: Date?
                let sent_at: Date?
                let created_at: Date?
            }
            
            let rows: [Row] = try await client.database
                .from("ai_followups")
                .select("id,draft_payload,expires_at,resolved_at,sent_at,created_at")
                .eq("user_id", value: userId)
                .eq("reason", value: "event_editor_draft")
                .is("resolved_at", value: nil)
                .gt("expires_at", value: now)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            
            guard let row = rows.first, let payload = row.draft_payload else { return }
            availableDraftPayload = payload
            loadedDraftFollowupId = row.id
        } catch {
            #if DEBUG
            print("[EventEditorView] Failed to load draft follow-up: \(error)")
            #endif
        }
    }
    
    private func resolveSpecificDraftFollowUp(id: UUID) async {
        guard let client = SupabaseManager.shared.client else { return }
        do {
            struct UpdateRow: Encodable { let resolved_at: Date }
            let update = UpdateRow(resolved_at: Date())
            _ = try await client
                .database
                .from("ai_followups")
                .update(update)
                .eq("id", value: id)
                .execute()
        } catch {
            #if DEBUG
            print("[EventEditorView] Failed to resolve draft follow-up: \(error)")
            #endif
        }
    }
    
    private func resolveAllDraftFollowUps() async {
        guard let client = SupabaseManager.shared.client else { return }
        do {
            let session = try await client.auth.session
            let userId = session.user.id
            struct UpdateRow: Encodable { let resolved_at: Date }
            let update = UpdateRow(resolved_at: Date())
            _ = try await client
                .database
                .from("ai_followups")
                .update(update)
                .eq("user_id", value: userId)
                .eq("reason", value: "event_editor_draft")
                .is("resolved_at", value: nil)
                .execute()
        } catch {
            #if DEBUG
            print("[EventEditorView] Failed to resolve all draft follow-ups: \(error)")
            #endif
        }
    }
    
    private func buildDraftPayload() -> [String: String] {
        let iso = ISO8601DateFormatter()
        return [
            "title": title,
            "start": iso.string(from: date),
            "end": iso.string(from: endDate),
            "is_all_day": isAllDay ? "true" : "false",
            "event_type": eventType,
            "location": location,
            "notes": notes,
            "group_id": selectedGroupId.uuidString,
            "member_ids": selectedMemberIds.map { $0.uuidString }.joined(separator: ","),
            "guest_names": guestNamesText,
            "category_id": selectedCategoryId?.uuidString ?? ""
        ]
    }
    
    private func applyDraftPayload(_ payload: [String: String]) {
        let iso = ISO8601DateFormatter()
        if let t = payload["title"] { title = t }
        if let startStr = payload["start"], let d = iso.date(from: startStr) { date = d }
        if let endStr = payload["end"], let d = iso.date(from: endStr) { endDate = d }
        if let allDay = payload["is_all_day"] { isAllDay = (allDay == "true") }
        if let et = payload["event_type"] { eventType = et }
        if let loc = payload["location"] { location = loc }
        if let n = payload["notes"] { notes = n }
        if let gid = payload["group_id"], let uuid = UUID(uuidString: gid) { selectedGroupId = uuid }
        if let mids = payload["member_ids"] {
            let ids = mids.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            selectedMemberIds = Set(ids)
        }
        if let guests = payload["guest_names"] { guestNamesText = guests }
        if let cat = payload["category_id"], let uuid = UUID(uuidString: cat) { selectedCategoryId = uuid }
    }

    private func applyAvailableDraft() {
        guard let payload = availableDraftPayload else { return }
        applyDraftPayload(payload)
        if let draftId = loadedDraftFollowupId {
            Task { await resolveSpecificDraftFollowUp(id: draftId) }
            loadedDraftFollowupId = nil
        }
        availableDraftPayload = nil
    }
    
    private func discardAvailableDraft() async {
        guard let draftId = loadedDraftFollowupId else { return }
        await resolveSpecificDraftFollowUp(id: draftId)
        await MainActor.run {
            availableDraftPayload = nil
            loadedDraftFollowupId = nil
        }
    }
}

// MARK: - Helper UI Components

private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    var color: Color
    let content: Content
    
    init(title: String, icon: String, color: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .imageScale(.medium)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)
            
            VStack(alignment: .leading) {
                content
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
        }
    }
}

struct CustomTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var icon: String? = nil
    var axis: Axis = .horizontal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                
                TextField(placeholder, text: $text, axis: axis)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color(.systemGroupedBackground).opacity(0.5))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct CustomToggle: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(label, isOn: $isOn)
            .padding(4)
    }
}

struct CustomPicker<Content: View, Selection: Hashable>: View {
    let label: String
    @Binding var selection: Selection
    let content: Content
    
    init(label: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.label = label
        self._selection = selection
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(label, selection: $selection) {
                content
            }
            .pickerStyle(.menu)
        }
    }
}

struct CustomDatePicker: View {
    let label: String
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]
    
    var body: some View {
        DatePicker(label, selection: $selection, displayedComponents: displayedComponents)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct MemberInviteChip: View {
    let member: DashboardViewModel.MemberSummary
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let url = member.avatarURL {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                            .frame(width: 50, height: 50)
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .background(Circle().fill(.white))
                            .offset(x: 4, y: 4)
                    }
                }
                
                Text(member.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .frame(width: 65)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

private struct ParticipantStatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
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

// MARK: - Category Creator View
struct CategoryCreatorView: View {
    let groupId: UUID
    let onCategoryCreated: (EventCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var categoryName: String = ""
    @State private var selectedColor: Color = .blue
    @State private var selectedEmoji: String? = nil
    @State private var selectedTemplate: EventThemeTemplate? = nil
    @State private var coverImageData: Data? = nil
    @State private var coverImageURL: String? = nil
    @State private var isSaving = false
    @State private var isUploadingImage = false
    @State private var errorMessage: String?
    @State private var shareWithGroup = false
    @State private var showingEmojiPicker = false
    @State private var showingImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue,
        .indigo, .purple, .pink, .brown
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                categoryDetailsSection
                themeSection
                colorSection
                if let errorMessage {
                    errorSection(message: errorMessage)
                }
            }
            .navigationTitle("New Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $selectedEmoji)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            coverImageData = data
                        }
                        await uploadCoverImage(data: data)
                    }
                }
            }
        }
    }
    
    private var categoryDetailsSection: some View {
        Section("Category Details") {
            TextField("Name", text: $categoryName)
            Toggle("Share with group", isOn: $shareWithGroup)
        }
    }
    
    private var themeSection: some View {
        Section("Theme") {
            templatePicker
            emojiPickerRow
            coverImagePicker
        }
    }
    
    private var templatePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(EventThemeTemplate.allTemplates) { template in
                    ThemeTemplateButton(
                        template: template,
                        isSelected: selectedTemplate?.id == template.id
                    ) {
                        applyTemplate(template)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private var emojiPickerRow: some View {
        HStack {
            Text("Emoji")
            Spacer()
            Button {
                showingEmojiPicker = true
            } label: {
                HStack {
                    Text(selectedEmoji ?? "✨")
                        .font(.system(size: 24))
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var coverImagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover Image")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let coverImageData = coverImageData,
               let uiImage = UIImage(data: coverImageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Button("Remove") {
                        self.coverImageData = nil
                        self.coverImageURL = nil
                    }
                    .foregroundColor(.red)
                    
                    Spacer()
                }
            } else {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Choose Cover Image", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                ForEach(presetColors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func errorSection(message: String) -> some View {
        Section {
            Text(message)
                .foregroundColor(.red)
        }
    }
    
    private func applyTemplate(_ template: EventThemeTemplate) {
        selectedTemplate = template
        selectedEmoji = template.emoji
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        #if canImport(UIKit)
        let uiColor = UIColor(
            red: CGFloat(template.suggestedColor.red),
            green: CGFloat(template.suggestedColor.green),
            blue: CGFloat(template.suggestedColor.blue),
            alpha: CGFloat(template.suggestedColor.alpha)
        )
        selectedColor = Color(uiColor)
        #else
        selectedColor = Color(
            red: template.suggestedColor.red,
            green: template.suggestedColor.green,
            blue: template.suggestedColor.blue,
            opacity: template.suggestedColor.alpha
        )
        #endif
        
        if template.id == "custom" {
            selectedTemplate = nil
        }
    }
    
    private func uploadCoverImage(data: Data) async {
        guard !isUploadingImage else { return }
        isUploadingImage = true
        defer { isUploadingImage = false }
        
        do {
            // Upload to R2 via pre-signed URL (user ID is determined server-side from the auth token)
            let filename = R2StorageService.eventCoverFilename()
            let url = try await R2StorageService.shared.upload(
                data: data,
                filename: filename,
                folder: .eventCovers,
                contentType: "image/jpeg"
            )
            
            await MainActor.run {
                coverImageURL = url.absoluteString
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to upload cover image: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveCategory() {
        Task {
            guard !isSaving else { return }
            isSaving = true
            defer { isSaving = false }
            
            do {
                let uid = try await SupabaseManager.shared.client.auth.session.user.id
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                #if canImport(UIKit)
                let uiColor = UIColor(selectedColor)
                uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                #else
                // Fallback: attempt to use cgColor if UIKit not available
                let comps = selectedColor.cgColor?.components ?? [0, 0, 1, 1]
                r = comps[0]; g = comps.count > 1 ? comps[1] : comps[0]; b = comps.count > 2 ? comps[2] : comps[0]; a = comps.count > 3 ? comps[3] : 1
                #endif
                let colorComponents = ColorComponents(
                    red: Double(r),
                    green: Double(g),
                    blue: Double(b),
                    alpha: Double(a)
                )
                
                let input = EventCategoryInsert(
                    user_id: uid,
                    group_id: shareWithGroup ? groupId : nil,
                    name: categoryName.trimmingCharacters(in: .whitespacesAndNewlines),
                    color: colorComponents,
                    emoji: selectedEmoji,
                    cover_image_url: coverImageURL
                )
                
                let category = try await CalendarEventService.shared.createCategory(input: input, currentUserId: uid)
                onCategoryCreated(category)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Event Theme Template
private struct EventThemeTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let suggestedColor: ColorComponents
    let presetImageName: String?
    
    static let movieNight = EventThemeTemplate(
        id: "movie_night",
        name: "Movie Night",
        emoji: "🎬",
        suggestedColor: ColorComponents(red: 0.2, green: 0.2, blue: 0.3, alpha: 1.0),
        presetImageName: nil
    )
    
    static let dinner = EventThemeTemplate(
        id: "dinner",
        name: "Dinner",
        emoji: "🍕",
        suggestedColor: ColorComponents(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0),
        presetImageName: nil
    )
    
    static let party = EventThemeTemplate(
        id: "party",
        name: "Party",
        emoji: "🎉",
        suggestedColor: ColorComponents(red: 0.9, green: 0.3, blue: 0.5, alpha: 1.0),
        presetImageName: nil
    )
    
    static let trip = EventThemeTemplate(
        id: "trip",
        name: "Trip",
        emoji: "✈️",
        suggestedColor: ColorComponents(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0),
        presetImageName: nil
    )
    
    static let gameNight = EventThemeTemplate(
        id: "game_night",
        name: "Game Night",
        emoji: "🎮",
        suggestedColor: ColorComponents(red: 0.5, green: 0.3, blue: 0.9, alpha: 1.0),
        presetImageName: nil
    )
    
    static let custom = EventThemeTemplate(
        id: "custom",
        name: "Custom",
        emoji: "✨",
        suggestedColor: ColorComponents(red: 0.58, green: 0.41, blue: 0.87, alpha: 1.0),
        presetImageName: nil
    )
    
    static let allTemplates: [EventThemeTemplate] = [
        .movieNight,
        .dinner,
        .party,
        .trip,
        .gameNight,
        .custom
    ]
}

// MARK: - Emoji Picker Helper
private struct EmojiPicker {
    static let popularEmojis: [String] = [
        "🎬", "🍕", "🎉", "✈️", "🎮", "🎂", "🎪", "🏖️", "⛷️", "🏄",
        "🎨", "🎭", "🎤", "🎧", "🎸", "🎹", "🥳", "🎊", "🎈", "🎁",
        "🏋️", "⚽", "🏀", "🎾", "🏐", "🏓", "🏸", "🏒", "⛳", "🏌️",
        "🍔", "🍟", "🍕", "🌮", "🌯", "🍜", "🍱", "🍣", "🍰", "🍪",
        "☕", "🍷", "🍸", "🍹", "🍺", "🍻", "🥂", "🧃", "🧉", "🧊",
        "🎓", "📚", "✏️", "📝", "📖", "📕", "📗", "📘", "📙", "📔",
        "🎯", "🎲", "🃏", "🀄", "🎴", "🎰", "🎳", "🎪", "🎭", "🎨"
    ]
    
    static let categories: [(name: String, emojis: [String])] = [
        ("Activities", ["🎬", "🎮", "🎨", "🎭", "🎤", "🎧", "🎸", "🎹", "🎯", "🎲"]),
        ("Food & Drink", ["🍕", "🍔", "🍟", "🌮", "🌯", "🍜", "🍱", "🍣", "🍰", "☕", "🍷", "🍸"]),
        ("Celebrations", ["🎉", "🎂", "🥳", "🎊", "🎈", "🎁", "🎪", "🎭"]),
        ("Travel", ["✈️", "🏖️", "⛷️", "🏄", "🚗", "🚂", "🚢", "🚁"]),
        ("Sports", ["⚽", "🏀", "🎾", "🏐", "🏓", "🏸", "🏒", "⛳", "🏋️"]),
        ("Education", ["🎓", "📚", "✏️", "📝", "📖", "🎯"])
    ]
}

// MARK: - Theme Template Button
private struct ThemeTemplateButton: View {
    let template: EventThemeTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(template.emoji)
                    .font(.system(size: 32))
                Text(template.name)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(.systemGray5) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Emoji Picker View
private struct EmojiPickerView: View {
    @Binding var selectedEmoji: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    
    private var filteredEmojis: [String] {
        if searchText.isEmpty {
            if selectedCategory == "All" {
                return EmojiPicker.popularEmojis
            } else {
                return EmojiPicker.categories.first(where: { $0.name == selectedCategory })?.emojis ?? []
            }
        } else {
            return EmojiPicker.popularEmojis.filter { emoji in
                // Simple search - could be enhanced with emoji names
                true
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        CategoryTab(title: "All", isSelected: selectedCategory == "All") {
                            selectedCategory = "All"
                        }
                        ForEach(EmojiPicker.categories, id: \.name) { category in
                            CategoryTab(title: category.name, isSelected: selectedCategory == category.name) {
                                selectedCategory = category.name
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Emoji grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                        ForEach(filteredEmojis, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                                dismiss()
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 32))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemGray6))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Choose Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CategoryTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(.systemGray5) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


