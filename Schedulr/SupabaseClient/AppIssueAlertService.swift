import Foundation
import SwiftUI
import Supabase

struct AppIssueAlertDTO: Decodable, Sendable {
    let id: UUID
    let key: String
    let title: String
    let message: String
    let isActive: Bool
    let presentation: String
    let severity: String
    let ctaLabel: String?
    let ctaURL: String?
    let ctaAction: String?
    let startsAt: Date?
    let endsAt: Date?
    let revision: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case title
        case message
        case isActive = "is_active"
        case presentation
        case severity
        case ctaLabel = "cta_label"
        case ctaURL = "cta_url"
        case ctaAction = "cta_action"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case revision
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        presentation = try container.decode(String.self, forKey: .presentation)
        severity = try container.decode(String.self, forKey: .severity)
        ctaLabel = try container.decodeIfPresent(String.self, forKey: .ctaLabel)
        ctaURL = try container.decodeIfPresent(String.self, forKey: .ctaURL)
        ctaAction = try container.decodeIfPresent(String.self, forKey: .ctaAction)
        startsAt = try Self.decodeDateIfPresent(container, key: .startsAt)
        endsAt = try Self.decodeDateIfPresent(container, key: .endsAt)
        revision = try container.decode(Int.self, forKey: .revision)
        createdAt = try Self.decodeRequiredDate(container, key: .createdAt)
        updatedAt = try Self.decodeRequiredDate(container, key: .updatedAt)
    }

    private static func decodeDateIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return try parseDate(raw)
    }

    private static func decodeRequiredDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date {
        let raw = try container.decode(String.self, forKey: key)
        return try parseDate(raw)
    }

    private static func parseDate(_ raw: String) throws -> Date {
        if let date = ISO8601DateFormatter.appIssueAlertDateFormatter.date(from: raw) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Invalid ISO8601 date: \(raw)")
        )
    }
}

private extension ISO8601DateFormatter {
    static let appIssueAlertDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct AppIssueAlert: Identifiable, Equatable, Sendable {
    enum CTAAction: String, Sendable {
        case url
        case moreInfo = "more_info"
    }

    enum Presentation: String, Sendable {
        case banner
        case modal
    }

    enum Severity: String, Sendable {
        case info
        case warning
        case critical

        var priority: Int {
            switch self {
            case .critical: return 3
            case .warning: return 2
            case .info: return 1
            }
        }
    }

    let id: UUID
    let key: String
    let title: String
    let message: String
    let isActive: Bool
    let presentation: Presentation
    let severity: Severity
    let ctaLabel: String?
    let ctaURL: URL?
    let ctaAction: CTAAction?
    let startsAt: Date?
    let endsAt: Date?
    let revision: Int
    let createdAt: Date
    let updatedAt: Date

    var displayInstanceKey: String {
        "\(key).r\(revision)"
    }

    init?(dto: AppIssueAlertDTO) {
        guard let presentation = Presentation(rawValue: dto.presentation.lowercased()) else { return nil }
        guard let severity = Severity(rawValue: dto.severity.lowercased()) else { return nil }

        let sanitizedCTALabel = dto.ctaLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCTAURL = dto.ctaURL.flatMap(URL.init(string:))
        let parsedCTAAction = dto.ctaAction.flatMap { CTAAction(rawValue: $0.lowercased()) }
        let resolvedCTAAction: CTAAction? = {
            if let parsedCTAAction { return parsedCTAAction }
            if parsedCTAURL != nil, sanitizedCTALabel?.isEmpty == false { return .url }
            return nil
        }()

        let finalCTALabel: String?
        let finalCTAURL: URL?
        switch resolvedCTAAction {
        case .url:
            finalCTALabel = (sanitizedCTALabel?.isEmpty == false && parsedCTAURL != nil) ? sanitizedCTALabel : nil
            finalCTAURL = finalCTALabel == nil ? nil : parsedCTAURL
        case .moreInfo:
            finalCTALabel = sanitizedCTALabel?.isEmpty == false ? sanitizedCTALabel : nil
            finalCTAURL = nil
        case nil:
            finalCTALabel = nil
            finalCTAURL = nil
        }

        self.id = dto.id
        self.key = dto.key
        self.title = dto.title
        self.message = dto.message
        self.isActive = dto.isActive
        self.presentation = presentation
        self.severity = severity
        self.ctaLabel = finalCTALabel
        self.ctaURL = finalCTAURL
        self.ctaAction = finalCTALabel == nil ? nil : resolvedCTAAction
        self.startsAt = dto.startsAt
        self.endsAt = dto.endsAt
        self.revision = dto.revision
        self.createdAt = dto.createdAt
        self.updatedAt = dto.updatedAt
    }
}

enum AppIssueAlertStore {
    static func makeSeenKey(userId: UUID, alertKey: String, revision: Int) -> String {
        "SchedulrIssueAlertSeen.\(userId.uuidString).\(alertKey).r\(revision)"
    }

    static func hasSeen(alert: AppIssueAlert, userId: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: makeSeenKey(userId: userId, alertKey: alert.key, revision: alert.revision))
    }

    static func markSeen(alert: AppIssueAlert, userId: UUID, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: makeSeenKey(userId: userId, alertKey: alert.key, revision: alert.revision))
    }
}

@MainActor
final class AppIssueAlertService: ObservableObject {
    @Published private(set) var currentAlert: AppIssueAlert?

    private var alerts: [AppIssueAlert] = []
    private var currentUserId: UUID?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var isStarting = false

    private var client: SupabaseClient? { SupabaseManager.shared.client }

    deinit {
        realtimeTask?.cancel()
    }

    func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        guard let client else { return }
        guard let userId = try? await client.auth.session.user.id else {
            await stop()
            return
        }

        if currentUserId != userId {
            await stop()
            currentUserId = userId
        }

        await refreshAlerts()

        if realtimeChannel == nil {
            await subscribeToRealtime(using: client)
        }
    }

    func stop() async {
        realtimeTask?.cancel()
        realtimeTask = nil

        if let channel = realtimeChannel, let client {
            await client.removeChannel(channel)
        }

        realtimeChannel = nil
        alerts = []
        currentAlert = nil
        currentUserId = nil
    }

    func dismissCurrentAlert() {
        currentAlert = nil
    }

    static func isEligible(_ alert: AppIssueAlert, now: Date) -> Bool {
        guard alert.presentation == .banner else { return false }
        guard alert.isActive else { return false }
        if let startsAt = alert.startsAt, now < startsAt { return false }
        if let endsAt = alert.endsAt, now > endsAt { return false }
        return true
    }

    static func selectNextVisibleAlert(
        from alerts: [AppIssueAlert],
        now: Date = Date(),
        hasSeen: (AppIssueAlert) -> Bool
    ) -> AppIssueAlert? {
        alerts
            .filter { isEligible($0, now: now) }
            .sorted {
                if $0.severity.priority != $1.severity.priority {
                    return $0.severity.priority > $1.severity.priority
                }
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.createdAt > $1.createdAt
            }
            .first(where: { !hasSeen($0) })
    }

    private func refreshAlerts() async {
        guard let client else { return }
        do {
            let rows: [AppIssueAlertDTO] = try await client
                .from("app_issue_alerts")
                .select()
                .execute()
                .value

            alerts = rows.compactMap(AppIssueAlert.init(dto:))
            reevaluateCurrentAlert()
        } catch {
            #if DEBUG
            print("[AppIssueAlertService] Failed to fetch alerts: \(error)")
            #endif
            alerts = []
            currentAlert = nil
        }
    }

    private func subscribeToRealtime(using client: SupabaseClient) async {
        // Use a unique topic to avoid reusing an already-joined channel if start() races.
        let channel = client.channel("public:app_issue_alerts:\(UUID().uuidString)")
        realtimeChannel = channel

        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "app_issue_alerts")
        do {
            try await channel.subscribeWithError()
        } catch {
            #if DEBUG
            print("[AppIssueAlertService] Failed to subscribe to realtime: \(error)")
            #endif
            if self.realtimeChannel === channel {
                self.realtimeChannel = nil
            }
            return
        }
        realtimeTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { break }
                await self.refreshAlerts()
            }
        }
    }

    private func reevaluateCurrentAlert(now: Date = Date()) {
        guard let currentUserId else {
            currentAlert = nil
            return
        }

        let next = Self.selectNextVisibleAlert(from: alerts, now: now) { alert in
            AppIssueAlertStore.hasSeen(alert: alert, userId: currentUserId)
        }

        if let next, next.displayInstanceKey != currentAlert?.displayInstanceKey {
            AppIssueAlertStore.markSeen(alert: next, userId: currentUserId)
        }

        currentAlert = next
    }
}
