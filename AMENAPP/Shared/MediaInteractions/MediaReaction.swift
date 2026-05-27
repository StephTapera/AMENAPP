import Foundation
import FirebaseFirestore

// Distinct from `PostReaction` (post-level flat emoji) — this model supports
// the richer media reaction surface: notes, prayer timers, and custom emoji.
enum MediaReactionType: String, Codable, CaseIterable {
    case heart, laugh, prayer, fire, cross, custom
}

struct MediaReaction: Identifiable, Codable, MediaInteraction {
    @DocumentID var id: String?
    var mediaId: String
    var userId: String
    var type: MediaReactionType
    /// Non-nil only when type == .custom; an emoji character the user picked.
    var emoji: String?
    /// Private one-line note paired with the reaction (sent as a DM on the server).
    var note: String?
    /// When set the prayer reaction expires after this date (24 h from creation).
    var prayerExpiresAt: Date?
    var createdAt: Date

    init(
        id: String? = nil,
        mediaId: String,
        userId: String,
        type: MediaReactionType,
        emoji: String? = nil,
        note: String? = nil,
        prayerExpiresAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.mediaId = mediaId
        self.userId = userId
        self.type = type
        self.emoji = emoji
        self.note = note
        self.prayerExpiresAt = prayerExpiresAt
        self.createdAt = createdAt
    }
}
