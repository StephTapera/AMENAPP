import SwiftUI

struct TestimonyCategory: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let backgroundColor: Color

    var semanticKeys: Set<String> {
        Self.semanticAliases[id, default: [id]]
    }

    static let healing = TestimonyCategory(
        id: "healing",
        title: "Healing",
        subtitle: "Physical and emotional restoration",
        icon: "heart.fill",
        color: Color(red: 0.93, green: 0.26, blue: 0.32),
        backgroundColor: Color(red: 0.93, green: 0.26, blue: 0.32).opacity(0.12)
    )

    static let career = TestimonyCategory(
        id: "career",
        title: "Career",
        subtitle: "Work, calling, and purpose",
        icon: "briefcase.fill",
        color: Color(red: 0.20, green: 0.47, blue: 0.93),
        backgroundColor: Color(red: 0.20, green: 0.47, blue: 0.93).opacity(0.12)
    )

    static let relationship = TestimonyCategory(
        id: "relationship",
        title: "Relationship",
        subtitle: "Family, friendship, and community",
        icon: "person.2.fill",
        color: Color(red: 0.97, green: 0.52, blue: 0.18),
        backgroundColor: Color(red: 0.97, green: 0.52, blue: 0.18).opacity(0.12)
    )

    static let financial = TestimonyCategory(
        id: "financial",
        title: "Financial",
        subtitle: "Provision, breakthrough, and blessing",
        icon: "dollarsign.circle.fill",
        color: Color(red: 0.20, green: 0.74, blue: 0.34),
        backgroundColor: Color(red: 0.20, green: 0.74, blue: 0.34).opacity(0.12)
    )

    static let spiritual = TestimonyCategory(
        id: "spiritual",
        title: "Spiritual",
        subtitle: "Faith, prayer, and transformation",
        icon: "sparkles",
        color: Color(red: 0.55, green: 0.27, blue: 0.90),
        backgroundColor: Color(red: 0.55, green: 0.27, blue: 0.90).opacity(0.12)
    )

    static let family = TestimonyCategory(
        id: "family",
        title: "Family",
        subtitle: "Marriage, parenting, and home",
        icon: "house.fill",
        color: Color(red: 0.90, green: 0.46, blue: 0.13),
        backgroundColor: Color(red: 0.90, green: 0.46, blue: 0.13).opacity(0.12)
    )

    static let all: [TestimonyCategory] = [
        .healing,
        .career,
        .relationship,
        .financial,
        .spiritual,
        .family
    ]

    private static let semanticAliases: [String: Set<String>] = [
        "healing": ["healing", "health", "restoration", "recovery"],
        "career": ["career", "work", "calling", "purpose", "job"],
        "relationship": ["relationship", "relationships", "friendship", "marriage", "community"],
        "financial": ["financial", "finance", "provision", "money", "breakthrough"],
        "spiritual": ["spiritual", "spiritual growth", "faith", "prayer", "transformation"],
        "family": ["family", "home", "parenting", "children"]
    ]

    static func category(for post: Post) -> TestimonyCategory? {
        let keys = semanticTopicKeys(for: post)
        return all.first { category in
            !category.semanticKeys.isDisjoint(with: keys)
        }
    }

    static func semanticTopicKeys(for post: Post) -> Set<String> {
        var keys = Set<String>()

        if let primaryTopicKey = post.primaryTopicKey {
            keys.insert(normalized(primaryTopicKey))
        }

        post.normalizedTopicKeys?.forEach {
            keys.insert(normalized($0))
        }

        if let topicTag = post.topicTag {
            keys.insert(normalized(topicTag))
        }

        return keys
    }

    func matches(_ post: Post) -> Bool {
        !semanticKeys.isDisjoint(with: Self.semanticTopicKeys(for: post))
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
