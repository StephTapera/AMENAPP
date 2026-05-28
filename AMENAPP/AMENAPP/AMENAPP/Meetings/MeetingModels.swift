import Foundation
import FirebaseFirestore

// MARK: - Meeting
// Generalises the existing "Get Ready" church-attendance feature.
// A meeting is any gathering attached to a group from the RelationshipGraph.

struct Meeting: Codable, Identifiable {
    @DocumentID var id: String?
    var groupId: String
    var hostUids: [String]
    var title: String
    var startAt: Date
    var locationLat: Double?
    var locationLng: Double?
    var locationName: String?
    var studyPassage: String?           // verse ref; pulls from KJV store via Berean
    var agendaBlocks: [AgendaBlock]     // reuses Smart Church Notes block model concept
    var status: MeetingStatus
    var rsvps: [MeetingRSVP]

    enum CodingKeys: String, CodingKey {
        case id, groupId, hostUids, title, startAt
        case locationLat, locationLng, locationName
        case studyPassage, agendaBlocks, status, rsvps
    }
}

enum MeetingStatus: String, Codable, CaseIterable {
    case scheduled, live, ended
}

// MARK: - RSVP

struct MeetingRSVP: Codable, Equatable {
    var uid: String
    var status: MeetingRSVPStatus
    var updatedAt: Date
}

enum MeetingRSVPStatus: String, Codable, CaseIterable {
    case going, notGoing, maybe

    var displayLabel: String {
        switch self {
        case .going: return "Going"
        case .notGoing: return "Can't Make It"
        case .maybe: return "Maybe"
        }
    }

    var systemImage: String {
        switch self {
        case .going: return "checkmark.circle.fill"
        case .notGoing: return "xmark.circle"
        case .maybe: return "questionmark.circle"
        }
    }
}

// MARK: - Agenda Block (mirrors Smart Church Notes block types)

struct AgendaBlock: Codable, Identifiable {
    var id: String
    var type: AgendaBlockType
    var content: String
    var order: Int
}

enum AgendaBlockType: String, Codable, CaseIterable {
    case heading
    case text
    case verse
    case prayerPoint = "prayer_point"
    case discussion

    var systemImage: String {
        switch self {
        case .heading: return "textformat"
        case .text: return "text.alignleft"
        case .verse: return "book.pages"
        case .prayerPoint: return "hands.sparkles"
        case .discussion: return "bubble.left.and.bubble.right"
        }
    }
}
