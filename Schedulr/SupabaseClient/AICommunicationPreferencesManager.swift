import Foundation
import Supabase

enum AICommunicationPreferencesValidationError: LocalizedError {
    case tooManyTraits
    case noteTooLong
    case containsBlockedInstruction
    case unsupportedCharacters

    var errorDescription: String? {
        switch self {
        case .tooManyTraits:
            return "Choose up to \(AICommunicationPreferences.maxPersonalityTraits) personality traits."
        case .noteTooLong:
            return "Keep the custom style note under \(AICommunicationPreferences.maxCustomNoteLength) characters."
        case .containsBlockedInstruction:
            return "Custom style notes can only describe tone, formality, and communication style."
        case .unsupportedCharacters:
            return "Custom style notes can only use standard letters, numbers, spaces, and basic punctuation."
        }
    }
}

final class AICommunicationPreferencesManager {
    static let shared = AICommunicationPreferencesManager()

    private init() {}

    private var client: SupabaseClient? { SupabaseManager.shared.client }

    private let blockedPatterns: [String] = [
        "ignore previous",
        "ignore all previous",
        "override",
        "system prompt",
        "developer prompt",
        "reveal prompt",
        "hidden instructions",
        "bypass",
        "content filter",
        "safety policy",
        "moderation",
        "jailbreak",
        "adversarial",
        "exploit",
        "tool call",
        "function call",
        "role:",
        "system:",
        "assistant:",
        "developer:"
    ]

    private let allowedNotePattern = #"^[A-Za-z0-9\s,\.\!\?'"\/&\(\)\-:;]+$"#

    func load(for userId: UUID) async throws -> AICommunicationPreferences {
        guard let client else {
            throw NSError(
                domain: "AICommunicationPrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }

        struct Row: Decodable {
            let user_id: UUID
            let ai_communication_preferences: AICommunicationPreferences?
        }

        let rows: [Row] = try await client
            .from("user_settings")
            .select("user_id, ai_communication_preferences")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        return rows.first?.ai_communication_preferences?.normalized ?? .default
    }

    func save(_ preferences: AICommunicationPreferences, for userId: UUID) async throws {
        guard let client else {
            throw NSError(
                domain: "AICommunicationPrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }

        let validatedPreferences = try validate(preferences)

        struct UpsertRow: Encodable {
            let user_id: UUID
            let ai_communication_preferences: AICommunicationPreferences
        }

        let row = UpsertRow(
            user_id: userId,
            ai_communication_preferences: validatedPreferences
        )

        _ = try await client
            .from("user_settings")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    func clear(for userId: UUID) async throws {
        guard let client else {
            throw NSError(
                domain: "AICommunicationPrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }

        struct ClearRow: Encodable {
            let user_id: UUID
            let ai_communication_preferences: AICommunicationPreferences?
        }

        _ = try await client
            .from("user_settings")
            .upsert(ClearRow(user_id: userId, ai_communication_preferences: nil), onConflict: "user_id")
            .execute()
    }

    func validate(_ preferences: AICommunicationPreferences) throws -> AICommunicationPreferences {
        let normalized = preferences.normalized

        if normalized.personalityTraits.count > AICommunicationPreferences.maxPersonalityTraits {
            throw AICommunicationPreferencesValidationError.tooManyTraits
        }

        if let customNote = normalized.customNote {
            if customNote.count > AICommunicationPreferences.maxCustomNoteLength {
                throw AICommunicationPreferencesValidationError.noteTooLong
            }

            if customNote.range(of: allowedNotePattern, options: .regularExpression) == nil {
                throw AICommunicationPreferencesValidationError.unsupportedCharacters
            }

            let lowered = customNote.lowercased()
            if blockedPatterns.contains(where: { lowered.contains($0) }) {
                throw AICommunicationPreferencesValidationError.containsBlockedInstruction
            }
        }

        return normalized
    }
}
