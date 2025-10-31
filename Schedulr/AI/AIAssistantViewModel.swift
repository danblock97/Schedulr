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
        
        do {
            // Check if query is about availability
            let query = try await aiService.parseAvailabilityQuery(userMessage, groupMembers: getGroupMembers())
            
            if query.type == .availability && !query.users.isEmpty {
                // Handle availability query
                await handleAvailabilityQuery(query: query)
            } else {
                // Handle general question
                await handleGeneralQuestion(question: userMessage)
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
        }
        
        isLoading = false
    }
    
    // MARK: - Query Handling
    
    private func handleAvailabilityQuery(query: AvailabilityQuery) async {
        guard let groupId = dashboardViewModel.selectedGroupID else {
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

