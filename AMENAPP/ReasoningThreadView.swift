import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ReasoningThreadView: View {
    let postId: String
    let postText: String
    let postAuthorName: String
    let entrySource: String?

    @StateObject private var vm: ReasoningViewModel
    @State private var showAddArgument = false
    @State private var composerParentNodeId: String? = nil
    @State private var composerPreferredType: DiscussionNode.NodeType = .argument
    @State private var steelForExpanded = false
    @State private var steelAgainstExpanded = false
    @State private var headerCompressed = false
    @State private var showReportDialog = false
    @State private var reportSubmitted = false
    @Environment(\.dismiss) private var dismiss

    init(postId: String, postText: String, postAuthorName: String, entrySource: String? = nil) {
        self.postId = postId
        self.postText = postText
        self.postAuthorName = postAuthorName
        self.entrySource = entrySource
        _vm = StateObject(wrappedValue: ReasoningViewModel(postId: postId, postText: postText))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            content
                .safeAreaInset(edge: .top) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .background(
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .opacity(headerCompressed ? 0.96 : 0.0)
                                .ignoresSafeArea()
                        )
                }

            if shouldShowFloatingButton {
                AddYourViewFloatingButton(
                    title: floatingButtonTitle,
                    icon: "plus",
                    action: openComposer
                )
                .padding(.bottom, 18)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showAddArgument) {
            AddArgumentSheet(
                vm: vm,
                parentNodeId: composerParentNodeId,
                preferredType: composerPreferredType
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Report Thread", isPresented: $showReportDialog, titleVisibility: .visible) {
            Button("Misinformation") { submitReport(reason: "misinformation") }
            Button("Harmful Content") { submitReport(reason: "harmful_content") }
            Button("Spam") { submitReport(reason: "spam") }
            Button("Off-Topic") { submitReport(reason: "off_topic") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Why are you reporting this thread?")
        }
        .alert("Report Submitted", isPresented: $reportSubmitted) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you. Our team will review this thread.")
        }
        .task {
            vm.threadOpenEntrySource = entrySource
            await vm.loadOrCreate()
        }
    }

    private func submitReport(reason: String) {
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let db = Firestore.firestore()
            do {
                try await db.collection("reportedContent").addDocument(data: [
                    "contentType": "discussionThread",
                    "contentId": postId,
                    "reportedBy": uid,
                    "reason": reason,
                    "postText": String(postText.prefix(300)),
                    "createdAt": FieldValue.serverTimestamp()
                ])
            } catch {
                print("ReasoningThreadView: failed to submit report — \(error.localizedDescription)")
            }
            await MainActor.run { reportSubmitted = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .idle, .loading:
            ThreadLoadingSkeleton()
        case .error(let message):
            ThreadUnavailableState(
                title: "Couldn’t Load Thread",
                message: message,
                retryTitle: "Try Again",
                onRetry: { Task { await vm.retryLoad() } }
            )
        case .unavailable(let message):
            ThreadUnavailableState(
                title: "Thread Unavailable",
                message: message,
                retryTitle: nil,
                onRetry: nil
            )
        case .loaded, .empty:
            threadContent
        }
    }

    private var header: some View {
        AmenGlassHeaderBar(
            title: "Discussion Thread",
            subtitle: entrySource.map { "From \($0)" } ?? subtitleText,
            onClose: { dismiss() },
            trailing: AnyView(
                Menu {
                    ShareLink(item: postText, subject: Text("Discussion Thread"), message: Text("Check out this discussion on AMEN.")) {
                        Label("Share Thread", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showReportDialog = true
                    } label: {
                        Label("Report Thread", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6))
                        )
                }
            )
        )
    }

    private var threadContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                offsetReader
                DiscussionTopicHeroCard(
                    authorName: postAuthorName,
                    sourceLabel: "Source",
                    title: vm.discussion.claim.isEmpty ? postText : vm.discussion.claim,
                    classification: frameTypeLabel,
                    smartTag: smartTag
                )

                HStack(spacing: 8) {
                    AmenGlassPill(title: frameTypeLabel, icon: "chart.bar.xaxis", tint: frameTint)
                    AmenGlassPill(title: discussionStatusLabel, icon: "sparkles", tint: Color.black.opacity(0.72))
                    if vm.discussion.viewUpdateCount > 0 {
                        AmenGlassPill(
                            title: "\(vm.discussion.viewUpdateCount) changed view",
                            icon: "arrow.uturn.left.circle",
                            tint: Color.green.opacity(0.9)
                        )
                    }
                }

                PerspectiveBriefCard(
                    label: "Strongest case FOR",
                    summary: compressedSummary(for: vm.discussion.aiSteelManFor),
                    bodyText: vm.discussion.aiSteelManFor,
                    helperText: "A concise AI summary of the strongest charitable supporting case.",
                    tint: Color(red: 0.55, green: 0.25, blue: 1.0),
                    isExpanded: $steelForExpanded,
                    onToggle: { trackBriefExpansion(side: "for") }
                )

                PerspectiveBriefCard(
                    label: "Strongest case AGAINST",
                    summary: compressedSummary(for: vm.discussion.aiSteelManAgainst),
                    bodyText: vm.discussion.aiSteelManAgainst,
                    helperText: "A concise AI summary of the strongest charitable opposing case.",
                    tint: Color(red: 0.87, green: 0.63, blue: 0.22),
                    isExpanded: $steelAgainstExpanded,
                    onToggle: { trackBriefExpansion(side: "against") }
                )

                AmenGlassCard(cornerRadius: 22, padding: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Discussion")
                                .font(.systemScaled(18, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(sectionSubtitle)
                                .font(.systemScaled(12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmenGlassPill(title: "\(vm.nodes.count) entries", icon: "bubble.left.and.bubble.right", tint: Color.black.opacity(0.7))
                    }
                }

                if vm.nodes.isEmpty {
                    DiscussionEmptyState(
                        onArgument: { openComposer(type: .argument) },
                        onEvidence: { openComposer(type: .evidence) },
                        onViewChange: { openComposer(type: .viewUpdate) }
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.rootNodes) { node in
                            ArgumentNodeView(
                                node: node,
                                depth: 0,
                                vm: vm,
                                onReply: { nodeId in
                                    composerParentNodeId = nodeId
                                    composerPreferredType = .counterargument
                                    showAddArgument = true
                                }
                            )
                            .id(node.id)
                        }
                    }
                }

                submissionNotice
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .coordinateSpace(name: "threadScroll")
    }

    @ViewBuilder
    private var submissionNotice: some View {
        switch vm.submissionState {
        case .idle, .posting:
            EmptyView()
        case .success:
            AmenGlassCard(cornerRadius: 20, padding: 14, tint: Color.green.opacity(0.6)) {
                Label("Your contribution was added to the discussion.", systemImage: "checkmark.circle.fill")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.primary)
            }
        case .pendingModeration:
            AmenGlassCard(cornerRadius: 20, padding: 14, tint: Color.orange.opacity(0.6)) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Submitted", systemImage: "clock.badge.checkmark")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Your contribution may need a quick review before it appears to everyone.")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            AmenGlassCard(cornerRadius: 20, padding: 14, tint: Color.red.opacity(0.45)) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn’t post", systemImage: "exclamationmark.circle")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var offsetReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ThreadOffsetKey.self, value: proxy.frame(in: .named("threadScroll")).minY)
        }
        .frame(height: 0)
        .onPreferenceChange(ThreadOffsetKey.self) { value in
            withAnimation(.easeInOut(duration: 0.18)) {
                headerCompressed = value < -12
            }
        }
    }

    private var shouldShowFloatingButton: Bool {
        if case .loading = vm.loadState { return false }
        if case .posting = vm.submissionState { return false }
        return !showAddArgument
    }

    private var frameTypeLabel: String {
        switch vm.discussion.aiFactualVsValues {
        case "factual":
            return "Factual"
        case "values":
            return "Values"
        default:
            return "Factual + Values"
        }
    }

    private var discussionStatusLabel: String {
        if vm.nodes.isEmpty { return "New discussion" }
        if vm.nodes.count > 5 { return "Active discussion" }
        return "Balanced thread"
    }

    private var smartTag: String? {
        if vm.nodes.count > 3 { return "Perspective thread" }
        if vm.nodes.isEmpty { return "Be the first voice" }
        return "Balanced thread"
    }

    private var frameTint: Color {
        switch vm.discussion.aiFactualVsValues {
        case "factual":
            return Color.blue.opacity(0.8)
        case "values":
            return Color.red.opacity(0.72)
        default:
            return Color.purple.opacity(0.85)
        }
    }

    private var sectionSubtitle: String {
        if vm.nodes.isEmpty {
            return "No responses yet. Add the first thoughtful contribution."
        }
        return "Follow the discussion, add context, or respond to the strongest case."
    }

    private var subtitleText: String? {
        switch vm.loadState {
        case .loaded, .empty:
            return vm.nodes.isEmpty ? "New thread" : "\(vm.nodes.count) contributions"
        default:
            return nil
        }
    }

    private var floatingButtonTitle: String {
        if vm.nodes.isEmpty { return "Add Your View" }
        if vm.discussion.aiFactualVsValues == "factual" { return "Add Evidence" }
        return "Add Your View"
    }

    private func compressedSummary(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else { return trimmed }
        let prefix = trimmed.prefix(157)
        return prefix + "..."
    }

    private func openComposer() {
        openComposer(type: .argument)
    }

    private func openComposer(type: DiscussionNode.NodeType) {
        composerParentNodeId = nil
        composerPreferredType = type
        showAddArgument = true
    }

    private func trackBriefExpansion(side: String) {
        dlog("[DiscussionThread] ai_brief_expanded side=\(side) postId=\(postId)")
    }
}

private struct ThreadOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
