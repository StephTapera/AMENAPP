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
                        .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: orbAnimation)

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
                        .animation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true), value: orb2Animation)

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
                        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: pulseAnimation)
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
                            totalMessages: premiumManager.FREE_MESSAGES_PER_DAY,
                            onUpgrade: { showProUpgrade = true }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Scrollable content area
                    ScrollViewReader { proxy in
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
                                        .frame(height: 90)
                                        .id("bottomSpacer")
                                }
                            }
                        }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottomSpacer", anchor: .bottom)
                            }
                        }
                        .onChange(of: isInputFocused) { _, focused in
                            if focused {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("bottomSpacer", anchor: .bottom)
                                    }
                                }
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
                                .font(.system(size: 15, weight: .semibold))
                            Text("Back")
                                .font(.custom("OpenSans-SemiBold", size: 15))
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
                                .font(.system(size: 15, weight: .light, design: .serif))
                                .foregroundStyle(Color(white: 0.2))
                        }

                        Text("Berean")
                            .font(.system(size: 17, weight: .semibold, design: .default))
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
                                .font(.system(size: 17))
                                .foregroundStyle(Color(white: 0.35))
                        }

                        Button {
                            HapticManager.impact(style: .light)
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Color(white: 0.35))
                        }
                    }
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showProUpgrade) {
            PremiumUpgradeView()
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
        .sheet(isPresented: $showVoiceInput) {
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
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                selectedTab = tab
                                isInputFocused = false
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))

                            Text(tab.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 13))

                            if tab.requiresPro && !hasProAccess {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
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
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = keyboardFrame.height
            }
        }

        NotificationCenter.default.addObserver(
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
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
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
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let premiumManager = PremiumManager.shared
        guard premiumManager.canSendMessage() else {
            showProUpgrade = true
            messages.append(AIStudyMessage(
                text: "You've reached your daily limit of \(premiumManager.FREE_MESSAGES_PER_DAY) free messages. Upgrade to Pro for unlimited AI conversations.\n\nYour limit resets at midnight.",
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
        premiumManager.incrementMessageCount()

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
                        .font(.system(size: 40, weight: .ultraLight, design: .serif))
                        .foregroundStyle(Color(white: 0.22))
                }

                VStack(spacing: 10) {
                    Text("Ask Berean")
                        .font(.system(size: 34, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.10))
                        .multilineTextAlignment(.center)

                    Text("Scripture-grounded answers\nto your deepest questions.")
                        .font(.custom("OpenSans-Regular", size: 16))
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
                    .font(.custom("OpenSans-SemiBold", size: 12))
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
                                    .font(.custom("OpenSans-Regular", size: 14))
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
                            .font(.system(size: 16, weight: .light, design: .serif))
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
                        .font(.system(size: 15, weight: .light, design: .serif))
                        .foregroundStyle(Color(white: 0.25))
                }
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 0) {
                Text(message.text)
                    .font(.custom("OpenSans-Regular", size: 15))
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
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72).delay(0.05)) {
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
                            .font(.system(size: 16, weight: .semibold))
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
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(Color(white: 0.55))
                                .padding(.leading, 2)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $userInput, axis: .vertical)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(Color(white: 0.10))
                            .padding(.leading, 2)
                            .lineLimit(1...4)
                            .focused($isInputFocused)
                            .submitLabel(.send)
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
                            .font(.system(size: 16, weight: .bold))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.25))

            Text("\(messagesRemaining) of \(totalMessages) free messages remaining today")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(Color(white: 0.35))

            Spacer()

            Button(action: onUpgrade) {
                Text("Upgrade")
                    .font(.custom("OpenSans-SemiBold", size: 12))
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                            .font(.system(size: 20))
                            .foregroundStyle(insight.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(Color(white: 0.12))

                        Text(insight.verse)
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                }

                if isExpanded {
                    Divider()

                    Text(insight.content)
                        .font(.custom("OpenSans-Regular", size: 14))
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
                .font(.custom("OpenSans-Bold", size: 20))
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
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.30, green: 0.60, blue: 0.95))

                Text(question)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(Color(white: 0.15))
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
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

// MARK: - Other Tab Content (stub views preserved)

struct DevotionalContent: View {
    @Binding var savedMessages: [AIStudyMessage]
    var body: some View {
        VStack(spacing: 20) {
            Text("Daily Devotional")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(Color(white: 0.12))
            Text("Pro feature — upgrade to unlock personalized devotionals")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(Color(white: 0.50))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct StudyPlansContent: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Study Plans")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(Color(white: 0.12))
            Text("Pro feature — upgrade to unlock custom study plans")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(Color(white: 0.50))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct AnalysisContent: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Biblical Analysis")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(Color(white: 0.12))
            Text("Pro feature — upgrade to unlock deep analysis tools")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(Color(white: 0.50))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct MemorizeContent: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Memory Verse")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(Color(white: 0.12))
            Text("Pro feature — upgrade to unlock memory verse tools")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(Color(white: 0.50))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
