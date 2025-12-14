import Foundation
import Supabase

@MainActor
final class SupportTicketViewModel: ObservableObject {
    enum Priority: String, CaseIterable, Identifiable {
        case none
        case urgent
        case high
        case medium
        case low
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .none: return "No priority"
            case .urgent: return "Urgent"
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            }
        }
    }
    
    struct CreatedIssue: Equatable {
        let issueId: String
        let identifier: String?
        let url: URL?
    }
    
    enum TicketType {
        case bug
        case featureRequest
        
        var title: String {
            switch self {
            case .bug: return "Report a Bug"
            case .featureRequest: return "Request a Feature"
            }
        }
        
        var descriptionPlaceholder: String {
            switch self {
            case .bug: return "Describe what happened, what you expected, and steps to reproduce..."
            case .featureRequest: return "Describe the feature you'd like to see and why it would be useful..."
            }
        }
        
        var labels: [String] {
            switch self {
            case .bug: return ["Bug"]
            case .featureRequest: return ["Feature"]
            }
        }
    }
    
    @Published var ticketType: TicketType = .bug
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var priority: Priority = .none
    
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String?
    @Published var createdIssue: CreatedIssue?
    
    private var supabaseURL: URL? {
        SupabaseManager.shared.configuration?.url
    }
    
    private var functionName: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SUPPORT_TICKETS_FUNCTION_NAME") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw! : "create-linear-issue"
    }
    
    func submit() async {
        errorMessage = nil
        createdIssue = nil
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Please enter a title."
            return
        }
        
        guard let supabaseURL else {
            errorMessage = "Unable to determine server configuration."
            return
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let accessToken = session.accessToken
            
            var url = supabaseURL
            url.appendPathComponent("functions")
            url.appendPathComponent("v1")
            url.appendPathComponent(functionName)
            
            struct Payload: Encodable {
                let title: String
                let description: String
                let priority: String
                let labels: [String]
            }
            
            let payload = Payload(
                title: trimmedTitle,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                priority: priority.rawValue,
                labels: ticketType.labels
            )
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "SupportTicket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                struct SuccessResponse: Decodable {
                    let issueId: String
                    let identifier: String?
                    let url: String?
                }
                let decoded = try JSONDecoder().decode(SuccessResponse.self, from: data)
                createdIssue = CreatedIssue(
                    issueId: decoded.issueId,
                    identifier: decoded.identifier,
                    url: decoded.url.flatMap(URL.init(string:))
                )
            } else {
                struct ErrorResponse: Decodable { let error: String? }
                let decoded = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                throw NSError(domain: "SupportTicket", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: decoded ?? "Failed to create ticket"])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


