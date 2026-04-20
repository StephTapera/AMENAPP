import SwiftUI
// MARK: - Empty Feed State

/// Shown when the OpenTable feed has no posts.
/// If the user has zero follows, surfaces a "Discover People" CTA to guide them.
struct EmptyFeedView: View {
    @ObservedObject private var followService = FollowService.shared

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
    }

    // ── New user: hasn't followed anyone yet ──────────────────────────────
    private var newUserState: some View {
        VStack(spacing: 0) {
            // Icon cluster
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.2.fill")
                    .font(.systemScaled(32, weight: .medium))
                    .foregroundStyle(.secondary)
            }

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

            // Primary CTA — find people
            Button {
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            } label: {
                Text("Find People to Follow")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    // ── Following people but their feed is empty ──────────────────────────
    private var followingButEmptyState: some View {
        VStack(spacing: 0) {
            // Icon cluster showing "all caught up / nothing new"
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.systemScaled(32, weight: .medium))
                    .foregroundStyle(.secondary)
            }

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
                NotificationCenter.default.post(name: .openCreatePost, object: nil)
            } label: {
                Text("Share Something")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer().frame(height: 12)

            // Secondary — find more people
            Button {
                NotificationCenter.default.post(name: .switchToDiscoverTab, object: nil)
            } label: {
                Text("Find more people to follow")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

extension Notification.Name {
    static let switchToDiscoverTab = Notification.Name("switchToDiscoverTab")
    static let feedDidRefresh = Notification.Name("feedDidRefresh")
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
