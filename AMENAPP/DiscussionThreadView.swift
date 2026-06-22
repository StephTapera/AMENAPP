// DiscussionThreadView.swift — AMEN App
// Full discussion thread UI with Phase 2 Discussion OS integration.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ViewModel

@MainActor
final class DiscussionThreadViewModel: ObservableObject {
    @Published var thread: DiscussionThread?
    @Published var comments: [DiscussionComment] = []
    @Published var bereanSummary: BereanThreadSummary?
    @Published var reputation: DiscussionReputationTier = .none
    @Published var isLoadingThread     = false
    @Published var isLoadingBerean     = false
    @Published var isSending           = false
    @Published var duplicateHint: DiscussionDuplicateResult = .clean
    @Published var errorMessage: String?
    @Published var helpfulSent: Set<String> = []

    // Discussion OS
    @Published var mode: DiscussionMode = .general
    @Published var healthSnapshot: DiscussionHealthSnapshot?
    @Published var participationTier: ParticipationTier = .observer
    @Published var isSlowModeActive: Bool = false
    @Published var slowModeSecondsLeft: Int = 0

    // Community OS A6 — Discussion provenance
    /// Optional spawn provenance. Set by callers that opened this thread from another object.
    /// Nil by default so all existing callers are unaffected.
    /// When non-nil and communityOSDiscussionEnabled is true, a DiscussionProvenanceBanner
    /// is rendered at the top of the thread scroll view.
    var provenance: SpawnProvenance? = nil

    private let service = DiscussionThreadService.shared
    private var commentListener: ListenerRegistration?
    private var threadListener:  ListenerRegistration?
    private var summaryListener: ListenerRegistration?
    private var dupTask: Task<Void, Never>?
    private var slowModeTask: Task<Void, Never>?

    deinit {
        // B-029: Remove Firestore listeners so they don't keep streaming after the
        // ViewModel is deallocated. Matches the pattern in CreatorEditorViewModel.
        commentListener?.remove()
        threadListener?.remove()
        summaryListener?.remove()
    }

    // MARK: Start

    func start(postId: String, postTitle: String?) async {
        isLoadingThread = true
        do {
            let t = try await service.getOrCreateThread(postId: postId, postTitle: postTitle)
            thread = t
            wireListeners(threadId: postId, summaryPath: t.bereanSummaryRef)
            reputation = (try? await service.fetchReputation()) ?? .none

            mode = (try? await DiscussionModeService.shared.getMode(threadId: postId)) ?? .general
            participationTier = await DiscussionParticipationService.shared.getTier(threadId: postId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingThread = false
    }

    private func wireListeners(threadId: String, summaryPath: String?) {
        commentListener = service.listenComments(threadId: threadId) { [weak self] in
            self?.comments = $0
        }
        threadListener = service.listenThread(threadId: threadId) { [weak self] t in
            guard let self, let t else { return }
            self.thread = t
            if let path = t.bereanSummaryRef, self.summaryListener == nil {
                self.summaryListener = self.service.listenBereanSummary(path: path) { [weak self] in
                    self?.bereanSummary = $0
                }
            }
        }
        if let path = summaryPath {
            summaryListener = service.listenBereanSummary(path: path) { [weak self] in
                self?.bereanSummary = $0
            }
        }
    }

    // MARK: Ask Berean

    func askBerean() {
        guard let tid = thread?.id else { return }
        isLoadingBerean = true
        Task {
            defer { isLoadingBerean = false }
            do {
                bereanSummary = try await service.askBerean(threadId: tid)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Duplicate detection (debounced)

    func onBodyChanged(_ body: String) {
        dupTask?.cancel()
        duplicateHint = .clean
        guard body.count >= 20, let tid = thread?.id else { return }
        dupTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            duplicateHint = (try? await service.detectDuplicate(threadId: tid, draftBody: body)) ?? .clean
        }
    }

    // MARK: Post comment

    func send(body: String, destination: DiscussionDestination) async {
        guard let tid = thread?.id else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await service.postComment(threadId: tid, body: trimmed, destination: destination)
            duplicateHint = .clean
            participationTier = await DiscussionParticipationService.shared.getTier(threadId: tid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Mark helpful

    func markHelpful(comment: DiscussionComment) {
        guard let tid = thread?.id, let cid = comment.id else { return }
        guard !helpfulSent.contains(cid) else { return }
        helpfulSent.insert(cid)
        Task {
            try? await service.markHelpful(threadId: tid, commentId: cid)
        }
    }

    // MARK: Action handling

    func handleAction(_ action: DiscussionAction, on comment: DiscussionComment) {
        switch action {
        case .markHelpful:
            markHelpful(comment: comment)
        default:
            break
        }
        guard let tid = thread?.id else { return }
        Task { participationTier = await DiscussionParticipationService.shared.getTier(threadId: tid) }
    }

    // MARK: Slow mode

    func activateSlowMode(seconds: Int = 30) {
        guard !isSlowModeActive else { return }
        isSlowModeActive = true
        slowModeSecondsLeft = seconds
        slowModeTask?.cancel()
        slowModeTask = Task {
            while slowModeSecondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                slowModeSecondsLeft -= 1
            }
            isSlowModeActive = false
        }
    }
}

// MARK: - Main View

struct DiscussionThreadView: View {
    let postId: String
    let postTitle: String?

    @StateObject private var vm = DiscussionThreadViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftBody    = ""
    @State private var destination  = DiscussionDestination.public
    @State private var showSummary  = true
    @State private var isAtBottom   = true

    // Discussion OS state
    @State private var selectedComment: DiscussionComment?
    @State private var showReflection = false
    @State private var showMediator = false
    @State private var showSlowModeNudge = true
    @State private var draftInsight: DraftIntelligenceService.DraftAnalysis?
    @State private var showDraftInsight = false

    // Community OS — Action Pill (A18) + Universal Composer (A3)
    @State private var showUniversalComposer = false
    @State private var composerInitialIntent: String? = nil

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    // MARK: - Discussion Action Pill actions

    private var discussionPillActions: [AmenPillAction] {
        [
            AmenPillAction(
                intent: "discuss",
                systemImage: "bubble.left.and.bubble.right",
                label: "Discuss"
            ) {
                composerInitialIntent = "discuss"
                showUniversalComposer = true
            },
            AmenPillAction(
                intent: "pray",
                systemImage: "hands.and.sparkles",
                label: "Pray"
            ) {
                composerInitialIntent = "pray"
                showUniversalComposer = true
            },
            AmenPillAction(
                intent: "share",
                systemImage: "square.and.arrow.up",
                label: "Share"
            ) {
                composerInitialIntent = "share"
                showUniversalComposer = true
            }
        ]
    }

    private var discussionPillPrimary: AmenPillAction {
        AmenPillAction(
            intent: "study",
            systemImage: "book.pages",
            label: "Study"
        ) {
            composerInitialIntent = "study"
            showUniversalComposer = true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background.ignoresSafeArea()

                if vm.isLoadingThread {
                    loadingState
                } else {
                    threadScrollView
                }

                // Composer
                composerBar

                // Community OS: Universal Action Pill (A18)
                // Floats above the composer bar so it doesn't obstruct typing.
                if AMENFeatureFlags.shared.communityOSActionPillEnabled {
                    VStack {
                        Spacer()
                        AmenActionPill(
                            actions: discussionPillActions,
                            primaryAction: discussionPillPrimary
                        )
                        .padding(.bottom, 80) // clears the composer bar height
                        .padding(.horizontal, 16)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            )
                        )
                    }
                }
            }
            .navigationTitle("Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if let snap = vm.healthSnapshot {
                            Image(systemName: snap.status.icon)
                                .font(.systemScaled(12))
                                .foregroundStyle(snap.status.color)
                                .accessibilityLabel("Discussion health: \(snap.status.label)")
                        }
                        askBereanButton
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .sheet(item: $selectedComment) { comment in
                DiscussionActionSheet(
                    comment: comment,
                    threadTitle: vm.thread?.postTitle,
                    onShareToSpaces: { _ in }
                )
            }
            .sheet(isPresented: $showReflection) {
                ReflectionFirstSheet(
                    onComment: { showReflection = false },
                    onReflect: { showReflection = false },
                    onPray: { showReflection = false },
                    onSaveToNotes: { showReflection = false }
                )
            }
            .sheet(isPresented: $showMediator) {
                if let tid = vm.thread?.id {
                    DiscussionMediatorView(threadId: tid)
                }
            }
            .sheet(isPresented: $showDraftInsight) {
                if let analysis = draftInsight {
                    DraftInsightSheet(
                        analysis: analysis,
                        onRevise: { showDraftInsight = false },
                        onPostAnyway: { showDraftInsight = false }
                    )
                }
            }
            // Community OS: Universal Composer (A3) — gated by communityOSUniversalComposerEnabled
            .sheet(isPresented: $showUniversalComposer) {
                if AMENFeatureFlags.shared.communityOSUniversalComposerEnabled,
                   let threadId = vm.thread?.id {
                    AmenUniversalComposer(
                        sourceRef: "discussions/\(threadId)",
                        sourceType: "post",
                        initialIntent: composerInitialIntent,
                        isPresented: $showUniversalComposer
                    )
                }
            }
        }
        .task { await vm.start(postId: postId, postTitle: postTitle) }
        .animation(.easeInOut(duration: 0.22), value: vm.duplicateHint)
        .animation(.easeInOut(duration: 0.22), value: vm.healthSnapshot?.isSlowModeActive)
    }

    private var threadScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                threadStack
            }
            .onChange(of: vm.comments.count) { _, _ in
                guard isAtBottom else { return }
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var threadStack: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // Community OS A6 — Provenance banner (injected when discussion was spawned from another object)
            if AMENFeatureFlags.shared.communityOSDiscussionEnabled,
               let prov = vm.provenance {
                DiscussionProvenanceBanner(provenance: prov)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            if vm.mode != .general {
                modePill
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }
            bereanCard
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            if let summary = vm.bereanSummary {
                DiscussionSummaryV2(summary: summary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if vm.healthSnapshot?.isSlowModeActive == true, showSlowModeNudge {
                slowModeNudgeBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if vm.duplicateHint != .clean {
                duplicateHintBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if vm.comments.isEmpty {
                emptyState.padding(.top, 40)
            } else {
                ForEach(vm.comments) { comment in commentCell(comment) }
            }
            CommunityMemoryView(threadId: postId)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Color.clear.frame(height: 100).id("bottom")
        }
    }

    @ViewBuilder
    private func commentCell(_ comment: DiscussionComment) -> some View {
        let isHelpful = vm.helpfulSent.contains(comment.id ?? "")
        CommentRow(
            comment: comment,
            currentUid: currentUid,
            isHelpfulSent: isHelpful,
            onHelpful: { vm.markHelpful(comment: comment) }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contextMenu {
            Button { selectedComment = comment } label: {
                Label("Actions…", systemImage: "ellipsis.circle")
            }
            Button { UIPasteboard.general.string = comment.body } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        Color(.systemGroupedBackground)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(Color.accentColor)
            Text("Opening discussion…")
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(32, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.2))
            Text("Be the first to share your perspective.")
                .font(.custom("Georgia", size: 16))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Mode pill

    private var modePill: some View {
        HStack(spacing: 5) {
            Image(systemName: vm.mode.icon)
                .font(.systemScaled(11))
            Text(vm.mode.displayName)
                .font(.systemScaled(12, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .accessibilityLabel("Discussion mode: \(vm.mode.displayName)")
    }

    // MARK: - Slow mode nudge

    private var slowModeNudgeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise.fill")
                .font(.systemScaled(12))
                .foregroundStyle(Color.accentColor)
            Text("Slow mode is on — take a breath before posting.")
                .font(.systemScaled(12))
                .foregroundStyle(Color.primary.opacity(0.7))
            Spacer()
            Button("OK") { showSlowModeNudge = false }
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Berean Summary Card

    @ViewBuilder
    private var bereanCard: some View {
        if vm.isLoadingBerean {
            HStack(spacing: 10) {
                ProgressView().tint(Color.accentColor).scaleEffect(0.8)
                Text("Berean is reading the discussion…")
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - Duplicate hint banner

    @ViewBuilder
    private var duplicateHintBanner: some View {
        let (icon, text, color): (String, String, Color) = {
            switch vm.duplicateHint {
            case .isDuplicate:
                return ("doc.on.doc", "A very similar comment already exists — consider supporting it instead.", .orange)
            case .addAngle:
                return ("arrow.triangle.branch", "A related view exists. Try a fresh angle.", Color.accentColor)
            case .clean:
                return ("", "", .clear)
            }
        }()
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(12))
                .foregroundStyle(color)
            Text(text)
                .font(.systemScaled(12))
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Ask Berean toolbar button

    @ViewBuilder
    private var askBereanButton: some View {
        if vm.isLoadingBerean {
            ProgressView().tint(Color.accentColor).scaleEffect(0.8)
        } else {
            Button {
                vm.askBerean()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.systemScaled(11))
                    Text("Ask Berean")
                        .font(.systemScaled(13, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }
            .disabled(vm.isLoadingBerean || vm.comments.isEmpty)
        }
    }

    // MARK: - Composer bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            // Destination picker (only when body is non-empty)
            if !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 0) {
                    ForEach(DiscussionDestination.allCases, id: \.self) { dest in
                        Button {
                            destination = dest
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: dest.icon)
                                    .font(.systemScaled(11))
                                Text(dest.label)
                                    .font(.systemScaled(12, weight: destination == dest ? .semibold : .regular))
                            }
                            .foregroundStyle(destination == dest ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(destination == dest
                                          ? Color.accentColor.opacity(0.12)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                // Reputation / participation badge
                let badgeIcon: String? = {
                    if vm.participationTier != .observer { return vm.participationTier.icon }
                    if vm.reputation != .none { return vm.reputation.icon }
                    return nil
                }()
                if let icon = badgeIcon {
                    Image(systemName: icon)
                        .font(.systemScaled(13))
                        .foregroundStyle(vm.reputation != .none ? vm.reputation.color : Color.accentColor)
                }

                TextField(vm.mode.composerPlaceholder, text: $draftBody, axis: .vertical)
                    .font(.systemScaled(15))
                    .foregroundStyle(Color.white)
                    .tint(Color.accentColor)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    )
                    .onChange(of: draftBody) { _, body in
                        vm.onBodyChanged(body)
                        Task {
                            let analysis = await DraftIntelligenceService.shared.analyzeDraft(
                                threadId: vm.thread?.id ?? postId, draftBody: body
                            )
                            if analysis.hasConcern {
                                draftInsight = analysis
                                if !showDraftInsight { showDraftInsight = true }
                            }
                        }
                    }
                    .accessibilityLabel("Comment input")

                // Reflection shortcut
                if !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        showReflection = true
                    } label: {
                        Image(systemName: "book.closed")
                            .font(.systemScaled(20))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .accessibilityLabel("Save as reflection")
                }

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, 4)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.04)))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.18), value: draftBody.isEmpty)
    }

    private var sendButton: some View {
        Button {
            let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, !vm.isSending, !vm.isSlowModeActive else { return }
            draftBody = ""
            isAtBottom = true

            // Show mediator if discussion is heated or duplicate flagged
            if vm.duplicateHint != .clean || vm.healthSnapshot?.isSlowModeActive == true {
                showMediator = true
            }

            Task { await vm.send(body: body, destination: destination) }
        } label: {
            ZStack {
                if vm.isSending {
                    ProgressView().tint(.white).scaleEffect(0.75)
                } else if vm.isSlowModeActive {
                    Text("\(vm.slowModeSecondsLeft)")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.systemScaled(28))
                        .foregroundStyle(
                            draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color.accentColor
                        )
                }
            }
            .frame(width: 36, height: 36)
        }
        .disabled(
            draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            vm.isSending ||
            vm.isSlowModeActive
        )
        .accessibilityLabel(vm.isSlowModeActive
            ? "Slow mode — \(vm.slowModeSecondsLeft)s remaining"
            : "Send comment")
    }
}

// MARK: - Comment Row

private struct CommentRow: View {
    let comment: DiscussionComment
    let currentUid: String
    let isHelpfulSent: Bool
    let onHelpful: () -> Void

    private var isOwn: Bool { comment.authorUID == currentUid }

    private var initials: String {
        let parts = comment.authorDisplayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var timeLabel: String {
        let date = comment.createdAt.dateValue()
        let diff = Date().timeIntervalSince(date)
        if diff < 60      { return "now" }
        if diff < 3600    { return "\(Int(diff / 60))m" }
        if diff < 86400   { return "\(Int(diff / 3600))h" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorDisplayName)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(isOwn ? Color.accentColor : Color.primary.opacity(0.75))
                    Text(timeLabel)
                        .font(.systemScaled(11))
                        .foregroundStyle(Color.white.opacity(0.28))
                    Spacer()
                    if comment.destination != "public" {
                        Image(systemName: "lock.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                }

                Text(comment.body)
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onHelpful()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isHelpfulSent ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.systemScaled(11))
                        if comment.helpfulCount > 0 {
                            Text("\(comment.helpfulCount + (isHelpfulSent ? 1 : 0))")
                                .font(.systemScaled(11, weight: .medium))
                        }
                    }
                    .foregroundStyle(isHelpfulSent
                                     ? Color.accentColor
                                     : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel(isHelpfulSent ? "Marked as helpful" : "Mark as helpful")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comment.authorDisplayName): \(comment.body)")
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(isOwn
                      ? Color.accentColor.opacity(0.18)
                      : Color.secondary.opacity(0.15))
                .frame(width: 32, height: 32)

            if let urlStr = comment.authorAvatarURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        initialsLabel
                    }
                }
            } else {
                initialsLabel
            }
        }
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.systemScaled(11, weight: .bold))
            .foregroundStyle(isOwn ? Color.accentColor : Color.secondary)
    }
}

// MARK: - Sheet modifier

extension View {
    func discussionThreadSheet(
        postId: String?,
        postTitle: String? = nil,
        isPresented: Binding<Bool>
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            if let id = postId {
                DiscussionThreadView(postId: id, postTitle: postTitle)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DiscussionThreadView(postId: "preview_post_001", postTitle: "What does faith mean in action?")
}
