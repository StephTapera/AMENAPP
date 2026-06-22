import SwiftUI

/// Main Amen Object Hub view — a Liquid Glass surface centered on a canonical object.
/// Presents 10 sections: background, nav, hero, action dock, activity strip,
/// topic chips, hub content, discussion prompts, related objects, bottom dock.
///
/// Entry point: use AmenObjectHubView(canonicalObjectId:) or AmenObjectHubView(url:).
/// Constraint: this view is self-contained and does NOT modify any other view in the app.
struct AmenObjectHubView: View {
    // MARK: - Init modes
    let canonicalObjectId: String?
    let url: String?

    @StateObject private var viewModel = AmenObjectHubViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showReportSheet = false
    @State private var showMuteConfirm = false
    @State private var pendingDiscussionPrompt: String?
    @State private var showDiscussionComposer = false
    @State private var showUseInPostSheet = false
    @State private var contentOffset: CGFloat = 0

    // Affordance / discussion room state (A7 thesis engine)
    @State private var affordances: [ObjectAffordance] = []
    @State private var isLoadingAffordances = false
    @State private var activeRoomType: ObjectDiscussionRoom.ObjectDiscussionRoomType = .discussion
    @State private var showDiscussionRoom = false

    init(canonicalObjectId: String) {
        self.canonicalObjectId = canonicalObjectId
        self.url = nil
    }

    init(url: String) {
        self.url = url
        self.canonicalObjectId = nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.isLoading {
                AmenObjectHubSkeletonView()
                    .transition(.opacity)
            } else if let hub = viewModel.hub, let canonical = viewModel.canonicalObject {
                hubContent(hub: hub, canonical: canonical)
                    .transition(.opacity)
            } else if let error = viewModel.error {
                AmenObjectHubErrorState(error: error) {
                    Task { await loadContent() }
                }
                .transition(.opacity)
            } else {
                AmenObjectHubEmptyState()
                    .transition(.opacity)
            }

            // Floating nav overlay
            floatingNav
        }
        .ignoresSafeArea(edges: .top)
        .task { await loadContent() }
        .sheet(isPresented: $showReportSheet) {
            AmenHubReportSheet { reason in
                Task { await viewModel.reportContent(reason: reason) }
            }
        }
        .alert("Mute this hub?", isPresented: $showMuteConfirm) {
            Button("Mute", role: .destructive) {
                Task { await viewModel.muteHub() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see posts from this hub in your feed.")
        }
    }

    // MARK: - Main Hub Content

    private func hubContent(hub: AmenCommunityHub, canonical: AmenCanonicalObject) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // 1. Hero header (includes background + artwork + identity)
                AmenObjectHubHeader(canonicalObject: canonical, hub: hub)

                VStack(spacing: 24) {
                    // 2. Affordance chips — above-the-fold relationship affordances
                    // Build pack thesis: every detail screen must expose a "join people" affordance above the fold.
                    if isLoadingAffordances {
                        AmenAffordanceChipRowSkeleton()
                    } else if !affordances.isEmpty {
                        AmenAffordanceChipRow(affordances: affordances) { affordance in
                            handleAffordanceTap(affordance)
                        }
                    }

                    // 3. Action dock
                    AmenObjectHubActionDock(
                        canonicalObject: canonical,
                        membership: viewModel.membership,
                        onListen: { handleListen(canonical: canonical) },
                        onSaveToSelah: { Task { await handleSaveToSelah() } },
                        onDiscuss: {
                            activeRoomType = .discussion
                            showDiscussionRoom = true
                        },
                        onUseInPost: { showUseInPostSheet = true }
                    )

                    // 4. Activity strip
                    AmenObjectHubActivityStrip(hub: hub)

                    // 5. Topic chips
                    if !hub.topicChips.isEmpty {
                        AmenObjectHubTopicChips(
                            chips: hub.topicChips,
                            selectedChip: $viewModel.selectedTopicChip
                        )
                    }

                    // 5. Hub stats summary
                    hubStatsSummary(hub: hub)
                        .padding(.horizontal, 16)

                    // 6. Discussion prompts — tap opens the discussion room
                    AmenObjectHubDiscussionPrompts(prompts: hub.discussionPrompts) { prompt in
                        pendingDiscussionPrompt = prompt
                        activeRoomType = .discussion
                        showDiscussionRoom = true
                    }

                    // 7. Related objects carousel
                    if !viewModel.relatedObjects.isEmpty {
                        AmenObjectHubRelatedCarousel(relatedObjects: viewModel.relatedObjects) { related in
                            handleRelatedObjectTap(related)
                        }
                    }

                    // 8. Safety banner (explicit/limited content)
                    if hub.explicitContentState == .limited || hub.explicitContentState == .explicit {
                        AmenObjectHubSafetyBanner(state: hub.explicitContentState)
                            .padding(.horizontal, 16)
                    }

                    // 9. Bottom dock (mute / report)
                    bottomDock
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
                .padding(.top, 20)
            }
        }
        .sheet(isPresented: $showDiscussionRoom) {
            if let canonical = viewModel.canonicalObject {
                AmenObjectDiscussionRoomView(
                    objectId:     canonical.id,
                    objectTitle:  canonical.title,
                    roomType:     activeRoomType,
                    existingRoom: nil
                )
            }
        }
        .sheet(isPresented: $showUseInPostSheet) {
            if let canonical = viewModel.canonicalObject {
                AmenUniversalComposerView(
                    source: composerSource(for: canonical),
                    onDismiss: { showUseInPostSheet = false }
                )
            }
        }
    }

    // MARK: - Floating Nav

    private var floatingNav: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background {
                        if reduceTransparency {
                            Circle().fill(.black.opacity(0.6))
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
            }
            .accessibilityLabel("Back")

            Spacer()

            HStack(spacing: 8) {
                // Join / Joined indicator
                if let hub = viewModel.hub {
                    joinButton(hub: hub)
                }

                // Share
                Button {
                    shareHub()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            if reduceTransparency {
                                Circle().fill(.black.opacity(0.6))
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                }
                .accessibilityLabel("Share hub")

                // Overflow menu
                Menu {
                    Button("Mute Hub", systemImage: "bell.slash") {
                        showMuteConfirm = true
                    }
                    Button("Report Content", systemImage: "flag", role: .destructive) {
                        showReportSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            if reduceTransparency {
                                Circle().fill(.black.opacity(0.6))
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                }
                .accessibilityLabel("More options")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    // MARK: - Join Button

    private func joinButton(hub: AmenCommunityHub) -> some View {
        let hasJoined = viewModel.membership?.hasJoined ?? false
        return Button {
            Task {
                if hasJoined {
                    // Already joined — no action needed, handled via mute/leave flow
                } else {
                    await viewModel.joinHub()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasJoined ? "checkmark" : "plus")
                    .font(.systemScaled(11, weight: .bold))
                Text(hasJoined ? "Joined" : "Join")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if reduceTransparency {
                    Capsule().fill(hasJoined ? Color.clear : Color.accentColor)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: hasJoined ? 1 : 0))
                } else {
                    Capsule().fill(hasJoined ? AnyShapeStyle(Material.ultraThinMaterial) : AnyShapeStyle(Color.accentColor))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasJoined ? "Joined hub" : "Join hub")
    }

    // MARK: - Hub Stats Summary

    private func hubStatsSummary(hub: AmenCommunityHub) -> some View {
        HStack(spacing: 0) {
            statItem(label: "Members", value: formatCount(hub.totalMembers))
            Divider().frame(height: 32)
            statItem(label: "Posts", value: formatCount(hub.totalPostCount))
            Divider().frame(height: 32)
            statItem(label: "This Week", value: formatCount(hub.weeklyPostCount))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.systemScaled(18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Dock

    private var bottomDock: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 16) {
                Button {
                    showMuteConfirm = true
                } label: {
                    Label("Mute Hub", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mute this hub")

                Spacer()

                Button {
                    showReportSheet = true
                } label: {
                    Label("Report", systemImage: "flag")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Report hub content")
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Affordance Handlers

    private func handleAffordanceTap(_ affordance: ObjectAffordance) {
        switch affordance.kind {
        case .discussion:     activeRoomType = .discussion
        case .prayerRoom:     activeRoomType = .prayer
        case .studyGroup:     activeRoomType = .studyGroup
        case .membersPresent, .liveNow: activeRoomType = .discussion
        }
        showDiscussionRoom = true
        Task { await viewModel.recordInteraction(.discussed) }
    }

    private func loadAffordances(for canonical: AmenCanonicalObject) async {
        isLoadingAffordances = true
        affordances = await AmenObjectDiscussionService.shared.buildAffordances(
            objectId:    canonical.id,
            objectTitle: canonical.title
        )
        isLoadingAffordances = false
    }

    // MARK: - Action Handlers

    private func handleListen(canonical: AmenCanonicalObject) {
        guard let urlString = canonical.canonicalUrl, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
        Task { await viewModel.recordInteraction(.listened) }
    }

    private func handleSaveToSelah() async {
        guard let attachment = buildAttachment() else { return }
        try? await AmenMediaGraphService.shared.saveToSelah(attachment, sourcePostId: nil)
        await viewModel.recordInteraction(.saved)
    }

    private func handleRelatedObjectTap(_ object: AmenCanonicalObject) {
        guard let hubId = object.hubId ?? object.id as String? else { return }
        // Navigation handled externally — here we just reload the view model
        Task { await viewModel.loadHub(canonicalObjectId: hubId) }
    }

    private func shareHub() {
        guard let hub = viewModel.hub,
              let canonical = viewModel.canonicalObject else { return }
        let text = "Check out the \(canonical.title) hub on AMEN — \(hub.totalMembers) members sharing and praying together."
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.rootViewController?.present(vc, animated: true)
        }
    }

    private func buildAttachment() -> AmenSmartAttachment? {
        guard let canonical = viewModel.canonicalObject else { return nil }
        let provider = canonical.primaryProvider ?? .generic
        let providerId = canonical.providerIds[provider.rawValue]
        let artType: AmenAttachmentType = attachmentType(canonical.objectType)

        return AmenSmartAttachment(
            id: "hub_\(canonical.id)",
            postId: nil,
            provider: provider,
            type: artType,
            providerId: providerId,
            title: canonical.title,
            subtitle: canonical.subtitle,
            creatorName: canonical.creatorName,
            description: nil,
            artworkUrl: canonical.artworkUrl,
            canonicalUrl: canonical.canonicalUrl ?? "",
            durationMs: nil,
            previewUrl: nil,
            attributionText: canonical.primaryProvider?.rawValue ?? "AMEN",
            sourceLogoRequired: canonical.primaryProvider != nil,
            playbackPolicy: .externalOnly,
            safetyStatus: canonical.safetyStatus,
            smartActions: [.saveToSelah, .addToChurchNotes, .saveForLater],
            soundtrackEnabled: false,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func attachmentType(_ objectType: AmenSmartObjectType) -> AmenAttachmentType {
        switch objectType {
        case .mediaTrack: return .song
        case .album: return .album
        case .playlist: return .playlist
        case .artist: return .artist
        case .video: return .video
        case .podcast: return .podcast
        case .article: return .article
        default: return .genericLink
        }
    }

    private func composerSource(for canonical: AmenCanonicalObject) -> ComposerSource {
        ComposerSource(
            type: composerSourceType(for: canonical.objectType),
            existingRef: "canonicalObjects/\(canonical.id)",
            existingOwnerId: nil,
            prefillText: smartComposerPrefill(for: canonical),
            prefillTitle: canonical.title
        )
    }

    private func composerSourceType(for objectType: AmenSmartObjectType) -> ComposerSourceType {
        switch objectType {
        case .event:
            return .event
        case .scripture:
            return .scriptureReference
        case .mediaTrack, .album, .playlist, .artist, .video, .podcast, .article, .genericLink:
            return .mediaObject
        case .person, .place:
            return .newPost
        }
    }

    private func smartComposerPrefill(for canonical: AmenCanonicalObject) -> String {
        let attribution = canonical.creatorName ?? canonical.subtitle
        let titleLine = attribution.map { "\(canonical.title) by \($0)" } ?? canonical.title

        switch canonical.contentCategory {
        case .worship, .music:
            return "This stood out to me from \(titleLine): "
        case .sermon, .devotional, .educational, .scripture:
            return "A thought worth discussing from \(titleLine): "
        case .prayer, .testimony:
            return "I want to invite prayer around \(titleLine): "
        default:
            return "Sharing \(titleLine) because "
        }
    }

    // MARK: - Load

    private func loadContent() async {
        if let id = canonicalObjectId {
            await viewModel.loadHub(canonicalObjectId: id)
        } else if let u = url {
            await viewModel.resolveAndLoad(url: u)
        }
        if let canonical = viewModel.canonicalObject {
            await loadAffordances(for: canonical)
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }
}

// MARK: - Supporting Sheets

private struct AmenHubReportSheet: View {
    let onReport: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason = ""
    private let reasons = ["Inappropriate content", "Spam", "Misleading information", "Harmful content", "Other"]

    var body: some View {
        NavigationStack {
            List(reasons, id: \.self) { reason in
                Button(reason) {
                    onReport(reason)
                    dismiss()
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Error / Empty States

struct AmenObjectHubErrorState: View {
    let error: AmenObjectHubViewModel.AmenHubError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(40))
                .foregroundStyle(.secondary)
            Text(error.errorDescription ?? "Something went wrong")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

struct AmenObjectHubEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "circle.dotted")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)
            Text("No hub found for this content yet.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

struct AmenObjectHubSafetyBanner: View {
    let state: AmenExplicitContentState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.orange)
            Text(state == .explicit
                 ? "This hub contains explicit content."
                 : "Some content in this hub has been limited.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .accessibilityLabel("Safety notice: \(state.rawValue) content warning")
    }
}
