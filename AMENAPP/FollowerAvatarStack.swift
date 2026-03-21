//
//  FollowerAvatarStack.swift
//  AMENAPP
//
//  Stacked follower avatar row for UserProfileView & ProfileView.
//  Adapts to the project's CachedAsyncImage, FollowUser model, and OpenSans fonts.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

// MARK: - Int compact formatting (1.2K / 65.6K / 2.1M)
// Used by FollowerAvatarStack and available app-wide.
extension Int {
    var compactFormatted: String {
        switch self {
        case 1_000_000...:
            return String(format: "%.1fM", Double(self) / 1_000_000)
        case 1_000...:
            let k = Double(self) / 1_000
            // Drop the decimal for clean thousands (e.g. 2000 → "2K", not "2.0K")
            return k.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fK", k)
                : String(format: "%.1fK", k)
        default:
            return "\(self)"
        }
    }
}

// MARK: - FollowerAvatarStack

/// A subtle row of stacked profile-image circles followed by a compact follower count.
/// Falls back gracefully to count-only text when no followers have profile photos.
///
/// Usage:
/// ```swift
/// FollowerAvatarStack(
///     followers: viewModel.recentFollowers,
///     followerCount: profileData.followersCount
/// )
/// ```
struct FollowerAvatarStack: View {
    /// Recent followers — only those with a profileImageURL will be shown.
    let followers: [FollowUser]
    /// Total count displayed in the trailing label.
    let followerCount: Int
    /// Diameter of each circle. Default matches the OpenSans-12 stat line height.
    var avatarSize: CGFloat = 26
    /// Maximum circles to stack (excess are hidden).
    var maxVisible: Int = 4
    /// Horizontal overlap between adjacent circles.
    var overlap: CGFloat = 8
    /// Separator ring colour — should match the view's background to create the
    /// illusion of separated circles. Exposed so callers can pass their bg colour.
    var ringColor: Color = Color(uiColor: .systemBackground)

    // ── Only followers who have an actual photo ──────────────────────────────
    private var photoFollowers: [FollowUser] {
        followers
            .filter { url in
                guard let u = url.profileImageURL else { return false }
                return !u.isEmpty
            }
            .prefix(maxVisible)
            .map { $0 }
    }

    var body: some View {
        if photoFollowers.isEmpty {
            countOnlyLabel
        } else {
            HStack(spacing: 7) {
                stackedAvatars
                countLabel
            }
        }
    }

    // MARK: - Stacked circles

    private var stackedAvatars: some View {
        let count = photoFollowers.count
        let totalWidth = avatarSize + CGFloat(max(count - 1, 0)) * (avatarSize - overlap)

        return ZStack(alignment: .leading) {
            // Reverse so index-0 is visually on top
            ForEach(Array(photoFollowers.enumerated().reversed()), id: \.element.id) { index, follower in
                avatarCircle(for: follower)
                    .offset(x: CGFloat(index) * (avatarSize - overlap))
            }
        }
        .frame(width: totalWidth, height: avatarSize)
    }

    @ViewBuilder
    private func avatarCircle(for follower: FollowUser) -> some View {
        let url = follower.profileImageURL.flatMap { URL(string: $0) }

        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
        } placeholder: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.55), Color.blue.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Text(follower.initials.prefix(2).uppercased())
                        .font(.custom("OpenSans-Bold", size: avatarSize * 0.36))
                        .foregroundStyle(.white)
                )
        }
        // Separation ring — gives the stacked circles visual breathing room
        .overlay(
            Circle()
                .strokeBorder(ringColor, lineWidth: 1.5)
        )
        .frame(width: avatarSize, height: avatarSize)
    }

    // MARK: - Labels

    private var countLabel: some View {
        Text("\(followerCount.compactFormatted) followers")
            .font(.custom("OpenSans-Regular", size: 12))
            .foregroundStyle(.secondary)
    }

    private var countOnlyLabel: some View {
        Text("\(followerCount.compactFormatted) followers")
            .font(.custom("OpenSans-Regular", size: 12))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Lightweight Firestore fetch

/// Fetches the most recent followers who have a profile photo.
/// Followers are stored in Realtime Database at `user-followers/{uid}/{followerId}`.
/// User profile details (including profileImageURL) are cross-referenced from Firestore.
/// Called once on profile appear — non-blocking, fire-and-forget safe.
enum FollowerAvatarFetcher {
    static func fetch(for userId: String, limit: Int = 8) async -> [FollowUser] {
        guard !userId.isEmpty else { return [] }
        let rtdb = Database.database().reference()
        let firestore = Firestore.firestore()

        do {
            // 1. Fetch follower IDs from RTDB (mirrors FollowersService.fetchFollowers)
            let snap = try await rtdb
                .child("user-followers")
                .child(userId)
                .getData()

            guard snap.exists(), let dict = snap.value as? [String: Any] else { return [] }

            // Sort by timestamp descending, take first `limit`
            let sortedIds: [String] = dict
                .compactMap { key, value -> (String, Double)? in
                    let ts = (value as? [String: Any])?["timestamp"] as? Double ?? 0
                    return (key, ts)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map(\.0)

            guard !sortedIds.isEmpty else { return [] }

            // 2. Batch-fetch Firestore user docs — "in" supports up to 10 IDs
            let userSnap = try await firestore
                .collection("users")
                .whereField(FieldPath.documentID(), in: Array(sortedIds.prefix(10)))
                .getDocuments()

            // 3. Filter to only those with a profile photo
            return userSnap.documents.compactMap { doc -> FollowUser? in
                let d = doc.data()
                guard let name = d["displayName"] as? String else { return nil }
                let imageURL = (d["profileImageURL"] as? String) ?? (d["profilePhotoURL"] as? String)
                guard let imageURL, !imageURL.isEmpty else { return nil }
                return FollowUser(
                    id: doc.documentID,
                    name: name,
                    username: d["username"] as? String ?? "",
                    initials: d["initials"] as? String ?? String(name.prefix(2)).uppercased(),
                    profileImageURL: imageURL,
                    bio: d["bio"] as? String,
                    followersCount: d["followersCount"] as? Int ?? 0,
                    isFollowing: false,
                    followedAt: nil
                )
            }
        } catch {
            return []
        }
    }
}

// MARK: - Preview

#Preview("Follower Avatar Stack") {
    let withPhotos: [FollowUser] = [
        FollowUser(id: "1", name: "Marcus Webb",   username: "marcuswebb",   initials: "MW", profileImageURL: nil, bio: nil, followersCount: 0, isFollowing: false, followedAt: nil),
        FollowUser(id: "2", name: "Amara Osei",    username: "amaraosei",    initials: "AO", profileImageURL: nil, bio: nil, followersCount: 0, isFollowing: false, followedAt: nil),
        FollowUser(id: "3", name: "Joshua Patel",  username: "joshuapatel",  initials: "JP", profileImageURL: nil, bio: nil, followersCount: 0, isFollowing: false, followedAt: nil),
        FollowUser(id: "4", name: "Deborah Asante", username: "dasante",     initials: "DA", profileImageURL: nil, bio: nil, followersCount: 0, isFollowing: false, followedAt: nil),
    ]
    let noPhotos: [FollowUser] = [
        FollowUser(id: "5", name: "Guest", username: "guest", initials: "GU", profileImageURL: nil, bio: nil, followersCount: 0, isFollowing: false, followedAt: nil),
    ]

    ZStack {
        Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

        VStack(alignment: .leading, spacing: 24) {
            // With placeholder circles (no real URLs — shows avatar initials)
            FollowerAvatarStack(followers: withPhotos, followerCount: 2_592)

            // Only 2 followers with photos
            FollowerAvatarStack(followers: Array(withPhotos.prefix(2)), followerCount: 847)

            // No photos — falls back to count text
            FollowerAvatarStack(followers: noPhotos, followerCount: 14)

            // Larger size variant
            FollowerAvatarStack(
                followers: withPhotos,
                followerCount: 65_320,
                avatarSize: 32,
                maxVisible: 5
            )
        }
        .padding(24)
    }
}
