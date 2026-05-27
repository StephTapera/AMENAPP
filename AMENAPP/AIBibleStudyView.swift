//
//  AIBibleStudyView.swift
//  AMENAPP
//
//  Berean AI — redesigned with light atmospheric aesthetic.
//  Reference: near-white background, soft color blobs at bottom corners,
//  editorial typography, premium minimalism.
//
//  All working logic preserved:
//   - BereanGenkitService API call
//   - SpeechRecognitionService (BereanMissingFeatures.swift)
//   - Firestore conversation persistence (AIBibleStudyExtensions.swift)
//   - PremiumManager free message limits
//   - Keyboard observers
//   - Orb animations (adapted to light theme, placed at bottom)
//   - GlassmorphicChatInput glow (adapted to light)
//

import SwiftUI
import FirebaseAuth

struct AIBibleStudyView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var premiumManager = PremiumManager.shared
    @State var selectedTab: AIStudyTab = .chat
    @State private var userInput = ""
    @State var messages: [AIStudyMessage] = []
    @State private var isProcessing = false
    @State private var showProUpgrade = false
    @State private var showVoiceInput = false
    @State private var isListening = false
    @State private var pulseAnimation = false
    @State private var orbAnimation = false
    @State private var orb2Animation = false
    @FocusState private var isInputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    // P0 FIX: Store tokens — closure-based observers MUST be removed via the
    // returned NSObjectProtocol token. removeObserver(self, ...) is a no-op for them
    // and caused duplicate observers + memory leaks on every view appearance.
    @State private var kbShowToken: NSObjectProtocol?
    @State private var kbHideToken: NSObjectProtocol?
    @State private var savedMessages: [AIStudyMessage] = []
    @State var conversationHistory: [[AIStudyMessage]] = []
    @State var showHistory = false
    @State private var showSettings = false
    @StateObject private var speechService = SpeechRecognitionService()
    @State private var speechAuthorized = false
    @State private var showCrisisResources = false
    @State private var crisisResult: CrisisDetectionResult? = nil

    private var hasProAccess: Bool {
        premiumManager.hasProAccess
    }

    enum AIStudyTab: String, CaseIterable {
        case chat = "Chat"
        case insights = "Insights"
        case questions = "Questions"
        case devotional = "Devotional"
        case study = "Study Plans"
        case analysis = "Analysis"
        case memorize = "Memory Verse"

        var icon: String {
            switch self {
            case .chat: return "message.fill"
            case .insights: return "lightbulb.fill"
            case .questions: return "questionmark.circle.fill"
            case .devotional: return "book.fill"
            case .study: return "list.bullet.clipboard.fill"
            case .analysis: return "chart.bar.doc.horizontal.fill"
            case .memorize: return "brain.head.profile"
            }
        }

        var requiresPro: Bool {
            switch self {
            case .devotional, .study, .analysis, .memorize:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let keyboardInset = max(0, keyboardHeight - proxy.safeAreaInsets.bottom)

            NavigationStack {
                ZStack(alignment: .bottom) {
                // MARK: Light atmospheric background
                Color(red: 0.949, green: 0.949, blue: 0.969) // iOS systemGray6 equivalent
                    .ignoresSafeArea()

                // Atmospheric bottom-corner color blobs (reference-inspired)
                ZStack {
                    // Left blob — warm red/coral
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.30),
                                    Color(red: 1.0, green: 0.45, blue: 0.30).opacity(0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )
                        .frame(width: 440, height: 440)
                        .offset(x: -160, y: 120)
                        .blur(radius: 70)
                        .scaleEffect(orbAnimation ? 1.08 : 1.0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 8).repeatForever(autoreverses: true), value: orbAnimation)

                    // Right blob — violet/purple
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.25),
                                    Color(red: 0.45, green: 0.20, blue: 0.80).opacity(0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: 160, y: 100)
                        .blur(radius: 60)
                        .scaleEffect(orb2Animation ? 1.12 : 1.0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 6.5).repeatForever(autoreverses: true), value: orb2Animation)

                    // Subtle center warmth
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.75, blue: 0.40).opacity(0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 160
                            )
                        )
                        .frame(width: 320, height: 320)
                        .offset(x: 0, y: 60)
                        .blur(radius: 50)
                        .scaleEffect(pulseAnimation ? 1.18 : 1.0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 5).repeatForever(autoreverses: true), value: pulseAnimation)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // MARK: Main content
                    VStack(spacing: 0) {
                    // Tab selector
                    lightTabSelector

                    // Usage limit banner
                    if !hasProAccess && selectedTab == .chat {
                        LightUsageLimitBanner(
                            messagesRemaining: premiumManager.freeMessagesRemaining,
                            totalMessages: premiumManager.dailyMessageLimit ?? premiumManager.FREE_MESSAGES_PER_DAY,
                            onUpgrade: { showProUpgrade = true }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Scrollable content area
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                switch selectedTab {
                                case .chat:
                                    if messages.isEmpty {
                                        BereanLandingEmbedded(onActionTap: { prompt in
                                            userInput = prompt
                                            isInputFocused = true
                                        })
                                        .id("emptyState")
                                    } else {
                                        LightChatContent(
                                            messages: $messages,
                                            isProcessing: $isProcessing,
                                            savedMessages: $savedMessages
                                        )
                                        .id("chatContent")
                                        .padding(.top, 8)
                                    }

                                case .insights:
                                    InsightsContent()
                                        .padding(.vertical, 20)
                                case .questions:
                                    QuestionsContent(onQuestionTap: { question in
                                        selectedTab = .chat
                                        userInput = question
                                        isInputFocused = true
                                    })
                                    .padding(.vertical, 20)
                                case .devotional:
                                    DevotionalContent(savedMessages: $savedMessages)
                                        .padding(.vertical, 20)
                                case .study:
                                    StudyPlansContent()
                                        .padding(.vertical, 20)
                                case .analysis:
                                    AnalysisContent()
                                        .padding(.vertical, 20)
                                case .memorize:
                                    MemorizeContent()
                                        .padding(.vertical, 20)
                                }

                                // Bottom spacer for input bar
                                if selectedTab == .chat {
                                    Color.clear
                                        .frame(height: 90 + keyboardInset)
                                        .id("bottomSpacer")
                                }
                            }
                        }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollProxy.scrollTo("bottomSpacer", anchor: .bottom)
                            }
                        }
                        .onChange(of: isInputFocused) { _, focused in
                            if focused {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        scrollProxy.scrollTo("bottomSpacer", anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .onChange(of: keyboardInset) { _, _ in
                            guard selectedTab == .chat else { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                scrollProxy.scrollTo("bottomSpacer", anchor: .bottom)
                            }
                        }
                    }

                    // Light Glassmorphic Input (chat tab only)
                    if selectedTab == .chat {
                        LightGlassmorphicChatInput(
                            userInput: $userInput,
                            isProcessing: $isProcessing,
                            isInputFocused: $isInputFocused,
                            isListening: $isListening,
                            keyboardHeight: keyboardHeight,
                            onSend: sendMessage,
                            onClear: clearConversation,
                            onMicTap: handleMicTap
                        )
                    }
                }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.impact(style: .light)
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.systemScaled(15, weight: .semibold))
                            Text("Back")
                                .font(AMENFont.semiBold(15))
                        }
                        .foregroundStyle(Color(white: 0.2))
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        // Berean "B" glyph — compact for nav bar
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.18),
                                            Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color(white: 0.85), lineWidth: 0.5))

                            Text("B")
                                .font(.systemScaled(15, weight: .light, design: .serif))
                                .foregroundStyle(Color(white: 0.2))
                        }

                        Text("Berean")
                            .font(.systemScaled(17, weight: .semibold, design: .default))
                            .foregroundStyle(Color(white: 0.12))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            HapticManager.impact(style: .light)
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.systemScaled(17))
                                .foregroundStyle(Color(white: 0.35))
                        }
                        .accessibilityLabel("History")

                        Button {
                            HapticManager.impact(style: .light)
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.systemScaled(17))
                                .foregroundStyle(Color(white: 0.35))
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            }
        }
        .preferredColorScheme(nil)
        .sheet(isPresented: $showProUpgrade) {
            PremiumUpgradeView(context: .aiLimit)
        }
        .sheet(isPresented: $showHistory) {
            AIBibleStudyConversationHistoryView(
                history: $conversationHistory,
                onLoad: loadConversation
            )
        }
        .sheet(isPresented: $showSettings) {
            AISettingsView()
        }
        .sheet(isPresented: $showVoiceInput, onDismiss: {
            if speechService.isRecording { speechService.stopRecording() }
        }) {
            VoiceInputView(
                speechRecognizer: speechService,
                isPresented: $showVoiceInput
            ) { transcribed in
                userInput = transcribed
                isInputFocused = true
            }
        }
        .sheet(isPresented: $showCrisisResources) {
            CrisisResourcesDetailView()
        }
        .onAppear {
            setupKeyboardObservers()
            withAnimation {
                orbAnimation = true
                orb2Animation = true
                pulseAnimation = true
            }
            Task {
                await premiumManager.checkSubscriptionStatus()
            }
            Task {
                await loadConversationsFromFirestore()
            }
            Task {
                speechAuthorized = await speechService.requestAuthorization()
            }
        }
        .onDisappear {
            removeKeyboardObservers()
            saveCurrentConversation()
        }
    }

    // MARK: - Light Tab Selector

    private var lightTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AIStudyTab.allCases, id: \.self) { tab in
                    Button {
                        HapticManager.selection()
                        if tab.requiresPro && !hasProAccess {
                            showProUpgrade = true
                        } else {
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.72))) {
                                selectedTab = tab
                                isInputFocused = false
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.systemScaled(12, weight: .semibold))

                            Text(tab.rawValue)
                                .font(AMENFont.semiBold(13))

                            if tab.requiresPro && !hasProAccess {
                                Image(systemName: "lock.fill")
                                    .font(.systemScaled(9))
                                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.25))
                            }
                        }
                        .foregroundStyle(
                            selectedTab == tab
                                ? Color(white: 0.08)
                                : Color(white: 0.50)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                }
                            }
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            Color(red: 0.949, green: 0.949, blue: 0.969)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        )
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        // Guard against duplicate registration on repeated onAppear calls
        guard kbShowToken == nil else { return }

        kbShowToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = keyboardFrame.height
            }
        }

        kbHideToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = 0
            }
        }
    }

    private func removeKeyboardObservers() {
        if let token = kbShowToken {
            NotificationCenter.default.removeObserver(token)
            kbShowToken = nil
        }
        if let token = kbHideToken {
            NotificationCenter.default.removeObserver(token)
            kbHideToken = nil
        }
    }

    // MARK: - Voice Input

    private func handleMicTap() {
        HapticManager.impact(style: .light)
        isInputFocused = false
        if speechService.isRecording {
            speechService.stopRecording()
            isListening = false
            if !speechService.transcribedText.isEmpty {
                userInput = speechService.transcribedText
            }
        } else {
            if speechAuthorized {
                do {
                    try speechService.startRecording()
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6))) {
                        isListening = true
                    }
                    // Auto-stop after 30s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                        if speechService.isRecording {
                            speechService.stopRecording()
                            withAnimation { isListening = false }
                            if !speechService.transcribedText.isEmpty {
                                userInput = speechService.transcribedText
                            }
                        }
                    }
                } catch {
                    // Fallback: open sheet
                    showVoiceInput = true
                }
            } else {
                showVoiceInput = true
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        Task { await sendMessageAfterServerLimitCheck() }
    }

    @MainActor
    private func sendMessageAfterServerLimitCheck() async {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let premiumManager = PremiumManager.shared
        guard premiumManager.canSendMessage(),
              await premiumManager.reserveAIMessageAllowance() else {
            showProUpgrade = true
            let limit = premiumManager.dailyMessageLimit ?? premiumManager.FREE_MESSAGES_PER_DAY
            messages.append(AIStudyMessage(
                text: "You've reached your daily limit of \(limit) AI study messages. Upgrade to Plus for more room or Pro for unlimited Berean depth.\n\nYour limit resets at midnight.",
                isUser: false
            ))
            return
        }

        // Stop voice if still recording
        if speechService.isRecording {
            speechService.stopRecording()
            withAnimation { isListening = false }
        }

        let message = AIStudyMessage(text: userInput, isUser: true)
        messages.append(message)
        let questionText = userInput
        userInput = ""

        isProcessing = true

        Task {
            do {
                let userId = Auth.auth().currentUser?.uid ?? "anon"

                // ── Step 1: Crisis detection (quick local keyword check) ──────
                if let crisis = try? await CrisisDetectionService.shared.detectCrisis(
                    in: questionText,
                    userId: userId
                ), crisis.isCrisis {
                    await MainActor.run {
                        crisisResult = crisis
                        // Show compassionate acknowledgment inline
                        let urgencyMessage = crisis.urgencyLevel == .critical
                            ? "I noticed something important in what you shared. You matter deeply, and help is available right now. Please reach out to the resources below — you don't have to face this alone."
                            : "I want to make sure you have the support you need. I've shared some resources that may help."
                        messages.append(AIStudyMessage(
                            text: "💛 \(urgencyMessage)",
                            isUser: false
                        ))
                        // Show crisis resources sheet for high/critical urgency
                        if crisis.urgencyLevel == .critical || crisis.urgencyLevel == .high {
                            showCrisisResources = true
                        }
                        isProcessing = false
                    }
                    // Still allow the message to proceed to Claude so the user
                    // receives scripture-grounded care, not just a hard stop.
                    // Fall through to policy + API call below.
                }

                // ── Step 2: Prompt policy evaluation ─────────────────────────
                let policyRequest = BereanAIRequest(
                    surface: .bereanChat,
                    category: .assistantResponse,
                    userInput: questionText,
                    userId: userId,
                    isPrivate: false
                )
                let policyResult = await PromptPolicyEngine.shared.evaluate(policyRequest)

                if policyResult.shouldBlock {
                    await MainActor.run {
                        messages.append(AIStudyMessage(
                            text: policyResult.blockReason ?? "I'm not able to respond to that kind of request.",
                            isUser: false
                        ))
                        isProcessing = false
                    }
                    return
                }

                // Use sanitized input if policy transformed it, otherwise raw input
                let effectiveInput = policyResult.transformedInput ?? questionText

                // ── Step 3: Call Berean (Claude via Genkit) ───────────────────
                let response = try await callBibleChatAPI(message: effectiveInput)
                await MainActor.run {
                    messages.append(AIStudyMessage(text: response, isUser: false))
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    messages.append(AIStudyMessage(
                        text: "Sorry, I encountered an error. Please try again. (Error: \(error.localizedDescription))",
                        isUser: false
                    ))
                    isProcessing = false
                }
            }
        }
    }

    private func callBibleChatAPI(message: String) async throws -> String {
        let genkitService = BereanGenkitService.shared

        let history = messages.map { msg in
            BereanMessage(
                content: msg.text,
                role: msg.isUser ? .user : .assistant,
                timestamp: Date(),
                verseReferences: []
            )
        }

        return try await genkitService.sendMessageSync(message, conversationHistory: history)
    }

    // Functions defined in AIBibleStudyExtensions.swift:
    // clearConversation(), saveCurrentConversation(), loadConversationsFromFirestore(), loadConversation(_:)
}

// MARK: - Berean Empty State

struct BereanEmptyState: View {
    let onSuggestionTap: (String) -> Void

    private let suggestions = [
        "What does John 3:16 mean?",
        "Explain the Sermon on the Mount",
        "What is the fruit of the Spirit?",
        "Help me understand Romans 8",
        "What did Jesus teach about prayer?",
        "Tell me about the book of Psalms"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            // Hero editorial headline
            VStack(spacing: 16) {
                // Berean glyph — large, airy
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.14),
                                    Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(Color(white: 0.88), lineWidth: 0.5))

                    Text("B")
                        .font(.systemScaled(40, weight: .ultraLight, design: .serif))
                        .foregroundStyle(Color(white: 0.22))
                }

                VStack(spacing: 10) {
                    Text("Ask Berean")
                        .font(.systemScaled(34, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.10))
                        .multilineTextAlignment(.center)

                    Text("Scripture-grounded answers\nto your deepest questions.")
                        .font(AMENFont.regular(16))
                        .foregroundStyle(Color(white: 0.50))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 40)

            // Suggestion chips
            VStack(alignment: .leading, spacing: 12) {
                Text("Try asking")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(Color(white: 0.55))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 10)
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                HapticManager.selection()
                                onSuggestionTap(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(Color(white: 0.25))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                    )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        Spacer(minLength: 10)
                    }
                }
            }

            Spacer(minLength: 100)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Light Chat Content

struct LightChatContent: View {
    @Binding var messages: [AIStudyMessage]
    @Binding var isProcessing: Bool
    @Binding var savedMessages: [AIStudyMessage]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(messages) { message in
                LightMessageBubble(message: message)
            }

            if isProcessing {
                HStack(alignment: .top, spacing: 10) {
                    // AI avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.15),
                                        Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color(white: 0.88), lineWidth: 0.5))

                        Text("B")
                            .font(.systemScaled(16, weight: .light, design: .serif))
                            .foregroundStyle(Color(white: 0.25))
                    }

                    // Typing dots
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color(white: 0.60))
                                .frame(width: 7, height: 7)
                                .scaleEffect(isProcessing ? 1.0 : 0.5)
                                .animation(
                                    .easeInOut(duration: 0.55)
                                        .repeatForever()
                                        .delay(Double(index) * 0.18),
                                    value: isProcessing
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
                    )

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
}

// MARK: - Light Message Bubble

struct LightMessageBubble: View {
    let message: AIStudyMessage
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.15),
                                    Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color(white: 0.88), lineWidth: 0.5))

                    Text("B")
                        .font(.systemScaled(15, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.25))
                }
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 0) {
                Text(message.text)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(
                        message.isUser
                            ? Color.white
                            : Color(white: 0.12)
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        Group {
                            if message.isUser {
                                // User: warm gradient bubble
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 1.0, green: 0.42, blue: 0.28),
                                                Color(red: 0.95, green: 0.32, blue: 0.20)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.20).opacity(0.28), radius: 10, y: 3)
                            } else {
                                // AI: clean white card
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.07), radius: 10, y: 3)
                            }
                        }
                    )
                    .contextMenu {
                        Button {
                            HapticManager.impact(style: .light)
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        if !message.isUser {
                            Button {
                                HapticManager.impact(style: .light)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                HapticManager.impact(style: .light)
                            } label: {
                                Label("Save", systemImage: "bookmark")
                            }
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
            .offset(x: appeared ? 0 : (message.isUser ? 30 : -30))
            .opacity(appeared ? 1.0 : 0)

            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.72)).delay(0.05)) {
                appeared = true
            }
        }
    }
}

// MARK: - Light Glassmorphic Chat Input

struct LightGlassmorphicChatInput: View {
    @Binding var userInput: String
    @Binding var isProcessing: Bool
    @FocusState.Binding var isInputFocused: Bool
    @Binding var isListening: Bool
    let keyboardHeight: CGFloat
    let onSend: () -> Void
    let onClear: () -> Void
    let onMicTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {

                // Mic / Voice button
                Button {
                    onMicTap()
                } label: {
                    ZStack {
                        // Pulse ring when listening
                        if isListening {
                            Circle()
                                .fill(Color.red.opacity(0.18))
                                .frame(width: 46, height: 46)
                                .scaleEffect(isListening ? 1.4 : 1.0)
                                .opacity(isListening ? 0 : 1)
                                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: isListening)
                        }

                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color(white: 0.88), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)

                        Image(systemName: isListening ? "waveform" : "mic.fill")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(
                                isListening
                                    ? Color.red
                                    : Color(white: 0.40)
                            )
                            .symbolEffect(.variableColor.iterative, options: .repeating, value: isListening)
                    }
                }
                .buttonStyle(ScaleButtonStyle())

                // Text field with glow border (preserved from original)
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        if userInput.isEmpty {
                            Text("Ask about Scripture...")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(Color(white: 0.55))
                                .padding(.leading, 2)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $userInput, axis: .vertical)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color(white: 0.10))
                            .padding(.leading, 2)
                            .lineLimit(1...4)
                            .focused($isInputFocused)
                            .submitLabel(.send)
                            .accessibilityLabel("Bible study question or request")
                            .onSubmit {
                                if !userInput.isEmpty && !isProcessing {
                                    HapticManager.impact(style: .light)
                                    onSend()
                                    isInputFocused = false
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white)

                        // Glow border — brighter when focused or processing (preserved behavior)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        isInputFocused || isProcessing
                                            ? Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.70)
                                            : Color(white: 0.84),
                                        isInputFocused || isProcessing
                                            ? Color(red: 0.58, green: 0.25, blue: 0.95).opacity(0.55)
                                            : Color(white: 0.84)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isInputFocused || isProcessing ? 1.5 : 0.8
                            )
                    }
                )
                .shadow(
                    color: isInputFocused || isProcessing
                        ? Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.18)
                        : Color.black.opacity(0.06),
                    radius: isInputFocused || isProcessing ? 14 : 6,
                    y: 3
                )
                .animation(.easeInOut(duration: 0.22), value: isInputFocused)
                .animation(.easeInOut(duration: 0.22), value: isProcessing)

                // Send button
                Button {
                    if !userInput.isEmpty && !isProcessing {
                        HapticManager.impact(style: .light)
                        onSend()
                        isInputFocused = false
                    }
                } label: {
                    ZStack {
                        // Glow halo when active
                        if !userInput.isEmpty {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.42, blue: 0.28).opacity(0.22))
                                .frame(width: 50, height: 50)
                                .blur(radius: 8)
                        }

                        Circle()
                            .fill(
                                userInput.isEmpty
                                    ? LinearGradient(colors: [Color(white: 0.88), Color(white: 0.84)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.48, blue: 0.30), Color(red: 0.95, green: 0.32, blue: 0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(
                                color: userInput.isEmpty ? .clear : Color(red: 1.0, green: 0.35, blue: 0.18).opacity(0.38),
                                radius: 8,
                                y: 2
                            )

                        Image(systemName: isProcessing ? "stop.fill" : "arrow.up")
                            .font(.systemScaled(16, weight: .bold))
                            .foregroundStyle(userInput.isEmpty ? Color(white: 0.55) : .white)
                            .symbolEffect(.bounce, value: !userInput.isEmpty)
                    }
                }
                .disabled(userInput.isEmpty || isProcessing)
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, y: -2)
            )
        }
        .padding(.bottom, keyboardHeight > 0 ? 8 : 0)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
    }
}

// MARK: - Light Usage Limit Banner

struct LightUsageLimitBanner: View {
    let messagesRemaining: Int
    let totalMessages: Int
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.25))

            Text("\(messagesRemaining) of \(totalMessages) free messages remaining today")
                .font(AMENFont.regular(13))
                .foregroundStyle(Color(white: 0.35))

            Spacer()

            Button(action: onUpgrade) {
                Text("Upgrade")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.25))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.45, blue: 0.25).opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color(white: 0.96))
                .overlay(
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.25).opacity(0.08)),
                    alignment: .bottom
                )
        )
    }
}

// MARK: - Tab Content Views (preserved unchanged)

struct InsightsContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(aiInsights) { insight in
                AIInsightCard(insight: insight)
            }
        }
    }
}

struct AIInsightCard: View {
    let insight: AIInsight
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(insight.color.opacity(0.12))
                            .frame(width: 48, height: 48)

                        Image(systemName: insight.icon)
                            .font(.systemScaled(20))
                            .foregroundStyle(insight.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(AMENFont.bold(16))
                            .foregroundStyle(Color(white: 0.12))

                        Text(insight.verse)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                }

                if isExpanded {
                    Divider()

                    Text(insight.content)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(Color(white: 0.20))
                        .lineSpacing(4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuestionsContent: View {
    let onQuestionTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Suggested Questions")
                .font(AMENFont.bold(20))
                .foregroundStyle(Color(white: 0.12))
                .padding(.horizontal)

            ForEach(suggestedQuestions, id: \.self) { question in
                QuestionCard(question: question, onTap: {
                    onQuestionTap(question)
                })
            }
        }
    }
}

struct QuestionCard: View {
    let question: String
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.systemScaled(20))
                    .foregroundStyle(Color(red: 0.30, green: 0.60, blue: 0.95))

                Text(question)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(Color(white: 0.15))
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.50))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 1)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AIStudyMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

// Note: AIInsight is defined in BibleAIService.swift

let aiInsights = [
    AIInsight(
        title: "The Power of Prayer",
        verse: "Matthew 7:7",
        content: "Jesus teaches us that persistent prayer is answered. 'Ask and it will be given to you; seek and you will find; knock and the door will be opened to you.' This verse encourages us to approach God boldly with our requests, knowing He hears and responds to those who seek Him earnestly.",
        icon: "hands.sparkles.fill",
        color: Color(red: 0.5, green: 0.3, blue: 0.9)
    ),
    AIInsight(
        title: "God's Faithfulness",
        verse: "Lamentations 3:22-23",
        content: "Even in our darkest moments, God's mercies are new every morning. His faithfulness is great, providing hope and strength for each new day. This passage reminds us that no matter what we face, God's compassion never fails and His steadfast love endures forever.",
        icon: "sunrise.fill",
        color: .orange
    ),
    AIInsight(
        title: "Walking in Love",
        verse: "1 Corinthians 13:4-7",
        content: "Love is patient, kind, and never fails. Paul's description of love shows us how to treat others with Christ-like compassion and grace. This agape love—unconditional and sacrificial—is the foundation of Christian relationships and reflects God's love for us.",
        icon: "heart.fill",
        color: .pink
    )
]

let suggestedQuestions = [
    "What does it mean to be born again?",
    "How can I strengthen my faith?",
    "What does the Bible say about forgiveness?",
    "Explain the significance of the cross",
    "What is the Holy Spirit's role in our lives?",
    "How do I find peace in difficult times?",
    "What does the Bible say about purpose?",
    "Help me understand the Trinity"
]

// MARK: - Devotional Content

struct DevotionalContent: View {
    @Binding var savedMessages: [AIStudyMessage]
    @State private var currentIndex: Int = DevotionalContent.todayIndex()
    @State private var noteSaved = false

    private static let devotionals: [(scripture: String, ref: String, title: String, reflection: String, prayer: String)] = [
        (
            "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
            "John 3:16",
            "The Gift of Eternal Life",
            "God's love for us is not passive or distant — it is active, costly, and personal. He gave what was most precious to Him so that you could have life. Today, sit with the word 'whoever.' It includes you, exactly as you are, right now.",
            "Father, thank You for a love that does not wait until I'm worthy. Help me receive it fully today and let it change how I see myself and others. Amen."
        ),
        (
            "I can do all things through Christ who strengthens me.",
            "Philippians 4:13",
            "Strength Not Your Own",
            "Paul wrote this from prison — not from a mountain top. The 'all things' he refers to includes contentment in lack and in abundance. This is not a promise of superhuman achievement, but of supernatural peace in every circumstance.",
            "Lord, I confess I often try to carry things on my own. Today I surrender my strength and ask for Yours. Where I feel weak, be strong through me. Amen."
        ),
        (
            "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
            "Proverbs 3:5-6",
            "Surrendering Understanding",
            "We often want to understand before we trust. God asks for the opposite — full trust even when we don't understand. Submitting 'all your ways' means every decision, not just the spiritual ones. Your career, relationships, and daily choices are all paths He wants to straighten.",
            "God, there are things in my life I cannot understand. Today I choose trust over clarity. Direct my steps even when I can't see where the path leads. Amen."
        ),
        (
            "Come to me, all you who are weary and burdened, and I will give you rest.",
            "Matthew 11:28",
            "An Invitation to Rest",
            "Jesus does not say 'clean up first, then come.' He invites the weary, the burdened, and the broken exactly as they are. The rest He offers is not just sleep — it is the soul-level peace that comes from releasing control to Him.",
            "Jesus, I come to You tired and carrying more than I can hold. I accept Your invitation. Teach me what it means to truly rest in You. Amen."
        ),
        (
            "The Lord is my shepherd; I shall not want.",
            "Psalm 23:1",
            "Under Good Shepherding",
            "A shepherd in ancient times did not merely manage sheep from a distance — he led them personally through danger, knew each one by name, and laid down his life for the flock. David knew this. So did Jesus, who called Himself the Good Shepherd. You are not anonymous to God.",
            "Good Shepherd, guide me through the valleys I'm walking today. Remind me that You are ahead of me, not far away. I trust Your leading. Amen."
        ),
        (
            "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control.",
            "Galatians 5:22-23",
            "The Fruit of Abiding",
            "Fruit is not manufactured — it is grown. You cannot force a tree to produce fruit; it comes naturally when the roots are nourished. These nine qualities are the natural overflow of a life connected to God's Spirit. The question is not 'how do I produce more?' but 'how deeply am I rooted?'",
            "Holy Spirit, I want my life to look like this list. Show me where I have tried to manufacture what only You can grow. Root me deeper in You today. Amen."
        ),
        (
            "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
            "Romans 8:28",
            "All Things Working",
            "'All things' is not 'most things' or 'the good things.' Paul includes suffering, disappointment, and loss in this promise. This does not mean everything is good — it means God is working even through what is not good. Your current hardship is not wasted.",
            "Father, I confess that I struggle to believe this promise in the middle of pain. Help my unbelief. Show me, even dimly, how You might be working in what I cannot yet understand. Amen."
        )
    ]

    private static func todayIndex() -> Int {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return dayOfYear % devotionals.count
    }

    private var today: (scripture: String, ref: String, title: String, reflection: String, prayer: String) {
        DevotionalContent.devotionals[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY DEVOTIONAL")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                        .kerning(2)
                    Text(formattedDate)
                        .font(AMENFont.bold(18))
                        .foregroundStyle(Color(white: 0.12))
                }
                Spacer()
                // Day navigation
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentIndex = (currentIndex - 1 + DevotionalContent.devotionals.count) % DevotionalContent.devotionals.count
                            noteSaved = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(Color(white: 0.4))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.06), radius: 4))
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentIndex = (currentIndex + 1) % DevotionalContent.devotionals.count
                            noteSaved = false
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(Color(white: 0.4))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.06), radius: 4))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Scripture card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "book.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88))
                            Text(today.ref)
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88))
                        }
                        Text("\u{201C}\(today.scripture)\u{201D}")
                            .font(AMENFont.regular(17))
                            .foregroundStyle(Color(white: 0.10))
                            .lineSpacing(5)
                            .italic()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                    )
                    .padding(.horizontal, 16)

                    // Title + reflection
                    VStack(alignment: .leading, spacing: 10) {
                        Text(today.title)
                            .font(AMENFont.bold(20))
                            .foregroundStyle(Color(white: 0.10))
                        Text(today.reflection)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color(white: 0.25))
                            .lineSpacing(5)
                    }
                    .padding(.horizontal, 20)

                    // Prayer section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "hands.sparkles.fill")
                                .font(.systemScaled(14))
                                .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
                            Text("TODAY'S PRAYER")
                                .font(.systemScaled(10, weight: .bold))
                                .kerning(2)
                                .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
                        }
                        Text(today.prayer)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color(white: 0.20))
                            .lineSpacing(5)
                            .italic()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 1.0, green: 0.96, blue: 0.90))
                    )
                    .padding(.horizontal, 16)

                    // Save to notes button
                    Button {
                        let note = BereanStudyNote(
                            verseReference: today.ref,
                            noteText: "\(today.title)\n\n\(today.reflection)\n\nPrayer: \(today.prayer)",
                            messageId: UUID().uuidString
                        )
                        BereanStudyNotesService.shared.saveNote(note)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { noteSaved = true }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: noteSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                                .font(.systemScaled(15))
                            Text(noteSaved ? "Saved to Notes" : "Save Devotional")
                                .font(AMENFont.semiBold(14))
                        }
                        .foregroundStyle(noteSaved ? .green : Color(white: 0.30))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        )
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: Date())
    }
}

// MARK: - Study Plans Content

struct StudyPlansContent: View {
    @State private var showGenerator = false

    private let accentPurple = Color(red: 0.56, green: 0.27, blue: 0.88)

    private let featuredPlans: [(icon: String, title: String, days: String, color: Color, description: String)] = [
        ("star.fill",           "Gospel Foundations",        "30 days", Color(red: 0.95, green: 0.50, blue: 0.10), "Walk through the four Gospels and discover who Jesus is."),
        ("book.fill",           "Psalms & Proverbs",         "21 days", Color(red: 0.25, green: 0.55, blue: 0.90), "Daily wisdom and worship from Israel's poetic library."),
        ("flame.fill",          "Letters of Paul",           "45 days", Color(red: 0.80, green: 0.20, blue: 0.20), "Deep dive into Romans, Galatians, Philippians and more."),
        ("leaf.fill",           "New Believer Essentials",   "14 days", Color(red: 0.20, green: 0.65, blue: 0.35), "Core foundations for those new to the Christian faith."),
        ("mountain.2.fill",     "Old Testament Overview",    "60 days", Color(red: 0.55, green: 0.30, blue: 0.10), "Survey from Genesis to Malachi in 60 focused readings."),
        ("brain.head.profile",  "Faith & Science",           "10 days", Color(red: 0.45, green: 0.20, blue: 0.80), "Explore how faith and reason speak to one another."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STUDY PLANS")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                        .kerning(2)
                    Text("Guided Reading")
                        .font(AMENFont.bold(18))
                        .foregroundStyle(Color(white: 0.12))
                }
                Spacer()
                Button {
                    showGenerator = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(12))
                        Text("Custom Plan")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundStyle(accentPurple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(accentPurple.opacity(0.10))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(featuredPlans.enumerated()), id: \.offset) { _, plan in
                        StudyPlanRowCard(
                            icon: plan.icon,
                            title: plan.title,
                            days: plan.days,
                            color: plan.color,
                            description: plan.description
                        )
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showGenerator) {
            StudyPlanGeneratorView()
        }
    }
}

private struct StudyPlanRowCard: View {
    let icon: String
    let title: String
    let days: String
    let color: Color
    let description: String
    @State private var enrolled = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.systemScaled(20))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(Color(white: 0.10))
                Text(description)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(Color(white: 0.45))
                    .lineLimit(2)
                Text(days)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3)) { enrolled.toggle() }
            } label: {
                Text(enrolled ? "Enrolled" : "Start")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(enrolled ? .green : color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(enrolled ? Color.green.opacity(0.12) : color.opacity(0.12))
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}

// MARK: - Analysis Content

struct AnalysisContent: View {
    @State private var searchWord = ""
    @State private var selectedEntry: WordStudyEntry? = WordAnalysisData.entries.first
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("WORD STUDY")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
                    .kerning(2)
                Text("Biblical Analysis")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(Color(white: 0.12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color(white: 0.50))
                TextField("Search a word (e.g. grace, faith, love...)", text: $searchWord)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.15))
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .accessibilityLabel("Search biblical word")
                    .onSubmit {
                        let q = searchWord.trimmingCharacters(in: .whitespaces).lowercased()
                        selectedEntry = WordAnalysisData.entries.first { $0.word.lowercased() == q }
                            ?? WordAnalysisData.entries.first(where: { $0.word.lowercased().hasPrefix(q) })
                        isSearchFocused = false
                    }
                if !searchWord.isEmpty {
                    Button { searchWord = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(white: 0.65))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Word chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(WordAnalysisData.entries) { entry in
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedEntry = entry
                                        searchWord = entry.word
                                    }
                                } label: {
                                    Text(entry.word)
                                        .font(AMENFont.semiBold(13))
                                        .foregroundStyle(selectedEntry?.id == entry.id
                                            ? Color(red: 0.56, green: 0.27, blue: 0.88)
                                            : Color(white: 0.35))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(selectedEntry?.id == entry.id
                                                    ? Color(red: 0.56, green: 0.27, blue: 0.88).opacity(0.12)
                                                    : Color.white)
                                                .shadow(color: .black.opacity(0.04), radius: 4)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if let entry = selectedEntry {
                        WordStudyCard(entry: entry)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.systemScaled(36))
                                .foregroundStyle(Color(white: 0.70))
                            Text("Search a biblical term above")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(Color(white: 0.50))
                        }
                        .padding(.top, 40)
                    }

                    Color.clear.frame(height: 30)
                }
            }
        }
    }
}

struct WordStudyEntry: Identifiable {
    let id = UUID()
    let word: String
    let hebrew: String?   // Hebrew transliteration
    let greek: String?    // Greek transliteration
    let strongs: String   // Strongs number
    let definition: String
    let usage: String
    let keyVerses: [(ref: String, text: String)]
    let relatedWords: [String]
}

enum WordAnalysisData {
    static let entries: [WordStudyEntry] = [
        WordStudyEntry(
            word: "Grace",
            hebrew: "חֵן (chen)",
            greek: "χάρις (charis)",
            strongs: "H2580 / G5485",
            definition: "Unmerited favor or kindness extended freely, without expectation of repayment. In the New Testament, grace is the foundational term for God's saving work — unearned, undeserved, and freely given through Christ.",
            usage: "Used 156 times in the NT. Central to Paul's theology of salvation: we are saved by grace through faith, not works (Eph 2:8). The Hebrew 'chen' emphasizes finding favor in someone's sight.",
            keyVerses: [
                ("Ephesians 2:8-9", "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God — not by works, so that no one can boast."),
                ("Romans 3:24", "And all are justified freely by his grace through the redemption that came by Christ Jesus."),
                ("John 1:17", "For the law was given through Moses; grace and truth came through Jesus Christ.")
            ],
            relatedWords: ["Mercy", "Love", "Redemption", "Justification"]
        ),
        WordStudyEntry(
            word: "Faith",
            hebrew: "אֱמוּנָה (emunah)",
            greek: "πίστις (pistis)",
            strongs: "H530 / G4102",
            definition: "Firm belief, trust, and confidence in God and His promises. In the Hebrew, 'emunah' emphasizes steadfastness and faithfulness — being true. The Greek 'pistis' conveys active trust that produces obedience.",
            usage: "Found over 240 times in the NT. Faith is both the instrument by which we receive salvation and the ongoing disposition of the Christian life. Hebrews 11 catalogs its heroes.",
            keyVerses: [
                ("Hebrews 11:1", "Now faith is confidence in what we hope for and assurance about what we do not see."),
                ("Romans 10:17", "Consequently, faith comes from hearing the message, and the message is heard through the word about Christ."),
                ("James 2:17", "In the same way, faith by itself, if it is not accompanied by action, is dead.")
            ],
            relatedWords: ["Trust", "Hope", "Belief", "Obedience"]
        ),
        WordStudyEntry(
            word: "Love",
            hebrew: "אַהֲבָה (ahavah)",
            greek: "ἀγάπη (agape)",
            strongs: "H160 / G26",
            definition: "Greek has four words for love; 'agape' is the highest — unconditional, self-giving love that seeks the good of another regardless of merit. It is the love God has for humanity and commands Christians to show one another.",
            usage: "1 John alone uses 'agape' 18 times. The famous 'love chapter' (1 Cor 13) describes its characteristics exhaustively. Jesus names it the greatest commandment.",
            keyVerses: [
                ("1 John 4:8", "Whoever does not love does not know God, because God is love."),
                ("1 Corinthians 13:4-5", "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking."),
                ("John 15:13", "Greater love has no one than this: to lay down one's life for one's friends.")
            ],
            relatedWords: ["Grace", "Mercy", "Compassion", "Agape"]
        ),
        WordStudyEntry(
            word: "Redemption",
            hebrew: "גָּאַל (ga'al)",
            greek: "ἀπολύτρωσις (apolytrosis)",
            strongs: "H1350 / G629",
            definition: "To buy back from bondage; to liberate by paying a price. In the OT, the 'kinsman-redeemer' (goel) had the right and obligation to rescue a relative from debt or slavery. Christ fulfills this role for all of humanity.",
            usage: "The concept permeates both Testaments. Israel's Exodus from Egypt is the paradigmatic redemption event. The NT applies this template to Christ's death as cosmic ransom (Mark 10:45).",
            keyVerses: [
                ("Ephesians 1:7", "In him we have redemption through his blood, the forgiveness of sins, in accordance with the riches of God's grace."),
                ("Galatians 3:13", "Christ redeemed us from the curse of the law by becoming a curse for us."),
                ("Ruth 4:14", "The women said to Naomi: 'Praise be to the Lord, who this day has not left you without a guardian-redeemer.'")
            ],
            relatedWords: ["Atonement", "Salvation", "Grace", "Forgiveness"]
        ),
        WordStudyEntry(
            word: "Shalom",
            hebrew: "שָׁלוֹם (shalom)",
            greek: "εἰρήνη (eirene)",
            strongs: "H7965 / G1515",
            definition: "Far more than the absence of conflict, shalom denotes wholeness, completeness, and well-being in every dimension — relational, physical, spiritual, and social. It is the condition of things as God designed them to be.",
            usage: "Used 237 times in the OT. The priestly blessing of Numbers 6:24-26 culminates with shalom. Jesus' resurrection greeting was 'Peace be with you' — shalom to His frightened disciples.",
            keyVerses: [
                ("Isaiah 26:3", "You will keep in perfect peace those whose minds are steadfast, because they trust in you."),
                ("John 14:27", "Peace I leave with you; my peace I give you. I do not give to you as the world gives."),
                ("Romans 5:1", "Therefore, since we have been justified through faith, we have peace with God through our Lord Jesus Christ.")
            ],
            relatedWords: ["Peace", "Rest", "Wholeness", "Blessing"]
        ),
        WordStudyEntry(
            word: "Repentance",
            hebrew: "שׁוּב (shuv)",
            greek: "μετάνοια (metanoia)",
            strongs: "H7725 / G3341",
            definition: "A complete change of mind and direction. The Hebrew 'shuv' means to turn around — literally to stop going one way and go another. The Greek 'metanoia' is a transformation of mind (nous) that leads to behavioral change.",
            usage: "The opening message of both John the Baptist and Jesus was 'Repent, for the kingdom of heaven has come near.' It is not primarily sorrow for sin, but a reorientation of life toward God.",
            keyVerses: [
                ("Acts 3:19", "Repent, then, and turn to God, so that your sins may be wiped out, that times of refreshing may come from the Lord."),
                ("Luke 15:7", "I tell you that in the same way there will be more rejoicing in heaven over one sinner who repents than over ninety-nine righteous persons who do not need to repent."),
                ("2 Corinthians 7:10", "Godly sorrow brings repentance that leads to salvation and leaves no regret.")
            ],
            relatedWords: ["Forgiveness", "Restoration", "Grace", "Humility"]
        ),
    ]
}

private struct WordStudyCard: View {
    let entry: WordStudyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Word + transliterations
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.word)
                    .font(AMENFont.bold(26))
                    .foregroundStyle(Color(white: 0.08))
                HStack(spacing: 16) {
                    if let h = entry.hebrew {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("HEBREW").font(.systemScaled(9, weight: .bold)).kerning(1.5).foregroundStyle(Color(white: 0.55))
                            Text(h).font(AMENFont.regular(14)).foregroundStyle(Color(white: 0.25))
                        }
                    }
                    if let g = entry.greek {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("GREEK").font(.systemScaled(9, weight: .bold)).kerning(1.5).foregroundStyle(Color(white: 0.55))
                            Text(g).font(AMENFont.regular(14)).foregroundStyle(Color(white: 0.25))
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("STRONG'S").font(.systemScaled(9, weight: .bold)).kerning(1.5).foregroundStyle(Color(white: 0.55))
                        Text(entry.strongs).font(AMENFont.regular(14)).foregroundStyle(Color(white: 0.25))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white).shadow(color: .black.opacity(0.04), radius: 6, y: 2))

            // Definition
            sectionCard(title: "DEFINITION", icon: "text.quote") {
                Text(entry.definition)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.20))
                    .lineSpacing(4)
            }

            // Usage
            sectionCard(title: "USAGE IN SCRIPTURE", icon: "chart.bar.fill") {
                Text(entry.usage)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.20))
                    .lineSpacing(4)
            }

            // Key verses
            sectionCard(title: "KEY VERSES", icon: "book.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(entry.keyVerses.enumerated()), id: \.offset) { _, v in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(v.ref)
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88))
                            Text("\u{201C}\(v.text)\u{201D}")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(Color(white: 0.20))
                                .lineSpacing(3)
                                .italic()
                        }
                        if v.ref != entry.keyVerses.last?.ref {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            // Related words
            VStack(alignment: .leading, spacing: 8) {
                Text("RELATED TERMS")
                    .font(.systemScaled(10, weight: .bold))
                    .kerning(2)
                    .foregroundStyle(Color(white: 0.50))
                HStack(spacing: 8) {
                    ForEach(entry.relatedWords, id: \.self) { word in
                        Text(word)
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.56, green: 0.27, blue: 0.88).opacity(0.10))
                            )
                    }
                }
            }
            .padding(.horizontal, 16)

            Color.clear.frame(height: 4)
        }
        .padding(.horizontal, 16)
    }

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(11))
                    .foregroundStyle(Color(white: 0.50))
                Text(title)
                    .font(.systemScaled(10, weight: .bold))
                    .kerning(2)
                    .foregroundStyle(Color(white: 0.50))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}

// MARK: - Memory Verse Content

struct MemorizeContent: View {
    @AppStorage("berean_memorize_index") private var currentCardIndex: Int = 0
    @AppStorage("berean_memorize_mastered") private var masteredRaw: String = ""
    @State private var isRevealed = false
    @State private var showMastered = false
    @State private var dragOffset: CGFloat = 0

    private static let verses: [(ref: String, text: String, theme: String)] = [
        ("John 3:16",           "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",                 "Salvation"),
        ("Philippians 4:13",    "I can do all this through him who gives me strength.",                                                                                              "Strength"),
        ("Romans 8:28",         "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",                       "Providence"),
        ("Psalm 23:1",          "The Lord is my shepherd, I lack nothing.",                                                                                                         "Provision"),
        ("Proverbs 3:5-6",      "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.", "Guidance"),
        ("Matthew 6:33",        "But seek first his kingdom and his righteousness, and all these things will be given to you as well.",                                              "Priority"),
        ("Isaiah 40:31",        "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.", "Hope"),
        ("1 Corinthians 10:13", "No temptation has overtaken you except what is common to mankind. And God is faithful; he will not let you be tempted beyond what you can bear.",  "Faithfulness"),
        ("Ephesians 2:8-9",     "For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God — not by works, so that no one can boast.", "Grace"),
        ("Joshua 1:9",          "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.",                       "Courage"),
        ("Romans 12:2",         "Do not conform to the pattern of this world, but be transformed by the renewing of your mind.",                                                    "Transformation"),
        ("James 1:2-3",         "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds, because you know that the testing of your faith produces perseverance.", "Perseverance"),
    ]

    private var masteredSet: Set<Int> {
        Set(masteredRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var unmastered: [Int] {
        (0..<MemorizeContent.verses.count).filter { !masteredSet.contains($0) }
    }

    private var currentVerse: (ref: String, text: String, theme: String) {
        MemorizeContent.verses[currentCardIndex % MemorizeContent.verses.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header + progress
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MEMORY VERSE")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(Color(white: 0.55))
                            .kerning(2)
                        Text("Flashcard Practice")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(Color(white: 0.12))
                    }
                    Spacer()
                    Text("\(masteredSet.count)/\(MemorizeContent.verses.count) mastered")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(Color(red: 0.20, green: 0.65, blue: 0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 0.20, green: 0.65, blue: 0.35).opacity(0.10)))
                }
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.88)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.20, green: 0.65, blue: 0.35))
                            .frame(width: geo.size.width * (Double(masteredSet.count) / Double(MemorizeContent.verses.count)), height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Flashcard
                    ZStack {
                        // Card back (revealed)
                        if isRevealed {
                            VStack(spacing: 16) {
                                Text("\u{201C}\(currentVerse.text)\u{201D}")
                                    .font(AMENFont.regular(16))
                                    .foregroundStyle(Color(white: 0.10))
                                    .lineSpacing(5)
                                    .multilineTextAlignment(.center)
                                    .italic()
                                Text(currentVerse.ref)
                                    .font(AMENFont.bold(15))
                                    .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88))
                            }
                            .padding(28)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color(red: 0.95, green: 0.93, blue: 1.0))
                                    .shadow(color: Color(red: 0.56, green: 0.27, blue: 0.88).opacity(0.12), radius: 16, y: 6)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            // Card front (tap to reveal)
                            VStack(spacing: 12) {
                                Text(currentVerse.theme.uppercased())
                                    .font(.systemScaled(10, weight: .bold))
                                    .kerning(3)
                                    .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88).opacity(0.70))
                                Text(currentVerse.ref)
                                    .font(AMENFont.bold(24))
                                    .foregroundStyle(Color(white: 0.12))
                                    .multilineTextAlignment(.center)
                                Image(systemName: "hand.tap.fill")
                                    .font(.systemScaled(22))
                                    .foregroundStyle(Color(white: 0.65))
                                    .padding(.top, 8)
                                Text("Tap to reveal")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(Color(white: 0.50))
                            }
                            .padding(32)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isRevealed.toggle()
                        }
                    }

                    // Action buttons (only shown when revealed)
                    if isRevealed {
                        HStack(spacing: 12) {
                            // Not yet
                            Button {
                                advanceCard(mastered: false)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.systemScaled(14))
                                    Text("Practice Again")
                                        .font(AMENFont.semiBold(14))
                                }
                                .foregroundStyle(Color(white: 0.35))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                                )
                            }

                            // Mastered
                            Button {
                                advanceCard(mastered: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.systemScaled(14))
                                    Text("Mastered!")
                                        .font(AMENFont.semiBold(14))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(red: 0.20, green: 0.65, blue: 0.35))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Verse list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALL VERSES")
                            .font(.systemScaled(10, weight: .bold))
                            .kerning(2)
                            .foregroundStyle(Color(white: 0.50))
                            .padding(.horizontal, 16)
                        ForEach(Array(MemorizeContent.verses.enumerated()), id: \.offset) { idx, verse in
                            HStack(spacing: 12) {
                                Image(systemName: masteredSet.contains(idx) ? "checkmark.circle.fill" : "circle")
                                    .font(.systemScaled(16))
                                    .foregroundStyle(masteredSet.contains(idx)
                                        ? Color(red: 0.20, green: 0.65, blue: 0.35)
                                        : Color(white: 0.70))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verse.ref)
                                        .font(AMENFont.semiBold(14))
                                        .foregroundStyle(Color(white: 0.12))
                                    Text(verse.theme)
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(Color(white: 0.50))
                                }
                                Spacer()
                                if currentCardIndex % MemorizeContent.verses.count == idx {
                                    Text("current")
                                        .font(.systemScaled(10, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.56, green: 0.27, blue: 0.88))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color(red: 0.56, green: 0.27, blue: 0.88).opacity(0.10)))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    currentCardIndex = idx
                                    isRevealed = false
                                }
                            }
                            if idx < MemorizeContent.verses.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    )
                    .padding(.horizontal, 16)

                    Color.clear.frame(height: 30)
                }
                .padding(.top, 4)
            }
        }
    }

    private func advanceCard(mastered: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if mastered {
            var set = masteredSet
            set.insert(currentCardIndex % MemorizeContent.verses.count)
            masteredRaw = set.map(String.init).joined(separator: ",")
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            // Find next unmastered, or just advance
            let total = MemorizeContent.verses.count
            let next = ((currentCardIndex % total) + 1) % total
            currentCardIndex = next
            isRevealed = false
        }
    }
}
