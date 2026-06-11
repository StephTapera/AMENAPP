import SwiftUI

// MARK: - Empty Feed State

/// Shown when the OpenTable feed has no posts.
/// Redesigned with iOS 26 Liquid Glass — avatar cluster merges via GlassEffectContainer,
/// CTAs use full-width interactive glass capsules.
struct EmptyFeedView: View {
    @ObservedObject private var followService = FollowService.shared

    private var isNewUser: Bool { followService.following.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            if isNewUser {
                newUserState
            } else {
                followingButEmptyState
            }

            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - New user: hasn't followed anyone yet

    private var newUserState: some View {
        VStack(spacing: 0) {

            avatarCluster
                .padding(.bottom, 32)

            Text("Follow people to see their posts")
                .font(AMENFont.bold(22))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text("When you follow fellow believers, their prayers, testimonies, and thoughts will appear here.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer().frame(height: 36)

            // Primary CTA — full-width interactive glass capsule
            Button {
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            } label: {
                Text("Find People to Follow")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .amenInteractiveGlassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Following people but their feed is empty

    private var followingButEmptyState: some View {
        VStack(spacing: 0) {

            // Single large glass icon orb
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, height: 80)
                .amenRegularGlassEffect(in: Circle())
                .padding(.bottom, 32)

            Text("Nothing here yet")
                .font(AMENFont.bold(22))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text("The people you follow haven't posted recently. Be the first to share something — a prayer, a testimony, or what's on your heart.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer().frame(height: 36)

            // Primary CTA
            Button {
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            } label: {
                Text("Share Something")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .amenInteractiveGlassEffect(in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 14)

            // Secondary CTA — smaller glass pill
            Button {
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            } label: {
                Text("Find more people to follow")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .amenInteractiveGlassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Liquid Glass Avatar Cluster

    /// Three overlapping glass circles that merge via GlassEffectContainer.
    /// The centre orb is larger and raised, flanked by two smaller orbs — their
    /// glass surfaces blend together at the overlap producing a single liquid shape.
    private var avatarCluster: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .center) {

                // Left orb
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 50, height: 50)
                    .amenRegularGlassEffect(in: Circle())
                    .offset(x: -36, y: 8)

                // Right orb
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 50, height: 50)
                    .amenRegularGlassEffect(in: Circle())
                    .offset(x: 36, y: 8)

                // Centre orb — larger, elevated
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 64, height: 64)
                    .amenRegularGlassEffect(in: Circle())
                    .zIndex(1)
            }
            .frame(width: 140, height: 80)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let switchToDiscoverTab = Notification.Name("switchToDiscoverTab")
    static let feedDidRefresh      = Notification.Name("feedDidRefresh")
}

// MARK: - Previews

#Preview("New user — Liquid Glass") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        EmptyFeedView()
    }
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
