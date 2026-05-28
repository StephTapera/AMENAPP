import Foundation

struct AmenThreadPresence: Identifiable, Codable, Equatable {
    var id: String { uid }
    var uid: String
    var state: AmenPresenceState
    var label: String
    var visibility: AmenPresenceVisibility
    var updatedAt: Date
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

enum AmenPresenceVisibility: String, Codable, CaseIterable {
    case `private`
    case members
    case groups
    case everyone
}
