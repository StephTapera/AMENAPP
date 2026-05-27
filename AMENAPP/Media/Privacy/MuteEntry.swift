import Foundation
import FirebaseFirestore

// MARK: - MuteTargetType

enum MuteTargetType: String, CaseIterable, Codable {
    case user
    case topic
}

// MARK: - MuteEntry

/// A single mute record owned by a user. Stored at /mutes/{userId}/entries/{id}.
/// `expiresAt == nil` means indefinite (user must manually unmute).
struct MuteEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String           // the user who is muting
    var mutedUserId: String?     // nil if muting a topic
    var mutedTopic: String?      // nil if muting a user
    var expiresAt: Date?         // nil = indefinite
    var createdAt: Date

    init(
        userId: String,
        mutedUserId: String? = nil,
        mutedTopic: String? = nil,
        expiresAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.userId = userId
        self.mutedUserId = mutedUserId
        self.mutedTopic = mutedTopic
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    /// Returns `true` while the mute is still in effect.
    var isActive: Bool { expiresAt.map { $0 > .now } ?? true }
}
