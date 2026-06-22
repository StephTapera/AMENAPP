import SwiftUI
import FirebaseAnalytics

// MARK: - ChapelInboxLane
// Each lane is a named spiritual triage bucket.
// Posts are routed into lanes by ChapelInboxClassifier based on content signals.

enum ChapelInboxLane: String, CaseIterable, Identifiable {
    case all            = "all"
    case forMe          = "for_me"
    case needsPrayer    = "needs_prayer"
    case reflectLater   = "reflect_later"
    case fromMyChurch   = "from_my_church"
    case encouragement  = "encouragement"
    case priorityVoices = "priority_voices"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:            return "All"
        case .forMe:          return "For Me"
        case .needsPrayer:    return "Needs Prayer"
        case .reflectLater:   return "Reflect Later"
        case .fromMyChurch:   return "My Church"
        case .encouragement:  return "Encouragement"
        case .priorityVoices: return "Priority"
        }
    }

    var icon: String {
        switch self {
        case .all:            return "tray"
        case .forMe:          return "person.crop.circle"
        case .needsPrayer:    return "hands.sparkles"
        case .reflectLater:   return "bookmark.circle"
        case .fromMyChurch:   return "building.columns"
        case .encouragement:  return "heart"
        case .priorityVoices: return "star"
        }
    }
}

// MARK: - ChapelInboxClassifier
// Lightweight heuristic that assigns a Post to the most relevant lane.
// Pure functions — no side effects, fully testable.

enum ChapelInboxClassifier {

    static func primaryLane(for post: Post, churchId: String?, priorityAuthorIds: Set<String>) -> ChapelInboxLane {
        // Priority Voices: from shepherds/mentors explicitly marked
        if priorityAuthorIds.contains(post.authorId) {
            return .priorityVoices
        }

        // From My Church: post is tagged to the user's saved church
        if let church = churchId,
           let taggedChurch = post.taggedChurchId,
           taggedChurch == church {
            return .fromMyChurch
        }

        let lower = post.content.lowercased()

        // Needs Prayer: prayer category or prayer language in content
        if post.category == .prayer || prayerSignals.contains(where: { lower.contains($0) }) {
            return .needsPrayer
        }

        // Encouragement: uplifting language, testimonies, hope signals
        if post.category == .testimonies || encouragementSignals.contains(where: { lower.contains($0) }) {
            return .encouragement
        }

        // For Me: mentions, tagged, or direct address signals
        if forMeSignals.contains(where: { lower.contains($0) }) {
            return .forMe
        }

        // Reflect Later: long-form content, church notes, scripture study
        if post.category == .openTable && lower.count > 300 ||
           post.churchNoteId != nil ||
           reflectionSignals.contains(where: { lower.contains($0) }) {
            return .reflectLater
        }

        return .all
    }

    // MARK: - Signal banks

    private static let prayerSignals = [
        "pray for", "need prayer", "please pray", "praying for", "prayer request",
        "asking for prayer", "lift up", "intercede", "standing in agreement"
    ]

    private static let encouragementSignals = [
        "he is faithful", "god is good", "testimony", "breakthrough", "healed",
        "answered prayer", "praise report", "victorious", "overcome", "rejoice",
        "hope", "trust in god", "blessed", "grateful", "thankful", "hallelujah"
    ]

    private static let forMeSignals = [
        "@", "speaking to someone", "if this is you", "someone needed this",
        "someone is going through", "for whoever", "this is for"
    ]

    private static let reflectionSignals = [
        "sermon notes", "sermon recap", "study notes", "reflecting on", "what i learned",
        "god showed me", "revelation", "deep dive", "theological", "exegesis",
        "bible study", "commentary", "devotional thoughts"
    ]
}

// MARK: - ChapelInboxBar
// Liquid Glass segmented lane switcher shown at the top of the feed.
// Horizontal scroll — only show lanes that have posts to avoid empty states.

struct ChapelInboxBar: View {

    @Binding var selectedLane: ChapelInboxLane
    let visibleLanes: [ChapelInboxLane]
    var counts: [ChapelInboxLane: Int] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleLanes) { lane in
                    ChapelInboxLanePill(
                        lane: lane,
                        isSelected: selectedLane == lane,
                        count: counts[lane]
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82))) {
                            selectedLane = lane
                        }
                        Analytics.logEvent("chapel_inbox_lane_tapped", parameters: [
                            "lane": lane.rawValue
                        ])
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 42)
    }
}

// MARK: - Lane Pill

private struct ChapelInboxLanePill: View {
    let lane: ChapelInboxLane
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: lane.icon)
                    .font(.systemScaled(11, weight: .medium))

                Text(lane.displayName)
                    .font(AMENFont.semiBold(13))
                    .lineLimit(1)

                if let n = count, n > 0, !isSelected {
                    Text("\(min(n, 99))")
                        .font(AMENFont.semiBold(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary))
                }
            }
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary : Color(.systemGray6))
                    .shadow(color: isSelected ? Color.black.opacity(0.12) : .clear, radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(lane.displayName)\(count.map { ", \($0) posts" } ?? "")")
    }
}

// MARK: - ChapelInboxViewModel
// Manages lane counts and filtered post list.

@MainActor
final class ChapelInboxViewModel: ObservableObject {

    @Published var selectedLane: ChapelInboxLane = .all
    @Published var visibleLanes: [ChapelInboxLane] = [.all]
    @Published var laneCounts: [ChapelInboxLane: Int] = [:]

    // Injected from the parent feed
    var churchId: String? = nil
    var priorityAuthorIds: Set<String> = []

    func update(posts: [Post]) {
        var counts: [ChapelInboxLane: Int] = [:]
        for post in posts {
            let lane = ChapelInboxClassifier.primaryLane(
                for: post,
                churchId: churchId,
                priorityAuthorIds: priorityAuthorIds
            )
            counts[lane, default: 0] += 1
        }
        laneCounts = counts

        // Always show All; show others only if they have posts
        visibleLanes = [.all] + ChapelInboxLane.allCases.dropFirst().filter { (counts[$0] ?? 0) > 0 }
    }

    func filtered(posts: [Post]) -> [Post] {
        guard selectedLane != .all else { return posts }
        return posts.filter {
            ChapelInboxClassifier.primaryLane(for: $0, churchId: churchId, priorityAuthorIds: priorityAuthorIds) == selectedLane
        }
    }
}
