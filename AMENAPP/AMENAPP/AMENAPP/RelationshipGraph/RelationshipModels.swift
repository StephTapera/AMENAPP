import Foundation
import FirebaseFirestore

// MARK: - Age Band

enum AgeBand: String, Codable, CaseIterable {
    case under13 = "under13"
    case teen = "13-17"
    case adult = "18+"

    var isMinor: Bool { self != .adult }
}

// MARK: - Church

struct Church: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var locationLat: Double
    var locationLng: Double
    var denomination: String?
    var ownerUids: [String]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, locationLat, locationLng, denomination, ownerUids, createdAt
    }
}

// MARK: - Group

struct AmenGroup: Codable, Identifiable {
    @DocumentID var id: String?
    var churchId: String?
    var name: String
    var type: GroupType
    var hostUids: [String]
    var memberUids: [String]
    var visibility: GroupVisibility
    var studyPassage: String?
    var createdAt: Date

    enum GroupType: String, Codable, CaseIterable {
        case smallGroup = "small_group"
        case ministry
        case study

        var displayName: String {
            switch self {
            case .smallGroup: return "Small Group"
            case .ministry: return "Ministry Team"
            case .study: return "Study Group"
            }
        }

        var systemImage: String {
            switch self {
            case .smallGroup: return "person.3"
            case .ministry: return "building.columns"
            case .study: return "book.pages"
            }
        }
    }

    enum GroupVisibility: String, Codable, CaseIterable {
        case `public`, `private`, invite

        var displayName: String {
            switch self {
            case .public: return "Public"
            case .private: return "Private"
            case .invite: return "Invite Only"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, churchId, name, type, hostUids, memberUids, visibility, studyPassage, createdAt
    }
}

// MARK: - Membership

struct Membership: Codable, Identifiable {
    @DocumentID var id: String?
    var uid: String
    var groupId: String
    var role: Role
    var joinedAt: Date

    enum Role: String, Codable {
        case host, member
    }

    enum CodingKeys: String, CodingKey {
        case id, uid, groupId, role, joinedAt
    }
}

// MARK: - Discipleship Pair
// This pair type unlocks a sacred DM channel — only between two adults (see ChannelService).

struct DiscipleshipPair: Codable, Identifiable {
    @DocumentID var id: String?
    var uids: [String]       // exactly 2, sorted lexicographically
    var status: Status
    var initiatedBy: String
    var createdAt: Date

    enum Status: String, Codable, CaseIterable {
        case pending, active, ended
    }

    enum CodingKeys: String, CodingKey {
        case id, uids, status, initiatedBy, createdAt
    }

    func contains(uid: String) -> Bool { uids.contains(uid) }
    func partnerUid(for uid: String) -> String? { uids.first { $0 != uid } }
}
