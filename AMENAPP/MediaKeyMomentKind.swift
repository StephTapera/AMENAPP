import Foundation

enum MediaKeyMomentKind: String, Codable, CaseIterable, Hashable {
    case verse
    case keyPoint
    case worship
    case highlight
    case intro
    case closing
    case mainPoint

    var title: String {
        switch self {
        case .verse:      return "Verse"
        case .keyPoint:   return "Key Point"
        case .worship:    return "Worship"
        case .highlight:  return "Highlight"
        case .intro:      return "Intro"
        case .closing:    return "Closing"
        case .mainPoint:  return "Main Point"
        }
    }
}

struct MediaKeyMoment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let timestamp: TimeInterval
    let label: String
    let kind: MediaKeyMomentKind
    let source: String?
    let sortOrder: Int?

    init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval,
        label: String,
        kind: MediaKeyMomentKind,
        source: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.kind = kind
        self.source = source
        self.sortOrder = sortOrder
    }

    var timestampLabel: String {
        let total = max(Int(timestamp.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var isPubliclyApproved: Bool { true }

    static func fallbackMoments(for duration: TimeInterval) -> [MediaKeyMoment] {
        let count = min(max(Int(duration / 15), 2), 4)
        let interval = duration / Double(count)
        let kinds: [MediaKeyMomentKind] = [.verse, .keyPoint, .worship, .highlight]
        let labels = ["Introduction", "Key Point", "Scripture", "Closing"]
        return (0..<count).map { index in
            MediaKeyMoment(
                timestamp: Double(index) * interval + interval * 0.25,
                label: labels[min(index, labels.count - 1)],
                kind: kinds[index % kinds.count],
                source: "generated",
                sortOrder: index
            )
        }
    }
}
