import SwiftUI
// MARK: - Empty Feed State

/// Shown when the OpenTable feed has no posts.
/// If the user has zero follows, surfaces a "Find People" CTA.
/// - FTUE not completed → opens `FindYourPeopleFTUEView` (church + interests + discovery)
/// - FTUE completed → opens `FindPeopleView` directly
struct EmptyFeedView: View {
    @ObservedObject private var followService      = FollowService.shared
    @ObservedObject private var ftueManager        = FTUEPeopleDiscoveryManager.shared
    @ObservedObject private var recommendedService = RecommendedUsersAIService.shared

    // Sheet routing
    @State private var showFTUESheet          = false
    @State private var showFindPeople         = false
    @State private var isHandlingFindPeopleTap = false

    // Which variant to show
    private var isNewUser: Bool { followService.following.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)

            if isNewUser {
                newUserState
            } else {
                followingButEmptyState
            }

            Spacer().frame(height: 48)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        // FTUE sheet — first-time personalized people discovery
        .fullScreenCover(isPresented: $showFTUESheet) {
            FindYourPeopleFTUEView {
                // After FTUE completes, switch to Discover so the user lands on
                // a personalized feed instead of an empty OpenTable.
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            }
        }
        // Direct discovery for returning users
        .fullScreenCover(isPresented: $showFindPeople) {
            FindPeopleView()
        }
    }

    /// Tapping "Find People" routes through FTUE if not yet completed.
    private func handleFindPeopleTap(hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard !isHandlingFindPeopleTap else { return }
        isHandlingFindPeopleTap = true
        UIImpactFeedbackGenerator(style: hapticStyle).impactOccurred()
        if ftueManager.hasCompleted {
            showFindPeople = true
        } else {
            showFTUESheet = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            isHandlingFindPeopleTap = false
        }
    }

    // ── New user: hasn't followed anyone yet ──────────────────────────────
    private var newUserState: some View {
        VStack(spacing: 0) {
            // Icon cluster (decorative) — blue-tinted glass circle for discovery CTA
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenBlue.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .strokeBorder(AmenTheme.Colors.amenBlue.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: "person.2.fill")
                    .font(.systemScaled(32, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenBlue.opacity(0.80))
            }
            .accessibilityHidden(true)

            Spacer().frame(height: 20)

            Text("Follow people to see their posts")
                .font(AMENFont.bold(20))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Text("When you follow fellow believers, their prayers, testimonies, and thoughts will appear here.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 28)

            // Suggested users rail — only shown when recommendations are available
            if !recommendedService.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested for you")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recommendedService.recommendations.prefix(5)) { rec in
                                VStack(spacing: 6) {
                                    Group {
                                        if let urlStr = rec.profileImageURL,
                                           let url = URL(string: urlStr) {
                                            AsyncImage(url: url) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.secondary.opacity(0.2)
                                            }
                                        } else {
                                            Image(systemName: "person.crop.circle.fill")
                                                .resizable()
                                                .foregroundStyle(Color.secondary.opacity(0.4))
                                        }
                                    }
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                                    )

                                    Text(rec.name)
                                        .font(AMENFont.semiBold(11))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 64)
                                }
                                .frame(width: 64)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.bottom, 16)
            }

            // Primary CTA — FTUE-gated: shows personalized setup on first use
            Button { handleFindPeopleTap() } label: {
                Text("Find People to Follow")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Find People to Follow")
            .accessibilityHint("Opens personalized people discovery")
        }
        .task { await RecommendedUsersAIService.shared.fetchRecommendations() }
    }

    // ── Following people but their feed is empty ──────────────────────────
    private var followingButEmptyState: some View {
        VStack(spacing: 0) {
            // Icon cluster (decorative) — purple-tinted glass circle (Berean/reflection theme)
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenPurple.opacity(0.10))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .strokeBorder(AmenTheme.Colors.amenPurple.opacity(0.20), lineWidth: 1)
                    )
                Image(systemName: "sparkles")
                    .font(.systemScaled(32, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenPurple.opacity(0.75))
            }
            .accessibilityHidden(true)

            Spacer().frame(height: 20)

            Text("Nothing here yet")
                .font(AMENFont.bold(20))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Text("The people you follow haven't posted recently. Be the first to share something — a prayer, a testimony, or what's on your heart.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 28)

            // Primary CTA — create a post
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            } label: {
                Text("Share Something")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.amenBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AmenTheme.Colors.amenGold, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Share Something")
            .accessibilityHint("Opens the post composer")

            Spacer().frame(height: 12)

            // Secondary — find more people (FTUE-gated)
            Button { handleFindPeopleTap(hapticStyle: .light) } label: {
                Text("Find more people to follow")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Find more people to follow")
            .accessibilityHint(ftueManager.hasCompleted ? "Opens Find People screen" : "Personalized people discovery")
        }
    }
}

extension Notification.Name {
    static let switchToDiscoverTab = Notification.Name("switchToDiscoverTab")
    static let feedDidRefresh = Notification.Name("feedDidRefresh")
    /// Fired by SuggestedRailViewModel when the user follows 3+ people from suggestions.
    static let feedSuggestionsPersonalized = Notification.Name("feedSuggestionsPersonalized")
}

#Preview("Posting Bar - Posting") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack {
            Spacer()
            ThreadsPostingBar(state: .posting, category: "openTable", post: nil) {}
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
        }
    }
}

#Preview("Posting Bar - Posted") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        VStack {
            Spacer()
            ThreadsPostingBar(state: .posted, category: "prayer", post: nil) {}
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
        }
    }
}

#Preview("ContentView") {
    ContentView()
}
