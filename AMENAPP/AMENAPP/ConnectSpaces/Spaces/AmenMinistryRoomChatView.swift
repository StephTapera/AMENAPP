// AmenMinistryRoomChatView.swift
// AMEN Connect + Spaces — Living Ministry Rooms
// Agent 3 — built 2026-06-01
// Agent 8 update — real Aegis conviction + before-share gate wired 2026-06-01

import SwiftUI
import FirebaseFirestore
import FirebaseAnalytics
import FirebaseAuth

// MARK: - Chat ViewModel

@MainActor
final class AmenMinistryRoomChatViewModel: ObservableObject {
    @Published var messages: [AmenConnectSpacesMessage] = []
    @Published var composerText: String = ""
    @Published var isSending: Bool = false
    @Published var sendError: String?
    @Published var showConvictionSheet: Bool = false
    @Published var pendingBody: String = ""
    @Published var activeBeforeShareWarnings: [AmenConnectSpacesBeforeShareWarning] = []
    @Published var showBeforeShareSheet: Bool = false

    private let spaceId: String
    private var listener: ListenerRegistration?

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func startListening() {
        Analytics.logEvent("ministry_room_chat_viewed", parameters: ["space_id": spaceId])
        let db = Firestore.firestore()
        listener = db
            .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
            .document(spaceId)
            .collection(AmenConnectSpacesFirestoreBinding.messagesSubcollection)
            .order(by: "createdAt", descending: false)
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                guard let snapshot else { return }
                self.messages = snapshot.documents.compactMap { doc in
                    try? AmenConnectSpacesFirestoreBinding.bindMessage(doc)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Checks whether the body warrants a conviction pause by calling the real Aegis service.
    /// Returns false on any error — Aegis failure must never block the user from sending.
    private func shouldShowConvictionCheck(for body: String, spaceId: String) async -> Bool {
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        do {
            let check = try await AmenConnectSpacesAegisService.shared.checkConviction(
                spaceId: spaceId,
                body: body
            )
            return check.suggestedPause
        } catch {
            return false // never block on Aegis failure
        }
    }

    func requestSend() {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let capturedSpaceId = spaceId

        Task {
            // 1. Conviction check (care signals)
            let pause = await shouldShowConvictionCheck(for: body, spaceId: capturedSpaceId)
            if pause {
                pendingBody = body
                showConvictionSheet = true
                return
            }

            // 2. Before-share check (gossip / slander / PII / PHI / financial)
            do {
                let warnings = try await AmenConnectSpacesAegisService.shared.checkBeforeShare(
                    surface: .spaces,
                    text: body
                )
                if !warnings.isEmpty {
                    pendingBody = body
                    activeBeforeShareWarnings = warnings
                    showBeforeShareSheet = true
                    return
                }
            } catch {
                // Never block on Aegis failure — proceed with send
            }

            performSend(body: body)
        }
    }

    func confirmSendAfterConviction() {
        let body = pendingBody
        pendingBody = ""
        showConvictionSheet = false
        performSend(body: body)
    }

    func dismissConviction() {
        showConvictionSheet = false
        pendingBody = ""
    }

    func confirmSendFromBeforeShare() {
        let body = pendingBody
        pendingBody = ""
        activeBeforeShareWarnings = []
        showBeforeShareSheet = false
        performSend(body: body)
    }

    func dismissBeforeShare() {
        showBeforeShareSheet = false
        activeBeforeShareWarnings = []
        // Restore composer text so the user can edit
        if composerText.isEmpty {
            composerText = pendingBody
        }
        pendingBody = ""
    }

    private func performSend(body: String) {
        let spaceId = self.spaceId
        isSending = true
        sendError = nil
        composerText = ""

        Task {
            do {
                _ = try await AmenConnectSpacesCallableProxy.shared.postMinistryMessage(
                    spaceId: spaceId,
                    body: body
                )
            } catch {
                self.sendError = error.localizedDescription
                // Restore composer text so user doesn't lose their message
                if self.composerText.isEmpty {
                    self.composerText = body
                }
            }
            self.isSending = false
        }
    }
}

// MARK: - Intent color helper

private extension AmenConnectSpacesMessageIntent {
    var pillColor: Color {
        switch self {
        case .prayerRequest, .struggling, .grief:
            return Color(red: 0.851, green: 0.643, blue: 0.255) // amenGold
        case .decision, .task:
            return Color(red: 0.141, green: 0.357, blue: 0.561) // amenBlue
        case .careFollowUp, .confession:
            return Color(red: 0.431, green: 0.294, blue: 0.710) // amenPurple
        default:
            return Color.white.opacity(0.55)
        }
    }

    var displayLabel: String {
        switch self {
        case .prayerRequest:  return "Prayer Request"
        case .struggling:     return "Struggling"
        case .leadSunday:     return "Leading Sunday"
        case .volunteerNeed:  return "Volunteer Need"
        case .testimony:      return "Testimony"
        case .confession:     return "Confession"
        case .grief:          return "Grief"
        case .decision:       return "Decision"
        case .task:           return "Task"
        case .risk:           return "Risk"
        case .question:       return "Question"
        case .careFollowUp:   return "Care Follow-Up"
        }
    }
}

// MARK: - Main Chat View

struct AmenMinistryRoomChatView: View {
    let spaceId: String

    @StateObject private var viewModel: AmenMinistryRoomChatViewModel

    init(spaceId: String) {
        self.spaceId = spaceId
        _viewModel = StateObject(wrappedValue: AmenMinistryRoomChatViewModel(spaceId: spaceId))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Matte message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.messages) { message in
                            AmenMinistryRoomMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(red: 0.027, green: 0.024, blue: 0.031))
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        let anim: Animation = reduceMotion
                            ? .easeInOut(duration: 0.01)
                            : .easeInOut(duration: 0.22)
                        withAnimation(anim) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Send error banner
            if let error = viewModel.sendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .accessibilityLabel("Send error: \(error)")
            }

            // Glass composer bar
            glassComposer
        }
        .task {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .sheet(isPresented: $viewModel.showConvictionSheet) {
            convictionSheet
        }
        .sheet(isPresented: $viewModel.showBeforeShareSheet) {
            AmenBeforeShareCheckView(
                warnings: viewModel.activeBeforeShareWarnings,
                onProceed: { viewModel.confirmSendFromBeforeShare() },
                onEdit: { viewModel.dismissBeforeShare() }
            )
        }
    }

    // MARK: - Glass Composer

    private var glassComposer: some View {
        HStack(spacing: 10) {
            // Glass input field
            TextField("Share with the room…", text: $viewModel.composerText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Message composer")

            // Send button (amenPurple fill)
            Button {
                viewModel.requestSend()
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color(red: 0.431, green: 0.294, blue: 0.710))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSending || viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.25)
                }
        }
    }

    // MARK: - Conviction Check Sheet (never moralizing, always dismissable)

    private var convictionSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(red: 0.851, green: 0.643, blue: 0.255))
                .accessibilityHidden(true)

            Text("Pause and reflect?")
                .font(.title2.bold())

            Text("Before sharing, take a moment to consider whether this message aligns with your intentions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                Button("Send Anyway") {
                    viewModel.confirmSendAfterConviction()
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.431, green: 0.294, blue: 0.710))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Keep editing") {
                    viewModel.dismissConviction()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Message Row

struct AmenMinistryRoomMessageRow: View {
    let message: AmenConnectSpacesMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                // Avatar circle (amenPurple)
                Circle()
                    .fill(Color(red: 0.431, green: 0.294, blue: 0.710))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(String(message.authorId.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    // Author name (stub: shows truncated userId)
                    Text(message.authorId.prefix(12).description)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.431, green: 0.294, blue: 0.710))

                    // Message body — matte text
                    Text(message.body)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    // Intent chips — glass pills
                    if !message.detectedIntents.isEmpty {
                        intentChips(message.detectedIntents)
                    }

                    // Care routing banner
                    if message.careRouted {
                        careRoutedBanner
                    }

                    // Timestamp
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buildAccessibilityLabel())
    }

    private func buildAccessibilityLabel() -> String {
        var parts = ["Message from \(message.authorId.prefix(12))"]
        parts.append(message.body)
        if message.careRouted {
            parts.append("Routed to Care Team")
        }
        let intentLabels = message.detectedIntents.map(\.displayLabel).joined(separator: ", ")
        if !intentLabels.isEmpty {
            parts.append("Detected: \(intentLabels)")
        }
        return parts.joined(separator: ". ")
    }

    private func intentChips(_ intents: [AmenConnectSpacesMessageIntent]) -> some View {
        MinistryFlowLayout(spacing: 4) {
            ForEach(intents, id: \.self) { intent in
                Text(intent.displayLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(intent.pillColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(intent.pillColor.opacity(0.15))
                            .overlay {
                                Capsule()
                                    .strokeBorder(intent.pillColor.opacity(0.35), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Detected: \(intent.displayLabel)")
            }
        }
    }

    private var careRoutedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.851, green: 0.643, blue: 0.255))
            Text("Routed to Care Team")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.851, green: 0.643, blue: 0.255))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color(red: 0.851, green: 0.643, blue: 0.255).opacity(0.12))
                .overlay {
                    Capsule()
                        .strokeBorder(Color(red: 0.851, green: 0.643, blue: 0.255).opacity(0.35), lineWidth: 1)
                }
        }
        .accessibilityLabel("Routed to Care Team")
    }
}

// MARK: - FlowLayout (simple horizontal-wrapping layout for intent chips)

struct MinistryFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + spacing
                totalHeight = y
                x = 0
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
    }
}
