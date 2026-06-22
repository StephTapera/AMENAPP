import Foundation
import FirebaseFirestore

// MARK: - Object Discussion Room
// A live room spawned from any canonical object (song, sermon, verse, study, etc.).
// Stored at: objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}

struct ObjectDiscussionRoom: Identifiable, Codable {
    @DocumentID var id: String?
    let canonicalObjectId: String
    let canonicalObjectTitle: String
    let roomType: ObjectDiscussionRoomType
    var participantCount: Int
    var messageCount: Int
    var lastMessage: String?
    var lastMessageAt: Timestamp?
    let createdBy: String
    let createdAt: Timestamp
    var updatedAt: Timestamp

    enum ObjectDiscussionRoomType: String, Codable, CaseIterable {
        case discussion  = "discussion"
        case prayer      = "prayer"
        case studyGroup  = "study_group"

        var displayName: String {
            switch self {
            case .discussion: return "Discussion"
            case .prayer:     return "Prayer Room"
            case .studyGroup: return "Study Group"
            }
        }

        var icon: String {
            switch self {
            case .discussion: return "bubble.left.and.bubble.right.fill"
            case .prayer:     return "hands.sparkles.fill"
            case .studyGroup: return "book.fill"
            }
        }

        var spawnLabel: String {
            switch self {
            case .discussion: return "Start Discussion"
            case .prayer:     return "Open Prayer Room"
            case .studyGroup: return "Start Study Group"
            }
        }

        var accentColorName: String {
            switch self {
            case .discussion: return "blue"
            case .prayer:     return "purple"
            case .studyGroup: return "green"
            }
        }
    }
}

// MARK: - Object Discussion Message

struct ObjectDiscussionMessage: Identifiable, Codable {
    @DocumentID var id: String?
    let canonicalObjectId: String
    let roomId: String
    let authorId: String
    let authorDisplayName: String
    let authorAvatarURL: String?
    let body: String
    var reactions: [String: Int]
    var isDeleted: Bool
    let createdAt: Timestamp
}

// MARK: - Object Affordance
// Matches the build-pack Affordance contract.
// Represents what live community a canonical object can spawn or join.

struct ObjectAffordance: Identifiable {
    let id: String
    let kind: Kind
    let roomId: String?      // nil → spawnable (no room exists yet)
    let spawnable: Bool
    let participantCount: Int
    let label: String

    enum Kind: String {
        case discussion     = "discussion"
        case prayerRoom     = "prayer_room"
        case studyGroup     = "study_group"
        case membersPresent = "members_present"
        case liveNow        = "live_now"
    }

    var isLive: Bool { participantCount > 0 }

    var accessibilityLabel: String {
        let countText = participantCount > 0
            ? ", \(participantCount) \(participantCount == 1 ? "person" : "people") inside"
            : ""
        return spawnable
            ? "\(label). Tap to start\(countText)."
            : "\(label)\(countText). Tap to join."
    }
}

// MARK: - Presence Member

struct DiscussionPresenceMember: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let displayName: String
    let joinedAt: Timestamp?
}
