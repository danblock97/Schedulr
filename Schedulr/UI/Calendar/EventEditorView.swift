import SwiftUI
import Supabase
import Auth
import UIKit

struct EventEditorView: View {
    let groupId: UUID
    @State private var members: [DashboardViewModel.MemberSummary]
    var existingEvent: CalendarEventWithUser? = nil
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
    
    init(groupId: UUID, members: [DashboardViewModel.MemberSummary], existingEvent: CalendarEventWithUser? = nil) {
        self.groupId = groupId
        self.members = members
        self.existingEvent = existingEvent
        _selectedGroupId = State(initialValue: groupId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    Toggle("All day", isOn: $isAllDay)
                    
                    Picker("Event Type", selection: $eventType) {
                        Text("Personal").tag("personal")
                        Text("Group").tag("group")
                    }
                    .onChange(of: eventType) { oldValue, newValue in
                        if newValue == "personal" {
                            // Clear all invites when marked as personal
                            selectedMemberIds.removeAll()
                            guestNamesText = ""
                        } else if newValue == "group" {
                            // Group events sync automatically, so disable the toggle
                            saveToAppleCalendar = false
                        }
                    }
                    
                    DatePicker("Start", selection: $date, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    TextField("Location", text: $location)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
                
                Section("Group") {
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
                        Picker("Group", selection: $selectedGroupId) {
                            ForEach(availableGroups) { group in
                                Text(group.name).tag(group.id)
                            }
                        }
                        .disabled(eventType == "personal")
                        .onChange(of: selectedGroupId) { oldValue, newValue in
                            // Reload members and categories when group changes
                            Task {
                                await loadMembersForGroup(newValue)
                                await loadCategoriesForGroup(newValue)
                            }
                        }
                    }
                }
                
                Section("Category") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(categories) { category in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(
                                        red: category.color.red,
                                        green: category.color.green,
                                        blue: category.color.blue,
                                        opacity: category.color.alpha
                                    ))
                                    .frame(width: 12, height: 12)
                                Text(category.name)
                                if let groupId = category.group_id, groupId == selectedGroupId {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(category.id as UUID?)
                        }
                    }
                    
                    Button("Create New Category") {
                        showingCategoryCreator = true
                    }
                }

                if eventType == "group" {
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
                }
                
                if existingEvent != nil && !currentAttendees.isEmpty {
                    Section("Current Attendees") {
                        ForEach(currentAttendees.indices, id: \.self) { index in
                            HStack {
                                Circle().fill(Color.blue.opacity(0.9)).frame(width: 8, height: 8)
                                Text(currentAttendees[index].displayName)
                                Spacer()
                                Text(currentAttendees[index].status.capitalized)
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }
                    }
                }

                if eventType == "personal" {
                    Section("Apple Calendar") {
                        Toggle("Save to Apple Calendar", isOn: $saveToAppleCalendar)
                            .accessibilityHint("Also creates/updates an Apple Calendar event")
                    }
                } else {
                    Section("Apple Calendar") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Group events automatically sync to Apple Calendar")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
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
        .task {
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
            }
        }
        .sheet(isPresented: $showingCategoryCreator) {
            CategoryCreatorView(groupId: selectedGroupId) { category in
                categories.append(category)
                selectedCategoryId = category.id
            }
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
                        ekId = try? await EventKitEventManager.shared.createEvent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: date, end: endDate, isAllDay: isAllDay, location: location.isEmpty ? nil : location, notes: notes.isEmpty ? nil : notes, categoryColor: categoryColor)
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
                    eventType: eventType
                )
                if let existingEvent {
                    try await CalendarEventService.shared.updateEvent(eventId: existingEvent.id, input: input, currentUserId: uid)
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
}

// MARK: - Category Creator View
struct CategoryCreatorView: View {
    let groupId: UUID
    let onCategoryCreated: (EventCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var categoryName: String = ""
    @State private var selectedColor: Color = .blue
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var shareWithGroup = false
    
    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue,
        .indigo, .purple, .pink, .brown
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Name", text: $categoryName)
                    
                    Toggle("Share with group", isOn: $shareWithGroup)
                }
                
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
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
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
                    color: colorComponents
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

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


