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
    
    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
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
    case general
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

