import SwiftUI
import Supabase
import Auth
import UIKit

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
    @State private var categories: [EventCategory] = []
    @State private var selectedCategoryId: UUID? = nil
    @State private var showingCategoryCreator = false
    @State private var isLoadingCategories = false

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
                
                Section("Category") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(categories) { category in
                            HStack {
                                Circle()
                                    .fill(Color(
                                        red: category.color.red,
                                        green: category.color.green,
                                        blue: category.color.blue,
                                        opacity: category.color.alpha
                                    ))
                                    .frame(width: 12, height: 12)
                                Text(category.name)
                            }
                            .tag(category.id as UUID?)
                        }
                    }
                    
                    Button("Create New Category") {
                        showingCategoryCreator = true
                    }
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
        .task {
            await loadCategories()
            prefillIfEditing()
        }
        .sheet(isPresented: $showingCategoryCreator) {
            CategoryCreatorView(groupId: groupId) { category in
                categories.append(category)
                selectedCategoryId = category.id
            }
        }
    }
    
    private func loadCategories() async {
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
                    originalEventId: ekId,
                    categoryId: selectedCategoryId
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
        selectedCategoryId = ev.category_id
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


