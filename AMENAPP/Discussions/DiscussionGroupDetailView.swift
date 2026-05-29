// DiscussionGroupDetailView.swift
// AMENAPP — Discussions
//
// Apple Music "Album page" assembled view for a group.
// Rendered when AMENFeatureFlags.shared.discussionAlbumUIEnabled == true.
//
// Navigation hierarchy: hero → channel list → ThreadDetailView (untouched)
// "More from org" shelf at bottom points back to other groups.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DiscussionGroupDetailView: View {
    let group: CommunityGroup
    var onEnterChannel: (DiscussionChannel) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var libraryService = DiscussionGroupLibraryService.shared
    @State private var channels: [DiscussionChannel] = []
    @State private var isLoadingChannels = true
    @State private var scrollOffset: CGFloat = 0
    @State private var joinInFlight = false
    @State private var showLeaveConfirm = false

    private var db: Firestore { Firestore.firestore() }
    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var isMember: Bool {
        guard currentUid != nil else { return false }
        return libraryService.addedGroups.first { $0.id == group.id }?.isJoined ?? false
    }

    private var notificationsOn: Bool {
        libraryService.notificationsEnabled(for: group.id)
    }

    private var collapseProgress: CGFloat {
        let startCollapse: CGFloat = 40
        let fullCollapse: CGFloat = 160
        let offset = max(0, -scrollOffset)
        return min(1, max(0, (offset - startCollapse) / (fullCollapse - startCollapse)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: DiscussionScrollOffsetKey.self,
                            value: geo.frame(in: .named("discussion_detail")).minY
                        )
                }
                .frame(height: 0)

                VStack(spacing: 0) {
                    DiscussionHeroHeader(
                        groupId: group.id,
                        groupName: group.name,
                        category: group.category.rawValue,
                        memberCount: group.memberCount,
                        isPrivate: group.isPrivate,
                        coverImageURL: group.coverImageURL,
                        isMember: isMember,
                        notificationsOn: notificationsOn,
                        onOpen: { openFirstChannel() },
                        onNotify: { toggleNotifications() },
                        onJoinOrLeave: {
                            if isMember { showLeaveConfirm = true }
                            else { Task { await joinGroup() } }
                        }
                    )
                    .collapseProgress(collapseProgress)

                    channelListSection
                        .padding(.top, 8)

                    if AMENFeatureFlags.shared.discussionMoreFromOrgShelfEnabled {
                        DiscussionMoreFromOrgShelf(
                            currentGroupId: group.id,
                            organizationId: nil,
                            category: group.category.rawValue
                        )
                        .padding(.top, 24)
                    }

                    Spacer().frame(height: 100)
                }
            }
            .coordinateSpace(name: "discussion_detail")
            .onPreferenceChange(DiscussionScrollOffsetKey.self) { scrollOffset = $0 }
            .background(Color(.systemBackground))

            // Floating back button
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                }
                .accessibilityLabel("Back")
                .padding(.leading, 16)
                .padding(.top, 56)

                Spacer()

                Button {
                    ShareRouter.presentGroup(group, sourceSurface: "discussion_detail")
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                }
                .accessibilityLabel("Share group")
                .padding(.trailing, 16)
                .padding(.top, 56)
            }
            .opacity(1 - min(1, collapseProgress * 3))
        }
        .navigationBarHidden(true)
        .task {
            await loadChannels()
            libraryService.startListening()
        }
        .confirmationDialog(
            "Leave \(group.name)?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Group", role: .destructive) {
                Task { await leaveGroup() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Channel list section

    private var channelListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Channels")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.bottom, 6)

            if isLoadingChannels {
                channelSkeleton
            } else if channels.isEmpty {
                emptyChannels
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { idx, ch in
                        DiscussionChannelRow(
                            channel: ch,
                            index: idx,
                            onSelect: onEnterChannel,
                            onCopyLink: { _ in },
                            onMarkRead: { _ in }
                        )
                        .staggeredReveal(index: idx, baseDelay: 0.04)

                        if idx < channels.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    private var channelSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(.systemFill))
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill))
                            .frame(width: 120, height: 13)
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemFill))
                            .frame(width: 80, height: 11)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
        .shimmering()
    }

    private var emptyChannels: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No channels yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Channels will appear here once the group is set up.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Data loading

    private func loadChannels() async {
        isLoadingChannels = true
        defer { isLoadingChannels = false }

        // Fetch channels for this group from conversations sub-structure.
        // Falls back to synthetic channels built from the group's purpose/category.
        do {
            let snapshot = try await db.collection("conversations")
                .document(group.id)
                .collection("channels")
                .order(by: "sortOrder")
                .getDocuments()

            if snapshot.documents.isEmpty {
                channels = syntheticChannels(for: group)
            } else {
                channels = snapshot.documents.compactMap { doc -> DiscussionChannel? in
                    let data = doc.data()
                    return DiscussionChannel(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "Channel",
                        description: data["description"] as? String ?? "",
                        icon: data["icon"] as? String ?? "bubble.left.fill",
                        unreadCount: data["unreadCount"] as? Int ?? 0,
                        isPinned: data["isPinned"] as? Bool ?? false,
                        isLocked: data["isLocked"] as? Bool ?? false,
                        lastActivityAt: (data["lastActivityAt"] as? Timestamp)?.dateValue()
                    )
                }
            }
        } catch {
            channels = syntheticChannels(for: group)
        }
    }

    // Synthesize sensible default channels from the group category when none exist yet
    private func syntheticChannels(for group: CommunityGroup) -> [DiscussionChannel] {
        let defaults: [(String, String, String)] = {
            switch group.category {
            case .bible:
                return [
                    ("General",       "Welcome & discussion",        "house.fill"),
                    ("Study Notes",   "This week's passages",        "book.fill"),
                    ("Prayer Requests", "Share your prayer needs",   "hands.sparkles.fill"),
                    ("Q&A",           "Questions & answers",         "questionmark.circle.fill"),
                ]
            case .prayer:
                return [
                    ("General",       "Welcome",                     "house.fill"),
                    ("Prayer Wall",   "Post your requests",          "hands.sparkles.fill"),
                    ("Answered",      "Praise reports",              "checkmark.seal.fill"),
                ]
            case .worship:
                return [
                    ("General",       "Welcome",                     "house.fill"),
                    ("Song Discussion","Talk about this week's songs","music.note"),
                    ("Requests",      "Request songs",               "list.bullet"),
                ]
            default:
                return [
                    ("General",       "Main discussion",             "house.fill"),
                    ("Announcements", "Important updates",           "megaphone.fill"),
                    ("Prayer Requests","Share your needs",           "hands.sparkles.fill"),
                ]
            }
        }()
        return defaults.enumerated().map { idx, t in
            DiscussionChannel(id: "synth_\(idx)", name: t.0, description: t.1,
                              icon: t.2, unreadCount: 0, isPinned: idx == 0,
                              isLocked: false, lastActivityAt: nil)
        }
    }

    // MARK: - Actions

    private func openFirstChannel() {
        if let ch = channels.first { onEnterChannel(ch) }
    }

    private func toggleNotifications() {
        Task {
            let isOn = notificationsOn
            try? await libraryService.setNotifications(groupId: group.id, enabled: !isOn)
            await AmenHapticEngine.shared.play(.encouragement)
        }
    }

    private func joinGroup() async {
        guard !joinInFlight else { return }
        joinInFlight = true
        defer { joinInFlight = false }
        do {
            try await libraryService.addGroup(group)
            try await libraryService.markJoined(groupId: group.id)
            await AmenHapticEngine.shared.play(.connectionMade)
        } catch {}
    }

    private func leaveGroup() async {
        try? await libraryService.removeGroup(groupId: group.id)
    }
}

// MARK: - Helpers

private struct DiscussionScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Adds collapseProgress modifier to hero without changing the struct's interface
private extension DiscussionHeroHeader {
    func collapseProgress(_ progress: CGFloat) -> DiscussionHeroHeader {
        var copy = self
        copy.collapseProgress = progress
        return copy
    }
}

// MARK: - Shimmer modifier (lightweight; uses onAppear phase animation)

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.35),
                        Color.white.opacity(0),
                    ],
                    startPoint: UnitPoint(x: phase - 0.3, y: 0),
                    endPoint: UnitPoint(x: phase + 0.3, y: 0)
                )
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

private extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Preview

#Preview {
    let group = CommunityGroup(
        id: "preview_group",
        name: "Morning Scripture Circle",
        description: "Daily devotions and study.",
        category: .bible,
        creatorId: "uid_1",
        memberCount: 234,
        coverImageURL: nil,
        isPrivate: false,
        createdAt: Date(),
        rules: []
    )
    NavigationStack {
        DiscussionGroupDetailView(group: group)
    }
}
