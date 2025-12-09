//
//  AIAssistantViewModel.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
final class AIAssistantViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var inputText: String = ""
    @Published var availableDraftPrompt: String?
    
    // Conversation persistence
    @Published var currentConversationId: UUID?
    @Published var conversations: [DBAIConversation] = []
    @Published var isLoadingConversations: Bool = false
    @Published var showConversationHistory: Bool = false
    
    // Track loaded draft follow-up (if any) to resolve when user resumes
    private var availableDraftFollowupId: UUID?
    private var activeDraftFollowupId: UUID?
    
    private let aiService = AIService.shared
    private let calendarAnalysisService = CalendarAnalysisService.shared
    private let persistenceService = AIChatPersistenceService.shared
    private let dashboardViewModel: DashboardViewModel
    private let calendarManager: CalendarSyncManager
    
    init(dashboardViewModel: DashboardViewModel, calendarManager: CalendarSyncManager) {
        self.dashboardViewModel = dashboardViewModel
        self.calendarManager = calendarManager
        
        // Add welcome message if no messages exist
        if messages.isEmpty {
            addWelcomeMessage()
        }
        
        // Load conversation history in background
        Task {
            await loadConversations()
        }
        
        // Attempt to load an open draft/follow-up for quick resume
        Task {
            await loadDraftIfAvailable()
        }
    }
    
    // MARK: - Message Handling
    
    func sendFollowUp(option: FollowUpOption, sourceMessageId: UUID) async {
        guard !isLoading else { return }
        
        if let index = messages.firstIndex(where: { $0.id == sourceMessageId }) {
            var updated = messages[index]
            updated.followUpOptions = []
            messages[index] = updated
        }
        
        inputText = option.prompt
        await sendMessage()
    }
    
    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        var assistantPersisted = false
        
        // If user resumed a draft, resolve that follow-up
        if let draftId = activeDraftFollowupId {
            await resolveSpecificAIFollowUp(id: draftId)
            activeDraftFollowupId = nil
        }
        
        // Clear input immediately
        inputText = ""
        errorMessage = nil
        
        // Add user message
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)
        
        // Ensure we have a conversation (create on first user message)
        _ = await ensureConversation(firstMessage: userMessage)
        
        // Persist the user message
        await persistMessage(userMsg)
        
        // Show loading state
        isLoading = true
        defer {
            // Always reset loading state, even if there's an unexpected error
            isLoading = false
        }
        
        // Check AI usage limits
        let canUseAI = await AIUsageTracker.shared.canMakeRequest()
        
        guard canUseAI else {
            // Show limit reached message
            let limitMsg = ChatMessage(
                role: .assistant,
                content: "⚠️ You've reached your AI usage limit for this month. Upgrade to Pro to get 300 AI requests per month!"
            )
            messages.append(limitMsg)
            await persistMessage(limitMsg)
            
            // Notify that limit check is needed
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowUpgradePaywall"),
                object: nil,
                userInfo: ["reason": "ai_limit"]
            )
            return
        }
        
        do {
            let lowercasedQuery = userMessage.lowercased()
            
            // PRIORITY 1: Check if query asks "what times work?" or similar availability questions
            // Note: We exclude "what's on" and "my schedule" as these are ambiguous - they could mean
            // "show my schedule" (listEvents) or "find free times" (availability)
            // Let the AI parsing handle the distinction
            let availabilityQuestionKeywords = ["what times work", "when are", "when can", "find times", "available times", "what times are", "when would", "times work", "find free", "free time", "available slots"]
            let isAvailabilityQuestion = availabilityQuestionKeywords.contains { lowercasedQuery.contains($0) }
            
            // PRIORITY 2: Check if this is a combined query (find slots then create event)
            let combinedKeywords = ["after finding", "after you find", "find a free slot", "find a time when", "find when"]
            let hasFindKeyword = combinedKeywords.contains { lowercasedQuery.contains($0) }
            let hasCreateKeyword = ["create", "schedule", "add", "set up", "plan", "book", "make"].contains { lowercasedQuery.contains($0) }
            let isCombinedQuery = hasFindKeyword && hasCreateKeyword && !isAvailabilityQuestion
            
            if isAvailabilityQuestion {
                // Handle as availability query (even if "schedule" is mentioned)
                let groupNames = dashboardViewModel.memberships.map { (id: $0.id, name: $0.name) }
                let availabilityQuery = try await aiService.parseAvailabilityQuery(messages, groupMembers: getGroupMembers(), groupNames: groupNames)
                
                // Handle group name references (e.g., "all team members from Work Team")
                var finalQuery = availabilityQuery
                var groupIdToUse = dashboardViewModel.selectedGroupID
                if availabilityQuery.type == .availability {
                    let (resolvedQuery, groupId) = await resolveGroupNameReferences(query: availabilityQuery, userMessage: userMessage)
                    finalQuery = resolvedQuery
                    groupIdToUse = groupId ?? groupIdToUse
                }
                
                if finalQuery.type == .availability && !finalQuery.users.isEmpty {
                    // Handle availability query with the correct group ID
                    assistantPersisted = await handleAvailabilityQuery(query: finalQuery, groupId: groupIdToUse)
                } else if finalQuery.type == .listEvents {
                    await handleListEventsQuery(query: finalQuery)
                } else {
                    // Handle general question
                    await handleGeneralQuestion(question: userMessage)
                }
            } else if isCombinedQuery {
                // Handle combined find-and-create query
                await handleFindAndCreateQuery(userMessage: userMessage)
            } else {
                // Try to parse as event creation
                let eventKeywords = ["create", "schedule", "add", "set up", "plan", "book", "make"]
                var isEventCreation = eventKeywords.contains { lowercasedQuery.contains($0) }
                
                // Refine "schedule" keyword - if it's "my schedule" or "the schedule", it's likely NOT creation
                if isEventCreation && lowercasedQuery.contains("schedule") {
                    if lowercasedQuery.contains("my schedule") || lowercasedQuery.contains("the schedule") || lowercasedQuery.contains("on schedule") {
                        isEventCreation = false
                    }
                }
                
                if isEventCreation {
                    // Event creation requires a selected group
                    guard let groupId = dashboardViewModel.selectedGroupID else {
                        let response = ChatMessage(
                            role: .assistant,
                            content: "Please select a group first to create an event. Go to the Groups tab and select a group."
                        )
                        messages.append(response)
                        await persistMessage(response)
                        return
                    }
                    
                    let selectedGroupName = dashboardViewModel.memberships.first(where: { $0.id == groupId })?.name
                    let eventQuery = try await aiService.parseEventCreationQuery(
                        messages,
                        groupMembers: getGroupMembers(),
                        groupName: selectedGroupName
                    )
                    await handleEventCreationQuery(query: eventQuery)
                } else {
                    // Check if query is about availability
                    // Get available group names for better parsing
                    let groupNames = dashboardViewModel.memberships.map { (id: $0.id, name: $0.name) }
                    let availabilityQuery = try await aiService.parseAvailabilityQuery(messages, groupMembers: getGroupMembers(), groupNames: groupNames)
                    
                    // Handle group name references (e.g., "all team members from Work Team")
                    var finalQuery = availabilityQuery
                    var groupIdToUse = dashboardViewModel.selectedGroupID
                    if availabilityQuery.type == .availability {
                        let (resolvedQuery, groupId) = await resolveGroupNameReferences(query: availabilityQuery, userMessage: userMessage)
                        finalQuery = resolvedQuery
                        groupIdToUse = groupId ?? groupIdToUse
                    }
                    
                    if finalQuery.type == .availability && !finalQuery.users.isEmpty {
                        // Handle availability query with the correct group ID
                        assistantPersisted = await handleAvailabilityQuery(query: finalQuery, groupId: groupIdToUse)
                    } else if finalQuery.type == .listEvents {
                        await handleListEventsQuery(query: finalQuery)
                    } else {
                        // Handle general question
                        await handleGeneralQuestion(question: userMessage)
                    }
                }
            }
            
            // Track AI usage after successful request
            await AIUsageTracker.shared.trackRequest()
            
            // Persist the last assistant message (the response)
            if !assistantPersisted, let lastMessage = messages.last, lastMessage.role == .assistant {
                await persistMessage(lastMessage)
            }
            
        } catch {
            // Show user-friendly error messages
            let friendlyError: String
            if let aiError = error as? AIServiceError {
                friendlyError = aiError.localizedDescription
            } else {
                friendlyError = error.localizedDescription
            }
            
            errorMessage = friendlyError
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "⚠️ \(friendlyError)"
            )
            messages.append(errorMsg)
            await persistMessage(errorMsg)
        }
    }
    
    // MARK: - Query Handling
    
    private func handleAvailabilityQuery(query: AvailabilityQuery, groupId: UUID? = nil) async -> Bool {
        let groupIdToUse = groupId ?? dashboardViewModel.selectedGroupID
        guard let groupId = groupIdToUse else {
            let response = ChatMessage(
                role: .assistant,
                content: "Please select a group first to check member availability. Go to the Groups tab and select a group."
            )
            messages.append(response)
            await persistMessage(response)
            return true
        }
        
        // Map user names to user IDs
        let memberMap = getMemberNameToIdMap()
        var userIds: [UUID] = []
        var foundNames: [String] = []
        
        for userName in query.users {
            if let userId = memberMap[userName.lowercased()] {
                userIds.append(userId)
                foundNames.append(userName)
            }
        }
        
        if userIds.isEmpty {
            let response = ChatMessage(
                role: .assistant,
                content: "I couldn't find those members in your current group. Please make sure you're using their exact names as they appear in the group members list."
            )
            messages.append(response)
            await persistMessage(response)
            return true
        }
        
        // Default duration to 1 hour if not specified
        let duration = query.durationHours ?? 1.0
        
        do {
            // Find free time slots
            let slots = try await calendarAnalysisService.findFreeTimeSlots(
                userIds: userIds,
                groupId: groupId,
                durationHours: duration,
                timeWindow: query.timeWindow,
                dateRange: query.dateRange
            )
            
            if slots.isEmpty {
                let response = ChatMessage(
                    role: .assistant,
                    content: "I couldn't find any free \(duration > 1 ? String(format: "%.1f", duration) : "1") hour time slots for \(foundNames.joined(separator: ", ")) in the requested time period. Try adjusting the duration or time window."
                )
                messages.append(response)
                await persistMessage(response)
            } else {
                // Format response with available slots
                let slotCount = min(slots.count, 5) // Show top 5 slots
                var responseText = "I found \(slots.count) available time slot\(slots.count == 1 ? "" : "s") for \(foundNames.joined(separator: ", ")):\n\n"
                
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                
                for (index, slot) in slots.prefix(slotCount).enumerated() {
                    let dateStr = formatter.string(from: slot.startDate)
                    let endStr = formatter.string(from: slot.endDate)
                    let confidence = Int(slot.confidence * 100)
                    
                    responseText += "\(index + 1). \(dateStr) - \(endStr)"
                    if confidence < 100 {
                        responseText += " (\(confidence)% available)"
                    }
                    responseText += "\n"
                }
                
                if slots.count > slotCount {
                    responseText += "\n...and \(slots.count - slotCount) more options."
                }
                
                let followUps = buildFollowUpOptions(for: Array(slots.prefix(slotCount)), durationHours: duration)
                let response = ChatMessage(role: .assistant, content: responseText, followUpOptions: followUps)
                messages.append(response)
                await persistMessage(response)
                // Track for AI follow-up since the user asked for availability
                Task { await recordPendingAIFollowUp(reason: "availability_slots_found") }
            }
        } catch {
            let response = ChatMessage(
                role: .assistant,
                content: "I encountered an error while checking availability: \(error.localizedDescription). Please try again."
            )
            messages.append(response)
            await persistMessage(response)
        }
        
        return true
    }
    
    private func handleListEventsQuery(query: AvailabilityQuery) async {
        // Get current user ID
        let currentUserId: UUID?
        do {
            if let client = SupabaseManager.shared.client {
                let session = try await client.auth.session
                currentUserId = session.user.id
            } else {
                currentUserId = nil
            }
        } catch {
            currentUserId = nil
        }
        
        // Check if this is a "next event" query by looking at recent conversation
        let lastUserMessage = messages.last(where: { $0.role == .user })?.content.lowercased() ?? ""
        let isNextEventQuery = lastUserMessage.contains("next event") || 
                               lastUserMessage.contains("next meeting") || 
                               lastUserMessage.contains("what's next") ||
                               lastUserMessage.contains("upcoming") ||
                               (lastUserMessage.contains("next") && lastUserMessage.contains("event"))
        
        // Parse date range
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let startDate: Date
        let endDate: Date
        
        if let range = query.dateRange,
           let start = dateFormatter.date(from: range.start),
           let end = dateFormatter.date(from: range.end) {
            startDate = start
            // If end date is same as start, make it end of day
            if start == end {
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            } else {
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            }
        } else if isNextEventQuery {
            // For "next event" queries, look forward from tomorrow
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            startDate = calendar.startOfDay(for: tomorrow)
            endDate = calendar.date(byAdding: .day, value: 30, to: startDate) ?? startDate
        } else {
            // Default to today
            startDate = Calendar.current.startOfDay(for: Date())
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }
        
        // Filter events
        let events = calendarManager.groupEvents.filter { event in
            // Check date overlap
            let eventStart = event.start_date
            let eventEnd = event.end_date
            return eventStart < endDate && eventEnd > startDate
        }
        
        // Filter by users if specified
        let memberMap = getMemberNameToIdMap()
        var targetUserIds: Set<UUID> = []
        
        if !query.users.isEmpty {
            for userName in query.users {
                if let userId = memberMap[userName.lowercased()] {
                    targetUserIds.insert(userId)
                }
            }
        } else {
            // If no users specified, assume current user ("my schedule")
            if let currentUserId = currentUserId {
                targetUserIds.insert(currentUserId)
            }
        }
        
        let filteredEvents = events.filter { event in
            if targetUserIds.isEmpty { return true } // Should not happen if logic above is correct
            
            // Check if event belongs to target user or they are attending
            if targetUserIds.contains(event.user_id) { return true }
            
            // Check attendees (if we had access to attendee list on event object easily)
            // For now, rely on user_id (owner) or if it's a group event visible to them
            // Ideally we check attendees, but CalendarEventWithUser doesn't expose raw attendee IDs list directly in a convenient way for this check without iterating
            // But wait, CalendarEventWithUser has `isCurrentUserAttendee`.
            
            if let currentUserId = currentUserId, targetUserIds.contains(currentUserId) {
                if event.isCurrentUserAttendee == true { return true }
            }
            
            return false
        }
        
        if filteredEvents.isEmpty {
            // Provide a more helpful message based on the query type
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            
            let rangeDescription: String
            if isNextEventQuery {
                rangeDescription = "the next 30 days"
            } else if let range = query.dateRange,
               let start = ISO8601DateFormatter().date(from: range.start) {
                let calendar = Calendar.current
                if calendar.isDateInToday(start) {
                    rangeDescription = "today"
                } else if calendar.isDateInTomorrow(start) {
                    rangeDescription = "tomorrow"
                } else {
                    rangeDescription = dateFormatter.string(from: start)
                }
            } else {
                rangeDescription = "today"
            }
            
            let responseText = isNextEventQuery 
                ? "You don't have any upcoming events scheduled in \(rangeDescription)."
                : "You don't have any events scheduled for \(rangeDescription)."
            
            let response = ChatMessage(
                role: .assistant,
                content: responseText
            )
            messages.append(response)
            await persistMessage(response)
        } else {
            let sortedEvents = filteredEvents.sorted { $0.start_date < $1.start_date }
            
            // Build a more conversational response
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE, MMM d"
            
            var responseText = ""
            var currentDay = ""
            var eventCount = 0
            
            for event in sortedEvents {
                let dayStr = dayFormatter.string(from: event.start_date)
                if dayStr != currentDay {
                    if !currentDay.isEmpty {
                        responseText += "\n"
                    }
                    responseText += "**\(dayStr)**\n"
                    currentDay = dayStr
                }
                
                let startStr = timeFormatter.string(from: event.start_date)
                let endStr = timeFormatter.string(from: event.end_date)
                let title = event.title
                
                responseText += "• \(startStr) - \(endStr): \(title)\n"
                eventCount += 1
            }
            
            // Add a summary at the beginning
            if isNextEventQuery {
                if eventCount == 1 {
                    responseText = "Your next event is:\n\n" + responseText
                } else {
                    responseText = "Here are your next \(eventCount) events:\n\n" + responseText
                }
            } else {
                if eventCount > 1 {
                    responseText = "You have \(eventCount) events scheduled:\n\n" + responseText
                } else if eventCount == 1 {
                    responseText = "You have 1 event scheduled:\n\n" + responseText
                }
            }
            
            let response = ChatMessage(role: .assistant, content: responseText)
            messages.append(response)
            await persistMessage(response)
        }
    }
    
    private func handleFindAndCreateQuery(userMessage: String) async {
        guard let groupId = dashboardViewModel.selectedGroupID else {
            let response = ChatMessage(
                role: .assistant,
                content: "Please select a group first. Go to the Groups tab and select a group."
            )
            messages.append(response)
            return
        }
        
        // Parse the query using AI to extract both availability requirements and event details
        do {
            let membersList = getGroupMembers().map { "\($0.name) (ID: \($0.id.uuidString))" }.joined(separator: ", ")
            
            // First, try to parse as a combined query
            let systemPrompt = """
You are Scheduly, a friendly AI scheduling assistant. The user wants to find free time slots AND then create an event at one of those slots.

Available group members: \(membersList)
Today's date: \(ISO8601DateFormatter().string(from: Date()).prefix(10))

Parse the query to extract:
1. Availability requirements (who, duration, time window, date range)
   - Match user names to the available members list
   - Extract duration in hours (e.g., "2 hours", "1 hour")
   - Extract time window in 24-hour format (e.g., "9 AM to 5 PM" becomes "09:00-17:00")
   - Extract date range in ISO 8601 format (e.g., "next week", "this weekend")
2. Event creation details (title, location, category, attendees, notes)
   - Match attendee names to available members or mark as guests

Return JSON in this format:
{
  "type": "findAndCreate",
  "availability": {
    "users": ["Member Name 1", "Member Name 2"],
    "durationHours": 2.0,
    "timeWindow": {"start": "09:00", "end": "17:00"},
    "dateRange": {"start": "2025-11-03", "end": "2025-11-10"}
  },
  "event": {
    "title": "Event Title",
    "location": "Location if mentioned",
    "categoryName": "Category if mentioned",
    "attendeeNames": ["Member Name"],
    "guestNames": ["Guest Name"],
    "notes": "Notes if mentioned"
  }
}

Omit fields that are not mentioned. Ensure user names match exactly to the available members list.
"""
            
            let aiMessages = [
                ChatMessage(role: .system, content: systemPrompt),
                ChatMessage(role: .user, content: userMessage)
            ]
            
            let aiResponse = try await aiService.chatCompletion(messages: aiMessages)
            
            // Extract JSON
            var jsonString = aiResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonString.hasPrefix("```") {
                let lines = jsonString.components(separatedBy: .newlines)
                jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
            }
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw AIServiceError.invalidResponse
            }
            
            // Parse the combined query
            struct CombinedQuery: Decodable {
                let type: String
                let availability: AvailabilityPart?
                let event: EventPart?
                
                struct AvailabilityPart: Decodable {
                    let users: [String]?
                    let durationHours: Double?
                    let timeWindow: TimeWindowPart?
                    let dateRange: DateRangePart?
                }
                
                struct TimeWindowPart: Decodable {
                    let start: String?
                    let end: String?
                }
                
                struct DateRangePart: Decodable {
                    let start: String?
                    let end: String?
                }
                
                struct EventPart: Decodable {
                    let title: String?
                    let location: String?
                    let categoryName: String?
                    let attendeeNames: [String]?
                    let guestNames: [String]?
                    let notes: String?
                }
            }
            
            let combinedQuery = try JSONDecoder().decode(CombinedQuery.self, from: jsonData)
            
            guard let availabilityPart = combinedQuery.availability,
                  let eventPart = combinedQuery.event,
                  let eventTitle = eventPart.title, !eventTitle.isEmpty else {
                // Fallback to general question if parsing fails
                await handleGeneralQuestion(question: userMessage)
                return
            }
            
            // Map user names to user IDs for availability check
            let memberMap = getMemberNameToIdMap()
            var userIds: [UUID] = []
            var foundNames: [String] = []
            
            for userName in availabilityPart.users ?? [] {
                if let userId = memberMap[userName.lowercased()] {
                    userIds.append(userId)
                    foundNames.append(userName)
                }
            }
            
            if userIds.isEmpty {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "I couldn't find the members mentioned for the availability check. Please make sure you're using their exact names as they appear in the group members list."
                )
                self.messages.append(errorMessage)
                return
            }
            
            // Find free time slots
            let duration = availabilityPart.durationHours ?? 2.0
            
            var timeWindow: AvailabilityQuery.TimeWindow? = nil
            if let tw = availabilityPart.timeWindow,
               let start = tw.start, let end = tw.end {
                timeWindow = AvailabilityQuery.TimeWindow(start: start, end: end)
            }
            
            var dateRange: AvailabilityQuery.DateRange? = nil
            if let dr = availabilityPart.dateRange,
               let start = dr.start, let end = dr.end {
                dateRange = AvailabilityQuery.DateRange(start: start, end: end)
            }
            
            let slots = try await calendarAnalysisService.findFreeTimeSlots(
                userIds: userIds,
                groupId: groupId,
                durationHours: duration,
                timeWindow: timeWindow,
                dateRange: dateRange
            )
            
            if slots.isEmpty {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "I couldn't find any free \(duration > 1 ? String(format: "%.1f", duration) : "1") hour time slots for \(foundNames.joined(separator: ", ")) in the requested time period. Try adjusting the duration or time window."
                )
                self.messages.append(errorMessage)
                return
            }
            
            // Use the first (best) available slot
            guard !slots.isEmpty else {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "I couldn't find any available time slots. Please try again."
                )
                self.messages.append(errorMessage)
                return
            }
            let selectedSlot = slots[0]
            
            // Create the event at the selected slot time
            let currentUserId: UUID
            do {
                guard let client = SupabaseManager.shared.client else {
                    throw NSError(domain: "AIAssistantViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not initialized"])
                }
                let session = try await client.auth.session
                currentUserId = session.user.id
            } catch {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "⚠️ Unable to authenticate. Please try logging in again."
                )
                self.messages.append(errorMessage)
                return
            }
            
            // Map attendee names for event creation
            var attendeeUserIds: [UUID] = []
            var guestNames: [String] = []
            
            for name in eventPart.attendeeNames ?? [] {
                if let userId = memberMap[name.lowercased()] {
                    attendeeUserIds.append(userId)
                } else {
                    guestNames.append(name)
                }
            }
            guestNames.append(contentsOf: eventPart.guestNames ?? [])
            
            // Get category ID if category name is provided
            var categoryId: UUID? = nil
            if let categoryName = eventPart.categoryName, !categoryName.isEmpty {
                do {
                    let categories = try await CalendarEventService.shared.fetchCategories(userId: currentUserId, groupId: groupId)
                    if let category = categories.first(where: { $0.name.lowercased() == categoryName.lowercased() }) {
                        categoryId = category.id
                    }
                } catch {
                    // If category lookup fails, continue without category
                }
            }
            
            // Determine event type
            let eventType = (attendeeUserIds.isEmpty && guestNames.isEmpty ? "personal" : "group")
            
            // Create the event
            let eventInput = NewEventInput(
                groupId: groupId,
                title: eventTitle,
                start: selectedSlot.startDate,
                end: selectedSlot.endDate,
                isAllDay: false,
                location: eventPart.location,
                notes: eventPart.notes,
                attendeeUserIds: attendeeUserIds,
                guestNames: guestNames,
                originalEventId: nil,
                categoryId: categoryId,
                eventType: eventType
            )
            
            let eventId = try await CalendarEventService.shared.createEvent(input: eventInput, currentUserId: currentUserId)
            
            // Refresh calendar data
            await dashboardViewModel.refreshCalendarIfNeeded()
            // Clear pending AI follow-ups now that an event was created
            await resolvePendingAIFollowUps()
            
            // Format confirmation message
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            
            var confirmationMessage = "✅ Great! I found an available time slot and created \"\(eventTitle)\" on the calendar.\n\n"
            confirmationMessage += "**Details:**\n"
            confirmationMessage += "• Date: \(dateFormatter.string(from: selectedSlot.startDate))\n"
            
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            confirmationMessage += "• Time: \(timeFormatter.string(from: selectedSlot.startDate))-\(timeFormatter.string(from: selectedSlot.endDate))\n"
            
            if let categoryName = eventPart.categoryName {
                confirmationMessage += "• Category: \(categoryName)\n"
            }
            
            if !attendeeUserIds.isEmpty || !guestNames.isEmpty {
                let allAttendees = attendeeUserIds.compactMap { id in
                    dashboardViewModel.members.first(where: { $0.id == id })?.displayName
                } + guestNames
                confirmationMessage += "• Attendees: \(allAttendees.joined(separator: ", "))\n"
            }
            
            if let location = eventPart.location {
                confirmationMessage += "• Location: \(location)\n"
            }
            
            if let notes = eventPart.notes, !notes.isEmpty {
                confirmationMessage += "• Notes: \(notes)\n"
            }
            
            let confirmationResponse = ChatMessage(role: .assistant, content: confirmationMessage)
            self.messages.append(confirmationResponse)
            
        } catch {
            // If parsing fails, fall back to general question handling
            #if DEBUG
            print("Failed to parse find-and-create query: \(error)")
            #endif
            await handleGeneralQuestion(question: userMessage)
        }
    }
    
    private func handleEventCreationQuery(query: EventCreationQuery) async {
        guard let groupId = dashboardViewModel.selectedGroupID else {
            let response = ChatMessage(
                role: .assistant,
                content: "Please select a group first to create an event. Go to the Groups tab and select a group."
            )
            messages.append(response)
            return
        }
        
        // Get current user ID
        guard let client = SupabaseManager.shared.client else {
            let response = ChatMessage(
                role: .assistant,
                content: "⚠️ Unable to access your account. Please try again."
            )
            messages.append(response)
            return
        }
        
        let currentUserId: UUID
        do {
            let session = try await client.auth.session
            currentUserId = session.user.id
        } catch {
            let response = ChatMessage(
                role: .assistant,
                content: "⚠️ Unable to authenticate. Please try logging in again."
            )
            messages.append(response)
            return
        }
        
        // Parse date and time
        let calendar = Calendar.current
        let now = Date()
        var startDate: Date
        var endDate: Date
        var durationMinutesResolved: Int?
        
        // Parse date
        if let dateString = query.date {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            if let date = dateFormatter.date(from: dateString) {
                startDate = calendar.startOfDay(for: date)
            } else {
                // If parsing fails, default to today
                startDate = calendar.startOfDay(for: now)
            }
        } else {
            // Default to today if no date specified
            startDate = calendar.startOfDay(for: now)
        }
        
        // Parse time and duration
        if query.isAllDay {
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            // Parse time
            if let timeString = query.time {
                let components = timeString.split(separator: ":")
                if components.count == 2,
                   let hour = Int(components[0]),
                   let minute = Int(components[1]) {
                    startDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startDate) ?? startDate
                }
            } else {
                // Default to current time if not specified
                let components = calendar.dateComponents([.hour, .minute], from: now)
                startDate = calendar.date(bySettingHour: components.hour ?? 9, minute: components.minute ?? 0, second: 0, of: startDate) ?? startDate
            }
            
            // Calculate end date based on duration
            let durationMinutes = query.durationMinutes ?? 60 // Default to 1 hour
            durationMinutesResolved = durationMinutes
            endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
        }
        
        // Validate required fields (title). If missing, ask for details using known time window.
        if (query.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = query.isAllDay ? .none : .short
            let startString = dateFormatter.string(from: startDate)
            var details: [String] = ["date/time: \(startString)"]
            if !query.isAllDay {
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                let endString = timeFormatter.string(from: endDate)
                details.append("until \(endString)")
                if let durationMinutesResolved {
                    details.append("duration \(durationMinutesResolved) min")
                }
            }
            if let location = query.location, !location.isEmpty {
                details.append("location \"\(location)\"")
            }
            if !query.attendeeNames.isEmpty || !query.guestNames.isEmpty {
                let names = (query.attendeeNames + query.guestNames).joined(separator: ", ")
                if !names.isEmpty {
                    details.append("attendees: \(names)")
                }
            }
            
            let responseText = """
I can create this event, but I need a title. Here’s what I have so far:
- \(details.joined(separator: "\n- "))

What should I call it? You can also add a location, attendees, or notes if you like.
"""
            let response = ChatMessage(role: .assistant, content: responseText)
            messages.append(response)
            // Track for AI follow-up since the user started an event but hasn't finished
            Task { await recordPendingAIFollowUp(reason: "event_creation_missing_title") }
            return
        }
        
        let title = query.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Map attendee names to user IDs
        let memberMap = getMemberNameToIdMap()
        var attendeeUserIds: [UUID] = []
        var guestNames: [String] = []
        
        for name in query.attendeeNames {
            if let userId = memberMap[name.lowercased()] {
                attendeeUserIds.append(userId)
            } else {
                // Not found in members, treat as guest
                guestNames.append(name)
            }
        }
        guestNames.append(contentsOf: query.guestNames)
        
        // Get category ID if category name is provided
        var categoryId: UUID? = nil
        if let categoryName = query.categoryName, !categoryName.isEmpty {
            do {
                let categories = try await CalendarEventService.shared.fetchCategories(userId: currentUserId, groupId: groupId)
                if let category = categories.first(where: { $0.name.lowercased() == categoryName.lowercased() }) {
                    categoryId = category.id
                }
            } catch {
                // If category lookup fails, continue without category
                #if DEBUG
                print("Failed to fetch categories: \(error)")
                #endif
            }
        }
        
        // Determine event type
        let eventType = query.eventType ?? (attendeeUserIds.isEmpty && guestNames.isEmpty ? "personal" : "group")
        
        // Create the event
        let eventInput = NewEventInput(
            groupId: groupId,
            title: title,
            start: startDate,
            end: endDate,
            isAllDay: query.isAllDay,
            location: query.location,
            notes: query.notes,
            attendeeUserIds: attendeeUserIds,
            guestNames: guestNames,
            originalEventId: nil,
            categoryId: categoryId,
            eventType: eventType
        )
        
        do {
            let eventId = try await CalendarEventService.shared.createEvent(input: eventInput, currentUserId: currentUserId)
            
            // Refresh calendar data
            await dashboardViewModel.refreshCalendarIfNeeded()
            // Clear pending AI follow-ups now that an event was created
            await resolvePendingAIFollowUps()
            
            // Format confirmation message
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = query.isAllDay ? .none : .short
            
            var confirmationMessage = "✅ All set! I've created \"\(title)\" on the calendar.\n\n"
            confirmationMessage += "**Details:**\n"
            confirmationMessage += "• Date: \(dateFormatter.string(from: startDate))\n"
            
            if !query.isAllDay {
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                confirmationMessage += "• Time: \(timeFormatter.string(from: startDate))-\(timeFormatter.string(from: endDate))\n"
            }
            
            if let categoryName = query.categoryName {
                confirmationMessage += "• Category: \(categoryName)\n"
            }
            
            if !attendeeUserIds.isEmpty || !guestNames.isEmpty {
                let allAttendees = attendeeUserIds.compactMap { id in
                    dashboardViewModel.members.first(where: { $0.id == id })?.displayName
                } + guestNames
                confirmationMessage += "• Attendees: \(allAttendees.joined(separator: ", "))\n"
            }
            
            if let location = query.location {
                confirmationMessage += "• Location: \(location)\n"
            }
            
            if let notes = query.notes, !notes.isEmpty {
                confirmationMessage += "• Notes: \(notes)\n"
            }
            
            let response = ChatMessage(role: .assistant, content: confirmationMessage)
            messages.append(response)
        } catch {
            let response = ChatMessage(
                role: .assistant,
                content: "⚠️ I encountered an error while creating the event: \(error.localizedDescription). Please try again."
            )
            messages.append(response)
        }
    }
    
    private func handleGeneralQuestion(question: String) async {
        // Build context for the AI
        let systemPrompt = """
You are Scheduly, a friendly and helpful AI scheduling assistant for the Schedulr app. You help users:
- Understand how to use the app
- Find available times for group meetings
- Schedule events with group members
- Answer questions about calendar syncing

Be concise and friendly in your responses. If asked about availability, remind users they can ask questions like "Find me a date where John, Sarah & Mike are free for 5 hours between 12pm and 5pm".
"""
        
        // Build message history (keep last 10 messages for context)
        var aiMessages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt)
        ]
        
        let recentMessages = messages.suffix(10)
        aiMessages.append(contentsOf: recentMessages)
        
        do {
            let response = try await aiService.chatCompletion(messages: aiMessages)
            let responseMsg = ChatMessage(role: .assistant, content: response)
            messages.append(responseMsg)
        } catch {
            // Show user-friendly error messages
            let errorMessage: String
            if let aiError = error as? AIServiceError {
                errorMessage = aiError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
            
            let responseMsg = ChatMessage(
                role: .assistant,
                content: "⚠️ \(errorMessage)"
            )
            messages.append(responseMsg)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getGroupMembers() -> [(id: UUID, name: String)] {
        return dashboardViewModel.members.map { (id: $0.id, name: $0.displayName) }
    }
    
    private func getMemberNameToIdMap() -> [String: UUID] {
        var map: [String: UUID] = [:]
        for member in dashboardViewModel.members {
            map[member.displayName.lowercased()] = member.id
        }
        return map
    }
    
    private func buildFollowUpOptions(for slots: [FreeTimeSlot], durationHours: Double) -> [FollowUpOption] {
        guard !slots.isEmpty else { return [] }
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        return slots.prefix(3).enumerated().map { index, slot in
            let day = dayFormatter.string(from: slot.startDate)
            let start = timeFormatter.string(from: slot.startDate)
            let end = timeFormatter.string(from: slot.endDate)
            let label = "#\(index + 1) \(day) · \(start)–\(end)"
            let durationText = durationHours > 1 ? String(format: "%.1f", durationHours) : "1"
            let prompt = "Create an event on \(day) from \(start) to \(end) for \(durationText) hour\(durationHours > 1 ? "s" : "")."
            return FollowUpOption(label: label, prompt: prompt)
        }
    }
    
    /// Resolves group name references in availability queries (e.g., "all team members from Work Team")
    /// Returns the resolved query and the group ID to use for the availability check
    private func resolveGroupNameReferences(query: AvailabilityQuery, userMessage: String) async -> (AvailabilityQuery, UUID?) {
        var resolvedQuery = query
        let lowercasedMessage = userMessage.lowercased()
        
        // Check if query mentions "all team members" or "all members"
        let allMembersKeywords = ["all team members", "all members", "everyone", "every team member", "all the team members"]
        let mentionsAllMembers = allMembersKeywords.contains { lowercasedMessage.contains($0) }
        
        // Check if query mentions a specific group name
        var mentionedGroupName: String? = nil
        var mentionedGroupId: UUID? = nil
        for membership in dashboardViewModel.memberships {
            if lowercasedMessage.contains(membership.name.lowercased()) {
                mentionedGroupName = membership.name
                mentionedGroupId = membership.id
                break
            }
        }
        
        var groupIdToUse: UUID? = dashboardViewModel.selectedGroupID
        
        // If "all members" is mentioned
        if mentionsAllMembers {
            // If a specific group is mentioned, fetch members from that group
            if let groupId = mentionedGroupId {
                groupIdToUse = groupId
                // Check if this is the currently selected group
                if dashboardViewModel.selectedGroupID == groupId {
                    // Use current members
                    if !dashboardViewModel.members.isEmpty {
                        resolvedQuery.users = dashboardViewModel.members.map { $0.displayName }
                    }
                } else {
                    // Fetch members from the mentioned group
                    await dashboardViewModel.fetchMembers(for: groupId)
                    // Wait a bit for the fetch to complete
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    // Use the members from that group
                    if !dashboardViewModel.members.isEmpty {
                        resolvedQuery.users = dashboardViewModel.members.map { $0.displayName }
                    }
                }
            } else if dashboardViewModel.selectedGroupID != nil && !dashboardViewModel.members.isEmpty {
                // If no specific group mentioned, use all members from selected group
                resolvedQuery.users = dashboardViewModel.members.map { $0.displayName }
            }
        } else if resolvedQuery.users.isEmpty && dashboardViewModel.selectedGroupID != nil && !dashboardViewModel.members.isEmpty {
            // If no users were parsed but members are available, use all members as fallback
            // This handles cases where the AI didn't parse "all members" correctly
            resolvedQuery.users = dashboardViewModel.members.map { $0.displayName }
        }
        
        return (resolvedQuery, groupIdToUse)
    }
    
    private func addWelcomeMessage() {
        let welcomeMsg = ChatMessage(
            role: .assistant,
            content: "👋 Hi! I'm Scheduly, your AI scheduling assistant! ✨\n\nI can help you:\n• Find free times for group members\n• Answer questions about scheduling\n• Suggest meeting times\n\nTry asking: \"Find me a date where [member names] are free for [duration] hours\""
        )
        messages.append(welcomeMsg)
    }
    
    func clearMessages() {
        messages.removeAll()
        currentConversationId = nil
        addWelcomeMessage()
    }
    
    // MARK: - Conversation Persistence
    
    /// Load all conversations for the current user
    func loadConversations() async {
        guard !isLoadingConversations else { return }
        
        do {
            guard let client = SupabaseManager.shared.client else { return }
            let userId = try await client.auth.session.user.id
            
            isLoadingConversations = true
            defer { isLoadingConversations = false }
            
            conversations = try await persistenceService.fetchConversations(userId: userId)
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to load conversations: \(error)")
            #endif
        }
    }
    
    /// Load a specific conversation and its messages
    func loadConversation(_ conversation: DBAIConversation) async {
        do {
            // Fetch messages for this conversation
            let dbMessages = try await persistenceService.fetchMessages(conversationId: conversation.id)
            
            // Clear current messages and set conversation ID
            messages.removeAll()
            currentConversationId = conversation.id
            
            // Convert DB messages to ChatMessages
            messages = dbMessages.map { $0.toChatMessage() }
            
            // Add welcome message if empty
            if messages.isEmpty {
                addWelcomeMessage()
            }
            
            // Close history sheet
            showConversationHistory = false
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to load conversation: \(error)")
            #endif
            errorMessage = "Failed to load conversation"
        }
    }
    
    /// Start a new conversation (clears current and resets)
    func startNewConversation() {
        clearMessages()
        showConversationHistory = false
    }
    
    /// Delete a conversation
    func deleteConversation(_ conversation: DBAIConversation) async {
        do {
            try await persistenceService.deleteConversation(conversationId: conversation.id)
            
            // Remove from local list
            conversations.removeAll { $0.id == conversation.id }
            
            // If we deleted the current conversation, start fresh
            if currentConversationId == conversation.id {
                clearMessages()
            }
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to delete conversation: \(error)")
            #endif
            errorMessage = "Failed to delete conversation"
        }
    }
    
    /// Save current message to persistence (called after message is added)
    private func persistMessage(_ message: ChatMessage) async {
        // Only persist if we have a conversation
        guard let conversationId = currentConversationId else { return }
        
        do {
            try await persistenceService.saveMessage(conversationId: conversationId, message: message)
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to persist message: \(error)")
            #endif
            // Don't show error to user - persistence failure shouldn't block chat
        }
    }
    
    /// Ensure a conversation exists, creating one if needed
    private func ensureConversation(firstMessage: String) async -> UUID? {
        // Already have a conversation
        if let conversationId = currentConversationId {
            return conversationId
        }
        
        do {
            guard let client = SupabaseManager.shared.client else { return nil }
            let userId = try await client.auth.session.user.id
            
            // Generate title from first message
            let title = persistenceService.generateTitle(from: firstMessage)
            
            // Create new conversation
            let conversation = try await persistenceService.createConversation(userId: userId, title: title)
            currentConversationId = conversation.id
            
            // Add to local list
            conversations.insert(conversation, at: 0)
            
            return conversation.id
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to create conversation: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - AI Follow-up Tracking
    
    /// Record a pending AI follow-up for engagement nudges (e.g., availability provided but no event yet).
    private func recordPendingAIFollowUp(reason: String, expiresInHours: Double = 24) async {
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
                let draft_payload: [String: String]?
            }
            
            let row = InsertRow(
                user_id: userId,
                conversation_id: currentConversationId,
                expires_at: expiresAt,
                reason: reason,
                draft_payload: draftPayloadForCurrentContext(reason: reason)
            )
            
            _ = try await client
                .database
                .from("ai_followups")
                .insert(row)
                .execute()
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to record AI follow-up: \(error)")
            #endif
        }
    }
    
    /// Resolve any pending AI follow-ups for the current user (e.g., after an event is created).
    private func resolvePendingAIFollowUps() async {
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
                .is("resolved_at", value: nil)
                .execute()
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to resolve AI follow-ups: \(error)")
            #endif
        }
    }
    
    /// Resolve a specific follow-up by id (used when loading/resuming a draft).
    private func resolveSpecificAIFollowUp(id: UUID) async {
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
            print("[AIAssistantViewModel] Failed to resolve specific follow-up: \(error)")
            #endif
        }
    }
    
    /// Load the most recent, not-expired, unresolved follow-up draft and prefill input for quick resume.
    private func loadDraftIfAvailable() async {
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
            }
            
            let rows: [Row] = try await client.database
                .from("ai_followups")
                .select("id,draft_payload,expires_at,resolved_at,sent_at")
                .eq("user_id", value: userId)
                .is("resolved_at", value: nil)
                .gt("expires_at", value: now)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            
            guard let row = rows.first,
                  let payload = row.draft_payload,
                  let prompt = payload["prompt"] else { return }
            
            await MainActor.run {
                availableDraftPrompt = prompt
            }
            availableDraftFollowupId = row.id
        } catch {
            #if DEBUG
            print("[AIAssistantViewModel] Failed to load draft follow-up: \(error)")
            #endif
        }
    }
    
    /// Build a simple draft payload to allow resuming.
    private func draftPayloadForCurrentContext(reason: String) -> [String: String]? {
        switch reason {
        case "availability_slots_found":
            if let firstFollowUp = messages.last?.followUpOptions.first?.prompt {
                return ["prompt": firstFollowUp]
            }
            return nil
        case "event_creation_missing_title":
            // Suggest a prompt to finish creating the event
            return ["prompt": "Add a title and create the event I just outlined."]
        default:
            return nil
        }
    }
    
    // MARK: - Draft resume controls
    func resumeAvailableDraft() {
        guard let prompt = availableDraftPrompt, let id = availableDraftFollowupId else { return }
        inputText = prompt
        activeDraftFollowupId = id
        availableDraftPrompt = nil
        availableDraftFollowupId = nil
    }
    
    func discardAvailableDraft() {
        guard let id = availableDraftFollowupId else { return }
        Task {
            await resolveSpecificAIFollowUp(id: id)
            await MainActor.run {
                availableDraftPrompt = nil
                availableDraftFollowupId = nil
            }
        }
    }
}

