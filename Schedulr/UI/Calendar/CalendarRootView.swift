import SwiftUI
import Supabase
import Auth

enum CalendarMode: String, CaseIterable, Identifiable {
    case agenda = "List"
    case day = "Day"
    case month = "Month"

    var id: String { rawValue }
}

struct CalendarRootView: View {
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @ObservedObject var viewModel: DashboardViewModel

    @State private var mode: CalendarMode = .agenda
    @State private var selectedDate: Date = Date()
    @State private var preferences = CalendarPreferences(hideHolidays: true, dedupAllDay: true)
    @State private var isLoadingPrefs = false
    @State private var showingEditor = false
    @State private var categories: [EventCategory] = []
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var isLoadingCategories = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 12) {
                    header
                    Picker("Mode", selection: $mode) {
                        ForEach(CalendarMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    if !categories.isEmpty {
                        categoryFilterBar
                    }

                    Group {
                        switch mode {
                        case .agenda:
                            AgendaListView(
                                events: displayEvents,
                                members: memberColorMapping,
                                selectedDate: $selectedDate
                            )
                        case .day:
                            DayTimelineView(
                                events: dayViewEvents,
                                members: memberColorMapping,
                                date: $selectedDate
                            )
                        case .month:
                            MonthGridView(
                                events: displayEvents,
                                members: memberColorMapping,
                                selectedDate: $selectedDate
                            )
                        }
                    }
                    .animation(.default, value: mode)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                refreshButton
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let gid = viewModel.selectedGroupID {
                        Button {
                            showingEditor = true
                        } label: { Image(systemName: "plus") }
                        .disabled(calendarSync.isRefreshing)
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                if let gid = viewModel.selectedGroupID {
                    EventEditorView(groupId: gid, members: viewModel.members)
                }
            }
            .task {
                await loadPreferences()
                await loadCategories()
            }
        }
    }
    
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" button to clear filters
                Button(action: {
                    selectedCategoryIds.removeAll()
                }) {
                    Text("All")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategoryIds.isEmpty ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(selectedCategoryIds.isEmpty ? .white : .primary)
                        .cornerRadius(16)
                }
                
                // Category filter buttons
                ForEach(categories) { category in
                    Button(action: {
                        if selectedCategoryIds.contains(category.id) {
                            selectedCategoryIds.remove(category.id)
                        } else {
                            selectedCategoryIds.insert(category.id)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(
                                    red: category.color.red,
                                    green: category.color.green,
                                    blue: category.color.blue,
                                    opacity: category.color.alpha
                                ))
                                .frame(width: 10, height: 10)
                            Text(category.name)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategoryIds.contains(category.id) ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(selectedCategoryIds.contains(category.id) ? .white : .primary)
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }
    
    private func loadCategories() async {
        guard !isLoadingCategories else { return }
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            let uid = try await viewModel.client?.auth.session.user.id
            if let uid = uid, let groupId = viewModel.selectedGroupID {
                categories = try await CalendarEventService.shared.fetchCategories(userId: uid, groupId: groupId)
            }
        } catch {
            // Silently fail - categories are optional
        }
    }

    private var header: some View {
        HStack {
            Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate }) {
                Image(systemName: "chevron.left.circle.fill").font(.title2)
                    .foregroundStyle(LinearGradient(colors: [
                        Color(red: 0.98, green: 0.29, blue: 0.55),
                        Color(red: 0.58, green: 0.41, blue: 0.87)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Spacer()
            Text(dateTitle(for: selectedDate))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            Button(action: { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate }) {
                Image(systemName: "chevron.right.circle.fill").font(.title2)
                    .foregroundStyle(LinearGradient(colors: [
                        Color(red: 0.98, green: 0.29, blue: 0.55),
                        Color(red: 0.58, green: 0.41, blue: 0.87)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .padding(.horizontal)
    }

    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if calendarSync.syncEnabled, let groupId = viewModel.selectedGroupID {
                Button {
                    Task {
                        if let userId = try? await viewModel.client?.auth.session.user.id {
                            await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(calendarSync.isRefreshing)
            }
        }
    }

    // MARK: - Event filtering/deduping
    private var filteredEvents: [CalendarEventWithUser] {
        var list = calendarSync.groupEvents
        if preferences.hideHolidays {
            list = list.filter { ev in
                let name = (ev.calendar_name ?? ev.title).lowercased()
                let cal = (ev.calendar_name ?? "").lowercased()
                let isHoliday = name.contains("holiday") || cal.contains("holiday")
                let isBirthday = name.contains("birthday") || cal.contains("birthday")
                return !(isHoliday || isBirthday)
            }
        }
        
        // Filter by selected categories
        if !selectedCategoryIds.isEmpty {
            list = list.filter { ev in
                if let categoryId = ev.category_id {
                    return selectedCategoryIds.contains(categoryId)
                }
                return false
            }
        }
        
        return list
    }

    private var displayEvents: [DisplayEvent] {
        // Always deduplicate events: group identical events by normalized title + time range
        var result: [DisplayEvent] = []
        let calendar = Calendar.current
        
        let groups = Dictionary(grouping: filteredEvents) { ev -> String in
            let title = ev.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ev.is_all_day {
                // For all-day events, group by day + title
                let day = calendar.startOfDay(for: ev.start_date)
                return "allday:\(day.timeIntervalSince1970):\(title)"
            } else {
                // For timed events, group by start/end time (within 1 minute tolerance) + title
                let startRounded = round(ev.start_date.timeIntervalSince1970 / 60) * 60
                let endRounded = round(ev.end_date.timeIntervalSince1970 / 60) * 60
                return "timed:\(startRounded):\(endRounded):\(title)"
            }
        }
        
        for (_, arr) in groups {
            if let first = arr.first {
                // Always show with shared count if multiple users have the same event
                result.append(DisplayEvent(base: first, sharedCount: arr.count))
            }
        }
        
        // Sort by start date
        return result.sorted { a, b in
            if a.base.start_date == b.base.start_date { return a.base.end_date < b.base.end_date }
            return a.base.start_date < b.base.start_date
        }
    }

    private var dayViewEvents: [CalendarEventWithUser] {
        // Return deduplicated events for day view (extract from displayEvents)
        return displayEvents.map { $0.base }
    }

    private var memberColorMapping: [UUID: (name: String, color: Color)] {
        var mapping: [UUID: (name: String, color: Color)] = [:]
        for member in viewModel.members {
            mapping[member.id] = (name: member.displayName, color: calendarSync.userColor(for: member.id))
        }
        return mapping
    }

    private func dateTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: date)
    }
}

// MARK: - Preferences IO
extension CalendarRootView {
    private func loadPreferences() async {
        guard !isLoadingPrefs else { return }
        isLoadingPrefs = true
        defer { isLoadingPrefs = false }
        if let uid = try? await viewModel.client?.auth.session.user.id {
            if let prefs = try? await CalendarPreferencesManager.shared.load(for: uid) {
                preferences = prefs
            }
        }
    }

    private func savePreferences() async {
        if let uid = try? await viewModel.client?.auth.session.user.id {
            try? await CalendarPreferencesManager.shared.save(preferences, for: uid)
        }
    }
}


