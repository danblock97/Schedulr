import SwiftUI
import Supabase

/// A sheet that lets Pro users propose meeting times via AI or the deterministic engine.
struct ProposeTimesView: View {
    enum Mode: String, CaseIterable {
        case standard = "Standard"
        case aiAssist = "AI Assist"
    }
    
    @ObservedObject var dashboardViewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var mode: Mode = .aiAssist
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var durationHours: Double = 1.0
    @State private var windowStart = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var windowEnd = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var rangeStart = Calendar.current.startOfDay(for: Date())
    @State private var rangeEnd = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var titleText: String = "Proposed meeting"
    
    // AI mode
    @State private var aiPrompt: String = ""
    @State private var remainingAIRequests: Int?
    @State private var showPaywall = false
    
    // Results / status
    @State private var isLoading = false
    @State private var slots: [FreeTimeSlot] = []
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerCard
                    
                    if subscriptionManager.isPro {
                        modePickerCard
                        
                        if mode == .standard {
                            standardForm
                        } else {
                            aiForm
                        }
                        
                        if let success = successMessage {
                            StatusBanner(
                                icon: "checkmark.circle.fill",
                                text: success,
                                tint: themeManager.primaryColor
                            )
                        }
                        
                        if let error = errorMessage {
                            StatusBanner(
                                icon: "exclamationmark.triangle.fill",
                                text: error,
                                tint: Color.orange
                            )
                        }
                        
                        if !slots.isEmpty {
                            slotResults
                        }
                    } else {
                        paywallGate
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .overlay(alignment: .center) {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Finding times…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(radius: 12)
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut, value: isLoading)
            .navigationTitle("Propose times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                // Preselect all members by default
                selectedMemberIds = Set(dashboardViewModel.members.map { $0.id })
                remainingAIRequests = await AIUsageTracker.shared.getRemainingRequests()
            }
        }
    }
    
    // MARK: - Hero & mode
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(themeManager.gradient)
                    )
                Spacer()
                if let remaining = remainingAIRequests, subscriptionManager.isPro {
                    Text("\(remaining) AI left")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(themeManager.primaryColor.opacity(0.12))
                        )
                }
            }
            
            Text("Find the best time together")
                .font(.title3.weight(.bold))
            
            Text(subscriptionManager.isPro ? "Use AI Assist for natural language or Standard to pick with precise controls." : "Upgrade to Pro to propose times with AI and the shared availability engine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeManager.gradient.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.primaryColor.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var modePickerCard: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Text(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Shared constraints (used by both flows)
    
    private var memberSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dashboardViewModel.members.isEmpty {
                Text("No members found in this group.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dashboardViewModel.members) { member in
                    memberRow(member)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
    
    private var durationPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                durationChip("30m", value: 0.5)
                durationChip("1h", value: 1.0)
                durationChip("1h 30m", value: 1.5)
            }
            HStack(spacing: 8) {
                durationChip("2h", value: 2.0)
                durationChip("3h", value: 3.0)
                Spacer()
            }
        }
    }
    
    private var timeWindowPickers: some View {
        VStack(spacing: 8) {
            timeField(label: "Start", date: $windowStart)
            timeField(label: "End", date: $windowEnd)
        }
    }
    
    private var dateRangePickers: some View {
        VStack(spacing: 8) {
            dateField(label: "Start", date: $rangeStart)
            dateField(label: "End", date: $rangeEnd)
        }
    }
    
    private var standardForm: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Who should attend?", themeManager: themeManager)
            memberSelector
            
            inputCard(title: "Duration") {
                durationPicker
            }
            
            inputCard(title: "Time window") {
                timeWindowPickers
            }
            
            inputCard(title: "Date range") {
                dateRangePickers
            }
            
            inputCard(title: "Event title") {
                TextField("e.g. Project kickoff", text: $titleText)
                    .padding(12)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            }
            
            actionButton(
                title: "Find times (Standard)",
                icon: "sparkles",
                isLoading: isLoading,
                action: runStandardSearch
            )
        }
    }
    
    private var aiForm: some View {
        VStack(spacing: 10) {
            TextEditor(text: $aiPrompt)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Ask in plain English (e.g., \"Find 90 mins next week after 10am for Alice & Bob\")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
            
            actionButton(
                title: "Let AI propose times",
                icon: "sparkles",
                isLoading: isLoading,
                action: runAISearch
            )
        }
    }
    
    private var paywallGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(themeManager.gradient)
            Text("AI propose times is a Pro feature")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Upgrade to let Scheduly find and create the best slots for your group, with natural language and AI ranking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            Button {
                showPaywall = true
            } label: {
                Text("Upgrade to Pro")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(themeManager.gradient)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: themeManager.primaryColor.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
        )
        .padding(.top, 12)
    }
    
    // MARK: - Results
    
    private var slotResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Suggested slots (\(min(slots.count, 3)) of \(slots.count))", themeManager: themeManager)
            
            ForEach(Array(slots.prefix(3)).indices, id: \.self) { idx in
                let slot = slots[idx]
                SlotRow(
                    slot: slot,
                    memberNames: memberNames,
                    onCreate: { Task { await createEvent(from: slot) } }
                )
                .environmentObject(themeManager)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func runStandardSearch() {
        Task {
            isLoading = true
            successMessage = nil
            errorMessage = nil
            slots = []
            defer { isLoading = false }
            
            guard subscriptionManager.isPro else {
                showPaywall = true
                return
            }
            guard let groupId = dashboardViewModel.selectedGroupID else {
                errorMessage = "Select a group first."
                return
            }
            guard !selectedMemberIds.isEmpty else {
                errorMessage = "Pick at least one attendee."
                return
            }
            guard windowEnd > windowStart else {
                errorMessage = "End time must be after start time."
                return
            }
            guard rangeEnd >= rangeStart else {
                errorMessage = "Date range end must be after start."
                return
            }
            await performSearch(
                groupId: groupId,
                userIds: Array(selectedMemberIds),
                duration: durationHours,
                timeWindow: AvailabilityQuery.TimeWindow(
                    start: hhmm(from: windowStart),
                    end: hhmm(from: windowEnd)
                ),
                dateRange: AvailabilityQuery.DateRange(
                    start: isoDate(rangeStart),
                    end: isoDate(rangeEnd)
                ),
                debitAI: false
            )
        }
    }
    
    private func runAISearch() {
        Task {
            isLoading = true
            successMessage = nil
            errorMessage = nil
            slots = []
            defer { isLoading = false }
            
            guard subscriptionManager.isPro else {
                showPaywall = true
                return
            }
            let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                errorMessage = "Add a brief request for the AI to work with."
                return
            }
            guard let groupId = dashboardViewModel.selectedGroupID else {
                errorMessage = "Select a group first."
                return
            }
            
            // Check quota
            let canUseAI = await AIUsageTracker.shared.canMakeRequest()
            guard canUseAI else {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowUpgradePaywall"),
                    object: nil,
                    userInfo: ["reason": "ai_limit"]
                )
                showPaywall = true
                return
            }
            
            // Build minimal chat history for parsing
            let system = ChatMessage(role: .system, content: "You are Scheduly, an AI scheduling assistant.")
            let user = ChatMessage(role: .user, content: aiPrompt)
            let members = dashboardViewModel.members.map { ($0.id, $0.displayName) }
            let groups = dashboardViewModel.memberships.map { ($0.id, $0.name) }
            
            do {
                let availability = try await AIService.shared.parseAvailabilityQuery(
                    [system, user],
                    groupMembers: members,
                    groupNames: groups
                )
                
                guard availability.type == .availability else {
                    errorMessage = "I couldn't understand that. Try asking for times for specific people."
                    return
                }
                
                let resolvedUsers = resolveUserIds(from: availability.users)
                let userIdsToUse: [UUID]
                if !resolvedUsers.isEmpty {
                    userIdsToUse = resolvedUsers
                } else if !selectedMemberIds.isEmpty {
                    userIdsToUse = Array(selectedMemberIds)
                } else {
                    userIdsToUse = members.map { $0.0 }
                }
                selectedMemberIds = Set(userIdsToUse)
                
                let duration = availability.durationHours ?? durationHours
                
                let timeWindow = availability.timeWindow.map { tw in
                    AvailabilityQuery.TimeWindow(start: tw.start, end: tw.end)
                } ?? AvailabilityQuery.TimeWindow(start: hhmm(from: windowStart), end: hhmm(from: windowEnd))
                
                let dateRange = availability.dateRange.map { dr in
                    AvailabilityQuery.DateRange(start: dr.start, end: dr.end)
                } ?? AvailabilityQuery.DateRange(start: isoDate(rangeStart), end: isoDate(rangeEnd))
                
                await performSearch(
                    groupId: groupId,
                    userIds: userIdsToUse,
                    duration: duration,
                    timeWindow: timeWindow,
                    dateRange: dateRange,
                    debitAI: true
                )
                
                // Fetch updated remaining quota
                remainingAIRequests = await AIUsageTracker.shared.getRemainingRequests()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func performSearch(
        groupId: UUID,
        userIds: [UUID],
        duration: Double,
        timeWindow: AvailabilityQuery.TimeWindow,
        dateRange: AvailabilityQuery.DateRange,
        debitAI: Bool
    ) async {
        // Basic validation for time and date ranges
        if let start = parsedTime(timeWindow.start), let end = parsedTime(timeWindow.end), end <= start {
            errorMessage = "End time must be after start time."
            return
        }
        if let startDate = parsedDate(dateRange.start), let endDate = parsedDate(dateRange.end), endDate < startDate {
            errorMessage = "Date range end must be after start."
            return
        }
        
        do {
            let results = try await CalendarAnalysisService.shared.findFreeTimeSlots(
                userIds: userIds,
                groupId: groupId,
                durationHours: duration,
                timeWindow: timeWindow,
                dateRange: dateRange
            )
            slots = results
            if debitAI {
                await AIUsageTracker.shared.trackRequest()
            }
            if slots.isEmpty {
                errorMessage = "No free slots found. Try widening the time window or date range."
            } else {
                successMessage = "Here are the best options."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func createEvent(from slot: FreeTimeSlot) async {
        guard let groupId = dashboardViewModel.selectedGroupID else {
            errorMessage = "Select a group first."
            return
        }
        do {
            guard let currentUserId = try? await SupabaseManager.shared.client.auth.session.user.id else {
                errorMessage = "Could not verify your account."
                return
            }
            
            let attendeeIds = Array(selectedMemberIds)
            let eventType = attendeeIds.isEmpty ? "personal" : "group"
            
            let input = NewEventInput(
                groupId: groupId,
                title: titleText.isEmpty ? "Meeting" : titleText,
                start: slot.startDate,
                end: slot.endDate,
                isAllDay: false,
                location: nil,
                notes: nil,
                attendeeUserIds: attendeeIds,
                guestNames: [],
                originalEventId: nil,
                categoryId: nil,
                eventType: eventType
            )
            
            let eventId = try await CalendarEventService.shared.createEvent(input: input, currentUserId: currentUserId)
            successMessage = "Event created and shared with your group."
            await dashboardViewModel.refreshCalendarIfNeeded()
            // Navigate to the new event detail then dismiss
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToEvent"),
                object: nil,
                userInfo: ["eventId": eventId]
            )
            dismiss()
        } catch {
            errorMessage = "Couldn't create event: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    
    private func hhmm(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func displayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func parsedTime(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: string)
    }
    
    private func parsedDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
    
    private func resolveUserIds(from names: [String]) -> [UUID] {
        let map = memberLookup
        return names.compactMap { map[$0.lowercased()] }
    }
    
    private var memberLookup: [String: UUID] {
        var dict: [String: UUID] = [:]
        for member in dashboardViewModel.members {
            dict[member.displayName.lowercased()] = member.id
        }
        return dict
    }
    
    private var memberNames: [UUID: String] {
        var dict: [UUID: String] = [:]
        for member in dashboardViewModel.members {
            dict[member.id] = member.displayName
        }
        return dict
    }
}

// MARK: - Small helpers

private struct SectionHeader: View {
    let title: String
    let themeManager: ThemeManager
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(themeManager.gradient)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBanner: View {
    let icon: String
    let text: String
    let tint: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SlotRow: View {
    let slot: FreeTimeSlot
    let memberNames: [UUID: String]
    let onCreate: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatter.string(from: slot.startDate)) - \(formatter.string(from: slot.endDate))")
                        .font(.subheadline.weight(.semibold))
                    Text("\(Int(slot.confidence * 100))% of invitees free")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(slot.durationHours * 60)) min")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(themeManager.primaryColor.opacity(0.12), in: Capsule())
            }
            if !slot.availableUsers.isEmpty {
                let names = slot.availableUsers.compactMap { memberNames[$0] }
                if !names.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(names.prefix(4), id: \.self) { name in
                            Text(name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(themeManager.primaryColor.opacity(0.1), in: Capsule())
                        }
                        if names.count > 4 {
                            Text("+\(names.count - 4)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                    }
                }
            }
            
            Button(action: onCreate) {
                Label("Create event here", systemImage: "plus.circle.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeManager.primaryColor)
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension ProposeTimesView {
    func inputCard<V: View>(title: String, @ViewBuilder content: @escaping () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
            content()
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func durationChip(_ label: String, value: Double) -> some View {
        let isSelected = durationHours == value
        return Button {
            durationHours = value
        } label: {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(themeManager.gradient)
                                .opacity(isSelected ? 1 : 0)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(themeManager.primaryColor.opacity(isSelected ? 0.0 : 0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func timeField(label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(themeManager.primaryColor)
                Text(displayTime(date.wrappedValue))
                    .font(.body.weight(.semibold))
                Spacer()
                DatePicker(label, selection: date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func dateField(label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(themeManager.primaryColor)
                Text(displayDate(date.wrappedValue))
                    .font(.body.weight(.semibold))
                Spacer()
                DatePicker(label, selection: date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(themeManager.primaryColor.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    func actionButton(title: String, icon: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                    Text(title)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .padding(.vertical, 2)
        .background(themeManager.gradient)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: themeManager.primaryColor.opacity(0.25), radius: 12, x: 0, y: 6)
        .disabled(isLoading)
    }
    
    private func memberRow(_ member: DashboardViewModel.MemberSummary) -> some View {
        let isOn = selectedMemberIds.contains(member.id)
        return Button {
            if isOn {
                selectedMemberIds.remove(member.id)
            } else {
                selectedMemberIds.insert(member.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.displayName)
                        .font(.body.weight(.semibold))
                    Text(member.role.capitalized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? themeManager.primaryColor : .secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeManager.primaryColor.opacity(isOn ? 0.12 : 0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

