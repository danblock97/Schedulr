//
//  AIChatPersistenceService.swift
//  Schedulr
//
//  Created by Daniel Block on 04/12/2025.
//

import Foundation
import Supabase

/// Service for persisting AI chat conversations to Supabase
final class AIChatPersistenceService {
    static let shared = AIChatPersistenceService()
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    private init() {}
    
    // MARK: - Conversation Operations
    
    /// Create a new conversation
    func createConversation(userId: UUID, title: String = "New Chat") async throws -> DBAIConversation {
        guard let client else {
            throw AIChatPersistenceError.clientUnavailable
        }
        
        let insert = DBAIConversationInsert(user_id: userId, title: title)
        
        let conversations: [DBAIConversation] = try await client.database
            .from("ai_conversations")
            .insert(insert)
            .select()
            .execute()
            .value
        
        guard let conversation = conversations.first else {
            throw AIChatPersistenceError.createFailed
        }
        
        return conversation
    }
    
    /// Fetch all conversations for a user, ordered by most recent
    func fetchConversations(userId: UUID) async throws -> [DBAIConversation] {
        guard let client else {
            throw AIChatPersistenceError.clientUnavailable
        }
        
        let conversations: [DBAIConversation] = try await client.database
            .from("ai_conversations")
            .select()
            .eq("user_id", value: userId)
            .order("updated_at", ascending: false)
            .execute()
            .value
        
        return conversations
    }
    
    /// Update conversation title
    func updateConversationTitle(conversationId: UUID, title: String) async throws {
        guard let client else {
            throw AIChatPersistenceError.clientUnavailable
        }
        
        _ = try await client.database
            .from("ai_conversations")
            .update(DBAIConversationUpdate(title: title, updated_at: Date()))
            .eq("id", value: conversationId)
            .execute()
    }
    
    /// Delete a conversation (messages cascade automatically)
    func deleteConversation(conversationId: UUID) async throws {
        guard let client else {
            throw AIChatPersistenceError.clientUnavailable
        }
        
        _ = try await client.database
            .from("ai_conversations")
            .delete()
            .eq("id", value: conversationId)
            .execute()
    }
    
    // MARK: - Message Operations
    
    /// Save a message to a conversation
    func saveMessage(conversationId: UUID, message: ChatMessage) async throws {
        guard let client else {
            throw AIChatPersistenceError.clientUnavailable
        }
        
        // Don't persist system messages
        guard message.role != .system else { return }
        
        let insert = DBAIMessageInsert(
            conversation_id: conversationId,
            role: message.role.rawValue,
            content: message.content
        )
        
        _ = try await client.database
            .from("ai_messages")
            .insert(insert)
            .execute()
    }
    
    /// Fetch all messages for a conversation, ordered chronologically
    func fetchMessages(conversationId: UUID) async throws -> [DBAIMessage] {
        guard let client else {
            throw AIChatPersistenceError.clientUnavailable
        }
        
        let messages: [DBAIMessage] = try await client.database
            .from("ai_messages")
            .select()
            .eq("conversation_id", value: conversationId)
            .order("timestamp", ascending: true)
            .execute()
            .value
        
        return messages
    }
    
    // MARK: - Helper Methods
    
    /// Generate a title from the first user message
    func generateTitle(from message: String) -> String {
        let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedMessage.count <= 50 {
            return cleanedMessage
        }
        // Truncate at word boundary
        let truncated = String(cleanedMessage.prefix(50))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
}

// MARK: - Errors

enum AIChatPersistenceError: LocalizedError {
    case clientUnavailable
    case createFailed
    case saveFailed
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .clientUnavailable:
            return "Database service unavailable"
        case .createFailed:
            return "Failed to create conversation"
        case .saveFailed:
            return "Failed to save message"
        case .fetchFailed:
            return "Failed to fetch data"
        }
    }
}
