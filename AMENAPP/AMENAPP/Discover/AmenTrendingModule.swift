// AmenTrendingModule.swift
// AMENAPP
//
// Trending topics, Berean AI summaries, chip filter row, and follow suggestions
// for the Search & Discover surface (Agent H).
//
// Components exported:
//   - AmenTrendingService        (@MainActor ObservableObject)
//   - AmenTopicChipRow           (horizontal chip filter)
//   - AmenTrendingSection        (embeddable trending hub)
//   - AmenFollowSuggestionsSection (embeddable follow row)
//   - SuggestedProfile           (lightweight display model)
//
// Integration note:
//   Embed AmenTrendingSection and AmenFollowSuggestionsSection inside
//   AmenDiscoverView's ScrollView VStack — no modifications to existing files
//   required. Pass a @StateObject AmenTrendingService from the parent or let
//   each section own its own @StateObject.

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - SuggestedProfile

/// Lightweight display model for the Follow Suggestions row.
/// Distinct from SuggestedUser (SuggestedFollowsService.swift) which is a
/// full ranked model. SuggestedProfile is the minimal surface-level struct
/// used by AmenFollowSuggestionsSection.
struct SuggestedProfile: Identifiable {
    var id: String
    var displayName: String
    var username: String
    var profileImageURL: String?
    var initials: String
    var isVerified: Bool = false
    var followerCount: Int = 0
}

// MARK: - AmenTrendingService

@MainActor
final class AmenTrendingService: ObservableObject {

    // MARK: Published state

    @Published var trendingTopics: [DiscoverTopic] = []
    @Published var isLoadingTrending = false
    @Published var isLoadingSummaries = false

    // MARK: Private

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Fallback faith topics (used when Firestore returns empty)

    private static let fallbackTopics: [DiscoverTopic] = [
        DiscoverTopic(id: "prayer_requests",  key: "prayer_requests",  displayName: "Prayer Requests", postCount: 8420),
        DiscoverTopic(id: "testimonies",      key: "testimonies",      displayName: "Testimonies",     postCount: 6100),
        DiscoverTopic(id: "bible_study",      key: "bible_study",      displayName: "Bible Study",     postCount: 4300),
        DiscoverTopic(id: "worship",          key: "worship",          displayName: "Worship",         postCount: 3800),
        DiscoverTopic(id: "faith_work",       key: "faith_work",       displayName: "Faith & Work",    postCount: 2100),
    ]

    // MARK: - loadTrending

    func loadTrending() async {
        guard !isLoadingTrending else { return }
        isLoadingTrending = true
        defer { isLoadingTrending = false }

        do {
            let snapshot = try await db.collection("trending")
                .order(by: "postCount", descending: true)
                .limit(to: 10)
                .getDocuments()

            let fetched: [DiscoverTopic] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard
                    let key         = data["key"]         as? String,
                    let displayName = data["displayName"] as? String,
                    let postCount   = data["postCount"]   as? Int
                else { return nil }
                return DiscoverTopic(
                    id:          doc.documentID,
                    key:         key,
                    displayName: displayName,
                    postCount:   postCount,
                    aiSummary:   data["aiSummary"] as? String,
                    thumbnailURL: data["thumbnailURL"] as? String
                )
            }

            trendingTopics = fetched.isEmpty ? Self.fallbackTopics : fetched

        } catch {
            // Firestore error — fall back silently; the hardcoded topics guarantee
            // content even offline.
            trendingTopics = Self.fallbackTopics
        }
    }

    // MARK: - fetchBereanSummaries

    /// Calls the `bereanTrendingSummary` Cloud Function and merges AI one-liners
    /// into the matching DiscoverTopic.aiSummary. Failures are silent — summaries
    /// are purely additive and never block the UI.
    func fetchBereanSummaries() async {
        guard !trendingTopics.isEmpty else { return }
        isLoadingSummaries = true
        defer { isLoadingSummaries = false }

        let topicPayload: [[String: Any]] = trendingTopics.map { topic in
            ["key": topic.key, "count": topic.postCount]
        }

        do {
            let result = try await functions
                .httpsCallable("bereanTrendingSummary")
                .call(["topics": topicPayload])

            guard let data = result.data as? [String: Any],
                  let summaries = data["summaries"] as? [[String: Any]]
            else { return }

            // Build a lookup so we can merge in O(n) without nested loops.
            var summaryMap: [String: String] = [:]
            for entry in summaries {
                if let key     = entry["key"]     as? String,
                   let oneLiner = entry["oneLiner"] as? String {
                    summaryMap[key] = oneLiner
                }
            }

            // Merge: produce a new array rather than mutating in place so
            // SwiftUI correctly diffs the published array.
            trendingTopics = trendingTopics.map { topic in
                guard let oneLiner = summaryMap[topic.key] else { return topic }
                var updated = topic
                updated.aiSummary = oneLiner
                return updated
            }

        } catch {
            // Summaries are optional — fail silently.
            return
        }
    }
}

// MARK: - Post count formatter

private func formattedPostCount(_ count: Int) -> String {
    switch count {
    case 0..<1_000:
        return "\(count) posts"
    case 1_000..<1_000_000:
        let k = Double(count) / 1_000
        let formatted = k.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fk", k)
            : String(format: "%.1fk", k)
        return "\(formatted) posts"
    default:
        let m = Double(count) / 1_000_000
        let formatted = m.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fM", m)
            : String(format: "%.1fM", m)
        return "\(formatted) posts"
    }
}

// MARK: - AmenTopicChipRow

/// Horizontal scrolling chip row for quick topic filter selection.
/// `selected == nil` means "All" — no filter applied.
struct AmenTopicChipRow: View {

    let topics: [String]
    @Binding var selected: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                chipView(label: "All", isSelected: selected == nil) {
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        selected = nil
                    }
                }

                ForEach(topics, id: \.self) { topic in
                    let isSelected = selected == topic
                    chipView(label: topic, isSelected: isSelected) {
                        withAnimation(Motion.adaptive(Motion.popToggle)) {
                            selected = isSelected ? nil : topic
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func chipView(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? AmenTheme.Colors.amenBlue
                              : AmenTheme.Colors.surfaceChip)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected
                                ? Color.clear
                                : AmenTheme.Colors.borderSoft,
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(AmenPressStyle(scale: 0.96))
        .accessibilityLabel("\(label), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(Motion.adaptive(Motion.popToggle), value: isSelected)
    }
}

// MARK: - AmenTrendingTopicCard

private struct AmenTrendingTopicCard: View {

    let topic: DiscoverTopic

    var body: some View {
        HStack(spacing: 12) {

            // Optional thumbnail
            if let thumbnailURL = topic.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        thumbnailPlaceholder
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            } else {
                thumbnailPlaceholder
                    .accessibilityHidden(true)
            }

            // Text stack
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.displayName)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                if let summary = topic.aiSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(formattedPostCount(topic.postCount))
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            // Right chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .amenCard(cornerRadius: 14, shadow: true)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: topic))
        .accessibilityHint("Double tap to browse this topic")
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AmenTheme.Colors.amenBlue.opacity(0.12))
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: "number")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenBlue.opacity(0.7))
            )
    }

    private func accessibilityLabel(for topic: DiscoverTopic) -> String {
        var parts = [topic.displayName, formattedPostCount(topic.postCount)]
        if let summary = topic.aiSummary, !summary.isEmpty {
            parts.append(summary)
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - AmenTrendingSection

/// The embeddable trending hub for Discover. Owns an AmenTrendingService
/// and renders topic cards with show-more / show-less toggle.
struct AmenTrendingSection: View {

    @StateObject var service: AmenTrendingService

    // Show-more expansion state
    @State private var isExpanded = false

    // Collapsed list shows the first 5 topics
    private let collapsedLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            headerRow
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if service.isLoadingTrending {
                trendingSkeletons
            } else {
                topicList
            }

            // Show more / show less toggle
            if service.trendingTopics.count > collapsedLimit {
                showMoreButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 16)
        .task {
            if service.trendingTopics.isEmpty {
                await service.loadTrending()
                await service.fetchBereanSummaries()
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Trending now")
                    .font(AMENFont.bold(17))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Spacer()

                if service.isLoadingSummaries {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(AmenTheme.Colors.amenBlue)
                        .accessibilityLabel("Loading Berean summaries")
                }
            }

            Text("What people are saying, summarized by Berean")
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Trending now. What people are saying, summarized by Berean")
    }

    // MARK: Topic list

    @ViewBuilder
    private var topicList: some View {
        let visibleTopics = isExpanded
            ? service.trendingTopics
            : Array(service.trendingTopics.prefix(collapsedLimit))

        VStack(spacing: 8) {
            ForEach(Array(visibleTopics.enumerated()), id: \.element.id) { index, topic in
                // NavigationLink destination is EmptyView — wired at integration time.
                NavigationLink(destination: EmptyView()) {
                    AmenTrendingTopicCard(topic: topic)
                }
                .buttonStyle(AmenPressStyle(scale: 0.985))
                .padding(.horizontal, 16)
                .staggeredReveal(index: index, baseDelay: 0.04, maxDelay: 0.20)
            }
        }
        .animation(Motion.adaptive(Motion.springRelease), value: isExpanded)
    }

    // MARK: Show more / less

    private var showMoreButton: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.36, dampingFraction: 0.76))) {
                isExpanded.toggle()
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded
            ? "Show fewer topics"
            : "Show \(service.trendingTopics.count - collapsedLimit) more topics")
        .accessibilityHint(isExpanded
            ? "Collapses the trending topics list"
            : "Expands the trending topics list")
        .animation(Motion.adaptive(Motion.popToggle), value: isExpanded)
    }

    // MARK: Loading skeleton

    private var trendingSkeletons: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(height: 72)
                    .amenSkeleton()
                    .padding(.horizontal, 16)
            }
        }
        .accessibilityLabel("Loading trending topics")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - AmenFollowSuggestionsSection

/// Embeddable follow suggestions row for Discover.
/// Pass a pre-fetched [SuggestedProfile] array; the actual follow action
/// is a closure wired by the integrating parent.
struct AmenFollowSuggestionsSection: View {

    let suggestions: [SuggestedProfile]
    var onFollow: (SuggestedProfile) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            Text("Follow suggestions")
                .font(AMENFont.bold(17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            if suggestions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, profile in
                        AmenFollowSuggestionRow(profile: profile, onFollow: {
                            onFollow(profile)
                        })
                        .padding(.horizontal, 16)
                        .staggeredReveal(index: index, baseDelay: 0.04, maxDelay: 0.16)
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    private var emptyState: some View {
        Text("No suggestions right now — check back after connecting with more people.")
            .font(AMENFont.regular(14))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityLabel("No follow suggestions available at this time")
    }
}

// MARK: - AmenFollowSuggestionRow

private struct AmenFollowSuggestionRow: View {

    let profile: SuggestedProfile
    var onFollow: () -> Void

    @State private var isFollowPending = false

    var body: some View {
        HStack(spacing: 12) {

            // Avatar
            avatarView
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            // Name + username
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AmenTheme.Colors.amenBlue)
                            .accessibilityLabel("Verified")
                    }
                }

                Text("@\(profile.username)")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)

                if profile.followerCount > 0 {
                    Text("\(formattedPostCount(profile.followerCount).replacingOccurrences(of: " posts", with: " followers"))")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            // Follow pill button
            followButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .amenCard(cornerRadius: 14, shadow: true)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint("Double tap to follow \(profile.displayName)")
    }

    // MARK: Avatar

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = profile.profileImageURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                case .failure, .empty:
                    initialsCircle
                @unknown default:
                    initialsCircle
                }
            }
            .clipShape(Circle())
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        AmenTheme.Colors.amenBlue.opacity(0.7),
                        AmenTheme.Colors.amenPurple.opacity(0.7),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(profile.initials)
                    .font(AMENFont.bold(16))
                    .foregroundStyle(Color.white)
            )
    }

    // MARK: Follow button

    private var followButton: some View {
        Button {
            guard !isFollowPending else { return }
            isFollowPending = true
            HapticManager.impact(style: .medium)
            onFollow()
        } label: {
            Text(isFollowPending ? "Requested" : "Follow")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(isFollowPending ? AmenTheme.Colors.textSecondary : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isFollowPending
                              ? AmenTheme.Colors.surfaceChip
                              : AmenTheme.Colors.textPrimary)
                )
        }
        .buttonStyle(AmenPressStyle(scale: 0.96))
        .disabled(isFollowPending)
        .accessibilityLabel(isFollowPending
            ? "Follow request sent to \(profile.displayName)"
            : "Follow \(profile.displayName)")
        .animation(Motion.adaptive(Motion.popToggle), value: isFollowPending)
    }

    // MARK: Accessibility label

    private var rowAccessibilityLabel: String {
        var parts = [profile.displayName]
        if profile.isVerified { parts.append("Verified") }
        parts.append("@\(profile.username)")
        if profile.followerCount > 0 {
            parts.append("\(profile.followerCount) followers")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Trending Section") {
    NavigationStack {
        ScrollView {
            AmenTrendingSection(service: AmenTrendingService())
        }
    }
}

#Preview("Follow Suggestions") {
    let samples = [
        SuggestedProfile(
            id: "1",
            displayName: "Priscilla Okafor",
            username: "priscilla.ok",
            profileImageURL: nil,
            initials: "PO",
            isVerified: true,
            followerCount: 12_400
        ),
        SuggestedProfile(
            id: "2",
            displayName: "Marcus Webb",
            username: "mwebb",
            profileImageURL: nil,
            initials: "MW",
            isVerified: false,
            followerCount: 870
        ),
        SuggestedProfile(
            id: "3",
            displayName: "Grace & Truth Church",
            username: "graceandtruth",
            profileImageURL: nil,
            initials: "GT",
            isVerified: true,
            followerCount: 5_210
        ),
    ]
    ScrollView {
        AmenFollowSuggestionsSection(suggestions: samples)
    }
}

#Preview("Chip Row") {
    @Previewable @State var selected: String? = nil
    VStack {
        AmenTopicChipRow(
            topics: ["Prayer Requests", "Testimonies", "Bible Study", "Worship", "Faith & Work"],
            selected: $selected
        )
        Text(selected ?? "All")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
