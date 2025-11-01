import SwiftUI
import Supabase
import Auth

enum CalendarMode: String, CaseIterable, Identifiable {
    case year = "Year"
    case month = "Month"
    case list = "List"
    
    var id: String { rawValue }
}

enum MonthViewMode: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case stacked = "Stacked"
    case details = "Details"
    
    var id: String { rawValue }
}

struct CalendarRootView: View {
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @ObservedObject var viewModel: DashboardViewModel

    @State private var mode: CalendarMode = .month
    @State private var monthViewMode: MonthViewMode = .compact
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var displayedYear: Date = Date()
    @State private var preferences = CalendarPreferences(hideHolidays: true, dedupAllDay: true)
    @State private var isLoadingPrefs = false
    @State private var showingEditor = false
    @State private var showingMonthModePicker = false
    @State private var categories: [EventCategory] = []
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var isLoadingCategories = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft background color
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                // Subtle soft color overlay
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.08),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.06),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 300
                            )
                        )
                        .offset(x: -150, y: -200)
                        .blur(radius: 80)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 350
                            )
                        )
                        .offset(x: 180, y: 400)
                        .blur(radius: 100)
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Apple Calendar style header
                    calendarHeader
                    
                    if !categories.isEmpty {
                        categoryFilterBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    // Main calendar content
                    Group {
                        switch mode {
                        case .year:
                            YearlyCalendarView(
                                selectedDate: $selectedDate,
                                displayedYear: $displayedYear,
                                events: displayEvents,
                                onMonthSelected: { monthDate in
                                    withAnimation {
                                        selectedDate = monthDate
                                        displayedMonth = startOfMonth(for: monthDate)
                                        mode = .month
                                    }
                                }
                            )
                            .id("year-\(Calendar.current.component(.year, from: displayedYear))")
                        case .month:
                            MonthGridView(
                                events: displayEvents,
                                members: memberColorMapping,
                                selectedDate: $selectedDate,
                                displayedMonth: $displayedMonth,
                                viewMode: monthViewMode,
                                onDateSelected: { date in
                                    // When a date is selected, switch to Details mode to show events
                                    if monthViewMode != .details {
                                        withAnimation {
                                            monthViewMode = .details
                                        }
                                    }
                                }
                            )
                        case .list:
                            AgendaListView(
                                events: displayEvents,
                                members: memberColorMapping,
                                selectedDate: $selectedDate
                            )
                        }
                    }
                    .animation(.default, value: mode)
                    .animation(.default, value: monthViewMode)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // View mode picker button
                    Menu {
                        Button {
                            withAnimation {
                                mode = .year
                            }
                        } label: {
                            HStack {
                                Text("Year")
                                if mode == .year {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Button {
                            withAnimation {
                                mode = .month
                            }
                        } label: {
                            HStack {
                                Text("Month")
                                if mode == .month {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Button {
                            withAnimation {
                                mode = .list
                            }
                        } label: {
                            HStack {
                                Text("List")
                                if mode == .list {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: mode == .year ? "calendar" : (mode == .month ? "calendar" : "list.bullet"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    if let gid = viewModel.selectedGroupID {
                        Button {
                            showingEditor = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .disabled(calendarSync.isRefreshing)
                    }
                    
                    if calendarSync.syncEnabled, let groupId = viewModel.selectedGroupID {
                        Button {
                            Task {
                                if let userId = try? await viewModel.client?.auth.session.user.id {
                                    await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                                }
                            }
                        } label: {
                            Image(systemName: calendarSync.isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .rotationEffect(.degrees(calendarSync.isRefreshing ? 360 : 0))
                                .animation(calendarSync.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: calendarSync.isRefreshing)
                        }
                        .disabled(calendarSync.isRefreshing)
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                if let gid = viewModel.selectedGroupID {
                    EventEditorView(groupId: gid, members: viewModel.members)
                }
            }
            .sheet(isPresented: $showingMonthModePicker) {
                MonthViewModePicker(selectedMode: $monthViewMode)
                    .presentationDetents([.height(280)])
            }
            .task {
                await loadPreferences()
                await loadCategories()
                displayedMonth = startOfMonth(for: selectedDate)
                displayedYear = startOfYear(for: selectedDate)
            }
            .onChange(of: selectedDate) { _, newDate in
                // Only update displayedMonth/Year if they're not already in sync
                // This prevents unnecessary updates when navigating months
                let newMonth = startOfMonth(for: newDate)
                let newYear = startOfYear(for: newDate)
                
                if !Calendar.current.isDate(displayedMonth, equalTo: newMonth, toGranularity: .month) {
                    displayedMonth = newMonth
                }
                if !Calendar.current.isDate(displayedYear, equalTo: newYear, toGranularity: .year) {
                    displayedYear = newYear
                }
            }
        }
    }
    
    private var calendarHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Navigation buttons (back and forward)
                HStack(spacing: 8) {
                    // Back button
                    if mode == .year {
                        Button {
                            withAnimation {
                                displayedYear = Calendar.current.date(byAdding: .year, value: -1, to: displayedYear) ?? displayedYear
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    } else if mode == .month {
                        Button {
                            withAnimation {
                                let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                                displayedMonth = previousMonth
                                selectedDate = startOfMonth(for: previousMonth)
                                // Update displayedYear if we crossed a year boundary
                                displayedYear = startOfYear(for: previousMonth)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    } else {
                        Button {
                            withAnimation {
                                mode = .month
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Forward button (for year and month views)
                    if mode == .year {
                        Button {
                            withAnimation {
                                displayedYear = Calendar.current.date(byAdding: .year, value: 1, to: displayedYear) ?? displayedYear
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    } else if mode == .month {
                        Button {
                            withAnimation {
                                let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                                displayedMonth = nextMonth
                                selectedDate = startOfMonth(for: nextMonth)
                                // Update displayedYear if we crossed a year boundary
                                displayedYear = startOfYear(for: nextMonth)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                }
                
                Spacer()
                
                // Month/Year title
                if mode == .year {
                    Text("\(Calendar.current.component(.year, from: displayedYear))")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.red)
                } else if mode == .month {
                    Text(monthTitleWithYear(displayedMonth))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                } else {
                    // List view - show selected date title
                    Text(monthTitle(selectedDate))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Month view mode picker (only for month view)
                if mode == .month {
                    Button {
                        showingMonthModePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(monthViewMode.rawValue)
                                .font(.system(size: 16, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            
            // Days of week header (for month view)
            if mode == .month {
                HStack(spacing: 0) {
                    ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { index, day in
                        Text(day)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }
    
    private var weekdayHeaders: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let weekdaySymbols = formatter.shortWeekdaySymbols ?? []
        // Apple Calendar uses Sunday-first (default)
        return weekdaySymbols.map { String($0.prefix(1)).uppercased() }
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

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }
    
    private func monthTitleWithYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func startOfMonth(for date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? date
    }
    
    private func startOfYear(for date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year], from: date)
        return Calendar.current.date(from: components) ?? date
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
        // Deduplicate events: group by event ID first (same ID = same event, show once)
        // Then group remaining by title+time, but only show as "shared" if multiple different users have them
        var result: [DisplayEvent] = []
        let calendar = Calendar.current
        
        // First pass: Group by event ID to handle true duplicates - each event ID appears once
        let idGroups = Dictionary(grouping: filteredEvents) { $0.id }
        
        for (_, events) in idGroups {
            // All events with same ID are the same event - show once with count 1
            if let first = events.first {
                result.append(DisplayEvent(base: first, sharedCount: 1))
            }
        }
        
        // Second pass: For events not already in result, group by title+time
        // Only show as "shared" if multiple different users have different events with same title/time
        let alreadyIncludedIds = Set(result.map { $0.base.id })
        let remainingEvents = filteredEvents.filter { !alreadyIncludedIds.contains($0.id) }
        
        let groups = Dictionary(grouping: remainingEvents) { ev -> String in
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
                // Only show as "shared" if there are multiple unique event IDs AND multiple unique users
                // This ensures personal events from same user don't show as shared
                let uniqueIds = Set(arr.map { $0.id })
                let uniqueUsers = Set(arr.map { $0.user_id })
                
                if uniqueIds.count > 1 && uniqueUsers.count > 1 {
                    // Multiple different events from different users with same title/time = shared
                    result.append(DisplayEvent(base: first, sharedCount: uniqueIds.count))
                } else {
                    // Single event or events from same user = not shared, show once
                    result.append(DisplayEvent(base: first, sharedCount: 1))
                }
            }
        }
        
        // Sort by start date
        return result.sorted { a, b in
            if a.base.start_date == b.base.start_date { return a.base.end_date < b.base.end_date }
            return a.base.start_date < b.base.start_date
        }
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


