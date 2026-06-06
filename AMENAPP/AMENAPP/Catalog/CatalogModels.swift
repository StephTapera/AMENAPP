import Foundation
import FirebaseFirestore

// MARK: - WorkType

enum WorkType: String, CaseIterable, Codable {
    case book, album, track, podcast, episode, video, sermon, article, course, event

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .book:    return "book"
        case .album:   return "music.note"
        case .track:   return "music.note.list"
        case .podcast: return "mic"
        case .episode: return "waveform"
        case .video:   return "play.rectangle"
        case .sermon:  return "cross"
        case .article: return "doc.text"
        case .course:  return "graduationcap"
        case .event:   return "calendar"
        }
    }
}

// MARK: - WorkVisibility

enum WorkVisibility: String, Codable {
    case `public`, followers, paid_members, organization, `private`
}

// MARK: - WorkReviewState

enum WorkReviewState: String, Codable {
    case imported, draft, review, approved, published
}

// MARK: - WorkLink

struct WorkLink: Codable, Identifiable {
    let id = UUID()
    let kind: String
    let platform: String
    let url: String
    let affiliateUrl: String?

    enum CodingKeys: String, CodingKey {
        case kind, platform, url, affiliateUrl
    }
}

// MARK: - CatalogWork

struct CatalogWork: Identifiable {
    let id: String
    let creatorId: String
    let type: WorkType
    let title: String
    let subtitle: String?
    let description: String?
    let coverUrl: String?
    let publishedAt: Date?
    let links: [WorkLink]
    let topics: [String]
    let visibility: WorkVisibility
    let reviewState: WorkReviewState
    let verifiedOwnership: Bool
    let createdAt: Date

    init?(document: DocumentSnapshot) {
        guard
            let data = document.data(),
            let creatorId = data["creatorId"] as? String,
            let typeRaw = data["type"] as? String,
            let type = WorkType(rawValue: typeRaw),
            let title = data["title"] as? String
        else { return nil }

        self.id = document.documentID
        self.creatorId = creatorId
        self.type = type
        self.title = title
        self.subtitle = data["subtitle"] as? String
        self.description = data["description"] as? String
        self.coverUrl = data["coverUrl"] as? String
        self.publishedAt = (data["publishedAt"] as? Timestamp)?.dateValue()
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.topics = data["topics"] as? [String] ?? []
        self.verifiedOwnership = data["verifiedOwnership"] as? Bool ?? false

        let visRaw = data["visibility"] as? String ?? ""
        self.visibility = WorkVisibility(rawValue: visRaw) ?? .public

        let stateRaw = data["reviewState"] as? String ?? ""
        self.reviewState = WorkReviewState(rawValue: stateRaw) ?? .draft

        let linksRaw = data["links"] as? [[String: Any]] ?? []
        self.links = linksRaw.compactMap { dict -> WorkLink? in
            guard
                let kind = dict["kind"] as? String,
                let platform = dict["platform"] as? String,
                let url = dict["url"] as? String
            else { return nil }
            return WorkLink(kind: kind, platform: platform, url: url, affiliateUrl: dict["affiliateUrl"] as? String)
        }
    }
}

// MARK: - CatalogUIState

enum CatalogUIState {
    case loading
    case empty
    case syncing
    case populated([CatalogWork])
    case error(String)
    case locked
}

// MARK: - AskCreatorResult

struct AskCreatorResult {
    let answer: String
    let citations: [CatalogCitation]
    let mode: String
    let confidence: Double
    let refused: Bool
}

// MARK: - CatalogCitation

struct CatalogCitation: Identifiable {
    let id = UUID()
    let workId: String
    let snippet: String
    let sourceUrl: String
    let confidence: Double
}

// MARK: - CatalogTab

struct CatalogTab: Identifiable {
    let id = UUID()
    let type: WorkType?
    let count: Int

    var displayName: String { type?.displayName ?? "All" }
    var icon: String { type?.icon ?? "square.grid.2x2" }
}

// MARK: - KnowledgeNode

struct KnowledgeNode: Identifiable {
    let id: String
    let creatorId: String
    let topic: String
    let workCount: Int
    let workRefs: [String]

    init?(document: DocumentSnapshot) {
        guard
            let data = document.data(),
            let creatorId = data["creatorId"] as? String,
            let topic = data["topic"] as? String
        else { return nil }

        self.id = document.documentID
        self.creatorId = creatorId
        self.topic = topic
        self.workCount = data["workCount"] as? Int ?? 0
        self.workRefs = data["workRefs"] as? [String] ?? []
    }
}
