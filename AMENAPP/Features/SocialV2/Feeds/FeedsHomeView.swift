import SwiftUI

struct FeedsHomeView: View {
    let selectedTab: SocialV2FeedKind
    let calmModeEnabled: Bool

    init(selectedTab: SocialV2FeedKind = .following, calmModeEnabled: Bool = true) {
        self.selectedTab = selectedTab
        self.calmModeEnabled = calmModeEnabled
    }

    private var selectedFeedTitle: String {
        FeedsContent.tabs.first { $0.kind == selectedTab }?.title ?? "Feeds"
    }

    private var rankedPosts: [FeedPost] {
        FeedRanker(calmModeEnabled: calmModeEnabled)
            .rankedPosts(FeedsContent.posts, for: selectedTab)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                tabStrip
                calmModeCard
                feedList
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(Color.white)
        .navigationTitle("Feeds")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedFeedTitle)
                .font(.largeTitle.bold())

            Text("A quieter social feed tuned for learning, care, and useful context.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedsContent.tabs) { tab in
                    SocialV2GlassPill(isSelected: selectedTab == tab.kind) {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .accessibilityAddTraits(selectedTab == tab.kind ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var calmModeCard: some View {
        SocialV2GlassCard(tintContext: calmModeEnabled ? .state : .neutral, isActive: calmModeEnabled) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: calmModeEnabled ? "leaf.fill" : "leaf")
                    .font(.title2)
                    .foregroundStyle(calmModeEnabled ? .green : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Calm Mode", isOn: .constant(calmModeEnabled))
                        .font(.headline)

                    Text("Down-weights outrage, arguments, and clickbait while up-weighting educational, encouraging, and helpful posts. Ranking does not use likes, shares, streaks, or other virality metrics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var feedList: some View {
        LazyVStack(spacing: 12) {
            ForEach(rankedPosts) { post in
                FeedPostCard(post: post, calmModeEnabled: calmModeEnabled)
            }
        }
    }
}

private struct FeedPostCard: View {
    let post: FeedPost
    let calmModeEnabled: Bool

    private var tintContext: SocialV2GlassTintContext {
        post.qualities.isDisfavoredByCalmMode ? .alert : .neutral
    }

    var body: some View {
        SocialV2GlassCard(tintContext: tintContext) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(.headline)

                        Text("\(post.communityName) - \(post.publishedContext)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    if calmModeEnabled {
                        SocialV2GlassPill(
                            tintContext: post.qualities.isDisfavoredByCalmMode ? .alert : .state,
                            isSelected: true
                        ) {
                            Label(calmModeLabel, systemImage: calmModeSystemImage)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.title)
                        .font(.title3.weight(.semibold))

                    Text(post.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                qualityStrip
            }
        }
    }

    private var qualityStrip: some View {
        HStack(spacing: 6) {
            ForEach(post.qualities.displayLabels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.05), in: Capsule())
            }
        }
    }

    private var calmModeLabel: String {
        post.qualities.isDisfavoredByCalmMode ? "Lower" : "Calm"
    }

    private var calmModeSystemImage: String {
        post.qualities.isDisfavoredByCalmMode ? "arrow.down" : "leaf"
    }
}

private extension Set where Element == FeedPostQuality {
    var isDisfavoredByCalmMode: Bool {
        !isDisjoint(with: [.outrage, .argument, .clickbait])
    }

    var displayLabels: [String] {
        sorted { $0.rawValue < $1.rawValue }
            .map(\.displayLabel)
    }
}

private extension FeedPostQuality {
    var displayLabel: String {
        switch self {
        case .educational:
            return "Educational"
        case .encouraging:
            return "Encouraging"
        case .helpful:
            return "Helpful"
        case .reflective:
            return "Reflective"
        case .communityCare:
            return "Community care"
        case .outrage:
            return "Outrage"
        case .argument:
            return "Argument"
        case .clickbait:
            return "Clickbait"
        }
    }
}
