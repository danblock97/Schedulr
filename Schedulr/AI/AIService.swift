//
//  AIService.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation

enum AIServiceError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Please add your API key in the configuration file."
        case .invalidResponse:
            return "Received an invalid response from OpenAI API."
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

final class AIService {
    static let shared = AIService()
    
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-5-nano-2025-08-07"
    
    private var apiKey: String? {
        SupabaseManager.shared.configuration?.openAIAPIKey
    }
    
    private init() {}
    
    // MARK: - Chat Completion
    
    /// Sends a chat completion request to OpenAI
    /// - Parameters:
    ///   - messages: Array of chat messages (including system, user, and assistant messages)
    ///   - temperature: Sampling temperature (optional, defaults to 1.0 for GPT-5 nano)
    /// - Returns: The assistant's response message
    func chatCompletion(messages: [ChatMessage], temperature: Double? = nil) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        // Convert ChatMessage to OpenAIMessage
        let openAIMessages = messages.map { msg in
            OpenAIMessage(role: msg.role.rawValue, content: msg.content)
        }
        
        let request = OpenAIRequest(
            model: model,
            messages: openAIMessages,
            temperature: temperature, // nil will use API default (1.0 for GPT-5 nano)
            stream: false
        )
        
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    let errorMessage = errorResponse.error?.message ?? "Unknown API error"
                    
                    // Provide more helpful messages for common errors
                    var userFriendlyMessage = errorMessage
                    if errorMessage.localizedCaseInsensitiveContains("quota") || 
                       errorMessage.localizedCaseInsensitiveContains("exceeded") ||
                       errorMessage.localizedCaseInsensitiveContains("insufficient_quota") {
                        userFriendlyMessage = "Your OpenAI API quota has been exceeded. Please add payment information to your OpenAI account at https://platform.openai.com/account/billing to continue using Scheduly."
                    } else if errorMessage.localizedCaseInsensitiveContains("invalid_api_key") {
                        userFriendlyMessage = "Invalid OpenAI API key. Please check your API key in Xcode Build Settings."
                    }
                    
                    throw AIServiceError.apiError(userFriendlyMessage)
                }
                throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
            }
            
            let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let content = apiResponse.choices?.first?.message?.content else {
                throw AIServiceError.invalidResponse
            }
            
            return content
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
    
    // MARK: - Query Parsing
    
    /// Uses AI to parse a natural language query and determine if it's an availability query or event creation query
    /// - Parameter query: The user's natural language query
    /// - Returns: A structured query (AvailabilityQuery or EventCreationQuery)
    func parseQuery(_ query: String, groupMembers: [(id: UUID, name: String)], groupName: String?) async throws -> Any {
        // Check if query asks "what times work?" or similar availability questions first
        // This takes priority over event creation keywords
        let lowercasedQuery = query.lowercased()
        let availabilityQuestionKeywords = ["what times work", "when are", "when can", "find times", "available times", "what times are", "when would"]
        let isAvailabilityQuestion = availabilityQuestionKeywords.contains { lowercasedQuery.contains($0) }
        
        if isAvailabilityQuestion {
            return try await parseAvailabilityQuery(query, groupMembers: groupMembers)
        }
        
        // Then check if it's an event creation query
        let eventKeywords = ["create", "schedule", "add", "set up", "plan", "book", "make"]
        let isEventCreation = eventKeywords.contains { lowercasedQuery.contains($0) }
        
        if isEventCreation {
            return try await parseEventCreationQuery(query, groupMembers: groupMembers, groupName: groupName)
        } else {
            return try await parseAvailabilityQuery(query, groupMembers: groupMembers)
        }
    }
    
    /// Uses AI to parse a natural language query into a structured EventCreationQuery
    /// - Parameter query: The user's natural language query
    /// - Returns: A structured EventCreationQuery
    func parseEventCreationQuery(_ query: String, groupMembers: [(id: UUID, name: String)], groupName: String?) async throws -> EventCreationQuery {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        let membersList = groupMembers.map { "\($0.name) (ID: \($0.id.uuidString))" }.joined(separator: ", ")
        let groupNameText = groupName ?? "current group"
        
        let systemPrompt = """
You are Scheduly, a friendly AI scheduling assistant. Parse event creation queries into structured JSON format.

Available group members: \(membersList)
Current group name: \(groupNameText)
Today's date: \(ISO8601DateFormatter().string(from: Date()).prefix(10))

Extract from the user's query:
1. Event title
2. Date (in ISO 8601 format YYYY-MM-DD, e.g., "tomorrow" becomes tomorrow's date, "next Friday" becomes that date)
3. Time in 24-hour format HH:mm (e.g., "10 AM" becomes "10:00", "2:30 PM" becomes "14:30")
4. Duration in minutes (e.g., "30 minutes", "1 hour", "2 hours")
5. Location (if mentioned)
6. Notes/description (if mentioned)
7. Group name (if different from current)
8. Attendee names (match to available members)
9. Guest names (names not in member list)
10. Category name (if mentioned like "Meetings", "Personal Development", etc.)
11. Event type: "personal" or "group" (default to "group" if attendees are mentioned, "personal" otherwise)

Return ONLY valid JSON in this exact format:
{
  "type": "createEvent",
  "title": "Event Title",
  "date": "2025-11-03",
  "time": "10:00",
  "durationMinutes": 30,
  "isAllDay": false,
  "location": "Location if mentioned",
  "notes": "Notes if mentioned",
  "groupName": "Group name if different",
  "attendeeNames": ["Member Name 1", "Member Name 2"],
  "guestNames": ["Guest Name"],
  "categoryName": "Category Name",
  "eventType": "group"
}

Omit fields that are not mentioned or can't be determined. If the query is not about creating an event, return {"type": "general"}.
"""
        
        let messages = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: query)
        ]
        
        let response = try await chatCompletion(messages: messages)
        
        // Extract JSON from response
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIServiceError.invalidResponse
        }
        
        do {
            let query = try JSONDecoder().decode(EventCreationQuery.self, from: jsonData)
            return query
        } catch {
            #if DEBUG
            print("Failed to parse AI response as EventCreationQuery: \(error)")
            print("Response was: \(response)")
            #endif
            throw AIServiceError.invalidResponse
        }
    }
    
    /// Uses AI to parse a natural language query into a structured AvailabilityQuery
    /// - Parameter query: The user's natural language query
    /// - Returns: A structured AvailabilityQuery
    func parseAvailabilityQuery(_ query: String, groupMembers: [(id: UUID, name: String)], groupNames: [(id: UUID, name: String)] = []) async throws -> AvailabilityQuery {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        // Build a system prompt that instructs the AI to parse the query
        let membersList = groupMembers.map { "\($0.name) (ID: \($0.id.uuidString))" }.joined(separator: ", ")
        let groupsList = groupNames.isEmpty ? "" : "\nAvailable groups: \(groupNames.map { "\($0.name) (ID: \($0.id.uuidString))" }.joined(separator: ", "))"
        
        let calendar = Calendar.current
        let today = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let todayString = formatter.string(from: today)
        
        // Calculate next week dates
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7 // Convert to Monday = 0, Sunday = 6
        let daysToAddToNextMonday = 7 - daysFromMonday + 1 // Days until next Monday, then add 1 week
        let nextWeekStart = calendar.date(byAdding: .day, value: daysToAddToNextMonday, to: today) ?? today
        let nextWeekEnd = calendar.date(byAdding: .day, value: 6, to: nextWeekStart) ?? today
        let nextWeekStartString = formatter.string(from: nextWeekStart)
        let nextWeekEndString = formatter.string(from: nextWeekEnd)
        
        let systemPrompt = """
You are Scheduly, a friendly AI scheduling assistant for the Schedulr app. Parse scheduling queries into structured JSON format.

Available group members: \(membersList)\(groupsList)
Today's date: \(todayString)
Next week dates: \(nextWeekStartString) to \(nextWeekEndString)

Parse the user's query and extract:
1. User names mentioned (match them to the available members list)
   - If query says "all team members" or "all members" from a group, include ALL members from the members list
   - If query mentions a group name, include ALL members from that group (you'll see group names in the query, match them)
   - Match user names exactly as they appear in the members list (case-insensitive matching)
2. Duration in hours (e.g., "2 hours" = 2.0, "1 hour" = 1.0, "30 minutes" = 0.5)
3. Time window in 24-hour format HH:mm (if mentioned, e.g., "12pm-5pm" becomes "12:00-17:00")
4. Date range in ISO 8601 format YYYY-MM-DD
   - "next week" = \(nextWeekStartString) to \(nextWeekEndString)
   - If specific days mentioned (e.g., "Tuesday, Wednesday, Thursday"), calculate those dates within the date range
   - Default to next 30 days if no date range mentioned

IMPORTANT: If the query mentions days of the week (Monday, Tuesday, etc.) or "preferably" specific days:
- Calculate the actual dates for those days within the specified date range
- If "next week" + "Tuesday, Wednesday, Thursday" → calculate next week's Tue, Wed, Thu dates
- Include those specific dates in the dateRange, or note them in the response

Return ONLY valid JSON in this exact format (no markdown, no code blocks, just raw JSON):
{
  "type": "availability",
  "users": ["User1", "User2"],
  "durationHours": 2.0,
  "timeWindow": {
    "start": "09:00",
    "end": "17:00"
  },
  "dateRange": {
    "start": "2025-11-03",
    "end": "2025-11-10"
  }
}

CRITICAL RULES:
- If "all team members" or "all members" is mentioned, include ALL members from the members list
- Match user/group names exactly (case-insensitive)
- If a field is not mentioned, omit it from the JSON
- Always return valid JSON, never return text explanations
- If the query is not about availability, return {"type": "general"}
"""
        
        let messages = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: query)
        ]
        
        // Don't pass temperature - let API use default (1.0 for GPT-5 nano)
        let response = try await chatCompletion(messages: messages)
        
        // Extract JSON from response (might have markdown code blocks)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        
        // Remove any leading/trailing whitespace
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            // Fallback: return a query with type general
            return AvailabilityQuery(type: .general)
        }
        
        do {
            let query = try JSONDecoder().decode(AvailabilityQuery.self, from: jsonData)
            return query
        } catch {
            #if DEBUG
            print("Failed to parse AI response as JSON: \(error)")
            print("Response was: \(response)")
            print("JSON string was: \(jsonString)")
            #endif
            
            // Try to extract JSON from text if it's wrapped in explanation
            if let jsonStart = jsonString.range(of: "{"),
               let jsonEnd = jsonString.range(of: "}", options: .backwards),
               jsonStart.lowerBound < jsonString.endIndex,
               jsonEnd.upperBound <= jsonString.endIndex,
               jsonStart.lowerBound < jsonEnd.upperBound {
                // Safely extract the substring including the closing brace
                // jsonEnd.upperBound is already after the '}', so we use it directly
                let endIndex = jsonEnd.upperBound
                let extractedJSON = String(jsonString[jsonStart.lowerBound..<endIndex])
                if let extractedData = extractedJSON.data(using: .utf8),
                   let extractedQuery = try? JSONDecoder().decode(AvailabilityQuery.self, from: extractedData) {
                    return extractedQuery
                }
            }
            
            // Fallback: try keyword-based parsing
            return parseQueryFallback(query: query, groupMembers: groupMembers)
        }
    }
    
    // MARK: - Fallback Parsing
    
    private func parseQueryFallback(query: String, groupMembers: [(id: UUID, name: String)]) -> AvailabilityQuery {
        var availabilityQuery = AvailabilityQuery()
        let lowercasedQuery = query.lowercased()
        
        // Check if it's an availability query
        let availabilityKeywords = ["free", "available", "schedule", "find", "when", "can", "time"]
        let isAvailabilityQuery = availabilityKeywords.contains { lowercasedQuery.contains($0) }
        
        if !isAvailabilityQuery {
            availabilityQuery.type = .general
            return availabilityQuery
        }
        
        availabilityQuery.type = .availability
        
        // Extract user names (simple keyword matching)
        for member in groupMembers {
            if lowercasedQuery.contains(member.name.lowercased()) {
                availabilityQuery.users.append(member.name)
            }
        }
        
        // Extract duration (look for patterns like "5 hours", "2h", etc.)
        let durationPattern = #"(\d+(?:\.\d+)?)\s*(?:hours?|h|hrs?)"#
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range(at: 1), in: query),
           let duration = Double(query[range]) {
            availabilityQuery.durationHours = duration
        }
        
        // Extract time window (look for patterns like "12pm-5pm", "between 12 and 5", etc.)
        // This is a simplified parser - the AI version is more robust
        let timePattern = #"(\d{1,2})\s*(?:pm|am|:)\s*(?:and|-|to)\s*(\d{1,2})\s*(?:pm|am)"#
        // For now, we'll rely on the AI parsing
        
        return availabilityQuery
    }
}

