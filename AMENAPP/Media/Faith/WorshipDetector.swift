import Foundation

struct WorshipDetector {
    private static let worshipKeywords: Set<String> = [
        "worship", "praise", "hymn", "gospel", "christian music",
        "contemporary worship", "ccm", "hillsong", "elevation worship",
        "bethel", "chris tomlin", "david crowder", "spontaneous worship",
        "devotional", "adoration", "sanctuary"
    ]

    private static let contentTypeKeywords: Set<String> = [
        "worship", "music", "song", "hymnal", "praise", "anthem",
        "spiritual song", "gospel music"
    ]

    static func isWorship(tags: [String]) -> Bool {
        let lowercasedTags = tags.map { $0.lowercased() }
        return lowercasedTags.contains { tag in
            worshipKeywords.contains(where: { tag.contains($0) })
        }
    }

    static func isWorship(contentType: String) -> Bool {
        let lower = contentType.lowercased()
        return contentTypeKeywords.contains(where: { lower.contains($0) })
    }
}
