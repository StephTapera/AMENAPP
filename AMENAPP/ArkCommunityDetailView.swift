//
//  ArkCommunityDetailView.swift
//  AMENAPP
//
//  Full community page — posts feed, members list, about tab.
//  Mirrors the Threads communities detail experience.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Detail ViewModel

@MainActor
final class CommunityDetailViewModel: ObservableObject {

    let community: ArkCommunity

    @Published var posts: [ArkPost] = []
    @Published var members: [ArkMember] = []
    @Published var currentMember: ArkMember?
    @Published var isMember = false
    @Published var isLoading = false
    @Published var isPosting = false
    @Published var errorMessage: String?

    private let service = ArkService.shared
    private var postsListener: ListenerRegistration?

    init(community: ArkCommunity) {
        self.community = community
    }

    deinit { postsListener?.remove() }

    // MARK: Load

    func load() async {
        guard let communityId = community.id,
              let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        async let memberFetch = service.fetchMember(userId: uid, communityId: communityId)
        async let postsFetch  = service.fetchPosts(communityId: communityId)

        currentMember = try? await memberFetch
        isMember = currentMember != nil
        posts     = (try? await postsFetch) ?? []
        startPostsListener(communityId: communityId)
    }

    func loadMembers() async {
        guard let communityId = community.id else { return }
        members = (try? await service.fetchMembers(communityId: communityId)) ?? []
    }

    // MARK: Join / Leave

    func join() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let communityId = community.id else { return }
        let now = Timestamp(date: Date())
        let member = ArkMember(
            id: nil, userId: uid, joinedAt: now, covenantSignedAt: now,
            arkScore: 50.0, arkScoreBreakdown: .empty,
            warningCount: 0, lastWarningReason: nil, status: "active"
        )
        do {
            try await service.joinCommunity(member: member, communityId: communityId)
            currentMember = member
            isMember = true
            dlog("✅ Joined community \(communityId)")
        } catch {
            errorMessage = "Couldn't join. Please try again."
        }
    }

    func leave() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let communityId = community.id else { return }
        do {
            try await service.leaveCommunity(userId: uid, communityId: communityId)
            currentMember = nil
            isMember = false
            dlog("✅ Left community \(communityId)")
        } catch {
            errorMessage = "Couldn't leave. Please try again."
        }
    }

    // MARK: Post

    func submitPost(content: String, isAnonymous: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid,
              isMember,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        let post = ArkPost(
            id: nil, userId: uid, content: content,
            createdAt: Timestamp(date: Date()), aiModerationStatus: "pending_review",
            aiModerationReason: nil, aiCovenantViolations: nil,
            communityReports: 0, isAnonymous: isAnonymous
        )
        do {
            try await service.submitPost(post, community: community)
        } catch {
            errorMessage = "Couldn't submit post."
        }
    }

    // MARK: Real-time

    private func startPostsListener(communityId: String) {
        postsListener?.remove()
        postsListener = Firestore.firestore()
            .collection("arkCommunities").document(communityId)
            .collection("posts")
            .whereField("aiModerationStatus", isEqualTo: "approved")
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                Task { @MainActor in
                    self.posts = snap.documents.compactMap { try? $0.data(as: ArkPost.self) }
                }
            }
    }
}

// MARK: - Category Helpers

private extension ArkCommunity {
    var categoryDisplayName: String {
        switch category {
        case "small_group": return "Small Group"
        case "ministry":    return "Ministry"
        case "recovery":    return "Recovery"
        case "study":       return "Study"
        case "prayer":      return "Prayer"
        default:            return category.capitalized
        }
    }

    var categoryColor: Color {
        switch category {
        case "small_group": return .blue
        case "ministry":    return .purple
        case "recovery":    return .orange
        case "study":       return .green
        case "prayer":      return .indigo
        default:            return .accentColor
        }
    }

    var categoryIcon: String {
        switch category {
        case "small_group": return "person.3.fill"
        case "ministry":    return "star.fill"
        case "recovery":    return "heart.fill"
        case "study":       return "book.fill"
        case "prayer":      return "hands.sparkles.fill"
        default:            return "person.3.fill"
        }
    }

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()
    }
}

// MARK: - Main View

struct ArkCommunityDetailView: View {
    @StateObject private var vm: CommunityDetailViewModel
    @State private var selectedTab = 0          // 0=Posts 1=Members 2=About
    @State private var showCovenant = false
    @State private var showLeaveConfirm = false
    @State private var postText = ""
    @State private var isAnonymousPost = false
    @FocusState private var composerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(community: ArkCommunity) {
        _vm = StateObject(wrappedValue: CommunityDetailViewModel(community: community))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Community header
                communityHeader

                // Tab bar
                tabBar

                // Tab content
                ZStack {
                    switch selectedTab {
                    case 0: postsTab
                    case 1: membersTab
                    default: aboutTab
                    }
                }

                // Compose bar (posts tab, members only)
                if selectedTab == 0, vm.isMember {
                    composeBar
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isMember {
                        Button {
                            showLeaveConfirm = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showCovenant) {
                CommunityCovenantView {
                    Task { await vm.join() }
                    showCovenant = false
                }
            }
            .confirmationDialog(
                "Leave \(vm.community.name)?",
                isPresented: $showLeaveConfirm,
                titleVisibility: .visible
            ) {
                Button("Leave Community", role: .destructive) {
                    Task { await vm.leave() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - Header

    private var communityHeader: some View {
        VStack(spacing: 0) {
            // Gradient banner
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                vm.community.categoryColor.opacity(0.8),
                                vm.community.categoryColor.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 90)

                // Community avatar
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                    Text(vm.community.initials)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(vm.community.categoryColor)
                }
                .offset(x: 20, y: 36)
            }

            // Info row
            HStack(alignment: .top) {
                // Spacer for avatar offset
                Spacer().frame(width: 108)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(vm.community.name)
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.primary)
                        if vm.community.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                        }
                    }

                    HStack(spacing: 8) {
                        // Category pill
                        Label(vm.community.categoryDisplayName, systemImage: vm.community.categoryIcon)
                            .font(AMENFont.semiBold(11))
                            .foregroundStyle(vm.community.categoryColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(vm.community.categoryColor.opacity(0.12), in: Capsule())

                        Text("\(vm.community.memberCount) members")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Join / Joined button
                joinButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 42)
            .padding(.bottom, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var joinButton: some View {
        if vm.isLoading {
            ProgressView().frame(width: 80, height: 32)
        } else if vm.isMember {
            Button {
                showLeaveConfirm = true
            } label: {
                Text("Joined")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                    .frame(width: 80, height: 32)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                HapticManager.impact(style: .medium)
                showCovenant = true
            } label: {
                Text("Join")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 32)
                    .background(vm.community.categoryColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(["Posts", "Members", "About"].indices, id: \.self) { i in
                let label = ["Posts", "Members", "About"][i]
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = i }
                    if i == 1 && vm.members.isEmpty {
                        Task { await vm.loadMembers() }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(label)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(selectedTab == i ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(selectedTab == i ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Posts Tab

    private var postsTab: some View {
        Group {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.posts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text(vm.isMember ? "Be the first to post!" : "Join to see community posts")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.secondary)
                    if !vm.isMember {
                        Button {
                            showCovenant = true
                        } label: {
                            Text("Join Community")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(vm.community.categoryColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.posts) { post in
                            ArkPostCard(post: post, community: vm.community)
                            Divider().opacity(0.25)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 12) {
                // Anonymous toggle
                Button {
                    isAnonymousPost.toggle()
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: isAnonymousPost ? "person.fill.questionmark" : "person.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isAnonymousPost ? .secondary : vm.community.categoryColor)
                }
                .buttonStyle(.plain)

                TextField("Share with the community…", text: $postText, axis: .vertical)
                    .font(AMENFont.regular(14))
                    .focused($composerFocused)
                    .lineLimit(1...5)

                if !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        let content = postText
                        let anon = isAnonymousPost
                        postText = ""
                        composerFocused = false
                        Task { await vm.submitPost(content: content, isAnonymous: anon) }
                        HapticManager.impact(style: .medium)
                    } label: {
                        if vm.isPosting {
                            ProgressView().frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(vm.community.categoryColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: postText.isEmpty)
    }

    // MARK: - Members Tab

    private var membersTab: some View {
        Group {
            if vm.members.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading members…")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.members) { member in
                            MemberRow(member: member, community: vm.community)
                            Divider()
                                .padding(.leading, 64)
                                .opacity(0.25)
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {

                // Description
                infoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(vm.community.description)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Covenant principles
                if !vm.community.covenantPrinciples.isEmpty {
                    infoCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Covenant Principles")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(Array(vm.community.covenantPrinciples.enumerated()), id: \.offset) { i, principle in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)")
                                        .font(AMENFont.bold(12))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(vm.community.categoryColor, in: Circle())
                                    Text(principle)
                                        .font(AMENFont.regular(14))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                // Stats row
                infoCard {
                    HStack(spacing: 0) {
                        statBlock(value: "\(vm.community.memberCount)", label: "Members")
                        Divider().frame(height: 36)
                        statBlock(value: vm.community.categoryDisplayName, label: "Category")
                        Divider().frame(height: 36)
                        statBlock(
                            value: vm.community.aiModerationLevel.capitalized,
                            label: "Moderation"
                        )
                    }
                }

                // Moderation level note
                infoCard {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(vm.community.categoryColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI-Assisted Moderation")
                                .font(AMENFont.semiBold(14))
                            Text("Posts are reviewed by AMEN's covenant AI before appearing in the community feed.")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AMENFont.bold(15))
                .foregroundStyle(.primary)
            Text(label)
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ArkPost Card

private struct ArkPostCard: View {
    let post: ArkPost
    let community: ArkCommunity

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(post.createdAt.dateValue())
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(post.isAnonymous ? Color.secondary.opacity(0.2) : community.categoryColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: post.isAnonymous ? "person.fill.questionmark" : "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(post.isAnonymous ? .secondary : community.categoryColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(post.isAnonymous ? "Anonymous" : "Community Member")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(timeAgo)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Text(post.content)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if post.aiModerationStatus == "pending_review" {
                    Label("Under review", systemImage: "clock.badge")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: ArkMember
    let community: ArkCommunity

    private var arkScoreColor: Color {
        switch member.arkScore {
        case 80...: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            ZStack {
                Circle()
                    .fill(community.categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(community.categoryColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Member")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                Text("Joined \(member.joinedAt.dateValue().formatted(date: .abbreviated, time: .omitted))")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Ark score pill
            Text("\(Int(member.arkScore))")
                .font(AMENFont.bold(12))
                .foregroundStyle(arkScoreColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(arkScoreColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
