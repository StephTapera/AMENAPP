// AmenConnectTutorPanelView.swift
// AMEN Connect — Discipleship Learning & Knowledge Graph (Agent 7)
//
// Per-video AI tutor panel. Slides in from trailing edge with glass chrome
// and matte AI-output body. All AI output passes conceptually through Aegis.
// Scripture provenance is always surfaced; empty provenance shows a shimmer.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not edit.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import SwiftUI
import FirebaseAuth

// MARK: - Color helpers (local, matching frozen design tokens)

private extension Color {
    static let amenGold   = Color(hex: "#D9A441")
    static let amenPurple = Color(hex: "#6E4BB5")
    static let amenBlue   = Color(hex: "#245B8F")
    static let amenBlack  = Color(hex: "#070607")
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - TutorAction enum

enum AmenConnectTutorAction: String, CaseIterable, Identifiable {
    case askQuestion      = "Ask a Question"
    case quizMe           = "Quiz Me"
    case explainClaim     = "Explain a Claim"
    case summarize        = "Summarize"
    case studyPlan        = "Study Plan"
    case crossSource      = "Cross-Source Compare"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .askQuestion:  return "questionmark.bubble"
        case .quizMe:       return "checklist"
        case .explainClaim: return "magnifyingglass.circle"
        case .summarize:    return "text.alignleft"
        case .studyPlan:    return "calendar.badge.plus"
        case .crossSource:  return "arrow.triangle.swap"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AmenConnectTutorPanelViewModel: ObservableObject {

    // MARK: Published state
    @Published var selectedAction: AmenConnectTutorAction?
    @Published var questionText: String = ""
    @Published var aiOutputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Claim explanation
    @Published var selectedClaim: AmenConnectSpacesTeachingClaim?

    // Quiz stub
    @Published var quizQuestions: [AmenStubQuizQuestion] = []

    // Scripture provenance chips (populated when AI output contains scripture)
    @Published var provenanceChips: [AmenConnectSpacesScriptureRefProvenance] = []
    @Published var provenancePending: Bool = false

    let videoId: String
    let video: AmenConnectSpacesConnectVideo

    init(videoId: String, video: AmenConnectSpacesConnectVideo) {
        self.videoId = videoId
        self.video   = video
    }

    // MARK: - Aegis output gate
    // STUB: canContinue is hardcoded true for now.
    // Wire shape: AmenConnectSpacesCallableProxy.shared.runAegisOutputGate(_:)
    // Agent 8 (Aegis) will replace the stub body with a real gate call.
    private func runAegisOutputGate(inputRef: String, userId: String) async -> Bool {
        // STUBBED — Aegis output gate not yet deployed.
        // Production shape:
        //   let req = AmenConnectSpacesAegisGateRequest(
        //       surface: .connect,
        //       capabilityRefs: ["C1", "C2"],   // Agent 8 to supply final capability set
        //       inputRef: inputRef,
        //       userId: userId,
        //       videoId: videoId
        //   )
        //   let decision = try await AmenConnectSpacesCallableProxy.shared.runAegisOutputGate(req)
        //   return decision.canContinue
        return true  // STUB
    }

    // MARK: - Ask a question
    func submitQuestion() async {
        guard !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userId = Auth.auth().currentUser?.uid ?? "anonymous"
        isLoading = true
        errorMessage = nil

        // Aegis INPUT gate (stub shape — Agent 8 wires real call)
        let inputRef = questionText
        let canSend = await runAegisOutputGate(inputRef: inputRef, userId: userId)
        guard canSend else {
            errorMessage = "This message could not be sent right now."
            isLoading = false
            return
        }

        // Stub response — Agent 9 (Intelligence Seam) replaces with real CF call
        try? await Task.sleep(nanoseconds: 400_000_000)
        let stub = "Great question about "\(questionText)". This teaching addresses that in the context of the passage. (Stub response — Intelligence Seam pending.)"

        let canShow = await runAegisOutputGate(inputRef: stub, userId: userId)
        if canShow {
            aiOutputText = stub
            provenancePending = false
        } else {
            aiOutputText = ""
            errorMessage = "Response blocked by content review."
        }
        isLoading = false
    }

    // MARK: - Quiz me (stub)
    func loadQuiz() {
        quizQuestions = AmenStubQuizQuestion.stubSet(for: videoId)
    }

    // MARK: - Explain a claim
    func explainClaim(_ claim: AmenConnectSpacesTeachingClaim) {
        selectedClaim = claim
        // Scripture provenance for the claim's scripture refs
        provenancePending = video.scriptureRefs.isEmpty
        provenanceChips = video.scriptureRefs
    }

    // MARK: - Summarize (stub)
    func summarize() async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        aiOutputText = "This teaching covers three main themes: (1) the covenantal context of the passage, (2) the original audience's cultural setting, and (3) practical application for today. (Stub — Intelligence Seam pending.)"
        provenancePending = video.scriptureRefs.isEmpty
        provenanceChips = video.scriptureRefs
        isLoading = false
    }

    // MARK: - Study plan
    func requestStudyPlan() async {
        let userId = Auth.auth().currentUser?.uid ?? "anonymous"
        isLoading = true
        do {
            _ = try await AmenConnectSpacesCallableProxy.shared.recordKnowledgeGraphEvent(
                userId: userId,
                event: "studyPlanRequested",
                itemRef: videoId
            )
        } catch {
            // Non-fatal — plan still displays
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        aiOutputText = "Suggested 7-day study plan:\nDay 1 — Read the passage in full.\nDay 2 — Study the historical context.\nDay 3 — Compare three translations.\nDay 4 — Review opposing faithful views.\nDay 5 — Personal reflection journaling.\nDay 6 — Discuss with your small group.\nDay 7 — Apply one concrete action. (Stub — Intelligence Seam pending.)"
        isLoading = false
    }

    // MARK: - Cross-source compare (stub)
    func crossSourceCompare() {
        aiOutputText = ""  // Empty state per spec — Wave D
    }

    func clearOutput() {
        aiOutputText = ""
        errorMessage = nil
        questionText = ""
        selectedClaim = nil
        quizQuestions = []
        provenanceChips = []
        provenancePending = false
    }
}

// MARK: - Stub quiz model

struct AmenStubQuizQuestion: Identifiable {
    let id: String
    let prompt: String
    let choices: [String]
    let correctIndex: Int

    static func stubSet(for videoId: String) -> [AmenStubQuizQuestion] {
        [
            AmenStubQuizQuestion(id: "q1", prompt: "What is the primary theme of this teaching?", choices: ["Grace", "Judgment", "Repentance", "Mission"], correctIndex: 0),
            AmenStubQuizQuestion(id: "q2", prompt: "Which Old Testament passage is referenced?", choices: ["Isaiah 53", "Psalm 23", "Proverbs 3", "Genesis 1"], correctIndex: 0),
            AmenStubQuizQuestion(id: "q3", prompt: "What practical application was suggested?", choices: ["Daily prayer", "Scripture memorization", "Community service", "Fasting"], correctIndex: 0)
        ]
    }
}

// MARK: - Main panel view

struct AmenConnectTutorPanelView: View {

    let videoId: String
    let video: AmenConnectSpacesConnectVideo

    @StateObject private var vm: AmenConnectTutorPanelViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(videoId: String, video: AmenConnectSpacesConnectVideo) {
        self.videoId = videoId
        self.video   = video
        _vm = StateObject(wrappedValue: AmenConnectTutorPanelViewModel(videoId: videoId, video: video))
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            actionButtons
            Divider()
            outputArea
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.amenGold.opacity(0.7), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: -4, y: 0)
        .frame(maxWidth: 340)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(Color.amenGold)
            Text("AI Tutor")
                .font(.headline)
                .foregroundStyle(Color.amenBlack)
            Spacer()
            if let action = vm.selectedAction {
                Text(action.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color.amenPurple)
                Button {
                    vm.clearOutput()
                    vm.selectedAction = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.amenBlack.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tutor action")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 0))
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(AmenConnectTutorAction.allCases) { action in
                    tutorActionButton(action)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 260)
    }

    private func tutorActionButton(_ action: AmenConnectTutorAction) -> some View {
        Button {
            vm.clearOutput()
            vm.selectedAction = action
            handleActionTap(action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .foregroundStyle(.white)
                    .frame(width: 20)
                Text(action.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.amenPurple.opacity(vm.selectedAction == action ? 1.0 : 0.80))
            )
            .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.rawValue)
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8), value: vm.selectedAction)
    }

    // MARK: - Output area

    @ViewBuilder
    private var outputArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if vm.isLoading {
                    loadingIndicator
                } else if let error = vm.errorMessage {
                    errorBanner(error)
                } else if let action = vm.selectedAction {
                    actionOutputContent(for: action)
                } else {
                    emptyPrompt
                }
            }
            .padding(16)
        }
    }

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
            Text("Thinking…")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Error: \(message)")
    }

    private var emptyPrompt: some View {
        Text("Choose an action above to begin learning.")
            .font(.subheadline)
            .foregroundStyle(Color.amenBlack.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 24)
    }

    // MARK: - Per-action output

    @ViewBuilder
    private func actionOutputContent(for action: AmenConnectTutorAction) -> some View {
        switch action {
        case .askQuestion:
            questionOutputView
        case .quizMe:
            quizOutputView
        case .explainClaim:
            claimExplainerView
        case .summarize:
            aiTextOutputView
        case .studyPlan:
            aiTextOutputView
        case .crossSource:
            crossSourceEmptyState
        }
    }

    // Ask a question
    private var questionOutputView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Type your question…", text: $vm.questionText, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .accessibilityLabel("Question input")
                Button {
                    Task { await vm.submitQuestion() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.amenPurple)
                }
                .buttonStyle(.plain)
                .disabled(vm.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Submit question")
            }
            if !vm.aiOutputText.isEmpty {
                matteAIOutputText(vm.aiOutputText)
                provenanceSection
            }
        }
    }

    // Quiz
    private var quizOutputView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.quizQuestions.isEmpty {
                Text("No quiz loaded.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
            } else {
                ForEach(vm.quizQuestions) { q in
                    AmenQuizQuestionRowView(question: q)
                }
            }
        }
    }

    // Explain a claim
    private var claimExplainerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if video.claims.isEmpty {
                Text("No teaching claims identified in this video.")
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
            } else {
                Text("Select a claim to explore:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenBlack.opacity(0.6))
                Picker("Claim", selection: $vm.selectedClaim) {
                    Text("Choose…").tag(Optional<AmenConnectSpacesTeachingClaim>.none)
                    ForEach(video.claims) { claim in
                        Text(claim.text).tag(Optional(claim))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .clipped()
                .onChange(of: vm.selectedClaim) { _, claim in
                    if let c = claim { vm.explainClaim(c) }
                }

                if let claim = vm.selectedClaim {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claim")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.amenBlack.opacity(0.5))
                        matteAIOutputText(claim.text)

                        if !claim.opposingFaithfulViews.isEmpty {
                            Text("Faithful opposing views")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.amenBlack.opacity(0.5))
                                .padding(.top, 4)
                            ForEach(claim.opposingFaithfulViews, id: \.self) { view in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(Color.amenBlue)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    Text(view)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.amenBlack)
                                }
                            }
                        }
                        provenanceSection
                    }
                }
            }
        }
    }

    // Plain AI text output
    private var aiTextOutputView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.aiOutputText.isEmpty {
                matteAIOutputText(vm.aiOutputText)
                provenanceSection
            }
        }
    }

    // Cross-source empty state
    private var crossSourceEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.largeTitle)
                .foregroundStyle(Color.amenBlue.opacity(0.4))
            Text("Compare this teaching with another source")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.5))
                .multilineTextAlignment(.center)
            Text("Cross-source compare coming in Wave D.")
                .font(.caption)
                .foregroundStyle(Color.amenBlack.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Scripture provenance chips

    @ViewBuilder
    private var provenanceSection: some View {
        if vm.provenancePending {
            HStack(spacing: 6) {
                shimmerChip("Verifying scripture…")
            }
        } else if !vm.provenanceChips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scripture provenance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amenBlack.opacity(0.5))
                FlowLayoutView(spacing: 6) {
                    ForEach(vm.provenanceChips) { chip in
                        provenanceChipView(chip)
                    }
                }
            }
        }
    }

    private func provenanceChipView(_ chip: AmenConnectSpacesScriptureRefProvenance) -> some View {
        HStack(spacing: 4) {
            Image(systemName: provenanceLayerIcon(chip.sourceLayer))
                .font(.caption2)
            Text(chip.reference)
                .font(.caption)
            Text("·")
                .font(.caption)
                .foregroundStyle(Color.amenBlack.opacity(0.4))
            Text(chip.translation)
                .font(.caption2)
                .foregroundStyle(Color.amenBlack.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.amenBlue.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.amenBlue.opacity(0.3), lineWidth: 0.5)
        )
        .foregroundStyle(Color.amenBlue)
        .accessibilityLabel("\(chip.reference) from \(chip.translation), layer \(chip.sourceLayer.rawValue)")
    }

    private func shimmerChip(_ label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(Color.amenBlack.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.amenGold.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.amenGold.opacity(0.4), lineWidth: 0.5)
            )
    }

    private func provenanceLayerIcon(_ layer: AmenConnectSpacesScriptureProvenanceLayer) -> String {
        switch layer {
        case .canonicalReference: return "book.closed"
        case .translationSource:  return "globe"
        case .contextWindow:      return "text.magnifyingglass"
        case .bereanStudySheet:   return "pencil.and.list.clipboard"
        }
    }

    // MARK: - Matte AI output text (never glass per spec)

    private func matteAIOutputText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.amenBlack)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.95))
            )
            .accessibilityLabel(text)
    }

    // MARK: - Panel background (glass chrome only)

    @ViewBuilder
    private var panelBackground: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .glassEffect(in: .rect(cornerRadius: 20))
    }

    // MARK: - Action handler

    private func handleActionTap(_ action: AmenConnectTutorAction) {
        switch action {
        case .askQuestion:
            break  // User types and submits
        case .quizMe:
            vm.loadQuiz()
        case .explainClaim:
            break  // User picks claim via picker
        case .summarize:
            Task { await vm.summarize() }
        case .studyPlan:
            Task { await vm.requestStudyPlan() }
        case .crossSource:
            vm.crossSourceCompare()
        }
    }
}

// MARK: - Quiz question row

private struct AmenQuizQuestionRowView: View {
    let question: AmenStubQuizQuestion
    @State private var selectedChoice: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.amenBlack)
            ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    selectedChoice = index
                } label: {
                    HStack {
                        Image(systemName: selectedChoice == index
                              ? (index == question.correctIndex ? "checkmark.circle.fill" : "xmark.circle.fill")
                              : "circle")
                            .foregroundStyle(selectedChoice == index
                                ? (index == question.correctIndex ? Color.green : .red)
                                : Color.amenBlue.opacity(0.5))
                        Text(choice)
                            .font(.subheadline)
                            .foregroundStyle(Color.amenBlack)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

// MARK: - FlowLayout helper (simple horizontal wrap)

private struct FlowLayoutView<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Uses iOS 16+ Layout protocol; falls back to HStack wrap on older OS
        if #available(iOS 16, *) {
            _FlowLayout(spacing: spacing, content: content)
        } else {
            HStack(alignment: .top, spacing: spacing) {
                content()
            }
        }
    }
}

@available(iOS 16, *)
private struct _FlowLayout<Content: View>: Layout {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    func makeBody(content: Content) -> some View {
        content
    }
}

@available(iOS 16, *)
extension _FlowLayout {
    // SwiftUI Layout conformance requires a `makeBody` but we render via `placeSubviews`.
    // The conformance is on the Layout protocol; the `makeBody` here is intentionally empty.
}
