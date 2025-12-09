//
//  AIModels.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation

// MARK: - Chat Message Models

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var followUpOptions: [FollowUpOption]
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        followUpOptions: [FollowUpOption] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.followUpOptions = followUpOptions
    }
    
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, followUpOptions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        followUpOptions = try container.decodeIfPresent([FollowUpOption].self, forKey: .followUpOptions) ?? []
    }
}

struct FollowUpOption: Identifiable, Equatable, Codable {
    let id: UUID
    let label: String
    let prompt: String
    
    init(id: UUID = UUID(), label: String, prompt: String) {
        self.id = id
        self.label = label
        self.prompt = prompt
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Query Models

enum QueryType: String, Codable {
    case availability
    case createEvent
    case findAndCreate
    case general
    case listEvents
    case unknown
}

struct AvailabilityQuery: Codable, Equatable {
    var type: QueryType = .availability
    var users: [String] = []
    var durationHours: Double?
    var timeWindow: TimeWindow?
    var dateRange: DateRange?
    
    struct TimeWindow: Codable, Equatable {
        var start: String // HH:mm format (24-hour)
        var end: String   // HH:mm format (24-hour)
    }
    
    struct DateRange: Codable, Equatable {
        var start: String // ISO 8601 date string
        var end: String   // ISO 8601 date string
    }
    
    // Custom decoder to handle missing keys with default values
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(QueryType.self, forKey: .type) ?? .availability
        users = try container.decodeIfPresent([String].self, forKey: .users) ?? []
        durationHours = try container.decodeIfPresent(Double.self, forKey: .durationHours)
        timeWindow = try container.decodeIfPresent(TimeWindow.self, forKey: .timeWindow)
        dateRange = try container.decodeIfPresent(DateRange.self, forKey: .dateRange)
    }
    
    init(type: QueryType = .availability, users: [String] = [], durationHours: Double? = nil, timeWindow: TimeWindow? = nil, dateRange: DateRange? = nil) {
        self.type = type
        self.users = users
        self.durationHours = durationHours
        self.timeWindow = timeWindow
        self.dateRange = dateRange
    }
}

struct EventCreationQuery: Codable, Equatable {
    var type: QueryType = .createEvent
    var title: String?
    var date: String? // ISO 8601 date string (YYYY-MM-DD)
    var time: String? // HH:mm format (24-hour)
    var durationMinutes: Int? // Duration in minutes
    var isAllDay: Bool = false
    var location: String?
    var notes: String?
    var groupName: String?
    var attendeeNames: [String] = []
    var guestNames: [String] = []
    var categoryName: String?
    var eventType: String? // "personal" or "group", defaults to "group" if attendees
    
    // Custom decoder to handle missing keys with default values
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(QueryType.self, forKey: .type) ?? .createEvent
        title = try container.decodeIfPresent(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        attendeeNames = try container.decodeIfPresent([String].self, forKey: .attendeeNames) ?? []
        guestNames = try container.decodeIfPresent([String].self, forKey: .guestNames) ?? []
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
    }
    
    init(type: QueryType = .createEvent, title: String? = nil, date: String? = nil, time: String? = nil, durationMinutes: Int? = nil, isAllDay: Bool = false, location: String? = nil, notes: String? = nil, groupName: String? = nil, attendeeNames: [String] = [], guestNames: [String] = [], categoryName: String? = nil, eventType: String? = nil) {
        self.type = type
        self.title = title
        self.date = date
        self.time = time
        self.durationMinutes = durationMinutes
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.groupName = groupName
        self.attendeeNames = attendeeNames
        self.guestNames = guestNames
        self.categoryName = categoryName
        self.eventType = eventType
    }
}

// MARK: - Free Time Slot Models

struct FreeTimeSlot: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let durationHours: Double
    let confidence: Double // 0.0 to 1.0
    let availableUsers: [UUID] // User IDs who are available
    
    init(id: UUID = UUID(), startDate: Date, endDate: Date, durationHours: Double, confidence: Double, availableUsers: [UUID]) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.durationHours = durationHours
        self.confidence = confidence
        self.availableUsers = availableUsers
    }
}

// MARK: - OpenAI API Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let stream: Bool?
    
    init(model: String = "gpt-5-nano-2025-08-07", messages: [OpenAIMessage], temperature: Double? = nil, stream: Bool = false) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.stream = stream
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [OpenAIChoice]?
    let usage: OpenAIUsage?
    
    struct OpenAIChoice: Codable {
        let index: Int?
        let message: OpenAIMessage?
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
    
    struct OpenAIUsage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIError?
    
    struct OpenAIError: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}

// MARK: - Database Models for AI Chat Persistence

struct DBAIConversation: Codable, Identifiable, Equatable {
    let id: UUID
    let user_id: UUID
    let title: String
    let created_at: Date?
    let updated_at: Date?
}

struct DBAIConversationInsert: Encodable {
    let user_id: UUID
    let title: String
}

struct DBAIConversationUpdate: Encodable {
    let title: String?
    let updated_at: Date?
}

struct DBAIMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let conversation_id: UUID
    let role: String
    let content: String
    let timestamp: Date?
    
    /// Convert to in-memory ChatMessage
    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: id,
            role: MessageRole(rawValue: role) ?? .assistant,
            content: content,
            timestamp: timestamp ?? Date()
        )
    }
}

struct DBAIMessageInsert: Encodable {
    let conversation_id: UUID
    let role: String
    let content: String
}
