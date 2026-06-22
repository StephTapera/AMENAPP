import Foundation

struct FeedTab: Identifiable, Hashable {
    let kind: SocialV2FeedKind
    let title: String
    let systemImage: String

    var id: SocialV2FeedKind { kind }
}

struct FeedPost: Identifiable, Hashable {
    let id: SocialV2Identifier
    let feedKinds: Set<SocialV2FeedKind>
    let authorName: String
    let communityName: String
    let title: String
    let summary: String
    let publishedContext: String
    let qualities: Set<FeedPostQuality>
}

enum FeedPostQuality: String, Hashable {
    case educational
    case encouraging
    case helpful
    case reflective
    case communityCare
    case outrage
    case argument
    case clickbait
}

struct FeedRanker {
    var calmModeEnabled: Bool

    func rankedPosts(_ posts: [FeedPost], for kind: SocialV2FeedKind) -> [FeedPost] {
        posts
            .filter { $0.feedKinds.contains(kind) }
            .sorted { first, second in
                score(first) > score(second)
            }
    }

    func score(_ post: FeedPost) -> Int {
        guard calmModeEnabled else { return 0 }

        return post.qualities.reduce(0) { score, quality in
            score + calmModeWeight(for: quality)
        }
    }

    private func calmModeWeight(for quality: FeedPostQuality) -> Int {
        switch quality {
        case .educational:
            return 4
        case .encouraging:
            return 3
        case .helpful:
            return 3
        case .reflective:
            return 2
        case .communityCare:
            return 2
        case .outrage:
            return -5
        case .argument:
            return -4
        case .clickbait:
            return -4
        }
    }
}

enum FeedsContent {
    static let tabs: [FeedTab] = [
        FeedTab(kind: .following, title: "Following", systemImage: "person.2"),
        FeedTab(kind: .forYou, title: "For You", systemImage: "sparkles"),
        FeedTab(kind: .communities, title: "Communities", systemImage: "bubble.left.and.bubble.right"),
        FeedTab(kind: .local, title: "Local", systemImage: "mappin.and.ellipse"),
        FeedTab(kind: .learning, title: "Learning", systemImage: "book"),
        FeedTab(kind: .trending, title: "Trending", systemImage: "chart.line.uptrend.xyaxis")
    ]

    static let posts: [FeedPost] = [
        FeedPost(
            id: "morning-practice",
            feedKinds: [.following, .forYou, .learning],
            authorName: "Maya Chen",
            communityName: "Daily Practice",
            title: "A slower way to plan the morning",
            summary: "Three prompts for choosing one useful action before opening the noisy parts of the day.",
            publishedContext: "Today",
            qualities: [.educational, .helpful, .reflective]
        ),
        FeedPost(
            id: "neighborhood-pantry",
            feedKinds: [.following, .communities, .local],
            authorName: "Northside Volunteers",
            communityName: "Local Care",
            title: "Pantry shift needs two more drivers",
            summary: "Saturday routes are mapped and ready. The only open gap is delivery help between 10 and noon.",
            publishedContext: "2 hr",
            qualities: [.helpful, .communityCare, .encouraging]
        ),
        FeedPost(
            id: "context-thread",
            feedKinds: [.forYou, .learning, .trending],
            authorName: "Jon Bell",
            communityName: "Context Notes",
            title: "What people miss in the headline",
            summary: "A source-by-source walkthrough that separates the confirmed update from speculation.",
            publishedContext: "4 hr",
            qualities: [.educational, .helpful]
        ),
        FeedPost(
            id: "heated-reply",
            feedKinds: [.forYou, .trending],
            authorName: "Open Thread",
            communityName: "Public Square",
            title: "This argument is everywhere today",
            summary: "A fast-moving thread collecting reactions, rebuttals, and quote posts from several communities.",
            publishedContext: "1 hr",
            qualities: [.argument, .outrage, .clickbait]
        ),
        FeedPost(
            id: "community-study",
            feedKinds: [.communities, .learning],
            authorName: "AMEN Study Group",
            communityName: "Learning Circle",
            title: "Shared notes from this week",
            summary: "A concise recap with definitions, open questions, and next readings for anyone catching up.",
            publishedContext: "Yesterday",
            qualities: [.educational, .encouraging, .helpful]
        ),
        FeedPost(
            id: "local-resource-map",
            feedKinds: [.local, .forYou],
            authorName: "Steph Rivera",
            communityName: "Austin Mutual Aid",
            title: "Updated local resource map",
            summary: "Clinics, food support, transit help, and verified hours refreshed from organizer notes.",
            publishedContext: "Yesterday",
            qualities: [.helpful, .communityCare]
        )
    ]
}
