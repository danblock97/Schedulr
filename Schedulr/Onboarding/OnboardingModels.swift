import Foundation

struct DBUser: Codable, Identifiable, Equatable {
    let id: UUID
    var display_name: String?
    var avatar_url: String?
    var created_at: Date?
    var updated_at: Date?
}

struct DBUserUpdate: Encodable {
    var display_name: String?
    var avatar_url: String?
}

struct DBGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var invite_slug: String
    var created_by: UUID
    var created_at: Date?
}

struct DBGroupInsert: Encodable {
    var name: String
    var created_by: UUID
}

struct DBGroupMember: Codable, Equatable {
    var group_id: UUID
    var user_id: UUID
    var role: String?
    var joined_at: Date?
}
