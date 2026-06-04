// DiscussionThreadView.swift — AMEN App
// Full discussion thread UI: Berean AI summary, comments, composer with
// duplicate detection + full Context-First Discussion OS integration.
// Follows the dark Berean aesthetic (#0A0A0F + gold).

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
    @Published var discussionMode: DiscussionMode = .general
    @Published var contextScore: ContextScore?
    @Published var healthSnapshot: DiscussionHealthSnapshot?
    @Published var isSlowModeActive: Bool = false
    @Published var slowModeSecondsLeft: Int = 0
    @Published var draftAnalysis: DraftIntelligenceService.DraftAnalysis?
    @Published var isAnalyzingDraft: Bool = false
    @Published var participationTier: ParticipationTier = .none

    private let service = DiscussionThreadService.shared
    private var commentListener: (any Sendable)?
    private var threadListener:  (any Sendable)?
    private var summaryListener: (any Sendable)?
    private var modeListener:    (any Sendable)?
    private var healthListener:  (any Sendable)?
    private var dupTask: Task<Void, Never>?
    private var slowModeTask: Task<Void, Never>?

    // MARK: Start

    func start(postId: String, postTitle: String?) async {
        isLoadingThread = true
        do {
            let t = try await service.getOrCreateThread(postId: postId, postTitle: postTitle)
            thread = t
            wireListeners(threadId: postId, summaryPath: t.bereanSummaryRef)
            reputation = (try? await service.fetchReputation()) ?? .none

            if DiscussionModeService.shared.isEnabled {
                discussionMode = (try? await DiscussionModeService.shared.getMode(threadId: postId)) ?? .general
                modeListener = DiscussionModeService.shared.listenMode(threadId: postId) { [weak self] mode in
                    self?.discussionMode = mode
                }
            }

            if DiscussionContextEngine.shared.isEnabled {
                contextScore = await DiscussionContextEngine.shared.getContextScore(postId: postId)
            }

            if DiscussionHealthEngine.shared.isEnabled {
                healthListener = DiscussionHealthEngine.shared.listenHealth(threadId: postId) { [weak self] snap in
                    self?.healthSnapshot = snap
                }
            }

            if AMENFeatureFlags.shared.participationTiersEnabled {
                participationTier = await DiscussionParticipationService.shared.getTier(threadId: postId)
            }
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
            try? await Task.sleep(nanoseconds: 900_000_000) // 0.9 s debounce
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

    // MARK: Draft intelligence

    func checkDraftBeforeSend(body: String) async -> DraftIntelligenceService.DraftAnalysis? {
        guard AMENFeatureFlags.shared.draftIntelligenceEnabled, let tid = thread?.id else { return nil }
        isAnalyzingDraft = true
        defer { isAnalyzingDraft = false }
        let analysis = await DraftIntelligenceService.shared.analyzeDraft(threadId: tid, draftBody: body)
        return analysis.hasConcern ? analysis : nil
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
    @State private var selectedResponseType: DiscussionResponseType? = nil
    @State private var showSlowModeNudge = true
    @State private var showDraftInsight = false
    @State private var showReflection = false
    @State private var showMediator = false
    @State private var pendingPostBody = ""
    @State private var actionSheetComment: DiscussionComment? = nil
    @State private var showCommandCenter = false

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    private var isDiscussionHost: Bool {
        guard let authorUID = vm.thread?.postAuthorUID else { return false }
        return authorUID == currentUid
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background.ignoresSafeArea()

                if vm.isLoadingThread {
                    loadingState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 0) {

                                // Mode pill
                                if AMENFeatureFlags.shared.discussionModesEnabled && vm.discussionMode != .general {
                                    modePill
                                        .padding(.horizontal, 16)
                                        .padding(.top, 14)
                                        .padding(.bottom, 4)
                                }

                                // Context participation nudge
                                if AMENFeatureFlags.shared.contextParticipationEnabled,
                                   let score = vm.contextScore, score.shouldNudge {
                                    contextNudgeBanner(score: score)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)
                                } else {
                                    watchNudgeBanner
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)
                                }

                                // Mediator banner
                                if AMENFeatureFlags.shared.discussionMediatorEnabled,
                                   vm.healthSnapshot?.status == .escalating {
                                    mediatorBanner
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 6)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                // Slow mode nudge
                                if AMENFeatureFlags.shared.discussionHealthEnabled,
                                   vm.healthSnapshot?.status.requiresSlowMode == true,
                                   showSlowModeNudge,
                                   let nudgeText = vm.healthSnapshot?.status.slowModeNudgeText,
                                   !nudgeText.isEmpty {
                                    slowModeNudgeBanner(text: nudgeText)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 6)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                // Berean summary card
                                bereanCard
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)

                                // Discussion summary (OS feature)
                                if AMENFeatureFlags.shared.discussionSummaryEnabled {
                                    DiscussionSummaryView(threadId: postId)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 8)
                                }

                                // Duplicate hint
                                if vm.duplicateHint != .clean {
                                    duplicateHintBanner
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 8)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                // Comments
                                if vm.comments.isEmpty {
                                    emptyState
                                        .padding(.top, 40)
                                } else {
                                    ForEach(vm.comments) { comment in
                                        CommentRow(
                                            comment: comment,
                                            currentUid: currentUid,
                                            isHelpfulSent: vm.helpfulSent.contains(comment.id ?? ""),
                                            onHelpful: { vm.markHelpful(comment: comment) }
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .contextMenu {
                                            if AMENFeatureFlags.shared.discussionActionsEnabled {
                                                Button {
                                                    actionSheetComment = comment
                                                } label: {
                                                    Label("Actions…", systemImage: "square.and.arrow.up")
                                                }
                                            }
                                            Button {
                                                UIPasteboard.general.string = comment.body
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                        }
                                    }
                                }

                                // Community memory
                                if AMENFeatureFlags.shared.communityMemoryEnabled {
                                    CommunityMemoryView(threadId: postId)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 12)
                                        .padding(.bottom, 8)
                                }

                                Color.clear
                                    .frame(height: 100)
                                    .id("bottom")
                            }
                        }
                        .onChange(of: vm.comments.count) { _, _ in
                            guard isAtBottom else { return }
                            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }

                // Composer
                composerBar
            }
            .navigationTitle("Discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#C9A84C"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if AMENFeatureFlags.shared.discussionCommandCenterEnabled && isDiscussionHost {
                            Button {
                                showCommandCenter = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(Color(hex: "#C9A84C"))
                            }
                            .accessibilityLabel("Discussion Controls")
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
            .sheet(isPresented: $showDraftInsight) {
                if let analysis = vm.draftAnalysis {
                    DraftInsightSheet(
                        analysis: analysis,
                        onRevise: { showDraftInsight = false },
                        onPostAnyway: {
                            showDraftInsight = false
                            Task { await vm.send(body: pendingPostBody, destination: destination) }
                        }
                    )
                }
            }
            .sheet(isPresented: $showReflection) {
                ReflectionFirstSheet(
                    onComment: {
                        showReflection = false
                    },
                    onReflect: { showReflection = false },
                    onPray:    { showReflection = false },
                    onSaveToNotes: { showReflection = false }
                )
            }
            .sheet(isPresented: $showMediator) {
                DiscussionMediatorView(threadId: postId)
            }
            .sheet(item: $actionSheetComment) { comment in
                DiscussionActionSheet(
                    comment: comment,
                    threadTitle: postTitle,
                    onShareToSpaces: { _ in }
                )
            }
            .sheet(isPresented: $showCommandCenter) {
                DiscussionCommandCenterView(threadId: postId, threadTitle: postTitle)
            }
        }
        .task { await vm.start(postId: postId, postTitle: postTitle) }
        .animation(.easeInOut(duration: 0.22), value: vm.duplicateHint)
        .animation(.easeInOut(duration: 0.22), value: vm.healthSnapshot?.status.rawValue)
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [Color(hex: "#0A0A0F"), Color(hex: "#111118")],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(Color(hex: "#C9A84C"))
            Text("Opening discussion…")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30))
                .foregroundStyle(Color.white.opacity(0.15))
            Text("Be the first to share your perspective")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mode pill

    private var modePill: some View {
        HStack(spacing: 5) {
            Image(systemName: vm.discussionMode.icon)
                .font(.system(size: 11))
            Text(vm.discussionMode.displayName)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(hex: "#C9A84C"))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: "#C9A84C").opacity(0.12), in: Capsule())
        .accessibilityLabel("Discussion mode: \(vm.discussionMode.displayName)")
    }

    // MARK: - Context nudge banner

    private func contextNudgeBanner(score: ContextScore) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                    .frame(width: 32, height: 32)
                Circle()
                    .trim(from: 0, to: score.progressFraction)
                    .stroke(Color(hex: "#C9A84C"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 32)
                Text(score.level.label.prefix(1))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#C9A84C"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(score.level.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#C9A84C"))
                if !score.level.nudgeText.isEmpty {
                    Text(score.level.nudgeText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#C9A84C").opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: "#C9A84C").opacity(0.15), lineWidth: 1))
        )
        .accessibilityLabel("Context level: \(score.level.label). \(score.level.nudgeText)")
    }

    // MARK: - Watch nudge banner (fallback when context engine off)

    private var watchNudgeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#C9A84C").opacity(0.7))
            Text("Read the post before commenting for a richer discussion")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Slow mode nudge

    private func slowModeNudgeBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer()
            Button("Continue") { showSlowModeNudge = false }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Mediator banner

    private var mediatorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#C9A84C"))
            Text("This discussion needs care. A neutral facilitator can help.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer()
            Button("Get Help") { showMediator = true }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#C9A84C"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#C9A84C").opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: "#C9A84C").opacity(0.15), lineWidth: 1))
        )
    }

    // MARK: - Berean card

    private var bereanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = vm.bereanSummary {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#C9A84C"))
                    Text("Berean Summary")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#C9A84C"))
                    Spacer()
                    Button { withAnimation { showSummary.toggle() } } label: {
                        Image(systemName: showSummary ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                if showSummary {
                    Text(summary.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.8))

                    if !summary.agreementPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Areas of Agreement")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.4))
                            ForEach(summary.agreementPoints, id: \.self) { pt in
                                Text("• \(pt)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.65))
                            }
                        }
                    }

                    if !summary.studyQuestions.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Study Questions")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.4))
                            ForEach(summary.studyQuestions, id: \.self) { q in
                                Text("• \(q)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.65))
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Duplicate hint banner

    private var duplicateHintBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: vm.duplicateHint == .isDuplicate ? "exclamationmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#C9A84C"))
            Text(vm.duplicateHint == .isDuplicate
                 ? "A similar comment already exists — consider supporting it instead."
                 : "A similar angle exists — try adding a new perspective.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#C9A84C").opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: "#C9A84C").opacity(0.15), lineWidth: 1))
        )
    }

    // MARK: - Ask Berean button

    private var askBereanButton: some View {
        Button {
            vm.askBerean()
        } label: {
            if vm.isLoadingBerean {
                ProgressView()
                    .tint(Color(hex: "#C9A84C"))
                    .scaleEffect(0.75)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                    Text("Berean")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color(hex: "#C9A84C"))
            }
        }
        .disabled(vm.isLoadingBerean || vm.comments.isEmpty)
    }

    // MARK: - Response type picker

    private var responseTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let types = vm.discussionMode.availableResponseTypes
                ForEach(types, id: \.self) { rt in
                    Button {
                        selectedResponseType = selectedResponseType == rt ? nil : rt
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: rt.icon).font(.system(size: 10))
                            Text(rt.label).font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selectedResponseType == rt
                                         ? Color(hex: "#0A0A0F")
                                         : Color.white.opacity(0.5))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(selectedResponseType == rt
                                    ? Color(hex: "#C9A84C")
                                    : Color.white.opacity(0.06),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 4)
    }

    // MARK: - Composer bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            // Response type picker (Discussion OS)
            if AMENFeatureFlags.shared.discussionModesEnabled,
               !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                responseTypePicker
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Destination picker (only when body is non-empty)
            if !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 0) {
                    ForEach(DiscussionDestination.allCases, id: \.self) { dest in
                        Button {
                            destination = dest
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: dest.icon)
                                    .font(.system(size: 11))
                                Text(dest.label)
                                    .font(.system(size: 12, weight: destination == dest ? .semibold : .regular))
                            }
                            .foregroundStyle(destination == dest ? Color(hex: "#C9A84C") : Color.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(destination == dest
                                          ? Color(hex: "#C9A84C").opacity(0.12)
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
                let tier = AMENFeatureFlags.shared.participationTiersEnabled ? vm.participationTier : .none
                let repIcon = tier.showsInComposer ? tier.icon : (vm.reputation != .none ? vm.reputation.icon : nil)
                let repColor = tier.showsInComposer ? tier.color : vm.reputation.color

                if let icon = repIcon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(repColor)
                        .accessibilityLabel(tier.showsInComposer ? tier.displayName : vm.reputation.label)
                }

                let placeholder = AMENFeatureFlags.shared.discussionModesEnabled
                    ? vm.discussionMode.composerPlaceholder
                    : "Share your perspective…"

                TextField(placeholder, text: $draftBody, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)
                    .tint(Color(hex: "#C9A84C"))
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
                    }
                    .accessibilityLabel("Comment input")

                // Save reflection button
                if AMENFeatureFlags.shared.discussionActionsEnabled,
                   !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        showReflection = true
                    } label: {
                        Image(systemName: "book.closed")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white.opacity(0.35))
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

            // If health requires slow mode and it's not yet active, activate it
            if AMENFeatureFlags.shared.discussionHealthEnabled,
               vm.healthSnapshot?.status.requiresSlowMode == true,
               !vm.isSlowModeActive {
                vm.activateSlowMode(seconds: 30)
            }

            draftBody = ""
            isAtBottom = true

            if AMENFeatureFlags.shared.draftIntelligenceEnabled {
                Task {
                    if let analysis = await vm.checkDraftBeforeSend(body: body) {
                        vm.draftAnalysis = analysis
                        pendingPostBody = body
                        showDraftInsight = true
                    } else {
                        await vm.send(body: body, destination: destination)
                    }
                }
            } else {
                Task { await vm.send(body: body, destination: destination) }
            }
        } label: {
            ZStack {
                if vm.isSending || vm.isAnalyzingDraft {
                    ProgressView().tint(.white).scaleEffect(0.75)
                } else if vm.isSlowModeActive {
                    Text("\(vm.slowModeSecondsLeft)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.15), in: Circle())
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.white.opacity(0.25)
                                : Color(hex: "#C9A84C")
                        )
                }
            }
            .frame(width: 36, height: 36)
        }
        .disabled(
            draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            vm.isSending ||
            vm.isSlowModeActive ||
            vm.isAnalyzingDraft
        )
        .accessibilityLabel(vm.isSlowModeActive ? "Slow mode active — \(vm.slowModeSecondsLeft)s remaining" : "Send comment")
    }
}

// MARK: - Comment Row

private struct CommentRow: View {
    let comment: DiscussionComment
    let currentUid: String
    let isHelpfulSent: Bool
    let onHelpful: () -> Void

    private var isOwn: Bool { comment.authorId == currentUid }

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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOwn ? Color(hex: "#C9A84C") : Color.white.opacity(0.75))
                    Text(timeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.28))
                    Spacer()
                    if comment.destination != "public" {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                }

                Text(comment.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onHelpful()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isHelpfulSent ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 11))
                        if comment.helpfulCount > 0 {
                            Text("\(comment.helpfulCount + (isHelpfulSent ? 1 : 0))")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .foregroundStyle(isHelpfulSent
                                     ? Color(hex: "#C9A84C")
                                     : Color.white.opacity(0.3))
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
                      ? Color(hex: "#C9A84C").opacity(0.18)
                      : Color.white.opacity(0.1))
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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isOwn ? Color(hex: "#C9A84C") : Color.white.opacity(0.6))
    }
}

// MARK: - Sheet modifier

extension View {
    /// Presents a DiscussionThreadView sheet for the given post.
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
