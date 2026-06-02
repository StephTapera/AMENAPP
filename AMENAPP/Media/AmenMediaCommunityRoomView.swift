// AmenMediaCommunityRoomView.swift
// AMENAPP
//
// Liquid Glass community room view. Shows pinned media, recent posts,
// discussion threads, community rules, moderators, and join/subscription state.
// Spec: Section 16 — Community Rooms.

import SwiftUI
import FirebaseAuth

// MARK: - Models

struct CommunityRoom: Identifiable {
    let id: String
    let name: String
    let description: String
    let memberCount: Int
    let iconName: String
    let accentColor: Color
    let rules: [String]
    let moderators: [CommunityModerator]
    let pinnedMedia: [PinnedMediaItem]
    let recentPosts: [CommunityPost]
    var isMember: Bool
    var tier: RoomTier

    enum RoomTier {
        case free, paid(price: String)
    }
}

struct CommunityModerator: Identifiable {
    let id: String
    let displayName: String
    let avatarInitials: String
    let accentColor: Color
}

struct PinnedMediaItem: Identifiable {
    let id: String
    let title: String
    let duration: String?
    let mediaType: MediaType
    let authorName: String

    enum MediaType {
        case photo, video, sermon, testimony
        var icon: String {
            switch self {
            case .photo:     return "photo"
            case .video:     return "play.circle"
            case .sermon:    return "book.closed"
            case .testimony: return "heart.text.clipboard"
            }
        }
    }
}

struct CommunityPost: Identifiable {
    let id: String
    let authorName: String
    let authorInitials: String
    let content: String
    let timestamp: String
    let replyCount: Int
    let mediaType: PinnedMediaItem.MediaType?
}

// MARK: - View

struct AmenMediaCommunityRoomView: View {
    let room: CommunityRoom
    @Environment(\.dismiss) private var dismiss
    @State private var isMember: Bool
    @State private var showJoinConfirm = false
    @State private var showRules = false
    @State private var selectedPost: CommunityPost?

    init(room: CommunityRoom) {
        self.room = room
        _isMember = State(initialValue: room.isMember)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        roomHero
                            .padding(.bottom, 4)
                        memberBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        pinnedMediaSection
                            .padding(.bottom, 28)
                        recentPostsSection
                            .padding(.bottom, 28)
                        moderatorsSection
                            .padding(.bottom, 28)
                        rulesSection
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRules = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .toolbarColorScheme(.dark)
            .sheet(isPresented: $showRules) {
                RulesSheet(rules: room.rules, roomName: room.name)
            }
        }
    }

    // MARK: - Hero

    private var roomHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [room.accentColor.opacity(0.7), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)

            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: room.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)

                Text(room.name)
                    .font(.custom("OpenSans-Bold", size: 26))
                    .foregroundStyle(.white)

                Text(room.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.system(size: 12))
                    Text("\(room.memberCount.formatted()) members")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Member Bar

    private var memberBar: some View {
        HStack(spacing: 12) {
            if case .paid(let price) = room.tier {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEMBERS ONLY · \(price)/mo")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(room.accentColor)
                        .tracking(0.8)
                    Text("Supports this creator directly")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            } else {
                Spacer()
            }

            Button {
                if isMember {
                    isMember = false
                } else {
                    showJoinConfirm = true
                }
            } label: {
                Text(isMember ? "Joined ✓" : "Join Room")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(isMember ? .white.opacity(0.6) : .black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        isMember
                            ? AnyShapeStyle(.white.opacity(0.12))
                            : AnyShapeStyle(room.accentColor),
                        in: Capsule()
                    )
            }
            .confirmationDialog("Join \(room.name)?", isPresented: $showJoinConfirm, titleVisibility: .visible) {
                Button("Join Room") { isMember = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                if case .paid(let price) = room.tier {
                    Text("This room costs \(price)/month. You'll be charged through the App Store.")
                } else {
                    Text("You'll see posts from this community in your feed.")
                }
            }
        }
    }

    // MARK: - Pinned Media

    private var pinnedMediaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("PINNED MEDIA", icon: "pin.fill")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(room.pinnedMedia) { item in
                        PinnedMediaCard(item: item, accentColor: room.accentColor)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Recent Posts

    private var recentPostsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("RECENT POSTS", icon: "bubble.left.and.bubble.right")
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                ForEach(room.recentPosts) { post in
                    CommunityPostCard(post: post)
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Moderators

    private var moderatorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("MODERATORS", icon: "shield.lefthalf.filled")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(room.moderators) { mod in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(mod.accentColor.opacity(0.3))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text(mod.avatarInitials)
                                        .font(.custom("OpenSans-Bold", size: 16))
                                        .foregroundStyle(mod.accentColor)
                                )
                            Text(mod.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .frame(width: 70)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("COMMUNITY RULES", icon: "list.bullet.clipboard")
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(Array(room.rules.enumerated()), id: \.offset) { idx, rule in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(room.accentColor)
                            .frame(width: 20)
                        Text(rule)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.custom("OpenSans-SemiBold", size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .tracking(1.1)
    }
}

// MARK: - Pinned Media Card

private struct PinnedMediaCard: View {
    let item: PinnedMediaItem
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 160, height: 100)
                Image(systemName: item.mediaType.icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(accentColor)
                if let dur = item.duration {
                    Text(dur)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }
            .frame(width: 160, height: 100)

            Text(item.title)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Text(item.authorName)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: 160)
    }
}

// MARK: - Post Card

private struct CommunityPostCard: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(post.authorInitials)
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)
                    Text(post.timestamp)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                if let mediaType = post.mediaType {
                    Image(systemName: mediaType.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13))
                Text("\(post.replyCount) repl\(post.replyCount == 1 ? "y" : "ies")")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09), lineWidth: 1))
    }
}

// MARK: - Rules Sheet

private struct RulesSheet: View {
    let rules: [String]
    let roomName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(rules.enumerated()), id: \.offset) { idx, rule in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(idx + 1)")
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.7))
                                    .frame(width: 22)
                                Text(rule)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(16)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("\(roomName) Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.7))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AmenMediaCommunityRoomView(room: CommunityRoom(
        id: "preview",
        name: "Morning Prayer Circle",
        description: "A quiet space for sunrise devotionals and intercessory prayer.",
        memberCount: 2_847,
        iconName: "sun.and.horizon",
        accentColor: Color(red: 0.4, green: 0.9, blue: 0.7),
        rules: [
            "Speak life — no discouraging or divisive content.",
            "Scripture references are welcomed and encouraged.",
            "No unsolicited promotion or external links.",
            "Pray for one another by name when requested.",
            "Moderators reserve the right to remove harmful posts."
        ],
        moderators: [
            CommunityModerator(id: "m1", displayName: "Pastor James", avatarInitials: "PJ", accentColor: Color(red: 0.4, green: 0.9, blue: 0.7)),
            CommunityModerator(id: "m2", displayName: "Sister Ruth", avatarInitials: "SR", accentColor: .purple),
        ],
        pinnedMedia: [
            PinnedMediaItem(id: "p1", title: "30-Day Sunrise Prayer Challenge", duration: "8 min", mediaType: .video, authorName: "Pastor James"),
            PinnedMediaItem(id: "p2", title: "Psalm 27 Photo Series", duration: nil, mediaType: .photo, authorName: "Sister Ruth"),
        ],
        recentPosts: [
            CommunityPost(id: "c1", authorName: "Marcus T.", authorInitials: "MT", content: "Praying for everyone starting a new job this week. May His favor go before you 🙏", timestamp: "2h ago", replyCount: 12, mediaType: nil),
            CommunityPost(id: "c2", authorName: "Grace O.", authorInitials: "GO", content: "Shared my testimony this morning — God is faithful. Watch here 👇", timestamp: "4h ago", replyCount: 7, mediaType: .testimony),
        ],
        isMember: false,
        tier: .free
    ))
}
