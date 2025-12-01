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
    
    private let aiService = AIService.shared
    private let calendarAnalysisService = CalendarAnalysisService.shared
    private let dashboardViewModel: DashboardViewModel
    private let calendarManager: CalendarSyncManager
    
    init(dashboardViewModel: DashboardViewModel, calendarManager: CalendarSyncManager) {
        self.dashboardViewModel = dashboardViewModel
        self.calendarManager = calendarManager
        
        // Add welcome message if no messages exist
        if messages.isEmpty {
            addWelcomeMessage()
        }
    }
    
    // MARK: - Message Handling
    
    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Clear input immediately
        inputText = ""
        errorMessage = nil
        
        // Add user message
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)
        
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
            // This takes priority even if "schedule" is mentioned
            let availabilityQuestionKeywords = ["what times work", "when are", "when can", "find times", "available times", "what times are", "when would", "times work"]
            let isAvailabilityQuestion = availabilityQuestionKeywords.contains { lowercasedQuery.contains($0) }
            
            // PRIORITY 2: Check if this is a combined query (find slots then create event)
            let combinedKeywords = ["after finding", "after you find", "find a free slot", "find a time when", "find when"]
            let hasFindKeyword = combinedKeywords.contains { lowercasedQuery.contains($0) }
            let hasCreateKeyword = ["create", "schedule", "add", "set up", "plan", "book", "make"].contains { lowercasedQuery.contains($0) }
            let isCombinedQuery = hasFindKeyword && hasCreateKeyword && !isAvailabilityQuestion
            
            if isAvailabilityQuestion {
                // Handle as availability query (even if "schedule" is mentioned)
                let groupNames = dashboardViewModel.memberships.map { (id: $0.id, name: $0.name) }
                let availabilityQuery = try await aiService.parseAvailabilityQuery(userMessage, groupMembers: getGroupMembers(), groupNames: groupNames)
                
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
                    await handleAvailabilityQuery(query: finalQuery, groupId: groupIdToUse)
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
                let isEventCreation = eventKeywords.contains { lowercasedQuery.contains($0) }
                
                if isEventCreation {
                    // Event creation requires a selected group
                    guard let groupId = dashboardViewModel.selectedGroupID else {
                        let response = ChatMessage(
                            role: .assistant,
                            content: "Please select a group first to create an event. Go to the Groups tab and select a group."
                        )
                        messages.append(response)
                        return
                    }
                    
                    let selectedGroupName = dashboardViewModel.memberships.first(where: { $0.id == groupId })?.name
                    let eventQuery = try await aiService.parseEventCreationQuery(
                        userMessage,
                        groupMembers: getGroupMembers(),
                        groupName: selectedGroupName
                    )
                    await handleEventCreationQuery(query: eventQuery)
                } else {
                    // Check if query is about availability
                    // Get available group names for better parsing
                    let groupNames = dashboardViewModel.memberships.map { (id: $0.id, name: $0.name) }
                    let availabilityQuery = try await aiService.parseAvailabilityQuery(userMessage, groupMembers: getGroupMembers(), groupNames: groupNames)
                    
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
                        await handleAvailabilityQuery(query: finalQuery, groupId: groupIdToUse)
                    } else {
                        // Handle general question
                        await handleGeneralQuestion(question: userMessage)
                    }
                }
            }
            
            // Track AI usage after successful request
            await AIUsageTracker.shared.trackRequest()
            
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
        }
    }
    
    // MARK: - Query Handling
    
    private func handleAvailabilityQuery(query: AvailabilityQuery, groupId: UUID? = nil) async {
        let groupIdToUse = groupId ?? dashboardViewModel.selectedGroupID
        guard let groupId = groupIdToUse else {
            let response = ChatMessage(
                role: .assistant,
                content: "Please select a group first to check member availability. Go to the Groups tab and select a group."
            )
            messages.append(response)
            return
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
            return
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
                
                let response = ChatMessage(role: .assistant, content: responseText)
                messages.append(response)
            }
        } catch {
            let response = ChatMessage(
                role: .assistant,
                content: "I encountered an error while checking availability: \(error.localizedDescription). Please try again."
            )
            messages.append(response)
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
        
        // Validate required fields
        guard let title = query.title, !title.isEmpty else {
            let response = ChatMessage(
                role: .assistant,
                content: "I couldn't determine the event title from your request. Please specify what event you'd like to create."
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
            endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
        }
        
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
        addWelcomeMessage()
    }
}

