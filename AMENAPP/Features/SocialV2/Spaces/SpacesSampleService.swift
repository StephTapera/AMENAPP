import Foundation

struct SpacesSpacePreview: Identifiable, Hashable {
    let space: SocialV2Space
    let memberCountLabel: String
    let moderationDecision: SocialV2ModerationDecision
    let highlightedTopics: [String]

    var id: SocialV2Identifier { space.id }

    var isReadable: Bool {
        moderationDecision.isReadable
    }
}

struct SpacesSampleService: SocialV2SpacesServicing {
    func discoverSpaces(for userID: SocialV2Identifier) async throws -> [SocialV2Space] {
        Self.previews.map(\.space)
    }

    func moderationDecision(forPostID postID: SocialV2Identifier) async throws -> SocialV2ModerationDecision {
        Self.previews.first { $0.id == postID }?.moderationDecision ?? Self.pendingDecision(id: postID)
    }

    static let previews: [SpacesSpacePreview] = [
        SpacesSpacePreview(
            space: SocialV2Space(
                id: "space-neighborhood-prayer",
                name: "Neighborhood Prayer",
                summary: "City-level requests, care updates, and volunteer coordination.",
                kind: .local,
                locationScope: .city,
                trustSignals: [.moderator, .volunteer]
            ),
            memberCountLabel: "1.2K members",
            moderationDecision: approvedDecision(id: "space-neighborhood-prayer", policyReference: "spaces.local.city"),
            highlightedTopics: ["Prayer", "Care", "Service"]
        ),
        SpacesSpacePreview(
            space: SocialV2Space(
                id: "space-campus-life",
                name: "Campus Life",
                summary: "Student groups, weekly rhythms, and mentor-led discussions.",
                kind: .school,
                locationScope: .region,
                trustSignals: [.verified, .contributor]
            ),
            memberCountLabel: "840 members",
            moderationDecision: approvedDecision(id: "space-campus-life", policyReference: "spaces.school.region"),
            highlightedTopics: ["Mentorship", "Study", "Events"]
        ),
        SpacesSpacePreview(
            space: SocialV2Space(
                id: "space-new-member-welcome",
                name: "New Member Welcome",
                summary: "This space is waiting for review before it can be opened.",
                kind: .church,
                locationScope: .hidden,
                trustSignals: [.creator]
            ),
            memberCountLabel: "Pending review",
            moderationDecision: pendingDecision(id: "space-new-member-welcome"),
            highlightedTopics: ["Welcome", "Guides"]
        )
    ]

    private static func approvedDecision(
        id: SocialV2Identifier,
        policyReference: String
    ) -> SocialV2ModerationDecision {
        SocialV2ModerationDecision(
            id: "moderation-\(id)",
            status: .approved,
            policyReference: policyReference,
            explanation: "Approved for discovery after moderation review.",
            decidedAt: Date(timeIntervalSince1970: 1_788_566_400)
        )
    }

    private static func pendingDecision(id: SocialV2Identifier) -> SocialV2ModerationDecision {
        SocialV2ModerationDecision(
            id: "moderation-\(id)",
            status: .pending,
            policyReference: "spaces.review.required",
            explanation: "Content remains hidden until review is complete.",
            decidedAt: Date(timeIntervalSince1970: 1_788_566_400)
        )
    }
}
