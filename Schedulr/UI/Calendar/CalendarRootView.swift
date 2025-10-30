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
            .task { await loadPreferences() }
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
        return list
    }

    private var displayEvents: [DisplayEvent] {
        if !preferences.dedupAllDay { return filteredEvents.map { DisplayEvent(base: $0, sharedCount: 1) } }
        // Group identical all‑day events by day + normalized title
        var result: [DisplayEvent] = []
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEvents) { ev -> String in
            let day = calendar.startOfDay(for: ev.start_date)
            let title = ev.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(day.timeIntervalSince1970)#\(ev.is_all_day ? "1" : "0")#\(title)"
            return key
        }
        for (_, arr) in groups {
            if let first = arr.first {
                if first.is_all_day {
                    result.append(DisplayEvent(base: first, sharedCount: arr.count))
                } else {
                    result.append(contentsOf: arr.map { DisplayEvent(base: $0, sharedCount: 1) })
                }
            }
        }
        // Sort by start date
        return result.sorted { a, b in
            if a.base.start_date == b.base.start_date { return a.base.end_date < b.base.end_date }
            return a.base.start_date < b.base.start_date
        }
    }

    private var dayViewEvents: [CalendarEventWithUser] {
        // Hide all‑day when dedup is enabled (they are summarized elsewhere)
        if preferences.dedupAllDay { return filteredEvents.filter { !$0.is_all_day } }
        return filteredEvents
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


