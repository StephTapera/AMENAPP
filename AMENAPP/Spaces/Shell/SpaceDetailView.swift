// SpaceDetailView.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// Hero-profile style Space detail view.
// Header: avatar, title, description, member preview, SharedCommunityBanner pills.
// Body: type-driven — .chat/.group use B's ThreadListView; .bibleStudy stub for D;
//       .announcement stub for D.
// Locked state: LockedPreviewShell overlay; onUnlock wired to E's SpacesPurchaseSheet.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
struct SpaceDetailView: View {

    let space: AmenSpaceExtended
    let communityId: String

    // MARK: State

    @State private var members: [SpaceCommunityMember] = []
    @State private var isLoadingMembers: Bool = false
    @State private var showMemberRoster: Bool = false
    @State private var isLocked: Bool = false
    @State private var isCheckingEntitlement: Bool = true

    // Shared community name resolution.
    // F's acceptCommunityLink writes community names into the sharedWith array;
    // call site (or Agent F's Links layer) passes pre-resolved names via this state.
    // SpaceDetailView re-renders SharedCommunityBanner whenever space.sharedWith changes.
    @State private var sharedCommunityNames: [String: String] = [:]

    // Agent E's purchase sheet — LockedPreviewShell sets this to true via onUnlock.
    @State private var showPurchaseSheet: Bool = false

    // Agent F: cross-community link state
    // LinkInviteSheet — shown from the "Link another community" toolbar action (admin/owner only).
    @State private var showLinkInviteSheet: Bool = false
    // CrossCommunityViewModel drives the real-time sharedWith stream + revoked banner.
    @StateObject private var crossCommunityVM = CrossCommunityViewModel()

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            mainScrollContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }

            // Locked overlay — full-screen LockedPreviewShell, wired to E's purchase sheet
            if isLocked && !isCheckingEntitlement {
                LockedPreviewShell(space: space) {
                    showPurchaseSheet = true
                }
                .transition(.opacity)
            }

            // Agent F: LinkRevokedBanner — shown when external members' link is revoked mid-session.
            // Driven by CrossCommunityViewModel.showRevokedBanner.
            // Non-blocking, auto-dismisses after 5 seconds.
            VStack {
                LinkRevokedBanner(isVisible: $crossCommunityVM.showRevokedBanner)
                    .padding(.top, 8)
                Spacer()
            }
            .allowsHitTesting(crossCommunityVM.showRevokedBanner)
        }
        .task {
            await checkEntitlement()
            await loadMembers()
            // Agent F: start real-time sharedWith stream.
            if let spaceId = space.id {
                crossCommunityVM.startListening(spaceId: spaceId)
            }
        }
        .onDisappear {
            crossCommunityVM.stopListening()
        }
        .sheet(isPresented: $showMemberRoster) {
            MemberRosterSheet(
                members: members,
                localCommunityId: communityId,
                isPresented: $showMemberRoster,
                communityNames: sharedCommunityNames
            )
        }
        // E's purchase sheet — presented when LockedPreviewShell calls onUnlock
        .sheet(isPresented: $showPurchaseSheet) {
            if let userId = Auth.auth().currentUser?.uid {
                SpacesPurchaseSheet(
                    space: space,
                    userId: userId,
                    isPresented: $showPurchaseSheet
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .animation(Motion.liquidSpring, value: isLocked)
        // Agent F: LinkInviteSheet — presented from the "Link a community" toolbar button.
        .sheet(isPresented: $showLinkInviteSheet) {
            if let spaceId = space.id {
                LinkInviteSheet(
                    spaceId: spaceId,
                    spaceTitle: space.title,
                    communityId: communityId,
                    isPresented: $showLinkInviteSheet
                )
            }
        }
    }

    // MARK: - Main scroll content

    private var mainScrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                    .padding(.bottom, 16)

                typeBody
                    // No extra horizontal padding — type bodies own their own layout
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 0) {
            spaceAvatarHeader

            VStack(alignment: .leading, spacing: 8) {
                Text(space.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let desc = space.description, !desc.isEmpty {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(3)

                    SpaceFaithMetadataRow(
                        spaceType: space.type,
                        memberCount: members.count,
                        bibleVersion: space.type == .bibleStudy ? "KJV" : nil,
                        liturgicalSeason: nil,
                        churchBadge: nil
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if !members.isEmpty || isLoadingMembers {
                memberPreviewRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            // SharedCommunityBanner pills.
            // Driven by space.sharedWith (denormalized).
            // Agent F's revokeCommunityLink removes an entry from sharedWith;
            // this view re-renders automatically via Firestore listener in the parent VM.
            if !space.sharedWith.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(space.sharedWith, id: \.self) { sharedId in
                        SharedCommunityBanner(
                            mode: .sharedWith(
                                communityName: sharedCommunityNames[sharedId] ?? sharedId
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }

            Divider()
                .padding(.top, 16)
        }
    }

    // MARK: - Avatar header (hero-profile style)

    @ViewBuilder
    private var spaceAvatarHeader: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let avatarURL = space.avatarURL, !avatarURL.isEmpty {
                    AsyncImage(url: URL(string: avatarURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            avatarGradient
                        }
                    }
                } else {
                    avatarGradient
                }
            }
            .frame(height: 220)
            .clipped()

            // Fade-to-background gradient at bottom
            LinearGradient(
                colors: [.clear, AmenTheme.Colors.backgroundPrimary],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)

            // 80pt type-icon avatar circle — offset so it bleeds below the image band
            ZStack {
                Circle()
                    .fill(LiquidGlassTokens.blurThin)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)

                Image(systemName: typeSystemImage)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
            .offset(y: 40)
            .accessibilityHidden(true)
        }
        .frame(height: 260)
        .accessibilityHidden(true)
    }

    private var avatarGradient: some View {
        LinearGradient(
            colors: [
                AmenTheme.Colors.amenPurple.opacity(0.60),
                AmenTheme.Colors.amenBlack
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Member preview row

    private var memberPreviewRow: some View {
        HStack(spacing: -8) {
            ForEach(Array(members.prefix(5).enumerated()), id: \.element.id) { idx, member in
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(AmenTheme.Colors.surfaceChip)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text(member.userId.prefix(1).uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        .overlay {
                            Circle().stroke(AmenTheme.Colors.backgroundPrimary, lineWidth: 2)
                        }
                        .zIndex(Double(5 - idx))

                    if let hcid = member.homeCommunityId, hcid != communityId {
                        LinkedGlyph(size: .small)
                            .scaleEffect(0.7)
                            .offset(x: 4, y: 4)
                    }
                }
                .accessibilityHidden(true)
            }

            if members.count > 5 {
                Text("+\(members.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.leading, 12)
            }

            Spacer(minLength: 0)

            Button {
                showMemberRoster = true
            } label: {
                Text("See all")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all members")
            .accessibilityHint("Opens the full member roster.")
        }
    }

    // MARK: - Type-driven body
    //
    // .chat / .group  → B's ThreadListView (live)
    // .bibleStudy     → stub for Agent D's StudyBlocksView
    // .announcement   → stub for Agent D's AnnouncementFeedView

    @ViewBuilder
    private var typeBody: some View {
        switch space.type {
        case .chat, .group:
            // Agent B's ThreadListView — canonical thread list for chat and group Spaces.
            // B's view owns its own filter tab row and navigation to ThreadDetailView.
            ThreadListView(spaceId: space.id ?? "", space: space)

        case .bibleStudy:
            // TODO(Agent D): Replace with StudyBlocksView(space: space)
            Text("Study coming from Agent D")
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.horizontal, 16)

        case .announcement:
            // TODO(Agent D): Replace with AnnouncementFeedView(space: space)
            Text("Announcements")
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            // Manage button — Admin/Owner only; Agent D wires settings destination.
            NavigationLink {
                // TODO(Agent D): Replace EmptyView with Space settings wizard.
                EmptyView()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .accessibilityLabel("Manage Space")
            .accessibilityHint("Opens Space settings.")
        }
        // Agent F: "Link another community" — admin/owner entry point for cross-community linking.
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showLinkInviteSheet = true
            } label: {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            }
            .accessibilityLabel("Link another community")
            .accessibilityHint("Opens the cross-community link management sheet.")
        }
    }

    // MARK: - Helpers

    private var typeSystemImage: String {
        switch space.type {
        case .chat:         return "number"
        case .bibleStudy:   return "book.closed.fill"
        case .group:        return "person.3.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    // MARK: - Data loading

    private func checkEntitlement() async {
        guard space.accessPolicy != .free else {
            isCheckingEntitlement = false
            isLocked = false
            return
        }
        guard let userId = Auth.auth().currentUser?.uid,
              let spaceId = space.id else {
            isCheckingEntitlement = false
            isLocked = true
            return
        }
        do {
            let entitlement = try await EntitlementService.shared.fetchEntitlement(
                userId: userId,
                spaceId: spaceId
            )
            isLocked = !(entitlement.map { $0.status == .active || $0.status == .grace } ?? false)
        } catch {
            isLocked = true
        }
        isCheckingEntitlement = false
    }

    private func loadMembers() async {
        guard let spaceId = space.id else { return }
        isLoadingMembers = true
        do {
            let snapshot = try await Firestore.firestore()
                .collection("spaces")
                .document(spaceId)
                .collection("members")
                .getDocuments()
            members = snapshot.documents.compactMap { doc -> SpaceCommunityMember? in
                let data = doc.data()
                guard
                    let roleStr   = data["role"] as? String,
                    let accessStr = data["access"] as? String,
                    let access    = SpaceCommunityMemberAccess(rawValue: accessStr)
                else { return nil }
                let homeCommunityId = data["homeCommunityId"] as? String
                let joinedAt        = (data["joinedAt"] as? Timestamp)?.dateValue()
                return SpaceCommunityMember(
                    userId: doc.documentID,
                    role: roleStr,
                    homeCommunityId: homeCommunityId,
                    access: access,
                    joinedAt: joinedAt
                )
            }
        } catch {
            // Non-fatal — empty roster is shown; no force-unwrap risk.
        }
        isLoadingMembers = false
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SpaceDetailView — chat, free") {
    NavigationStack {
        SpaceDetailView(
            space: AmenSpaceExtended(
                communityId: "community_1",
                type: .chat,
                title: "Welcome & Intros",
                description: "Introduce yourself and connect with others in this community.",
                avatarURL: nil,
                createdBy: "user_1",
                createdAt: Date(),
                accessPolicy: .free,
                priceConfig: nil,
                sharedWith: ["community_2"],
                isDeleted: false
            ),
            communityId: "community_1"
        )
    }
}

#Preview("SpaceDetailView — bibleStudy, locked") {
    NavigationStack {
        SpaceDetailView(
            space: AmenSpaceExtended(
                communityId: "community_1",
                type: .bibleStudy,
                title: "Deep Dive: Romans",
                description: "A weekly study of Paul's letter to the Romans.",
                avatarURL: nil,
                createdBy: "user_1",
                createdAt: Date(),
                accessPolicy: .recurring,
                priceConfig: PriceConfig(amountCents: 999, currency: "usd", interval: "month"),
                sharedWith: [],
                isDeleted: false
            ),
            communityId: "community_1"
        )
    }
}
#endif
