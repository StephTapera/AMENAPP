import Foundation
import FirebaseFirestore

// MARK: - Prayer Request
// First-class Firestore entity extracted from communal channel messages by Berean.
// Opt-in per group. Author can mark answered; Berean follows up at followUpAt.

struct ChannelPrayerRequest: Codable, Identifiable {
    @DocumentID var id: String?
    var groupId: String
    var authorUid: String
    var text: String
    var createdAt: Date
    var status: PrayerStatus
    var followUpAt: Date?       // push nudge sent at this time asking the author for an update
    var channelId: String
    var sourceMessageId: String

    enum CodingKeys: String, CodingKey {
        case id, groupId, authorUid, text, createdAt, status, followUpAt, channelId, sourceMessageId
    }
}

enum PrayerStatus: String, Codable {
    case open, answered
}

// MARK: - Prayer Request Offer
// Transient — shown to the sender in the composer; never stored.

struct PrayerRequestOffer {
    let message: CommunalMessage
    let groupId: String
    let suggestedText: String   // Berean's cleaned version of the prayer need
}
