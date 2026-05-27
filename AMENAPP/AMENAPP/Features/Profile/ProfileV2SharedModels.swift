import Foundation

// MARK: - LinkType (inlined — LinkType.swift not added to project target)

public enum LinkType: String, Codable, CaseIterable, Hashable {
    case church, giving, book, podcast, sermon, website, social, other

    public var systemImage: String {
        switch self {
        case .church:  return "building.columns.fill"
        case .giving:  return "heart.fill"
        case .book:    return "book.closed.fill"
        case .podcast: return "mic.fill"
        case .sermon:  return "waveform"
        case .website: return "globe"
        case .social:  return "person.2.fill"
        case .other:   return "link"
        }
    }

    public var defaultLabel: String {
        switch self {
        case .church:  return "My Church"
        case .giving:  return "Give"
        case .book:    return "Read the Book"
        case .podcast: return "Podcast"
        case .sermon:  return "Sermon Series"
        case .website: return "Website"
        case .social:  return "Social"
        case .other:   return "Link"
        }
    }

    public var displayName: String {
        switch self {
        case .church:  return "Church"
        case .giving:  return "Giving"
        case .book:    return "Book"
        case .podcast: return "Podcast"
        case .sermon:  return "Sermon"
        case .website: return "Website"
        case .social:  return "Social"
        case .other:   return "Other"
        }
    }
}

// MARK: - LinkSlot (inlined — LinkSlot.swift not added to project target)

public struct LinkSlot: Identifiable, Codable, Hashable {
    public let id: String
    public var type: LinkType
    public var url: URL
    public var label: String
    public var order: Int

    public init(
        id: String = UUID().uuidString,
        type: LinkType,
        url: URL,
        label: String,
        order: Int
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.label = label
        self.order = order
    }

    public init?(firestoreData data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let typeRaw = data["type"] as? String,
            let type = LinkType(rawValue: typeRaw),
            let urlString = data["url"] as? String,
            let url = URL(string: urlString),
            let label = data["label"] as? String,
            let order = data["order"] as? Int
        else { return nil }
        self.id = id
        self.type = type
        self.url = url
        self.label = label
        self.order = order
    }

    public var firestoreData: [String: Any] {
        ["id": id, "type": type.rawValue, "url": url.absoluteString, "label": label, "order": order]
    }
}

// MARK: - Profile Role Flags

public struct ProfileRoleFlags: Codable, Hashable {
    public var isMentor: Bool
    public var isCreator: Bool
    public var isMinistryLeader: Bool
    public var isChurchAccount: Bool
    public var churchId: String?

    public init(
        isMentor: Bool = false,
        isCreator: Bool = false,
        isMinistryLeader: Bool = false,
        isChurchAccount: Bool = false,
        churchId: String? = nil
    ) {
        self.isMentor = isMentor
        self.isCreator = isCreator
        self.isMinistryLeader = isMinistryLeader
        self.isChurchAccount = isChurchAccount
        self.churchId = churchId
    }

    public static let empty = ProfileRoleFlags()
}

// MARK: - Profile Metrics

public struct ProfileMetrics: Codable, Hashable {
    public var peopleDiscipled: Int
    public var versesShared: Int
    public var yearsWalkingWithChrist: Int?
    public var testimoniesGiven: Int
    public var prayersOffered: Int

    public init(
        peopleDiscipled: Int = 0,
        versesShared: Int = 0,
        yearsWalkingWithChrist: Int? = nil,
        testimoniesGiven: Int = 0,
        prayersOffered: Int = 0
    ) {
        self.peopleDiscipled = peopleDiscipled
        self.versesShared = versesShared
        self.yearsWalkingWithChrist = yearsWalkingWithChrist
        self.testimoniesGiven = testimoniesGiven
        self.prayersOffered = prayersOffered
    }

    public static let empty = ProfileMetrics()
}

// MARK: - Pro Role Enum

public enum ProRole: String, CaseIterable {
    case mentor
    case creator
    case ministryLeader
    case church

    public var priority: Int {
        switch self {
        case .mentor: return 10
        case .creator: return 20
        case .ministryLeader: return 30
        case .church: return 40
        }
    }
}

// MARK: - Profile Header Payload

/// Returned by the getProfileHeaderPayload Cloud Function.
public struct ProfileHeaderPayload {
    public var userId: String
    public var links: [LinkSlot]
    public var pinSlotIds: [String]
    public var roleFlags: ProfileRoleFlags
    public var profileMetrics: ProfileMetrics
    public var bereanAboutOptIn: Bool
    public var hasGivingEnabled: Bool
    public var hasSubscriptionEnabled: Bool
    public var visitChurchURL: URL?

    public init(
        userId: String,
        links: [LinkSlot] = [],
        pinSlotIds: [String] = [],
        roleFlags: ProfileRoleFlags = .empty,
        profileMetrics: ProfileMetrics = .empty,
        bereanAboutOptIn: Bool = false,
        hasGivingEnabled: Bool = false,
        hasSubscriptionEnabled: Bool = false,
        visitChurchURL: URL? = nil
    ) {
        self.userId = userId
        self.links = links
        self.pinSlotIds = pinSlotIds
        self.roleFlags = roleFlags
        self.profileMetrics = profileMetrics
        self.bereanAboutOptIn = bereanAboutOptIn
        self.hasGivingEnabled = hasGivingEnabled
        self.hasSubscriptionEnabled = hasSubscriptionEnabled
        self.visitChurchURL = visitChurchURL
    }
}
