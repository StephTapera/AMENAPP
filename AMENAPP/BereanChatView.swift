// BereanChatView.swift
// AMEN App — Berean AI core chat conversation screen.
// ChatGPT-inspired interface with AMEN's white Liquid Glass design.
// Streaming via ClaudeService.shared.sendMessage with structured response system.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics

private struct BereanChatCleanBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.956, green: 0.956, blue: 0.936)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.78),
                    Color(red: 0.94, green: 0.95, blue: 0.93).opacity(0.72),
                    Color(red: 0.98, green: 0.965, blue: 0.94).opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.white.opacity(0.62), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
    }
}

// MARK: - Models

/// Phase H3 — small Identifiable wrapper used by `.sheet(item:)` to
/// present the ReportUnsafeAIResponseSheet bound to a specific message.
private struct ReportingTarget: Identifiable, Equatable {
    let messageId: String
    let conversationId: String
    var id: String { messageId }
}

struct BereanChatMsg: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: BereanChatMsgRole
    var content: String
    var timestamp: Date
    var streamingState: StreamingState = .idle
    var structure: BereanResponseStructure? = nil
    var processingState: String? = nil
    var provenance: BereanProvenanceRecord? = nil

    /// Backward-compatible read for UI code that checks `message.isStreaming`.
    var isStreaming: Bool { streamingState == .streaming }

    enum StreamingState: Equatable {
        case idle
        case streaming
        case completed
        case cancelled
        case failed
    }

    enum BereanChatMsgRole: String, Codable {
        case user, assistant
    }
}

// MARK: - Response Structure

/// Structured response with progressive sections
struct BereanResponseStructure: Equatable {
    var directAnswer: String? = nil
    var meaning: String? = nil
    var context: String? = nil
    var application: String? = nil
    var followUpActions: [FollowUpAction] = []

    struct FollowUpAction: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let icon: String
    }
}

private struct BereanResumeCard: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let prompt: String
    let icon: String
}

private struct BereanChatWorkspaceCard: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
    let accent: Color
    let prompt: String
}

private struct BereanMemoryCard: Identifiable {
    let id = UUID()
    let title: String
    let scope: String
    let prompt: String
}

// MARK: - ViewModel

@MainActor
final class BereanChatViewModel: ObservableObject {
    @Published var messages: [BereanChatMsg] = []
    @Published var inputText: String = "" {
        didSet {
            if AMENFeatureFlags.shared.bereanHelperModelEnabled {
                grokCoordinator.classifyInput(inputText)
            }
        }
    }
    @Published var isThinking: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentMode: BereanPersonalityMode = .askBerean
    /// Non-nil when the backend ran a cheaper model tier than the user requested.
    /// Set from the SSE terminal event's mode authority fields; auto-clears after 4 s.
    @Published var modelFallbackNotice: String? = nil
    @Published var isStudyModeEnabled: Bool = false
    @Published var studyModeState: BereanStudyModeState = .off
    @Published var reasoningNodes: [BereanReasoningNode] = []

    private lazy var db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "" }
    private var streamTask: Task<Void, Never>? = nil

    private let freeMsgLimit = 10
    private let studyModeStorageKey = "berean_study_mode_enabled"
    @Published var messageCount: Int = 0
    @Published var isProUser: Bool = false
    @Published var simpleModeEnabled: Bool = UserDefaults.standard.bool(forKey: "berean_simple_mode")
    var isAtLimit: Bool { !isProUser && messageCount >= freeMsgLimit }
    let sessionId: String
    @Published var crisisEscalationDetected: Bool = false

    // MARK: - System 27: Grok Helper Coordinator
    let grokCoordinator = BereanGrokCoordinator()
    var activePostContext: BereanPostContext? {
        didSet {
            let key = "bereanPostContext_\(sessionId)"
            if let ctx = activePostContext,
               let encoded = try? JSONEncoder().encode(ctx) {
                UserDefaults.standard.set(encoded, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    var preSendInstruction: String?
    var pendingComposerContext: BereanComposerSubmissionContext?

    init(
        mode: BereanPersonalityMode = .askBerean,
        existingSessionId: String? = nil,
        postContext: BereanPostContext? = nil
    ) {
        self.sessionId = existingSessionId ?? UUID().uuidString
        self.currentMode = mode
        // Restore persisted context when resuming a session without a fresh context
        if let freshContext = postContext {
            self.activePostContext = freshContext
        } else if existingSessionId != nil,
                  let data = UserDefaults.standard.data(forKey: "bereanPostContext_\(self.sessionId)"),
                  let saved = try? JSONDecoder().decode(BereanPostContext.self, from: data) {
            self.activePostContext = saved
        } else {
            self.activePostContext = nil
        }
        if existingSessionId == nil {
            messages.append(BereanChatMsg(
                role: .assistant,
                content: "Hey — I'm Berean. Ask me anything. Scripture, life, business, whatever's on your mind.",
                timestamp: .now
            ))
        }
        // Wire Grok coordinator callbacks
        grokCoordinator.onInjectAndSend = { [weak self] text in
            self?.inputText = text
            self?.send()
        }
        grokCoordinator.onSaveOutlineToNotes = { [weak self] outline in
            Task { await self?.saveOutlineToChurchNotes(outline) }
        }
        let storedStudyMode = UserDefaults.standard.bool(forKey: studyModeStorageKey)
        isStudyModeEnabled = storedStudyMode
        studyModeState = storedStudyMode ? .idle : .off
        reasoningNodes = defaultReasoningNodes()
        loadMessageCount()
    }

    // MARK: Resume existing session from Firestore

    func loadExistingSession() async {
        guard !userId.isEmpty else { return }
        do {
            let convRef = db.collection("users").document(userId)
                .collection("bereanConversations").document(sessionId)
            let doc = try await convRef.getDocument()
            guard let data = doc.data() else { return }
            if let modeStr = data["mode"] as? String,
               let mode = BereanPersonalityMode(rawValue: modeStr) {
                currentMode = mode
            }
            // Prefer normalized subcollection (new schema); fall back to embedded array (legacy)
            let msgsSnap = try? await convRef.collection("messages")
                .order(by: "createdAt", descending: false)
                .getDocuments()
            if let msgsSnap, !msgsSnap.documents.isEmpty {
                let loaded = msgsSnap.documents.compactMap { d -> BereanChatMsg? in
                    guard let roleStr = d.data()["role"] as? String,
                          let content = d.data()["content"] as? String,
                          let role = BereanChatMsg.BereanChatMsgRole(rawValue: roleStr) else { return nil }
                    let ts = (d.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    return BereanChatMsg(role: role, content: content, timestamp: ts)
                }
                if !loaded.isEmpty { messages = loaded }
            } else if let msgsData = data["messages"] as? [[String: Any]] {
                // Legacy: messages embedded in the conversation document
                let loaded = msgsData.compactMap { m -> BereanChatMsg? in
                    guard let roleStr = m["role"] as? String,
                          let content = m["content"] as? String,
                          let role = BereanChatMsg.BereanChatMsgRole(rawValue: roleStr) else { return nil }
                    let ts = (m["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    return BereanChatMsg(role: role, content: content, timestamp: ts)
                }
                if !loaded.isEmpty { messages = loaded }
            }
        } catch {
            dlog("BereanChatViewModel.loadExistingSession error: \(error)")
        }
    }

    // MARK: All-Berean cross-session history (memory scope: allBerean)

    private func buildAllBereanHistory(snapshot: [BereanChatMsg]) async -> [OpenAIChatMessage] {
        // Current session tail — last 6 messages
        let currentMsgs = snapshot.dropLast(2).suffix(6)
            .map { OpenAIChatMessage(content: $0.content, isFromUser: $0.role == .user) }

        guard !userId.isEmpty else { return currentMsgs }
        do {
            let snap = try await db.collection("users").document(userId)
                .collection("bereanConversations")
                .order(by: "lastUpdated", descending: true)
                .limit(to: 4)
                .getDocuments()

            var crossMsgs: [OpenAIChatMessage] = []
            for doc in snap.documents {
                guard doc.documentID != sessionId else { continue }
                let convRef = db.collection("users").document(userId)
                    .collection("bereanConversations").document(doc.documentID)

                // Prefer normalized subcollection (new schema)
                var tail: [OpenAIChatMessage] = []
                let msgsSnap = try? await convRef.collection("messages")
                    .order(by: "createdAt", descending: true)
                    .limit(to: 4)
                    .getDocuments()
                if let msgsSnap, !msgsSnap.documents.isEmpty {
                    tail = msgsSnap.documents.reversed().compactMap { d -> OpenAIChatMessage? in
                        guard let role = d.data()["role"] as? String,
                              let content = d.data()["content"] as? String else { return nil }
                        return OpenAIChatMessage(
                            content: String(content.prefix(300)),
                            isFromUser: role == "user"
                        )
                    }
                } else if let msgsData = doc.data()["messages"] as? [[String: Any]] {
                    // Legacy: messages embedded in the conversation document
                    tail = msgsData.suffix(4).compactMap { m -> OpenAIChatMessage? in
                        guard let role = m["role"] as? String,
                              let content = m["content"] as? String else { return nil }
                        return OpenAIChatMessage(
                            content: String(content.prefix(300)),
                            isFromUser: role == "user"
                        )
                    }
                }
                crossMsgs.append(contentsOf: tail)
                if crossMsgs.count >= 8 { break }
            }
            // Prepend cross-session context (older) then current session (newest) — chronological order
            return crossMsgs + currentMsgs
        } catch {
            dlog("BereanChatViewModel.buildAllBereanHistory error: \(error)")
            return currentMsgs
        }
    }

    // MARK: Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, streamTask == nil, !isAtLimit else { return }

        isThinking = true

        AMENAnalyticsService.shared.track(.bereanChatMessageSent(
            tier: BereanModelStore.shared.selectedMode.backendValue,
            mode: BereanModeStore.shared.selectedMode.id
        ))

        inputText = ""
        errorMessage = nil

        let userMsg = BereanChatMsg(role: .user, content: text, timestamp: .now)
        messages.append(userMsg)
        messageCount += 1

        // Placeholder for streaming assistant message
        let assistantMsg = BereanChatMsg(
            role: .assistant,
            content: "",
            timestamp: .now,
            streamingState: .streaming
        )
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        if isStudyModeEnabled {
            beginReasoning()
        }

        // Capture scope and message snapshot before entering Task.
        // Respect the Berean AI personalization toggle before loading any saved user context.
        let personalizationEnabled = BereanAISettingsStore.personalizationEnabled
        let conciseModeEnabled = BereanAISettingsStore.conciseModeEnabled
        let scriptureSourcesRequired = BereanAISettingsStore.scriptureSourcesRequired
        let focusTopics = BereanAISettingsStore.focusTopics
        let memoryScope: BereanMemoryScope = personalizationEnabled ? BereanMemoryScopeStore.shared.scope : .off
        let capturedMessages = messages
        let composerContext = pendingComposerContext

        // System 27: Capture Grok provenance before Task — value-type safe to cross actor boundary
        let (grokHelperUsed, grokExternalUsed) = grokCoordinator.consumePendingFlags()
        let grokClassification = BereanGrokService.shared.classify(text: text)
        let capturedProvenance = grokCoordinator.recordForMessage(
            helperUsed: grokHelperUsed,
            externalUsed: grokExternalUsed,
            sensitiveDetected: grokClassification.isSensitive
        )

        // CRASH-3 FIX: [weak self] breaks the ViewModel → Task → ViewModel retain cycle.
        // The ViewModel holds streamTask strongly; Task previously captured self strongly.
        // If the view is dismissed mid-stream, [weak self] allows the ViewModel to
        // deallocate instead of being kept alive by the in-flight Task.
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Build conversation history — .allBerean fetches cross-session context from Firestore
                let history: [OpenAIChatMessage]
                switch memoryScope {
                case .off:
                    history = []
                case .thisChat, .thisProject:
                    history = capturedMessages.dropLast(2).suffix(10)
                        .map { OpenAIChatMessage(content: $0.content, isFromUser: $0.role == .user) }
                case .allBerean:
                    history = await buildAllBereanHistory(snapshot: capturedMessages)
                }

                // Study mode: wire each active reasoning node to a distinct retrieval directive
                let studyModeSuffix: String? = {
                    guard self.isStudyModeEnabled else { return nil }
                    let strategies = self.reasoningNodes
                        .filter { $0.state == .active || $0.state == .scanning }
                        .map { "• \($0.category.retrievalStrategy)" }
                    guard !strategies.isEmpty else { return nil }
                    return "[STUDY MODE — Address each dimension before answering:]\n"
                        + strategies.joined(separator: "\n")
                        + "\n\nStructure your response to explicitly cover each point above."
                }()

                let combinedSuffix: String? = { [self] in
                    var parts = [studyModeSuffix].compactMap { $0 }
                    if let preSendInstruction = self.preSendInstruction, !preSendInstruction.isEmpty {
                        parts.append(preSendInstruction)
                    }
                    if conciseModeEnabled {
                        parts.append("Keep the answer concise by default: lead with the answer, avoid unnecessary setup, and expand only where the user asks for depth.")
                    }
                    if scriptureSourcesRequired {
                        parts.append("When explaining Scripture or making a biblical claim, cite specific verse references. If no clear passage applies, say that plainly instead of guessing.")
                    }
                    if personalizationEnabled && !focusTopics.isEmpty {
                        parts.append("When relevant, keep these user focus topics in mind without forcing them into unrelated answers: \(focusTopics.joined(separator: ", ")).")
                    }
                    if self.simpleModeEnabled {
                        parts.append("Use a simple, clear format with shorter sentences, minimal jargon, and one practical next step.")
                    }
                    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
                }()

                let capturedSelectedMode = BereanModelStore.shared.selectedMode.backendValue
                let stream = ClaudeService.shared.sendBereanChatMessage(
                    text,
                    conversationId: sessionId,
                    conversationHistory: history,
                    mode: currentMode,
                    selectedMode: capturedSelectedMode,
                    memoryScope: memoryScope,
                    postContext: activePostContext,
                    systemPromptSuffix: combinedSuffix,
                    composerContext: composerContext,
                    onPreflight: { preflight in
                        if preflight.shortCircuitResponse != nil {
                            self.crisisEscalationDetected = true
                        }
                    },
                    onModeAuthority: { [weak self] authority in
                        guard let self else { return }
                        // Update quota/credit state using the authoritative server response.
                        BereanModelStore.shared.updateUsageState(
                            deepCreditsRemaining: authority.deepCreditsRemaining,
                            quotaExceeded: authority.quotaExceeded
                        )
                        guard authority.wasDowngraded else {
                            // Accepted mode matches request — sync if server echoed it back.
                            if let accepted = authority.acceptedMode,
                               let resolvedMode = BereanModelMode(rawValue: accepted) {
                                BereanModelStore.shared.selectedMode = resolvedMode
                            }
                            return
                        }
                        // Server ran a cheaper tier — fall back store + show notice.
                        BereanModelStore.shared.fallbackToCore()
                        let notice: String
                        if authority.entitlementRequired == true {
                            notice = "Berean switched to Core — Deep requires a Pro subscription."
                        } else if authority.quotaExceeded == true {
                            let credits = authority.deepCreditsRemaining ?? 0
                            notice = "Deep credits exhausted (\(credits) remaining). Using Berean Core."
                        } else {
                            notice = authority.fallbackReason ?? "Switched to Berean Core for this response."
                        }
                        self.modelFallbackNotice = notice
                        AMENAnalyticsService.shared.track(.bereanTierDowngradeBannerShown(
                            requestedTier: authority.fallbackMode ?? capturedSelectedMode,
                            grantedTier: authority.acceptedMode ?? "core"
                        ))
                        // Auto-clear after 4 seconds so the banner doesn't linger.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            if self.modelFallbackNotice == notice {
                                self.modelFallbackNotice = nil
                            }
                        }
                    }
                )
                for try await chunk in stream {
                    try Task.checkCancellation()
                    messages[assistantIndex].content += chunk
                }
                // Crisis short-circuit responses are pre-approved human text (988 Lifeline,
                // Crisis Text Line). Skip sanitization and alignment overrides entirely —
                // a false-positive .blocked result would erase life-saving contact numbers.
                if !crisisEscalationDetected {
                    // Belt-and-suspenders: run the client-side safety regex on the fully
                    // assembled response. The backend already validates, but this catches
                    // anything that slipped through on a bad connection or edge case.
                    let assembled = messages[assistantIndex].content
                    let safe = ClaudeService.shared.sanitizeResponse(assembled)
                    if safe != assembled {
                        messages[assistantIndex].content = safe
                    }
                    if let alignmentResult = try? await BiblicalAlignmentService.shared.checkBiblicalAlignment(
                        text: messages[assistantIndex].content,
                        targetType: "berean_response",
                        sourceSurface: "berean_chat",
                        requestedLens: simpleModeEnabled ? .simple : nil
                    ) {
                        switch alignmentResult.status {
                        case .aligned:
                            break
                        case .contextNeeded:
                            messages[assistantIndex].content = "Context note: this answer may benefit from prayerful reflection.\n\n" + messages[assistantIndex].content
                        case .needsDiscernment:
                            if let rewritten = alignmentResult.rewriteSuggestion, !rewritten.isEmpty {
                                messages[assistantIndex].content = rewritten
                            }
                        case .blocked, .humanReview:
                            messages[assistantIndex].content = "I can’t help with that request in its current form. If you want, I can help you pause, pray, or take a safer next step."
                        }
                    }
                }
                messages[assistantIndex].streamingState = .completed
                messages[assistantIndex].provenance = capturedProvenance
                if isStudyModeEnabled {
                    resolveReasoning()
                }
                let completedAssistantText = messages[assistantIndex].content
                preSendInstruction = nil
                pendingComposerContext = nil
                // Run intelligence layer: safety check, follow-up suggestions, auto-save
                await BereanIntelligenceCoordinator.shared.processResponse(
                    sessionId: sessionId,
                    responseText: completedAssistantText,
                    autoSaveInsight: true
                )
                await persistExchange(userText: text, assistantText: completedAssistantText, composerContext: composerContext)
            } catch is CancellationError {
                messages[assistantIndex].streamingState = .cancelled
                if isStudyModeEnabled {
                    resolveReasoning()
                }
                if messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content = "Cancelled."
                }
            } catch {
                messages[assistantIndex].streamingState = .failed
                if isStudyModeEnabled {
                    resolveReasoning()
                }
                messages[assistantIndex].content = "Something went wrong. Please try again."
                errorMessage = error.localizedDescription
                dlog("BereanChatView stream error: \(error)")
            }
            streamTask = nil
            isThinking = false
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isThinking = false
    }

    func setStudyModeEnabled(_ enabled: Bool) {
        isStudyModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: studyModeStorageKey)
        studyModeState = enabled ? .idle : .off
        if enabled && reasoningNodes.isEmpty {
            reasoningNodes = defaultReasoningNodes()
        }
    }

    func setDiscernmentInstruction(_ instruction: String?) {
        preSendInstruction = instruction
    }

    func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func saveOutlineToChurchNotes(_ outline: BereanStudyOutline) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var note = ChurchNoteV2.empty(userId: uid)
        note.title = outline.title
        note.scriptureReferences = outline.keyPassages
        note.tags = ["berean_study_outline"]
        note.updatedAt = Date()
        do { try await ChurchNoteBlockRepository.shared.createNote(note) } catch {
            dlog("[BereanChatViewModel] saveOutlineToChurchNotes failed: \(error)")
        }
    }

    private func defaultReasoningNodes() -> [BereanReasoningNode] {
        BereanReasoningCategory.allCases.map { category in
            BereanReasoningNode(category: category, state: .idle, summary: nil)
        }
    }

    private func beginReasoning() {
        studyModeState = .reasoning
        reasoningNodes = reasoningNodes.map { node in
            var updated = node
            updated.state = .scanning
            return updated
        }
        if let scriptureIndex = reasoningNodes.firstIndex(where: { $0.category == .scripture }) {
            reasoningNodes[scriptureIndex].state = .active
        }
        if let contextIndex = reasoningNodes.firstIndex(where: { $0.category == .historicalContext }) {
            reasoningNodes[contextIndex].state = .active
        }
        if let applicationIndex = reasoningNodes.firstIndex(where: { $0.category == .application }) {
            reasoningNodes[applicationIndex].state = .active
        }
    }

    private func resolveReasoning() {
        studyModeState = .resolved
        reasoningNodes = reasoningNodes.map { node in
            var updated = node
            updated.state = .complete
            if updated.summary == nil {
                updated.summary = summary(for: updated.category)
            }
            return updated
        }
    }

    private func summary(for category: BereanReasoningCategory) -> String {
        switch category {
        case .scripture: return "Primary passages highlighted"
        case .crossReferences: return "Related verses compared"
        case .commentary: return "Trusted commentary matched"
        case .sermons: return "Sermon insights noted"
        case .articles: return "Articles reviewed"
        case .originalLanguage: return "Key words checked"
        case .historicalContext: return "Historical setting applied"
        case .application: return "Practical application mapped"
        case .notes: return "Notes prepared for handoff"
        }
    }

    // MARK: Persistence

    /// Persist a completed user→assistant exchange using a normalized subcollection schema.
    ///
    /// Messages are written individually to `bereanConversations/{id}/messages/{msgId}` so:
    ///  - Large conversations never hit Firestore's 1 MB document limit
    ///  - Individual messages can be deleted for GDPR compliance
    ///  - Real-time listeners on the subcollection work cross-device
    ///
    /// Legacy sessions that were stored with an embedded `messages` array are still readable
    /// (via the fallback path in `loadExistingSession` / `buildAllBereanHistory`).
    private func persistExchange(userText: String, assistantText: String, composerContext: BereanComposerSubmissionContext? = nil) async {
        guard !userId.isEmpty else { return }
        let memoryScope = BereanMemoryScopeStore.shared.scope
        let convRef = db.collection("users").document(userId)
            .collection("bereanConversations").document(sessionId)
        if memoryScope == .off {
            await deleteConversation(at: convRef)
            return
        }
        let title = messages.first(where: { $0.role == .user })
            .map { String($0.content.prefix(60)) } ?? ""
        let now = Date()
        // Write conversation metadata document (no embedded messages array)
        let meta: [String: Any] = [
            "conversationId": sessionId,
            "title": title,
            "mode": currentMode.rawValue,
            "memoryScopeName": memoryScope.rawValue,
            "lastUpdated": Timestamp(date: now),
            "messageCount": messages.count
        ]
        do {
            try await convRef.setData(meta, merge: true)
        } catch {
            dlog("⚠️ BereanChatViewModel.persistExchange metadata: \(error)")
        }
        // Write each message to the normalized subcollection
        let msgsRef = convRef.collection("messages")
        let userMsgId = UUID().uuidString
        var userMessageData: [String: Any] = [
            "id": userMsgId,
            "conversationId": sessionId,
            "role": "user",
            "content": userText,
            "createdAt": Timestamp(date: now)
        ]
        if let composerContext {
            userMessageData["composerContext"] = composerContext.callData
        }
        do {
            try await msgsRef.document(userMsgId).setData(userMessageData)
        } catch {
            dlog("⚠️ BereanChatViewModel.persistExchange userMsg: \(error)")
        }
        let assistantMsgId = UUID().uuidString
        do {
            try await msgsRef.document(assistantMsgId).setData([
                "id": assistantMsgId,
                "conversationId": sessionId,
                "role": "assistant",
                "content": assistantText,
                "createdAt": Timestamp(date: now)
            ])
        } catch {
            dlog("⚠️ BereanChatViewModel.persistExchange assistantMsg: \(error)")
        }
    }

    func clearConversationHistory() {
        streamTask?.cancel()
        messages = [BereanChatMsg(
            role: .assistant,
            content: "Hey — I'm Berean. Ask me anything. Scripture, life, business, whatever's on your mind.",
            timestamp: .now
        )]
        messageCount = 0
        errorMessage = nil
        crisisEscalationDetected = false
        guard !userId.isEmpty else { return }
        let convRef = db.collection("users").document(userId)
            .collection("bereanConversations")
            .document(sessionId)
        Task { await deleteConversation(at: convRef) }
    }

    private func loadMessageCount() {
        guard !userId.isEmpty else { return }
        db.collection("users").document(userId)
            .getDocument { [weak self] doc, _ in
                DispatchQueue.main.async {
                    self?.messageCount = doc?.data()?["chatMessageCount"] as? Int ?? 0
                }
            }
    }

    private func deleteConversation(at convRef: DocumentReference) async {
        do {
            let messageSnapshot = try await convRef.collection("messages").getDocuments()
            for document in messageSnapshot.documents {
                do { try await document.reference.delete() }
                catch { dlog("⚠️ BereanChatViewModel.deleteConversation message: \(error)") }
            }
            do { try await convRef.delete() }
            catch { dlog("⚠️ BereanChatViewModel.deleteConversation conv: \(error)") }
        } catch {
            dlog("BereanChatViewModel.deleteConversation error: \(error)")
        }
    }
}

// MARK: - BereanChatView

struct BereanChatView: View {
    /// Pass a mode to seed the conversation; defaults to shepherd.
    var initialMode: BereanPersonalityMode = .askBerean
    /// Optional initial query auto-sent on appear.
    var initialQuery: String? = nil
    /// Optional conversation title shown in nav bar center.
    var conversationTitle: String? = nil
    /// Typed post routing payload for Live Activity deep dives.
    var postContext: BereanPostContext? = nil
    /// Pass an existing Firestore session ID to resume that conversation.
    var existingSessionId: String? = nil

    @StateObject private var vm: BereanChatViewModel
    @StateObject private var composerVM = BereanComposerViewModel()
    @StateObject private var scrollCoordinator = BereanScrollCoordinator()
    @StateObject private var wallpaperManager = BereanWallpaperManager()
    @State private var showModeSheet = false
    @State private var showModeDrawer = false
    @State private var showCompactModePicker = false
    @State private var showWallpaperPicker = false
    @State private var sendSweep = false
    @State private var pendingUserSend = false
    @State private var postAvailabilityMessage: String? = nil
    @State private var validatedPostContext: BereanPostContext?
    @State private var initialSendTask: Task<Void, Never>?
    @State private var hasPreparedInitialPrompt = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("berean_show_provenance_labels") private var showProvenanceLabels: Bool = true

    // MARK: - Addition 1: Context Memory rail
    @State private var selectedContextSources: Set<BereanContextSource> = [.thisChat]

    // MARK: - Addition 3: Save to Church Notes toast
    @State private var showSavedToNotesToast = false
    @State private var showSpiritualMemorySheet = false
    @State private var hasTrackedSessionStart = false
    @State private var discernmentPrompt: DiscernmentPromptResult?
    @State private var pendingDiscernmentInstruction: String?
    @State private var correctionTargetMessage: BereanChatMsg?
    @State private var showAttachmentPicker = false
    @State private var attachmentPickerMode: BereanAttachmentPickerMode = .file
    @State private var showAttachmentsComingSoon = false
    @State private var showVoiceDisabledAlert = false

    // Phase 5 / P0-2: real Berean voice input. Replaces the prior
    // dlog-only stub. See BereanVoiceInputSheet.swift.
    @State private var showVoiceInputSheet = false

    // Phase H3 / App Review Guideline 1.2: "Report this response"
    // affordance on Berean assistant messages.
    @State private var reportingMessageId: String?
    @State private var showReportedConfirmation: Bool = false

    // MARK: - Intelligence layer
    @ObservedObject private var intelligence = BereanIntelligenceCoordinator.shared

    init(initialMode: BereanPersonalityMode = .askBerean,
         initialQuery: String? = nil,
         conversationTitle: String? = nil,
         postContext: BereanPostContext? = nil,
         existingSessionId: String? = nil) {
        self.initialMode = initialMode
        self.initialQuery = initialQuery
        self.conversationTitle = conversationTitle
        self.postContext = postContext
        self.existingSessionId = existingSessionId
        _validatedPostContext = State(initialValue: postContext)
        _vm = StateObject(wrappedValue: BereanChatViewModel(
            mode: initialMode,
            existingSessionId: existingSessionId,
            postContext: postContext
        ))
    }

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var lastStreamingAutoScrollAt: Date = .distantPast
    @State private var streamingAutoScrollTimer: Timer?
    @State private var showHero: Bool = true
    @State private var selectedReasoningNode: BereanReasoningNode?
    // Staggered entrance animation state
    @State private var heroAppeared: Bool = false
    @State private var cardsAppeared: Bool = false

    // MARK: - Interaction layer: mode bar, floating tab bar, context lens
    @State private var bereanInteractionMode: BereanInteractionMode = .ask
    @State private var bereanSurfaceTab: BereanSurfaceTab = .chat
    @State private var showContextLens: Bool = false

    private let resumeCards: [BereanResumeCard] = [
        .init(
            title: "Continue Matthew 11 study",
            detail: "Meaning, context, and application from your last thread",
            prompt: "Continue our Matthew 11 study and pick up where we left off.",
            icon: "book.pages"
        ),
        .init(
            title: "Revisit cross-reference thread",
            detail: "Compare related passages with a cleaner summary",
            prompt: "Bring back the cross-references we discussed and summarize the key links.",
            icon: "arrow.triangle.branch"
        ),
        .init(
            title: "Find past prayer plan",
            detail: "Search older conversations semantically instead of by title",
            prompt: "Find the prayer plan we made before and show the main steps again.",
            icon: "clock.arrow.circlepath"
        )
    ]

    private let workspaceCards: [BereanChatWorkspaceCard] = [
        .init(
            title: "AMEN",
            detail: "Product, prompts, and interaction decisions",
            icon: "square.stack.3d.up.fill",
            accent: Color(red: 0.79, green: 0.66, blue: 0.30),
            prompt: "Open the AMEN project context and help me continue product work."
        ),
        .init(
            title: "Berean AI",
            detail: "Conversation design, memory, and study systems",
            icon: "brain.head.profile",
            accent: Color(red: 0.53, green: 0.61, blue: 0.84),
            prompt: "Switch into Berean AI project mode and help me design the chat experience."
        ),
        .init(
            title: "Church Notes",
            detail: "Sermon insights, anchors, and follow-up ideas",
            icon: "note.text",
            accent: Color(red: 0.51, green: 0.71, blue: 0.62),
            prompt: "Use my Church Notes context and help me connect recent sermon insights."
        )
    ]

    private let memoryCards: [BereanMemoryCard] = [
        .init(
            title: "Structured responses should stay scripture-first.",
            scope: "Global memory",
            prompt: "Use the memory that responses should stay scripture-first and help me refine it."
        ),
        .init(
            title: "Mobile composer should feel compact, liquid, and thumb-friendly.",
            scope: "Project memory",
            prompt: "Recall that the composer should stay compact and thumb-friendly, then apply it here."
        ),
        .init(
            title: "Search old threads semantically before starting from scratch.",
            scope: "Workflow memory",
            prompt: "Search my older threads semantically and bring back anything relevant before answering."
        )
    ]

    private struct DiscernmentPromptSheet: Identifiable {
        let id = UUID()
        let prompt: DiscernmentPromptResult
    }

    var body: some View {
        GeometryReader { proxy in
            // proxy.safeAreaInsets.top is 59pt on Dynamic Island devices,
            // 47pt on TrueDepth notch devices, ≤24pt on SE/older.
            // proxy.safeAreaInsets.bottom is ~34pt on Face ID phones (home indicator),
            // 0 on devices with a physical Home button.
            let metrics = BereanLayoutMetrics(size: proxy.size,
                                              topSafeAreaInset: proxy.safeAreaInsets.top,
                                              bottomSafeAreaInset: proxy.safeAreaInsets.bottom)

            ZStack(alignment: .bottom) {
                BereanChatCleanBackground()
                    .ignoresSafeArea()
                wallpaperManager.wallpaperView()
                    .opacity(0.08)
                    .ignoresSafeArea()
                Color.white.opacity(0.50)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    smartBlurHeader(metrics: metrics)
                    contentScrollView(metrics: metrics)
                }

                VStack(spacing: 0) {
                    if let notice = vm.modelFallbackNotice {
                        modeFallbackBanner(notice)
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if vm.isAtLimit {
                        paywallBanner
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, 8)
                    }
                    if let banner = intelligence.safetyBanner, !vm.isThinking {
                        intelligenceSafetyBanner(banner)
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if !intelligence.followUpSuggestions.isEmpty && !vm.isThinking {
                        intelligenceFollowUpRow
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    // Only show static suggestion chips when the AI hasn't produced
                    // follow-up suggestions yet — avoids duplicate actions and keeps
                    // the overlay height in check.
                    if shouldShowSuggestionRow && intelligence.followUpSuggestions.isEmpty {
                        focusedSuggestionRow
                            .padding(.bottom, shouldShowContextRail ? 8 : 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if shouldShowContextRail {
                        compactContextRail
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    // System 27: Thinking step banner (cycles during inference)
                    if vm.isThinking && AMENFeatureFlags.shared.bereanHelperModelEnabled {
                        BereanThinkingStateBanner(
                            step: BereanGrokService.shared.thinkingStep(for: vm.grokCoordinator.thinkingStepIndex)
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    // System 27: Grok helper pill row + sheet presentations
                    BereanGrokOverlay(coordinator: vm.grokCoordinator, currentText: vm.inputText)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    // Context lens — floats above mode bar when thinking or manually pinned
                    if vm.isThinking || showContextLens {
                        BereanContextLensView.fromConversationState(
                            mode: bereanInteractionMode,
                            isThinking: vm.isThinking,
                            messageCount: vm.messages.count
                        )
                        .padding(.horizontal, metrics.contentHorizontalPadding)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .onTapGesture { showContextLens = false }
                    }

                    selectedComposerModeChip
                        .padding(.horizontal, metrics.contentHorizontalPadding)
                        .padding(.bottom, 6)

                    adaptiveComposer(metrics: metrics, containerWidth: proxy.size.width)
                }
                .background(
                    // Scrim gradient fades up from the bottom so content under the composer
                    // stays legible without a heavy white plate. Kept subtle so the glass
                    // capsule reads as floating rather than sitting on a card tray.
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(contrastStyle.scrimOpacity + 0.12)
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.72)
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .navigationBarHidden(true)
            .bereanSelahMode(bereanSurfaceTab == .selah)
            .onChange(of: bereanInteractionMode) { _, newMode in
                vm.currentMode = newMode.personalityMode
            }
            .sheet(isPresented: $showModeSheet) {
                BereanModesSheet()
            }
            .sheet(isPresented: $showModeDrawer) {
                BereanModeDrawer(selectedMode: $vm.currentMode)
            }
            .confirmationDialog("Berean mode", isPresented: $showCompactModePicker, titleVisibility: .visible) {
                Button("Scripture") { setCompactMode(.scriptureStudy) }
                Button("Prayer") { setCompactMode(.prayerCompanion) }
                Button("Deep Study") { setCompactMode(.deepStudy) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose how Berean should respond.")
            }
            .sheet(isPresented: $showWallpaperPicker) {
                BereanWallpaperPickerSheet(manager: wallpaperManager)
            }
            .sheet(isPresented: $showAttachmentPicker) {
                BereanAttachmentPickerSheet(mode: attachmentPickerMode) { result in
                    composerVM.attach(BereanComposerAttachment(
                        displayName: result.displayName,
                        type: attachmentPickerMode.analyticsName,
                        promptPrefix: result.promptPrefix,
                        contextText: result.contextText,
                        contentType: result.contentType,
                        byteCount: result.byteCount,
                        storagePath: result.storagePath,
                        downloadURL: result.downloadURL
                    ))
                    Analytics.logEvent("berean_attachment_added", parameters: [
                        "mode": vm.currentMode.rawValue,
                        "type": attachmentPickerMode.analyticsName,
                        "has_storage_path": result.storagePath?.isEmpty == false,
                        "byte_count": result.byteCount ?? 0
                    ])
                    vm.inputText = attachmentPrompt(for: result)
                    inputFocused = true
                }
            }
            .alert("Attachments unavailable", isPresented: $showAttachmentsComingSoon) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Attachment upload is not enabled for this build. Describe what you want Berean to consider in the chat instead.")
            }
            .alert("Voice input is off", isPresented: $showVoiceDisabledAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Turn on Allow voice input in Berean AI settings before using the microphone.")
            }
            // Phase 5 / P0-2: real voice input. User must review/edit and
            // explicitly tap Send — no auto-submit from the sheet itself.
            .sheet(isPresented: $showVoiceInputSheet) {
                BereanVoiceInputSheet(
                    onAccept: { transcript in
                        vm.inputText = transcript
                        inputFocused = true
                    },
                    onCancel: { /* nothing — sheet dismisses itself */ }
                )
            }
            // Phase H3 / App Review Guideline 1.2: "Report this AI
            // response" sheet. Bound to the assistant-message context
            // menu via `reportingMessageId`.
            .sheet(item: Binding<ReportingTarget?>(
                get: {
                    reportingMessageId.map {
                        ReportingTarget(messageId: $0, conversationId: vm.sessionId)
                    }
                },
                set: { newValue in reportingMessageId = newValue?.messageId }
            )) { target in
                ReportUnsafeAIResponseSheet(
                    messageId: target.messageId,
                    conversationId: target.conversationId,
                    surface: .bereanChat,
                    onSubmitted: { _ in
                        reportingMessageId = nil
                        showReportedConfirmation = true
                    }
                )
            }
            .alert("Thank you", isPresented: $showReportedConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your report was submitted. Our team will review it.")
            }
            .sheet(isPresented: $showSpiritualMemorySheet) {
                NavigationStack {
                    SpiritualMemoryView()
                        .navigationTitle("Spiritual Memory")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedReasoningNode) { node in
                BereanReasoningSummarySheet(node: node)
            }
            .sheet(item: $correctionTargetMessage) { message in
                CorrectTheAIView(
                    originalText: message.content,
                    onSave: { lens, correction, remember in
                        Task {
                            _ = try? await BiblicalAlignmentService.shared.saveAICorrection(
                                targetType: "berean_response",
                                targetId: nil,
                                originalText: message.content,
                                correctionText: correction,
                                selectedLens: lens,
                                correctionIntent: "tone",
                                savedToProfile: remember
                            )
                            correctionTargetMessage = nil
                        }
                    },
                    onApplyRewrite: { lens in
                        Task {
                            let rewrite = try? await BiblicalAlignmentService.shared.suggestBiblicalRewrite(
                                originalText: message.content,
                                lens: lens,
                                targetType: "berean_response"
                            )
                            if let rewritten = rewrite?.rewrittenText {
                                vm.updateAssistantMessage(id: message.id, content: rewritten)
                            }
                            correctionTargetMessage = nil
                        }
                    },
                    onCancel: {
                        correctionTargetMessage = nil
                    }
                )
            }
            .sheet(item: Binding<DiscernmentPromptSheet?>(
                get: { discernmentPrompt.map { DiscernmentPromptSheet(prompt: $0) } },
                set: { _ in discernmentPrompt = nil }
            )) { sheet in
                SpiritualDiscernmentPromptView(
                    prompt: sheet.prompt,
                    onSelect: { option in
                        pendingDiscernmentInstruction = option.label
                        vm.setDiscernmentInstruction(instructionText(for: option.label))
                        discernmentPrompt = nil
                        vm.send()
                    },
                    onDismiss: {
                        discernmentPrompt = nil
                        vm.send()
                    }
                )
            }
            // Addition 2: Scripture chip sheet
            // Addition 3: Saved-to-Notes toast
            .overlay(alignment: .top) {
                if showSavedToNotesToast {
                    Text("Saved to Church Notes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.82))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        )
                        .padding(.top, 56)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSavedToNotesToast)
            .onDisappear {
                BereanIntelligenceCoordinator.shared.onSessionEnd()
            }
            .task {
                guard !hasPreparedInitialPrompt else { return }
                hasPreparedInitialPrompt = true
                if !hasTrackedSessionStart {
                    hasTrackedSessionStart = true
                    AMENAnalyticsService.shared.track(.bereanSessionStarted)
                    BereanIntelligenceCoordinator.shared.onSessionStart(sessionId: vm.sessionId)
                    await AmenJourneyContinuityEngine.shared.bereanSessionOpened()
                }
                if existingSessionId != nil {
                    await vm.loadExistingSession()
                    showHero = false
                }
                if let postContext {
                    dlog("📖 [BereanLiveActivity] BereanChatView entry for post \(postContext.postId)")
                    CrashlyticsIntegration.logAction("berean_live_activity_chat_entry")
                    CrashlyticsIntegration.setAppState(key: "berean_chat_post_id", value: postContext.postId)
                    await validatePostContextAvailability(postContext)
                }

                let resolvedInitialQuery = initialQuery?.isEmpty == false
                    ? initialQuery
                    : validatedPostContext?.initialPrompt

                if let query = resolvedInitialQuery, !query.isEmpty {
                    vm.inputText = query
                    showHero = false
                    // Short settling delay so the sheet present animation completes before
                    // the streaming spinner appears, preventing a jarring mid-animation flicker.
                    pendingUserSend = true
                    initialSendTask?.cancel()
                    initialSendTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        await prepareAndSendMessage()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .postEdited)) { notification in
                Task { await handlePostContextNotification(notification) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { notification in
                Task { await handlePostContextNotification(notification) }
            }
            .onChange(of: vm.isThinking) { _, thinking in
                if thinking {
                    composerVM.setState(.streaming)
                    vm.grokCoordinator.startThinkingCycle()
                } else {
                    if composerVM.state == .streaming {
                        composerVM.setState(.idle)
                    }
                    vm.grokCoordinator.stopThinkingCycle()
                    streamingAutoScrollTimer?.invalidate()
                    streamingAutoScrollTimer = nil
                }
            }
            .onDisappear {
                initialSendTask?.cancel()
                initialSendTask = nil
                pendingUserSend = false
                vm.cancelStreaming()
                streamingAutoScrollTimer?.invalidate()
                streamingAutoScrollTimer = nil
            }
        }
        .userActivity(AmenHandoff.BereanChat.activityType) { activity in
            let a = AmenHandoff.BereanChat.makeActivity(
                sessionId: vm.sessionId,
                lastQuery: vm.inputText.isEmpty ? nil : vm.inputText
            )
            activity.title = a.title
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            if let info = a.userInfo { activity.addUserInfoEntries(from: info) }
        }
    }

    private func handleSendTap() {
        let text = vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            let prompt = try? await BiblicalAlignmentService.shared.getDiscernmentPrompt(text: text, surface: "berean_chat")
            if let prompt, prompt.shouldPrompt {
                await MainActor.run {
                    discernmentPrompt = prompt
                }
            } else {
                await MainActor.run {
                    vm.send()
                }
            }
        }
    }

    private func instructionText(for label: String) -> String {
        switch label.lowercased() {
        case let value where value.contains("scripture"):
            return "Answer with biblical grounding and clear scripture context when relevant."
        case let value where value.contains("pastoral"):
            return "Use a gentle pastoral tone with emotional and spiritual care."
        case let value where value.contains("study"):
            return "Use study mode with deeper context and explanation."
        case let value where value.contains("practical"):
            return "Use practical wisdom and clear next steps."
        case let value where value.contains("simple"):
            return "Use simple language, short sentences, and a calm, clear structure."
        default:
            return "Keep the answer practical and low-pressure."
        }
    }

    // MARK: - Smart Blur Header (scroll-reactive)

    private func smartBlurHeader(metrics: BereanLayoutMetrics) -> some View {
        let blurIntensity = min(scrollOffset / 100, 1.0)
        // Compression starts at headerCompressionThreshold (40pt), fully compressed by 120pt
        let compressionProgress = min(max((scrollOffset - metrics.headerCompressionThreshold) / 80, 0), 1.0)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Back button
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundColor(BereanColor.textPrimary)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().fill(Color.white.opacity(0.64)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.80), lineWidth: 0.7))
                                .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                // Center: title fades in at low scroll; mode capsule fades in at high scroll
                ZStack {
                    // Conversation title (visible at low scroll)
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(conversationTitle ?? "Berean")
                            .font(.systemScaled(15, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(BereanColor.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.60)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.80), lineWidth: 0.7))
                            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                    )
                    .opacity((0.72 + blurIntensity * 0.28) * (1 - compressionProgress))

                    // Compressed mode capsule (visible when scrolled far)
                    if compressionProgress > 0 {
                        headerModeCapsule(compressionProgress: compressionProgress)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Study toggle hides into the mode capsule when fully compressed
                    if compressionProgress < 0.85 {
                        studyModeToggle
                            .opacity(1 - compressionProgress)
                    }
                    headerMenuButton
                }
            }
            .padding(.horizontal, metrics.contentHorizontalPadding + 2)
            // Vertical padding compresses from full to tight as user scrolls.
            .padding(.top, metrics.headerVerticalPadding + 2 - compressionProgress * 4)
            .padding(.bottom, 8 - compressionProgress * 3)

            // Bottom separator appears with scroll
            Rectangle()
                .fill(BereanColor.separator.opacity(blurIntensity * 0.6))
                .frame(height: 0.5)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.18 + blurIntensity * 0.42)))
                .opacity(0.58 + blurIntensity * 0.42)
                .ignoresSafeArea(edges: .top)
        )
        .animation(Motion.adaptive(.easeOut(duration: 0.18)), value: compressionProgress)
        .animation(Motion.adaptive(.easeOut(duration: 0.15)), value: blurIntensity)
    }

    /// The mode + study indicator that appears in the header centre when scrolled.
    private func headerModeCapsule(compressionProgress: CGFloat) -> some View {
        Button {
            showModeDrawer = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: vm.currentMode.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(vm.currentMode.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                if vm.isStudyModeEnabled {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.5)
            }
            .foregroundStyle(contrastStyle.foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.60)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .opacity(compressionProgress)
        .scaleEffect(0.9 + compressionProgress * 0.1, anchor: .center)
    }

    private var studyModeToggle: some View {
        Button {
            withAnimation(BereanAnimationCoordinator.softSpring) {
                vm.setStudyModeEnabled(!vm.isStudyModeEnabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Study")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(vm.isStudyModeEnabled ? Color.white : contrastStyle.foregroundColor.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(vm.isStudyModeEnabled ? Color.black : Color.white.opacity(0.6))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Study Mode")
        .accessibilityValue(vm.isStudyModeEnabled ? "On" : "Off")
    }

    private var headerMenuButton: some View {
        Menu {
            Button("Response Mode") {
                showModeDrawer = true
            }
            Button("Wallpaper") { showWallpaperPicker = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundColor(BereanColor.textPrimary)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.64)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.80), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Options")
    }

    private var contrastStyle: BereanContrastStyle {
        wallpaperManager.contrastStyle
    }

    // MARK: - Content Scroll View

    private func contentScrollView(metrics: BereanLayoutMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let postAvailabilityMessage {
                        Text(postAvailabilityMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.82))
                            )
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                    }

                    // Hero section (shown when no messages yet)
                    if showHero && vm.messages.count <= 1 {
                        heroSection
                            .padding(.top, 12)
                            .padding(.bottom, 18)
                            .id("hero")
                            .opacity(heroAppeared ? 1 : 0)
                            .offset(y: heroAppeared ? 0 : 14)
                            .onAppear {
                                guard !heroAppeared else { return }
                                withAnimation(Motion.adaptive(.spring(response: 0.52, dampingFraction: 0.82)).delay(0.05)) {
                                    heroAppeared = true
                                }
                            }

                        adaptivePromptSurface
                            .padding(.horizontal, 18)
                            .padding(.bottom, 12)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 18)
                            .onAppear {
                                guard !cardsAppeared else { return }
                                withAnimation(Motion.adaptive(.spring(response: 0.50, dampingFraction: 0.84)).delay(0.20)) {
                                    cardsAppeared = true
                                }
                            }

                        heroPromptChipRow
                            .padding(.bottom, 22)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 12)
                    }

                    if vm.isStudyModeEnabled {
                        let isCollapsed = scrollCoordinator.context != .nearBottom && scrollOffset > 120
                        BereanStudyModeSurface(
                            state: isCollapsed ? .collapsedSummary : vm.studyModeState,
                            nodes: vm.reasoningNodes,
                            onCategoryTap: { node in
                                selectedReasoningNode = node
                            },
                            isCollapsed: isCollapsed,
                            reduceMotion: reduceMotion
                        )
                        .padding(.horizontal, metrics.contentHorizontalPadding)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Messages
                    LazyVStack(spacing: 16) {
                        ForEach(vm.messages) { msg in
                            if msg.role == .user || !msg.content.isEmpty {
                                structuredMessageView(msg)
                                    .id(msg.id)
                                    .contextMenu {
                                        messageContextMenu(msg)
                                    }
                                    // MEDIUM FIX: Announce sender name and timestamp so VoiceOver
                                    // users know who sent each message and when.
                                    .accessibilityLabel(messageAccessibilityLabel(msg))
                            }
                        }

                        // Thinking indicator with processing state
                        if vm.isThinking && (vm.messages.last?.content.isEmpty ?? false) {
                            processingIndicator
                                .id("thinking")
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, metrics.contentHorizontalPadding)
                    .padding(.top, showHero ? 0 : 16)

                    // Auto-scroll anchor
                    Color.clear.frame(height: metrics.bottomContentInset).id("bottom")
                }
                .background(
                    ZStack {
                        BereanScrollOffsetReader(coordinateSpaceName: "scroll")
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ContentHeightKey.self, value: geo.size.height)
                        }
                    }
                )
                .animation(.easeOut(duration: 0.2), value: vm.isThinking)
            }
            .coordinateSpace(name: "scroll")
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, newValue in
                            viewportHeight = newValue
                        }
                }
            )
            .simultaneousGesture(
                // minimumDistance: 10 prevents taps (0px movement) from setting
                // setDragging(true) and incorrectly suppressing auto-scroll behavior.
                // The iOS default is also 10pt but we set it explicitly for clarity.
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in scrollCoordinator.setDragging(true) }
                    .onEnded { _ in scrollCoordinator.setDragging(false) }
            )
            .onPreferenceChange(ScrollOffsetPreference.self) { value in
                let rawOffset = value
                let newOffset = -value
                scrollOffset = newOffset
                scrollCoordinator.update(offset: newOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                composerVM.updateScroll(rawOffset)
                if scrollOffset > 50 && showHero {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showHero = false
                    }
                }
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                contentHeight = height
                scrollCoordinator.update(offset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
            }
            .onChange(of: vm.messages.count) {
                let shouldScroll = scrollCoordinator.shouldAutoScroll(isUserInitiated: pendingUserSend)
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.30)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                pendingUserSend = false
            }
            .onChange(of: vm.messages.last?.content) {
                if scrollCoordinator.shouldAutoScroll(isUserInitiated: pendingUserSend) {
                    debouncedScrollToBottom(using: proxy, isStreaming: vm.isThinking)
                }
            }
        }
    }

    private func debouncedScrollToBottom(using proxy: ScrollViewProxy, isStreaming: Bool) {
        guard isStreaming else {
            streamingAutoScrollTimer?.invalidate()
            streamingAutoScrollTimer = nil
            lastStreamingAutoScrollAt = Date()
            proxy.scrollTo("bottom", anchor: .bottom)
            return
        }

        let now = Date()
        let minimumInterval: TimeInterval = 0.1
        let elapsed = now.timeIntervalSince(lastStreamingAutoScrollAt)

        if elapsed >= minimumInterval {
            streamingAutoScrollTimer?.invalidate()
            streamingAutoScrollTimer = nil
            lastStreamingAutoScrollAt = now
            proxy.scrollTo("bottom", anchor: .bottom)
            return
        }

        guard streamingAutoScrollTimer == nil else { return }
        let delay = minimumInterval - elapsed
        streamingAutoScrollTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                lastStreamingAutoScrollAt = Date()
                proxy.scrollTo("bottom", anchor: .bottom)
                streamingAutoScrollTimer?.invalidate()
                streamingAutoScrollTimer = nil
            }
        }
    }

    private func validatePostContextAvailability(_ postContext: BereanPostContext) async {
        switch await BereanPostContextAvailabilityService.shared.validate(postContext) {
        case .available(let refreshedContext):
            validatedPostContext = refreshedContext
            vm.activePostContext = refreshedContext
            postAvailabilityMessage = nil
        case .unavailable(let message):
            validatedPostContext = nil
            vm.activePostContext = nil
            postAvailabilityMessage = message
        }
    }

    private func handlePostContextNotification(_ notification: Notification) async {
        guard let currentPostId = (validatedPostContext ?? vm.activePostContext)?.postId else { return }
        let notifiedPostId = notification.userInfo?["postId"] as? String
        guard notifiedPostId == nil || notifiedPostId == currentPostId else { return }
        if let context = validatedPostContext ?? vm.activePostContext {
            await validatePostContextAvailability(context)
        }
    }

    private struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private func adaptiveComposer(metrics: BereanLayoutMetrics, containerWidth: CGFloat) -> some View {
        compactComposer(availableWidth: containerWidth - (metrics.contentHorizontalPadding * 2))
            .padding(.horizontal, metrics.contentHorizontalPadding)
            .padding(.bottom, metrics.composerBottomPadding)
    }

    private func handleSend() {
        Task { await prepareAndSendMessage() }
    }

    private func prepareAndSendMessage() async {
        guard !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let activeContext = validatedPostContext ?? vm.activePostContext {
            await validatePostContextAvailability(activeContext)
        }

        let submissionContext = composerVM.submissionContext(mode: vm.currentMode)
        Analytics.logEvent("berean_composer_submitted", parameters: [
            "mode": vm.currentMode.rawValue,
            "has_attachment": submissionContext?.attachments.isEmpty == false,
            "tool_instruction": vm.preSendInstruction != nil,
            "tool_count": submissionContext?.selectedTools.count ?? 0
        ])
        vm.pendingComposerContext = submissionContext
        pendingUserSend = true
        sendSweep.toggle()
        withAnimation(BereanAnimationCoordinator.compactSpring) {
            showHero = false
        }
        handleSendTap()
        composerVM.clearSubmissionContext()
        initialSendTask = nil
    }

    private func handleVoiceAction() {
        guard BereanAISettingsStore.voiceInputEnabled else {
            showVoiceDisabledAlert = true
            return
        }
        // Phase 5 / P0-2: present the real voice input sheet. The sheet
        // wraps WhisperVoiceViewModel for recording + Whisper transcription,
        // then calls back with the user-approved transcript text. The
        // returned text is placed into the composer so the user must
        // explicitly tap Send — no auto-submit.
        Analytics.logEvent("berean_voice_started", parameters: ["mode": vm.currentMode.rawValue])
        showVoiceInputSheet = true
    }

    private func handleQuickAction(_ action: BereanLiquidAction.ActionType) {
        composerVM.recordTool(action)
        switch action {
        case .attachFile, .addFile:
            attachmentPickerMode = .file
            showAttachmentPicker = true
        case .camera, .addPhoto:
            attachmentPickerMode = .photo
            showAttachmentPicker = true
        case .voiceNote:
            handleVoiceAction()
        case .verseLookup:
            vm.inputText = ""
            inputFocused = true
        case .summarize:
            vm.inputText = "Summarize this: "
            inputFocused = true
        case .searchScripture:
            vm.inputText = "Search Scripture for "
            inputFocused = true
        case .explainSimply:
            applyToolPrompt("Explain simply: ", instruction: "Use simple language, short sentences, and a calm, clear structure.")
        case .exploreContext:
            applyToolPrompt("Explore the context of ", instruction: "Include historical, literary, and biblical context without fabricating sources.")
        case .crossReference:
            applyToolPrompt("Cross-reference ", instruction: "Find relevant biblical cross-references and explain why they connect.")
        case .prayer:
            applyToolPrompt("Help me pray about ", instruction: "Respond in prayer companion mode with a gentle prayer and Scripture anchor.")
            setCompactMode(.prayerCompanion)
        case .deepStudy:
            applyToolPrompt("Go deeper on ", instruction: "Use deeper study mode with context, structure, cross-references, and application.")
            setCompactMode(.deepStudy)
        case .createNote:
            applyToolPrompt("Create a Church Note from ", instruction: "Format the answer as a concise Church Note draft with title, anchors, and next steps.")
        case .saveToChurchNotes:
            if let latestAssistant = vm.messages.last(where: { $0.role == .assistant }) {
                Task { await saveMessageToChurchNotes(latestAssistant) }
            } else {
                applyToolPrompt(
                    "Create a Church Note from ",
                    instruction: "Format the answer as a concise Church Note draft with title, anchors, and next steps."
                )
            }
        }
    }

    private func applyToolPrompt(_ prefix: String, instruction: String? = nil) {
        let current = vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        vm.inputText = current.isEmpty ? prefix : "\(prefix)\(current)"
        vm.setDiscernmentInstruction(instruction)
        inputFocused = true
    }

    private func setCompactMode(_ mode: BereanPersonalityMode) {
        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.78))) {
            vm.currentMode = mode
            switch mode {
            case .scriptureStudy:
                bereanInteractionMode = .ask
            case .prayerCompanion:
                bereanInteractionMode = .reflect
            case .deepStudy:
                bereanInteractionMode = .reason
            case .scholar:
                bereanInteractionMode = .reason
            default:
                break
            }
        }
        Analytics.logEvent("berean_mode_changed", parameters: ["mode": mode.rawValue])
    }

    private var selectedComposerModeChip: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: compactModeIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(compactModeTitle)
                    .font(AMENFont.medium(12))
            }
            .foregroundStyle(BereanColor.textPrimary.opacity(0.66))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.48), lineWidth: 0.6))
            .accessibilityLabel("Current Berean mode: \(compactModeTitle)")

            Spacer(minLength: 0)
        }
    }

    private var compactModeTitle: String {
        switch vm.currentMode {
        case .scriptureStudy:
            return "Scripture"
        case .prayerCompanion:
            return "Prayer"
        case .deepStudy:
            return "Deep Study"
        case .scholar:
            return "Deep Study"
        default:
            return "Berean"
        }
    }

    private var compactModeIcon: String {
        switch vm.currentMode {
        case .scriptureStudy:
            return "book.closed"
        case .prayerCompanion:
            return "hands.sparkles"
        case .deepStudy:
            return "magnifyingglass.circle"
        case .scholar:
            return "magnifyingglass.circle"
        default:
            return "sparkles"
        }
    }

    private var composerFollowUpChips: [String] {
        guard let latestAssistantMessage = vm.messages.last(where: { $0.role == .assistant }) else { return [] }
        return latestAssistantMessage.structure?.followUpActions.map(\.title) ?? []
    }

    private func handleComposerFollowUp(_ chip: String) {
        vm.inputText = chip
        handleSend()
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 16) {
            // AMEN glass medallion — replaces old "B" monogram
            AmenHeroMarkView()
                .padding(.top, 24)
                .scaleEffect(1.0 - heroCompressionProgress * 0.06)
                .offset(y: heroCompressionProgress * -8)
                .opacity(Double(1.0 - heroCompressionProgress * 0.12))

            // Premium editorial typography
            VStack(spacing: 10) {
                Text("Berean")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundColor(BereanColor.textPrimary)

                Text("Scripture, context, prayer, and wisdom in a calmer assistant designed for AMEN.")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(BereanColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 330)
            }
            .scaleEffect(1.0 - heroCompressionProgress * 0.03)
            .opacity(Double(1.0 - heroCompressionProgress * 0.18))
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.88)), value: composerVM.collapseProgress)
    }

    // MARK: - Hero Prompt Surface

    private struct HeroPromptChip: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let prompt: String
    }

    private var heroPrompt: String {
        switch vm.currentMode {
        case .scriptureStudy:
            return "Which passage should Berean study with context, meaning, and cross-references?"
        case .askBerean:
            return "What Christian question do you want answered with Scripture and humility?"
        case .prayerCompanion:
            return "What do you want help praying through right now?"
        case .discernment:
            return "What decision needs Scripture, wisdom, motive checks, and counsel?"
        case .mediaInsight:
            return "What sermon, video, post, or caption should Berean summarize and review?"
        case .workLifeWisdom:
            return "Where do you need biblical wisdom for work, relationships, anxiety, or leadership?"
        case .safetyReview:
            return "What should Berean review for shame, manipulation, overreach, or harmful counsel?"
        case .shepherd:
            return "What do you want help carrying, praying through, or understanding right now?"
        case .deepStudy, .scholar:
            return "Which passage, doctrine, or hard question do you want to examine closely?"
        case .coach:
            return "What needs a practical next step instead of another abstract answer?"
        case .strategist:
            return "What do you want to study deeply enough to trace, compare, and organize?"
        case .creator:
            return "What needs a fresh devotional angle, reflection, or prayerful rewrite?"
        case .builder, .debater:
            return "What do you want Berean to help you think through carefully?"
        }
    }

    private var heroSupportLine: String {
        switch vm.currentMode {
        case .scriptureStudy:
            return "Answers separate biblical text from commentary and avoid fabricated verses."
        case .askBerean:
            return "Berean starts with Scripture, names uncertainty, and stays humble about debated matters."
        case .prayerCompanion:
            return "Berean can shape burdens into prayer without pressure, shame, or false certainty."
        case .discernment:
            return "Berean slows the decision down through principles, motives, risks, fruit, and wise counsel."
        case .mediaInsight:
            return "Berean summarizes claims, references, key moments, and discernment notes from supplied context."
        case .workLifeWisdom:
            return "Berean connects biblical wisdom to practical next steps for daily life."
        case .safetyReview:
            return "Berean reviews content pastorally for harm signals without becoming punitive."
        case .shepherd:
            return "Berean can calm the question down, turn it into prayer, and answer gently without losing biblical clarity."
        case .deepStudy, .scholar:
            return "Berean will stay close to the text, explain context, and surface the strongest cross-references first."
        case .coach:
            return "Berean will move from insight to action so the answer lands in real life, not just in theory."
        case .strategist:
            return "Berean will build a structured path: arguments, themes, related passages, and the next study step."
        case .creator:
            return "Berean will keep the response reflective, language-aware, and useful for devotion or writing."
        case .builder, .debater:
            return "Berean will keep the response focused, practical, and grounded in what you actually asked."
        }
    }

    private var heroPromptChips: [HeroPromptChip] {
        switch vm.currentMode {
        case .scriptureStudy:
            return [
                .init(title: "Explain passage", icon: "book.pages", prompt: "Explain Romans 8 in context."),
                .init(title: "Cross references", icon: "arrow.triangle.branch", prompt: "Show cross references for "),
                .init(title: "Word study", icon: "text.magnifyingglass", prompt: "Help me study the original language behind ")
            ]
        case .askBerean:
            return [
                .init(title: "Ask a question", icon: "bubble.left.and.bubble.right", prompt: "What does Scripture say about "),
                .init(title: "Explain simply", icon: "lightbulb", prompt: "Explain this Christian question simply: "),
                .init(title: "Show context", icon: "book.closed", prompt: "Give me biblical context for ")
            ]
        case .prayerCompanion:
            return [
                .init(title: "Guided prayer", icon: "hands.sparkles", prompt: "Help me pray through this: "),
                .init(title: "Scripture anchor", icon: "bookmark", prompt: "Give me a Scripture anchor for prayer about "),
                .init(title: "Reflection", icon: "sparkles", prompt: "Give me a reflection question for ")
            ]
        case .discernment:
            return [
                .init(title: "Clarify decision", icon: "scale.3d", prompt: "Help me discern this decision: "),
                .init(title: "Motive check", icon: "heart.text.square", prompt: "Help me check my motives about "),
                .init(title: "Wise next step", icon: "figure.walk", prompt: "Give me one wise next step for ")
            ]
        case .mediaInsight:
            return [
                .init(title: "Summarize sermon", icon: "play.rectangle", prompt: "Summarize this sermon: "),
                .init(title: "Main claims", icon: "list.bullet.rectangle", prompt: "Identify the main claims in this Christian media: "),
                .init(title: "Discernment notes", icon: "shield", prompt: "Review this content for biblical discernment: ")
            ]
        case .workLifeWisdom:
            return [
                .init(title: "Work wisdom", icon: "briefcase", prompt: "What does Scripture say about this work situation? "),
                .init(title: "Conflict", icon: "person.2.wave.2", prompt: "Help me handle this conflict wisely: "),
                .init(title: "Anxiety", icon: "leaf", prompt: "Help me apply biblical wisdom to anxiety about ")
            ]
        case .safetyReview:
            return [
                .init(title: "Review tone", icon: "shield.lefthalf.filled", prompt: "Review this for shame, manipulation, or harmful counsel: "),
                .init(title: "False certainty", icon: "exclamationmark.triangle", prompt: "Check this for false certainty or overreach: "),
                .init(title: "Safer rewrite", icon: "pencil.and.outline", prompt: "Rewrite this more pastorally and safely: ")
            ]
        case .shepherd:
            return [
                .init(title: "Ask a question", icon: "bubble.left.and.bubble.right", prompt: "I have a question about "),
                .init(title: "Build a prayer", icon: "hands.sparkles", prompt: "Turn this into a prayer: "),
                .init(title: "Find peace", icon: "leaf", prompt: "Help me find peace about ")
            ]
        case .deepStudy, .scholar:
            return [
                .init(title: "Search scripture", icon: "book.pages", prompt: "Search scripture for "),
                .init(title: "Explain simply", icon: "text.quote", prompt: "Explain this passage simply: "),
                .init(title: "Cross-references", icon: "arrow.triangle.branch", prompt: "Find cross-references for ")
            ]
        case .coach:
            return [
                .init(title: "Need guidance", icon: "map", prompt: "I need guidance about "),
                .init(title: "Pray with me", icon: "hands.sparkles", prompt: "Pray with me about "),
                .init(title: "Next step", icon: "figure.walk", prompt: "Give me one wise next step for ")
            ]
        case .strategist:
            return [
                .init(title: "Study plan", icon: "checklist", prompt: "Build me a deep study plan for "),
                .init(title: "Trace argument", icon: "point.topleft.down.curvedto.point.bottomright.up", prompt: "Trace the argument of this passage step by step: "),
                .init(title: "Compare themes", icon: "square.stack.3d.up", prompt: "Compare the major themes in ")
            ]
        case .creator:
            return [
                .init(title: "Devotional angle", icon: "heart.text.square", prompt: "Give me a devotional angle on "),
                .init(title: "Rewrite as prayer", icon: "hands.sparkles", prompt: "Rewrite this as a prayer: "),
                .init(title: "Reflective prompt", icon: "sparkles", prompt: "Give me a reflective prompt for ")
            ]
        case .builder, .debater:
            return [
                .init(title: "Start a thread", icon: "bubble.left.and.bubble.right", prompt: "Help me think through "),
                .init(title: "Search scripture", icon: "book.pages", prompt: "Search scripture for "),
                .init(title: "Another angle", icon: "arrow.triangle.branch", prompt: "Show me another angle on ")
            ]
        }
    }

    private var adaptivePromptSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: vm.currentMode.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BereanColor.textPrimary.opacity(0.66))
                Text(vm.currentMode.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(BereanColor.textSecondary)
            }

            Text(heroPrompt)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(heroSupportLine)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BereanColor.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.84), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 10)
        )
        .scaleEffect(1.0 - heroCompressionProgress * 0.02)
        .opacity(Double(1.0 - heroCompressionProgress * 0.10))
    }

    private var heroPromptChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(heroPromptChips) { chip in
                    Button {
                        vm.inputText = chip.prompt
                        inputFocused = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(chip.title)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(BereanColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.52)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.62), lineWidth: 0.6))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0))
        .opacity(Double(1.0 - heroCompressionProgress * 0.08))
    }

    // MARK: - Mode Chips

    private var modeChipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Berean Mode")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BereanColor.textSecondary)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    modeChip(title: "Study", icon: "book.pages.fill", mode: .scriptureStudy)
                    modeChip(title: "Ask", icon: "bubble.left.and.bubble.right.fill", mode: .askBerean)
                    modeChip(title: "Prayer", icon: "hands.sparkles.fill", mode: .prayerCompanion)
                    modeChip(title: "Discern", icon: "scale.3d", mode: .discernment)
                    modeChip(title: "Media", icon: "play.rectangle.on.rectangle.fill", mode: .mediaInsight)
                    modeChip(title: "Work/Life", icon: "briefcase.fill", mode: .workLifeWisdom)
                    modeChip(title: "Safety", icon: "shield.lefthalf.filled", mode: .safetyReview)
                }
                .padding(.horizontal, 18)
            }
            // Pass vertical gestures to the parent scroll view simultaneously
            // so swiping up/down over the pill row doesn't get captured by the
            // horizontal ScrollView and block the outer content scroll.
            .simultaneousGesture(DragGesture(minimumDistance: 0))
        }
    }

    private func modeChip(title: String, icon: String, mode: BereanPersonalityMode) -> some View {
        let isSelected = vm.currentMode == mode

        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.70))) {
                vm.currentMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? Color(.systemBackground) : BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color(.label))
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.56),
                                                Color.white.opacity(0.38),
                                                Color(red: 1.0, green: 0.96, blue: 0.93).opacity(0.18)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.70), Color.black.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                            )
                    }
                }
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.15) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                y: isSelected ? 3 : 2
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0 - heroCompressionProgress * 0.018)
        .opacity(Double(1.0 - heroCompressionProgress * 0.06))
    }

    // MARK: - Mode Drawer Trigger (System 14 Redesign)

    private var modeDrawerTrigger: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Berean Mode")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BereanColor.textSecondary)
                .padding(.horizontal, 18)

            Button {
                showModeDrawer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: vm.currentMode.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(vm.currentMode.rawValue)
                        .font(AMENFont.semiBold(15))
                    Spacer()
                    Text("Change")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AmenTheme.Colors.glassFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .sheet(isPresented: $showModeDrawer) {
            BereanModeDrawer(selectedMode: $vm.currentMode)
        }
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BereanColor.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickActionPill(title: "Search Scripture", icon: "magnifyingglass")
                    quickActionPill(title: "Explain Simply", icon: "lightbulb")
                    quickActionPill(title: "Build a Plan", icon: "list.bullet.clipboard")
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0))
        }
    }

    private func quickActionPill(title: String, icon: String) -> some View {
        Button {
            vm.inputText = title
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.58),
                                        Color.white.opacity(0.42),
                                        Color(red: 1.0, green: 0.96, blue: 0.93).opacity(0.20)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.75),
                                        Color.white.opacity(0.20),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0 - heroCompressionProgress * 0.02)
        .opacity(Double(1.0 - heroCompressionProgress * 0.08))
    }

    private var heroCompressionProgress: CGFloat {
        min(max(composerVM.collapseProgress, 0), 1)
    }

    // MARK: - Message Context Menu

    @ViewBuilder
    private func messageContextMenu(_ msg: BereanChatMsg) -> some View {
        Button {
            UIPasteboard.general.string = msg.content
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            Task { await saveMessageToChurchNotes(msg) }
        } label: {
            Label("Save to Notes", systemImage: "note.text.badge.plus")
        }

        if msg.role == .assistant {
            Button {
                Task {
                    _ = try? await BereanIntelligenceCoordinator.shared.memory.saveInsight(
                        sessionId: vm.sessionId,
                        text: String(msg.content.prefix(400)),
                        linkedVerses: BereanIntelligenceCoordinator.shared.grounding.extractVerseReferences(from: msg.content),
                        category: "insight"
                    )
                    withAnimation { showSavedToNotesToast = true }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showSavedToNotesToast = false }
                }
            } label: {
                Label("Save to Memory", systemImage: "brain")
            }

            Button {
                Task {
                    let title = vm.messages.first(where: { $0.role == .user })
                        .map { String($0.content.prefix(50)) } ?? "Study Thread"
                    _ = try? await BereanIntelligenceCoordinator.shared.threads.createThread(
                        title: title
                    )
                }
            } label: {
                Label("Start Study Thread", systemImage: "arrow.triangle.branch")
            }

            Button {
                showSpiritualMemorySheet = true
            } label: {
                Label("View in Memory", systemImage: "brain.head.profile")
            }

            Button {
                vm.cancelStreaming()
                // Remove the last assistant message and re-send previous user message
                if let lastUser = vm.messages.last(where: { $0.role == .user }) {
                    vm.messages.removeAll { $0.id == msg.id }
                    vm.inputText = lastUser.content
                    vm.messages.removeAll { $0.id == lastUser.id }
                    handleSendTap()
                }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }

            // Phase H3 / App Review Guideline 1.2: surface a way for the
            // user to report this assistant response as unsafe. Opens the
            // ReportUnsafeAIResponseSheet, which calls the secured
            // reportUnsafeAIResponse Cloud Function.
            Divider()
            Button(role: .destructive) {
                reportingMessageId = msg.id.uuidString
            } label: {
                Label("Report response", systemImage: "flag")
            }
            .accessibilityLabel("Report this AI response as unsafe")
        }
    }

    // MARK: - Addition 1: Context Memory Rail

    private var bereanContextMemoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(BereanContextSource.allCases, id: \.self) { source in
                    let isSelected = selectedContextSources.contains(source)
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.75))) {
                            if isSelected && selectedContextSources.count > 1 {
                                selectedContextSources.remove(source)
                            } else {
                                selectedContextSources.insert(source)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: source.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(source.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(isSelected
                            ? Color.black
                            : Color.black.opacity(0.45))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected
                                      ? Color.white.opacity(0.95)
                                      : Color.white.opacity(0.45))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected
                                                ? Color.black.opacity(0.14)
                                                : Color.black.opacity(0.06),
                                            lineWidth: 0.5
                                        )
                                )
                                .shadow(
                                    color: isSelected ? Color.black.opacity(0.07) : .clear,
                                    radius: 4, y: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(source.label) context \(isSelected ? "active" : "inactive")")
                }
            }
        }
        // Allow the parent vertical scroll to receive simultaneous gestures so
        // horizontal swipes on this rail don't block the feed from scrolling.
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private var shouldShowSuggestionRow: Bool {
        if vm.messages.count <= 1 { return inputFocused }
        return inputFocused || scrollCoordinator.context == .nearBottom
    }

    private var shouldShowContextRail: Bool {
        if vm.messages.count <= 1 { return false }
        return inputFocused || scrollCoordinator.context == .nearBottom
    }

    private var focusedSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                suggestionPill(title: "Search Scripture", icon: "book.pages", prompt: "Search scripture for ")
                suggestionPill(title: "Explain Simply", icon: "sparkles", prompt: "Explain this simply: ")
                suggestionPill(title: "Build a Prayer", icon: "hands.sparkles", prompt: "Turn this into a prayer: ")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private var compactContextRail: some View {
        bereanContextMemoryRail
            .frame(height: 34)
            .opacity(0.94)
    }

    private func suggestionPill(title: String, icon: String, prompt: String) -> some View {
        Button {
            vm.inputText = prompt
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.black.opacity(0.76))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.72)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Intelligence follow-up chips

    private var intelligenceFollowUpRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(intelligence.followUpSuggestions, id: \.self) { suggestion in
                    Button {
                        vm.inputText = suggestion
                        intelligence.followUpSuggestions = []
                        vm.send()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text(suggestion)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.accentColor.opacity(0.07)))
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    intelligence.followUpSuggestions = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(9)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private func intelligenceSafetyBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                intelligence.safetyBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Addition 3: Save to Church Notes

    private func saveMessageToChurchNotes(_ message: BereanChatMsg) async {
        guard !message.content.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let note = ChurchNote(
            userId: uid,
            title: "Berean Note — \(Date().formatted(date: .abbreviated, time: .omitted))",
            sermonTitle: conversationTitle,
            date: Date(),
            content: message.content
        )
        do {
            let service = ChurchNotesService()
            _ = try await service.createNote(note)
            await MainActor.run {
                withAnimation { showSavedToNotesToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { showSavedToNotesToast = false }
                }
            }
        } catch {
            dlog("BereanChatView: save to notes failed — \(error)")
        }
    }

    // MARK: - Compact ChatGPT-Style Composer

    private func attachmentPrompt(for result: BereanAttachmentResult) -> String {
        var lines = ["\(result.promptPrefix)\(result.displayName)"]
        if let contentType = result.contentType, !contentType.isEmpty {
            lines.append("Type: \(contentType)")
        }
        if let byteCount = result.byteCount, byteCount > 0 {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))")
        }
        if let storagePath = result.storagePath, !storagePath.isEmpty {
            lines.append("Uploaded attachment reference: \(storagePath)")
        }
        if let contextText = result.contextText, !contextText.isEmpty {
            lines.append(contextText)
        }
        return lines.joined(separator: "\n\n")
    }

    private func compactComposer(availableWidth: CGFloat) -> some View {
        BereanCompactComposerBar(
            composerVM: composerVM,
            messageText: $vm.inputText,
            isFocused: $inputFocused,
            availableWidth: availableWidth,
            selectedMode: vm.currentMode,
            onSend: {
                if vm.isThinking {
                    vm.cancelStreaming()
                } else {
                    handleSend()
                    inputFocused = false
                }
            },
            onVoice: handleVoiceAction,
            onAction: handleQuickAction,
            onTools: { showCompactModePicker = true },
            onStop: vm.cancelStreaming,
            isVoiceEnabled: BereanAISettingsStore.voiceInputEnabled,
            followUpChips: composerFollowUpChips,
            onChipTap: handleComposerFollowUp
        )
        .disabled(vm.isAtLimit)
    }

    // MARK: - Paywall Banner

    private var paywallBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(13))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
            VStack(alignment: .leading, spacing: 1) {
                Text("Free limit reached")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(BereanColor.textPrimary)
                Text("Upgrade to Pro for unlimited Berean AI")
                    .font(AMENFont.regular(11))
                    .foregroundColor(BereanColor.textSecondary)
            }
            Spacer()
            Button("Upgrade") {
                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
            .font(AMENFont.semiBold(12))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.clipShape(Capsule()))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Mode Fallback Banner

    private func modeFallbackBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.systemScaled(13))
                .foregroundColor(Color(red: 0.55, green: 0.40, blue: 0.80))
            Text(message)
                .font(AMENFont.regular(12))
                .foregroundColor(BereanColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    vm.modelFallbackNotice = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BereanColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss mode notice")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.55, green: 0.40, blue: 0.80).opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.55, green: 0.40, blue: 0.80).opacity(0.18), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mode notice: \(message)")
    }

    // MARK: - Structured Message View

    // MEDIUM FIX: Build a descriptive VoiceOver label for a chat message bubble.
    // Format: "<sender>: <content>, sent at <time>"
    private func messageAccessibilityLabel(_ message: BereanChatMsg) -> String {
        let sender = message.role == .user ? "You" : "Berean"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let time = timeFormatter.string(from: message.timestamp)
        let preview = message.content.isEmpty ? "Thinking…" : message.content
        return "\(sender): \(preview), sent at \(time)"
    }

    private func structuredMessageView(_ message: BereanChatMsg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.role == .user {
                userMessageBubble(message)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    bereanAvatar

                    VStack(alignment: .leading, spacing: 8) {
                        BereanStructuredResponseView(message: message)
                        // Addition 2: Scripture chip below assistant response
                        bereanScriptureChip(for: message)
                        // System 27: Provenance chips — show how this answer was prepared
                        if showProvenanceLabels && AMENFeatureFlags.shared.bereanHelperProvenanceChipsEnabled,
                           let provenance = message.provenance, !message.isStreaming {
                            BereanProvenanceChipRow(provenance: provenance) { _ in
                                vm.grokCoordinator.showProvenance(provenance)
                            }
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                        }
                        HStack {
                            Button("Correct the AI") {
                                correctionTargetMessage = message
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.58))
                            Spacer()
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)

                    Spacer(minLength: 30)
                }
            }
        }
    }

    /// Detects a scripture reference in an assistant message and surfaces a tappable chip.
    @ViewBuilder
    private func bereanScriptureChip(for message: BereanChatMsg) -> some View {
        if !message.isStreaming && !message.content.isEmpty {
            let references = BereanScriptureReferenceExtractor.references(in: message.content)
            if !references.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ScriptureCitationRow(references: references)
                    // Translation comparison inline chip for the first detected reference
                    AmenTranslationComparisonInline(reference: references[0])
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
        }
    }

    private func userMessageBubble(_ message: BereanChatMsg) -> some View {
        HStack {
            Spacer(minLength: 54)

            Text(message.content)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white.opacity(0.94))
                .lineSpacing(2)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .frame(maxWidth: 620, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.14), radius: 18, y: 7)
                )
        }
        .transition(.opacity.combined(with: .offset(x: 8)))
    }

    private func assistantStructuredResponse(_ message: BereanChatMsg) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Direct answer (one-line, appears first)
            if let directAnswer = message.structure?.directAnswer, !directAnswer.isEmpty {
                directAnswerCard(directAnswer)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }

            // Structured sections
            if let structure = message.structure {
                if let meaning = structure.meaning, !meaning.isEmpty {
                    sectionCard(title: "Meaning", icon: "lightbulb.fill", content: meaning, accentColor: Color(red: 0.30, green: 0.50, blue: 0.90))
                }

                if let context = structure.context, !context.isEmpty {
                    sectionCard(title: "Context", icon: "book.pages.fill", content: context, accentColor: Color(red: 0.35, green: 0.30, blue: 0.90))
                }

                if let application = structure.application, !application.isEmpty {
                    sectionCard(title: "Application", icon: "heart.fill", content: application, accentColor: Color(red: 0.55, green: 0.30, blue: 0.85))
                }

                // Follow-up action pills
                if !structure.followUpActions.isEmpty {
                    followUpActionPills(structure.followUpActions)
                }
            } else if !message.content.isEmpty {
                // Fallback: standard bubble if no structure
                HStack(alignment: .top, spacing: 10) {
                    bereanAvatar

                    Text(message.content)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(BereanColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(0.85))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                        )

                    Spacer(minLength: 60)
                }
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func directAnswerCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            bereanAvatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.30, green: 0.65, blue: 0.55))
                    Text("Direct Answer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BereanColor.textSecondary)
                }

                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(BereanColor.textPrimary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.30, green: 0.65, blue: 0.55).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(red: 0.30, green: 0.65, blue: 0.55).opacity(0.20), lineWidth: 1)
                    )
            )

            Spacer(minLength: 40)
        }
    }

    private func sectionCard(title: String, icon: String, content: String, accentColor: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer().frame(width: 36) // Align with avatar

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(accentColor)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BereanColor.textPrimary)
                }

                Text(content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(BereanColor.textPrimary)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.50), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            )

            Spacer(minLength: 20)
        }
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    private func followUpActionPills(_ actions: [BereanResponseStructure.FollowUpAction]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer().frame(width: 36)

            VStack(alignment: .leading, spacing: 8) {
                Text("Next Steps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BereanColor.textSecondary)

                BereanFollowUpFlowLayout(spacing: 8) {
                    ForEach(actions) { action in
                        Button {
                            vm.inputText = action.title
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Text(action.title)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(BereanColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.white.opacity(0.70)))
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 20)
        }
    }

    private var bereanAvatar: some View {
        BereanBrandBadge(size: 28, fontSize: 7.5, tracking: 1.2)
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            bereanAvatar

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)

                    Text(vm.messages.last?.processingState ?? "Reading passage...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BereanColor.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                )
            }

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Addition 1: BereanContextSource enum

enum BereanContextSource: String, CaseIterable {
    case thisChat      = "This Chat"
    case churchNotes   = "Church Notes"
    case currentVerse  = "Current Verse"
    case prayerContext = "Prayer Context"
    case recentTopic   = "Recent Topic"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .thisChat:      return "bubble.left.and.bubble.right"
        case .churchNotes:   return "note.text"
        case .currentVerse:  return "book.closed"
        case .prayerContext: return "hands.sparkles"
        case .recentTopic:   return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Addition 2: Berean Verse Preview Sheet

struct BereanVersePreviewSheet: View {
    let verse: BibleVerse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Reference header
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.788, green: 0.659, blue: 0.298))
                        Text(verse.reference)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(verse.translation)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color(.tertiarySystemFill))
                            )
                    }

                    // Verse text (only if we have it)
                    if !verse.text.isEmpty {
                        Text(verse.text)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(.primary)
                            .lineSpacing(6)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(AmenTheme.Colors.glassFill)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                            )
                    } else {
                        // Reference only — invite to open in Selah
                        Text("Tap Open in Selah to read the full passage.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // Actions row
                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Open in Selah", systemImage: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(Color.black)
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = verse.text.isEmpty
                                ? verse.reference
                                : "\(verse.reference) — \(verse.text)"
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.65))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.white.opacity(0.75)))
                                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Supporting Views

// Simple flow layout for follow-up pills
struct BereanFollowUpFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// Quick action press style
struct QuickActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Legacy BereanChatBubble (kept for compatibility)

struct BereanChatBubble: View {
    let message: BereanChatMsg
    private var isUser: Bool { message.role == .user }

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 52) }

            if !isUser {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleBody
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(BereanType.micro())
                    .foregroundColor(BereanColor.textTertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 52) }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (isUser ? 10 : -10))
        .scaleEffect(appeared ? 1 : 0.97, anchor: isUser ? .bottomTrailing : .bottomLeading)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.72))) {
                appeared = true
            }
        }
    }

    private var avatarView: some View {
        BereanBrandBadge(size: 26, fontSize: 7, tracking: 1.0)
            .alignmentGuide(.bottom) { dimensions in dimensions[VerticalAlignment.bottom] }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        let displayText = message.content.isEmpty && message.isStreaming ? "▌" : message.content

        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isUser || (message.content.isEmpty && message.isStreaming) {
                    Text(displayText)
                        .font(BereanType.body())
                        .foregroundColor(isUser ? Color.white : BereanColor.textPrimary)
                } else {
                    BereanMarkdownText(displayText, font: BereanType.body())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)

            if !isUser, !message.content.isEmpty {
                BereanAIResponseDisclosureRow()
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - Typing Indicator (reexported for backward compat)

struct BereanLiquidTypingIndicator: View {
    var body: some View { BereanThinkingIndicator() }
}

// MARK: - Preview

struct BereanChatView_Previews: PreviewProvider {
    static var previews: some View {
        BereanChatView(initialMode: .shepherd, conversationTitle: "Romans Study")
    }
}
