//
//  BereanAIAssistantView.swift
//  AMENAPP
//
//  Created by Steph on 1/16/26.
//

import SwiftUI
import Combine

/// Berean AI Assistant - Your intelligent Bible study companion
struct BereanAIAssistantView: View {
    /// Optional initial query — when set, sent automatically on appear (e.g. from testimony sparkle button)
    var initialQuery: String? = nil
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BereanViewModel()
    @State private var messageText = ""
    @State private var showSuggestions = true
    @State private var isThinking = false
    @FocusState private var isInputFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var showSmartFeatures = false
    @State private var keyboardHeight: CGFloat = 0
    // Stored tokens for closure-based NotificationCenter observers.
    // removeObserver(self, name:) is a no-op for closure-based observers;
    // the token returned by addObserver(forName:object:queue:using:) must be passed instead.
    @State private var keyboardShowObserver: NSObjectProtocol?
    @State private var keyboardHideObserver: NSObjectProtocol?
    @State private var isVoiceListening = false
    @State private var showContextMenu = false
    @State private var showShareSheet = false
    @State private var messageToShare: BereanMessage?
    @State private var showPremiumUpgrade = false
    @State private var isGenerating = false  // ✅ Track if AI is generating
    @State private var siriAnimationProgress: Double = 0  // ✅ Siri-like looping animation
    
    // ✅ New state variables for enhancements
    @State private var showTranslationPicker = false
    @State private var showHistoryView = false
    @State private var showClearAllAlert = false
    @State private var showNewConversationAlert = false
    
    // ✅ P0: Production readiness state
    @State private var lastSentMessageText = ""  // For duplicate prevention
    @State private var lastSentTime: Date?  // For debouncing
    @State private var lastFailedMessageText = ""  // For retry preservation
    @State private var retryAttempts = 0  // For exponential backoff
    @State private var userHasScrolledUp = false  // For smart scrolling
    @State private var isLoadingHistory = false  // For loading states
    private let sendDebounceInterval: TimeInterval = 0.5  // 500ms debounce
    private let maxRetryAttempts = 3
    
    // ✅ Performance monitoring
    @State private var performanceMetrics = PerformanceMetrics()
    
    struct PerformanceMetrics {
        var messageCount = 0
        var totalResponseTime: TimeInterval = 0
        var averageResponseTime: TimeInterval { messageCount > 0 ? totalResponseTime / Double(messageCount) : 0 }
        var fastestResponse: TimeInterval = .infinity
        var slowestResponse: TimeInterval = 0
        var lastRequestStartTime: Date?
    }
    
    // ✅ New state variables for new features
    @State private var showOnboarding = false
    @State private var showSavedMessages = false
    @State private var showReportIssue = false
    @State private var messageToReport: BereanMessage?
    @State private var showError: BereanError?
    @State private var showErrorBanner = false
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared
    @ObservedObject private var dataManager = BereanDataManager.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    
    // Advanced AI features
    @State private var showDevotionalGenerator = false
    @State private var showStudyPlanner = false
    @State private var showScriptureAnalyzer = false
    
    // Selah reading view
    @State private var selahMessage: BereanMessage?
    @State private var showSelahView = false
    @State private var selahQuery = ""

    // ✅ Plus button menu
    @State private var showPlusMenu = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    
    // ✅ Voice input
    @State private var speechRecognizer: SpeechRecognitionService?
    
    // ✅ Verse details
    @State private var showVerseDetail = false
    @State private var selectedVerse: String?
    
    // ✅ Response mode for cost-effective AI
    @State private var responseMode: BereanResponseMode = .balanced

    // ✅ Personality mode — controls Berean's voice/tone via system prompt prefix
    @State private var personalityMode: BereanPersonalityMode = .shepherd

    // ✅ Memory status banner
    @State private var showClearSessionConfirm = false
    
    // ✅ Debounce for contextual suggestions (avoids firing on every keystroke)
    @State private var suggestionDebounceTask: Task<Void, Never>?
    // Tasks used for delayed onAppear effects so they can be cancelled on disappear.
    @State private var initialQueryTask: Task<Void, Never>?
    @State private var longPressHintTask: Task<Void, Never>?
    
    // ✅ Long press quick actions
    @State private var showQuickActions = false
    @State private var quickActionButtonScale: CGFloat = 1.0
    @State private var showFirstTimeLongPressHint = false
    @AppStorage("hasSeenBereanLongPressHint") private var hasSeenLongPressHint = false
    
    // Welcome section animations
    @State private var bibleIconScale: CGFloat = 0.5
    @State private var bibleIconRotation: Double = 0
    @State private var bibleIconOpacity: Double = 0
    @State private var currentWelcomeTextIndex = 0
    @State private var scrollViewOffset: CGFloat = 0
    private let welcomeTexts = [
        "Your intelligent Bible study companion",
        "Ask me anything about Scripture",
        "Deep insights from God's Word",
        "Explore the Bible with AI assistance"
    ]
    
    // ✅ Smart contextual suggestions
    @State private var showContextualSuggestions = false
    @State private var contextualSuggestions: [String] = []
    @State private var isTyping = false
    
    private var shouldCollapseBibleIcon: Bool {
        scrollViewOffset > 100
    }
    
    private func startWelcomeTextRotation() {
        // ✅ Change welcome text only on view appear (not continuously)
        // Pick a random index each time the view appears
        let randomIndex = Int.random(in: 0..<welcomeTexts.count)
        withAnimation(.easeInOut(duration: 0.5)) {
            currentWelcomeTextIndex = randomIndex
        }
    }
    
    // ✅ Generate smart contextual suggestions based on user input
    private func generateContextualSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmed.isEmpty else {
            contextualSuggestions = []
            showContextualSuggestions = false
            return
        }
        
        var suggestions: [String] = []
        
        // Smart keyword-based suggestions
        if trimmed.contains("jesus") || trimmed.contains("christ") {
            suggestions = [
                "What did Jesus teach about love?",
                "Explain Jesus's parables in simple terms",
                "Show me Jesus's miracles and their significance"
            ]
        } else if trimmed.contains("prayer") || trimmed.contains("pray") {
            suggestions = [
                "How should I pray according to the Bible?",
                "What does the Lord's Prayer mean?",
                "Show me verses about prayer and fasting"
            ]
        } else if trimmed.contains("love") {
            suggestions = [
                "What does the Bible say about love?",
                "Explain 1 Corinthians 13 in depth",
                "How can I show love to others?"
            ]
        } else if trimmed.contains("faith") {
            suggestions = [
                "What is faith according to Hebrews 11?",
                "How do I strengthen my faith?",
                "Show me examples of faith in the Bible"
            ]
        } else if trimmed.contains("grace") {
            suggestions = [
                "What is grace in Christian theology?",
                "Explain salvation by grace through faith",
                "Show me verses about God's grace"
            ]
        } else if trimmed.contains("sin") {
            suggestions = [
                "What does the Bible say about forgiveness?",
                "How do I overcome sin in my life?",
                "Explain the concept of redemption"
            ]
        } else if trimmed.contains("psalm") {
            suggestions = [
                "Explain Psalm 23 verse by verse",
                "Show me Psalms about comfort",
                "What are the different types of Psalms?"
            ]
        } else if trimmed.contains("john") && trimmed.count < 15 {
            suggestions = [
                "Explain the Gospel of John's purpose",
                "What makes John's Gospel unique?",
                "Show me key verses from John"
            ]
        } else if trimmed.contains("genesis") || trimmed.contains("creation") {
            suggestions = [
                "Explain the creation account in Genesis",
                "What does Genesis teach about humanity?",
                "Show me Genesis 1 with historical context"
            ]
        } else {
            // Generic helpful suggestions based on input length
            if trimmed.count < 5 {
                suggestions = [
                    "Help me understand this passage better",
                    "What's the historical context?",
                    "Show me related verses"
                ]
            } else {
                suggestions = [
                    "Explain this in simple terms",
                    "What's the theological significance?",
                    "Show me cross-references"
                ]
            }
        }
        
        withAnimation(.easeOut(duration: 0.2)) {
            contextualSuggestions = Array(suggestions.prefix(3))
            showContextualSuggestions = !suggestions.isEmpty
        }
    }
    
    var body: some View {
        ZStack {
            // Clean gray background (Next.js style)
            Color(red: 0.96, green: 0.96, blue: 0.96)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Offline banner
                OfflineModeBanner(isOnline: $networkMonitor.isConnected)
                
                // Error banner
                if showErrorBanner, let error = showError {
                    BereanErrorBanner(
                        error: error,
                        onRetry: {
                            retryLastMessage()
                        },
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showErrorBanner = false
                            }
                        }
                    )
                    .zIndex(100)
                }
                
                // Header
                headerView
                
                // Chat Content
                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { geometry in
                            // Track scroll position for smart scrolling
                            let offset = geometry.frame(in: .named("scroll")).minY
                            Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: offset)
                                .onAppear {
                                    scrollViewOffset = offset
                                }
                                .onChange(of: offset) { _, newValue in
                                    scrollViewOffset = abs(newValue)
                                }
                        }
                        .frame(height: 0)
                        
                        VStack(spacing: 20) {
                            // Welcome Section
                            if viewModel.messages.isEmpty {
                                welcomeSection
                                
                                // Quick Actions
                                quickActionsSection
                                
                                // Suggested Prompts
                                if showSuggestions {
                                    suggestedPromptsSection
                                }
                            } else {
                                // Messages
                                ForEach(viewModel.messages) { message in
                                    MessageBubbleView(
                                        message: message,
                                        onOpenSelah: { msg in
                                            selahQuery = viewModel.messages
                                                .last(where: { $0.isFromUser })?.content ?? ""
                                            selahMessage = msg
                                            showSelahView = true
                                        }
                                    )
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                        .animation(.easeOut(duration: 0.2), value: viewModel.messages.count)
                                }
                                .environment(\.messageShareHandler) { message in
                                    messageToShare = message
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showShareSheet = true
                                    }
                                }
                                .environmentObject(dataManager)
                                
                                // Thinking Indicator
                                if isThinking {
                                    ThinkingIndicatorView()
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .padding(.bottom, 120) // ✅ Increased space for input bar + contextual suggestions
                    }
                    .refreshable {
                        await refreshConversation()
                    }
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        // ✅ P1-1: Smart scroll - only auto-scroll if user hasn't scrolled up
                        if !userHasScrolledUp, let lastMessage = viewModel.messages.last {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        // Detect if user has scrolled up manually
                        if value < -50 {  // User scrolled up more than 50 points
                            userHasScrolledUp = true
                        } else if value > -10 {  // User is near bottom
                            userHasScrolledUp = false
                        }
                    }
                    .coordinateSpace(name: "scroll")
                    .onChange(of: isInputFocused) { _, newValue in
                        // Scroll to bottom when keyboard appears
                        if newValue, let lastMessage = viewModel.messages.last {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                // Input Bar - Always at bottom
                inputBarView

                // AI Transparency Disclosure — required so users know they are interacting
                // with an AI assistant. Must remain visible and non-dismissible.
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Berean is an AI assistant. Responses may contain errors — verify with Scripture.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            
            // Smart Features Overlay
            if showSmartFeatures {
                SmartFeaturesPanel(isShowing: $showSmartFeatures, onFeatureSelect: { feature in
                    handleSmartFeature(feature)
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(10)
            }
            
            // Share to Feed Sheet
            if showShareSheet, let message = messageToShare {
                ShareToFeedSheet(
                    message: message,
                    isShowing: $showShareSheet,
                    onShare: { shareText in
                        // Post to OpenTable feed
                        shareToOpenTableFeed(text: shareText, originalMessage: message)
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(11)
            }
            
            // Premium Upgrade Modal handled by .sheet modifier below
        }
        .navigationBarHidden(true)
        // ✅ Translation Picker Sheet
        .sheet(isPresented: $showTranslationPicker) {
            BibleTranslationPicker(
                selectedTranslation: $viewModel.selectedTranslation,
                isShowing: $showTranslationPicker
            )
        }
        // ✅ Conversation History Sheet
        .sheet(isPresented: $showHistoryView) {
            BereanConversationManagementView(
                conversations: $viewModel.savedConversations,
                isLoading: $isLoadingHistory,  // ✅ P1-2: Loading state
                onSelect: { conversation in
                    isLoadingHistory = true
                    viewModel.loadConversation(conversation)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLoadingHistory = false
                        showHistoryView = false
                    }
                },
                onDelete: { conversation in
                    viewModel.deleteConversation(conversation)
                },
                onUpdate: { conversation, newTitle in
                    viewModel.updateConversationTitle(conversation, newTitle: newTitle)
                }
            )
        }
        // ✅ New Conversation Alert
        .alert("Start New Conversation?", isPresented: $showNewConversationAlert) {
            Button("Cancel", role: .cancel) { }
            Button("New Conversation") {
                startNewConversation()
            }
        } message: {
            Text("Current conversation will be saved to history.")
        }
        // ✅ Clear All Data Alert
        .alert("Clear All Data?", isPresented: $showClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all conversations and data. This action cannot be undone.")
        }
        // ✅ Onboarding
        .fullScreenCover(isPresented: $showOnboarding) {
            BereanOnboardingView(isPresented: $showOnboarding)
        }
        // Selah reading view
        .fullScreenCover(item: $selahMessage) { msg in
            SelahView(
                message: msg,
                originalQuery: selahQuery,
                onContinueInChat: nil,
                onAskFollowUp: { followUp in
                    messageText = followUp
                }
            )
        }
        // ✅ Saved Messages
        .sheet(isPresented: $showSavedMessages) {
            BereanSavedMessagesView()
        }
        // ✅ Report Issue
        .sheet(isPresented: $showReportIssue) {
            if let message = messageToReport {
                BereanReportIssueView(message: message, isPresented: $showReportIssue)
            }
        }
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
        }
        // ✅ Advanced AI Features
        .sheet(isPresented: $showDevotionalGenerator) {
            DevotionalGeneratorView()
        }
        .sheet(isPresented: $showStudyPlanner) {
            StudyPlanGeneratorView()
        }
        .sheet(isPresented: $showScriptureAnalyzer) {
            ScriptureAnalyzerView()
        }
        // ✅ Plus Menu
        .overlay {
            if showPlusMenu {
                BereanPlusMenu(
                    isShowing: $showPlusMenu,
                    onImageUpload: {
                        showImagePicker = true
                    },
                    onBibleSearch: {
                        messageText = "Search for "
                        isInputFocused = true
                    },
                    onSmartFeatures: {
                        showSmartFeatures = true
                    },
                    onSavedPrompts: {
                        // Show saved prompts
                        print("Saved prompts tapped")
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1000)
            }
        }
        // ✅ Image Picker
        .sheet(isPresented: $showImagePicker) {
            BereanImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                handleImageUpload(image)
            }
        }
        // ✅ Verse Detail
        .sheet(isPresented: $showVerseDetail) {
            if let verse = selectedVerse {
                VerseDetailView(verseReference: verse)
            }
        }
        .onAppear {
            checkOnboardingStatus()
            setupKeyboardObservers()
            // Initialize speech recognizer
            speechRecognizer = SpeechRecognitionService()
            
            // Auto-send initial query (e.g. testimony reflection from PostCard).
            // Use a stored Task so it can be cancelled in onDisappear, preventing
            // a use-after-free if the view is dismissed before the delay fires.
            if let query = initialQuery, !query.isEmpty {
                initialQueryTask?.cancel()
                initialQueryTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 s
                    guard !Task.isCancelled else { return }
                    sendMessage(query)
                }
            }

            // Show long press hint for first-time users.
            if !hasSeenLongPressHint {
                longPressHintTask?.cancel()
                longPressHintTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2.0 s
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showFirstTimeLongPressHint = true
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5.0 s
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        showFirstTimeLongPressHint = false
                    }
                }
            }
        }
        .onDisappear {
            removeKeyboardObservers()
            // ✅ P0-3: Cancel any ongoing generation when view disappears
            viewModel.stopGeneration()
            // Cancel suggestion debounce task
            suggestionDebounceTask?.cancel()
            suggestionDebounceTask = nil
            // Cancel delayed onAppear tasks so they don't fire after view is gone
            initialQueryTask?.cancel()
            initialQueryTask = nil
            longPressHintTask?.cancel()
            longPressHintTask = nil
            // Auto-save conversation if there are messages
            if !viewModel.messages.isEmpty {
                viewModel.saveCurrentConversation()
            }
        }
    }
    
    // MARK: - Share to OpenTable Feed
    
    private func shareToOpenTableFeed(text: String, originalMessage: BereanMessage) {
        Task {
            do {
                // Check network first
                guard networkMonitor.isConnected else {
                    throw BereanError.networkUnavailable
                }

                // Safety gate: run ThinkFirst guardrails before posting to OpenTable.
                // Berean responses are scripture-grounded but may contain user-added personal
                // notes that could violate community guidelines.
                let safetyResult = await ThinkFirstGuardrailsService.shared.checkContent(
                    text, context: .normalPost
                )
                switch safetyResult.action {
                case .block:
                    let reason = safetyResult.violations.first?.message
                        ?? "This content can't be shared to OpenTable."
                    await MainActor.run {
                        showError = .unknown(reason)
                        showErrorBanner = true
                    }
                    return
                case .requireEdit:
                    let reason = safetyResult.violations.first?.message
                        ?? "Please review your personal note before sharing."
                    await MainActor.run {
                        showError = .unknown(reason)
                        showErrorBanner = true
                    }
                    return
                case .allow, .softPrompt:
                    break  // proceed
                }
                
                // Extract personal note if present
                var personalNote: String? = nil
                if text.contains("---") {
                    let components = text.components(separatedBy: "---")
                    if components.count > 1 {
                        personalNote = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                // Share to feed
                try await dataManager.shareToFeed(
                    message: originalMessage,
                    personalNote: personalNote,
                    communityId: nil // Or get from current context
                )
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showShareSheet = false
                        messageToShare = nil
                    }
                }
            } catch let error as BereanError {
                print("❌ Berean error sharing to feed: \(error.localizedDescription)")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
                
                await MainActor.run {
                    showError = error
                    showErrorBanner = true
                }
            } catch {
                print("❌ Failed to share to feed: \(error.localizedDescription)")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
                
                await MainActor.run {
                    showError = .unknown("Failed to share to feed. Please try again.")
                    showErrorBanner = true
                }
            }
        }
    }
    
    // MARK: - Smart Feature Handler
    
    private func handleSmartFeature(_ feature: SmartFeature) {
        withAnimation(.easeOut(duration: 0.2)) {
            showSmartFeatures = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch feature {
            case .crossReference:
                messageText = "Show me cross-references for "
                isInputFocused = true
            case .greekHebrew:
                messageText = "What's the Greek/Hebrew meaning of "
                isInputFocused = true
            case .historicalTimeline:
                sendMessage("Show me a historical timeline of Biblical events")
            case .characterStudy:
                messageText = "Tell me about the character "
                isInputFocused = true
            case .theologicalThemes:
                sendMessage("Explain theological themes in Scripture")
            case .verseOfDay:
                sendMessage("Give me an encouraging verse for today")
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Close button - hides when scrolled
                if !shouldCollapseBibleIcon || !viewModel.messages.isEmpty {
                    closeButton
                        .transition(.opacity.combined(with: .scale))
                }
                
                Spacer()
                
                // ✅ Next.js-style "By AMEN" badge
                if !shouldCollapseBibleIcon || !viewModel.messages.isEmpty {
                    Text("By AMEN")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.6))
                        .transition(.opacity)
                }
                
                settingsMenuButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(red: 0.96, green: 0.96, blue: 0.96))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shouldCollapseBibleIcon)
        }
    }
    
    private var closeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black.opacity(0.6))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )
        }
    }
    
    private var bereanBranding: some View {
        HStack(spacing: 12) {
            // Minimal elegant icon
            ZStack {
                // Soft glow when thinking
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.7, blue: 0.5).opacity(isThinking ? 0.3 : 0.15),
                                Color(red: 0.6, green: 0.5, blue: 0.9).opacity(isThinking ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .scaleEffect(isThinking ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isThinking)
                
                // Sparkle icon
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.3, blue: 0.35),
                                Color(red: 0.25, green: 0.25, blue: 0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating, value: isThinking)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Berean")
                    .font(.custom("Georgia", size: 22))
                    .fontWeight(.light)
                    .foregroundStyle(Color(white: 0.2))
                    .tracking(0.5)
                
                Text(isThinking ? "Thinking..." : "AI Bible Study")
                    .font(.custom("SF Pro Display", size: 10))
                    .fontWeight(.regular)
                    .foregroundStyle(Color(white: 0.5))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
        }
    }
    
    private var smartFeaturesButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            withAnimation(.easeOut(duration: 0.25)) {
                showSmartFeatures.toggle()
            }
        } label: {
            Image(systemName: showSmartFeatures ? "star.circle.fill" : "star.circle")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(
                    showSmartFeatures ?
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.6, blue: 0.4), Color(red: 0.6, green: 0.5, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color(white: 0.4), Color(white: 0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
                .frame(width: 32, height: 32)
                .symbolEffect(.bounce, value: showSmartFeatures)
        }
    }
    
    private var premiumBadgeButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            withAnimation(.easeOut(duration: 0.25)) {
                showPremiumUpgrade = true
            }
        } label: {
            HStack(spacing: 4) {
                if premiumManager.hasProAccess {
                    // Pro badge for premium users
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("Pro")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                } else {
                    // Usage indicator for free tier
                    Image(systemName: premiumManager.freeMessagesRemaining > 3 ? "sparkles" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text("\(premiumManager.freeMessagesRemaining)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(
                premiumManager.hasProAccess ?
                    // Gold gradient for Pro
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.75, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    // Subtle warning colors for free tier
                    LinearGradient(
                        colors: premiumManager.freeMessagesRemaining > 3 ? 
                            [Color(white: 0.4), Color(white: 0.35)] : 
                            [Color.orange, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(premiumManager.hasProAccess ? 0.7 : 0.6))
                    .shadow(color: premiumManager.hasProAccess ? Color(red: 1.0, green: 0.6, blue: 0.3).opacity(0.2) : Color.black.opacity(0.05), radius: 8, y: 2)
            )
        }
    }
    
    private var settingsMenuButton: some View {
        Menu {
            // ✅ Bible Translation Picker
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                showTranslationPicker = true
            } label: {
                Label("Bible Translation: \(viewModel.selectedTranslation)", systemImage: "book.fill")
            }
            
            // ✅ Saved Messages
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                showSavedMessages = true
            } label: {
                Label("Saved Messages (\(dataManager.savedMessages.count))", systemImage: "bookmark.fill")
            }
            
            // ✅ Conversation History
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                showHistoryView = true
            } label: {
                Label("Conversation History", systemImage: "clock.fill")
            }
            
            Divider()
            
            // ✅ New Conversation
            Button {
                showNewConversationAlert = true
            } label: {
                Label("New Conversation", systemImage: "plus.circle")
            }
            
            Divider()
            
            // ✅ Advanced AI Features (Premium)
            Button {
                if premiumManager.hasProAccess {
                    showDevotionalGenerator = true
                } else {
                    showPremiumUpgrade = true
                }
            } label: {
                HStack {
                    Label("Daily Devotional", systemImage: "book.pages.fill")
                    if !premiumManager.hasProAccess {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Button {
                if premiumManager.hasProAccess {
                    showStudyPlanner = true
                } else {
                    showPremiumUpgrade = true
                }
            } label: {
                HStack {
                    Label("Study Plan Generator", systemImage: "calendar.badge.plus")
                    if !premiumManager.hasProAccess {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Button {
                if premiumManager.hasProAccess {
                    showScriptureAnalyzer = true
                } else {
                    showPremiumUpgrade = true
                }
            } label: {
                HStack {
                    Label("Scripture Analyzer", systemImage: "text.magnifyingglass")
                    if !premiumManager.hasProAccess {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Divider()
            
            // ✅ Show Onboarding
            Button {
                showOnboarding = true
            } label: {
                Label("View Tutorial", systemImage: "questionmark.circle")
            }
            
            // ✅ Clear All Data (Destructive)
            Button(role: .destructive) {
                showClearAllAlert = true
            } label: {
                Label("Clear All Data", systemImage: "trash")
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    )
                    .scaleEffect(quickActionButtonScale)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: quickActionButtonScale)
                
                // First-time hint badge
                if showFirstTimeLongPressHint {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.6, blue: 0.4), Color(red: 0.6, green: 0.5, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 8, height: 8)
                        .offset(x: -4, y: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onChanged { _ in
                    // Immediate haptic feedback
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        quickActionButtonScale = 0.85
                    }
                }
                .onEnded { _ in
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        quickActionButtonScale = 1.0
                        showQuickActions = true
                        showFirstTimeLongPressHint = false
                    }
                    
                    // Mark hint as seen
                    if !hasSeenLongPressHint {
                        hasSeenLongPressHint = true
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            if showQuickActions {
                BereanQuickActionsMenu(
                    isShowing: $showQuickActions,
                    onNewConversation: {
                        showQuickActions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showNewConversationAlert = true
                        }
                    },
                    onSavedMessages: {
                        showQuickActions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showSavedMessages = true
                        }
                    },
                    onHistory: {
                        showQuickActions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showHistoryView = true
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity)
                ))
                .zIndex(1000)
            }
        }
    }
    
    private var headerBackground: some View {
        ZStack {
            Color.white.opacity(0.4)
                .background(.ultraThinMaterial)
            
            // Subtle bottom border
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 0.5)
            }
        }
    }
    
    // MARK: - Welcome Section
    
    private var welcomeSection: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: shouldCollapseBibleIcon ? 20 : 60)
            
            // Animated Bible icon - collapses on scroll
            if !shouldCollapseBibleIcon {
                ZStack {
                    // Pulsing glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.black.opacity(0.08),
                                    Color.black.opacity(0.02),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(bibleIconScale)
                    
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.black)
                        .rotationEffect(.degrees(bibleIconRotation))
                }
                .opacity(bibleIconOpacity)
                .scaleEffect(bibleIconScale)
                .onAppear {
                    // Subtle entrance animation
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                        bibleIconOpacity = 1.0
                        bibleIconScale = 1.0
                    }
                    
                    // Continuous breathing animation
                    withAnimation(
                        .easeInOut(duration: 3.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        bibleIconRotation = 2
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Title
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    Text("BEREAN")
                        .font(.system(size: shouldCollapseBibleIcon ? 32 : 52, weight: .bold, design: .default))
                        .foregroundStyle(.black)
                    
                    Text("AI")
                        .font(.system(size: shouldCollapseBibleIcon ? 18 : 28, weight: .light, design: .rounded))
                        .foregroundStyle(.black.opacity(0.6))
                        .padding(.leading, 4)
                }
                .tracking(-1.5)
                
                if !shouldCollapseBibleIcon {
                    // "How can I help you today?" - ChatGPT style
                    VStack(spacing: 8) {
                        Text("How can I help you today?")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.black.opacity(0.8))
                            .multilineTextAlignment(.center)
                        
                        // Rotating welcome texts (secondary)
                        Text(welcomeTexts[currentWelcomeTextIndex])
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.black.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                            .id(currentWelcomeTextIndex)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldCollapseBibleIcon)
        }
        .onAppear {
            startWelcomeTextRotation()
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            // Top left - Soft blue grainy gradient (inspired by modern design)
            SquareActionCard(
                icon: "book.closed.fill",
                title: "Study Passage",
                gradient: LinearGradient(
                    colors: [
                        Color(red: 0.68, green: 0.85, blue: 0.90),  // Soft blue
                        Color(red: 0.80, green: 0.90, blue: 0.92),  // Light blue
                        Color(red: 0.88, green: 0.93, blue: 0.95)   // Very light blue
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                textColor: Color.white
            ) {
                messageText = "Help me study "
                isInputFocused = true
            }
            
            // Top right - Orange gradient
            SquareActionCard(
                icon: "lightbulb.fill",
                title: "Explain Verse",
                gradient: LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.5, blue: 0.4).opacity(0.15),
                        Color(red: 1.0, green: 0.6, blue: 0.5).opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                textColor: Color(red: 1.0, green: 0.5, blue: 0.4)
            ) {
                messageText = "Explain "
                isInputFocused = true
            }
            
            // Bottom left - Peach gradient
            SquareActionCard(
                icon: "doc.text.fill",
                title: "Compare Translations",
                gradient: LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.7, blue: 0.6).opacity(0.15),
                        Color(red: 1.0, green: 0.8, blue: 0.7).opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                textColor: Color(red: 0.95, green: 0.6, blue: 0.5)
            ) {
                sendMessage("Compare Bible translations for a verse")
            }
            
            // Bottom right - Purple gradient
            SquareActionCard(
                icon: "map.fill",
                title: "Historical Context",
                gradient: LinearGradient(
                    colors: [
                        Color(red: 0.6, green: 0.5, blue: 0.8).opacity(0.15),
                        Color(red: 0.7, green: 0.6, blue: 0.9).opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                textColor: Color(red: 0.6, green: 0.5, blue: 0.8)
            ) {
                sendMessage("Tell me about Biblical context")
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
    }
    
    // MARK: - Suggested Prompts
    
    private var suggestedPromptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .textCase(.uppercase)
                .tracking(2)
                .padding(.horizontal, 20)
            
            VStack(spacing: 8) {
                ForEach(viewModel.suggestedPrompts, id: \.self) { prompt in
                    SuggestedPromptCard(prompt: prompt) {
                        sendMessage(prompt)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
    }
    
    // MARK: - Input Bar (Glassmorphic - Bottom Fixed)

    // MARK: Memory Status Banner

    /// Pill displayed above the input bar when there are messages in session memory.
    /// Lets the user see retention status and clear the session with one tap.
    private var memoryStatusBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))

            Text("\(viewModel.messages.count) message\(viewModel.messages.count == 1 ? "" : "s") in session")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.3))

            Spacer()

            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                showClearSessionConfirm = true
            } label: {
                Text("Clear")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.1))
                    )
            }
            .accessibilityLabel("Clear session memory")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .confirmationDialog(
            "Clear Session Memory?",
            isPresented: $showClearSessionConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Session", role: .destructive) {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.clearMessages()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Berean will forget this conversation. Saved conversations are not affected.")
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }

    // MARK: Personality Mode Selector

    /// Horizontally scrollable chip row to switch Berean's persona/voice.
    /// Visible only when the input is empty (no clutter mid-conversation).
    private var personalityModeSelectorView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BereanPersonalityMode.allCases) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            personalityMode = mode
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10, weight: .medium))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(personalityMode == mode ? .white : Color(white: 0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(personalityMode == mode
                                    ? Color(red: 0.2, green: 0.5, blue: 0.9)
                                    : Color.white.opacity(0.6))
                        )
                    }
                    .accessibilityLabel("\(mode.rawValue) mode: \(mode.description)")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }

    private var inputBarView: some View {
        VStack(spacing: 0) {
            // Memory status banner — shown when there are messages and input is empty
            if !viewModel.messages.isEmpty && messageText.isEmpty {
                memoryStatusBanner
            }

            // Personality mode selector — shown when input is empty (welcome state or mid-session)
            if messageText.isEmpty && !isGenerating {
                personalityModeSelectorView
            }

            // ✅ Smart Contextual Suggestions (ChatGPT-style)
            if showContextualSuggestions && !contextualSuggestions.isEmpty && viewModel.messages.isEmpty {
                contextualSuggestionsView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // ✅ Response Mode Picker (collapsed by default)
            if viewModel.messages.isEmpty || isGenerating {
                responseModePickerView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Compact glassmorphic pill - smaller and closer to bottom
            HStack(alignment: .center, spacing: 12) {
                // Plus button (left side) - BLACK - Smaller
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    handlePlusButtonTap()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.4 : 1.0)
                .accessibilityLabel("Add attachment")

                // Text input field - WHITE TEXT
                textInputFieldGlassmorphic

                // Voice/Send button (right side) - DARK PILL - Smaller
                actionButtonGlassmorphic
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(largeGlassmorphicBackground)
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
    }
    
    private func getSafeAreaBottom() -> CGFloat {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }
    
    // ✅ Response Mode Picker View
    private var responseModePickerView: some View {
        HStack(spacing: 8) {
            ForEach(BereanResponseMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        responseMode = mode
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(responseMode == mode ? .white : .black.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(responseMode == mode ? mode.color : Color.white.opacity(0.5))
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
    
    private var textInputFieldGlassmorphic: some View {
        HStack(spacing: 8) {
            TextField("Ask me anything about the Bible...", text: $messageText, axis: .vertical)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.black)
                .lineLimit(1...1)
                .focused($isInputFocused)
                .disabled(isGenerating)
                .tint(.black)
                .onSubmit {
                    if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage(messageText)
                    }
                }
                .submitLabel(.send)
                .accessibilityLabel("Message input field")
                .onChange(of: messageText) { _, newValue in
                    // ✅ Update typing indicator immediately
                    isTyping = !newValue.isEmpty
                    // ✅ Debounce suggestions — don't fire on every keystroke
                    suggestionDebounceTask?.cancel()
                    suggestionDebounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
                        guard !Task.isCancelled else { return }
                        generateContextualSuggestions(for: newValue)
                    }
                }
            
            // ✅ Smart typing indicator (subtle)
            if isTyping && showContextualSuggestions {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // ✅ Contextual Suggestions View (ChatGPT-style smart questions)
    private var contextualSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(contextualSuggestions, id: \.self) { suggestion in
                Button {
                    messageText = suggestion
                    isInputFocused = true
                    // Hide suggestions after selection
                    withAnimation(.easeOut(duration: 0.2)) {
                        showContextualSuggestions = false
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.black.opacity(0.5))
                        
                        Text(suggestion)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.black.opacity(0.8))
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var actionButtonGlassmorphic: some View {
        if isGenerating {
            stopButtonGlassmorphic
        } else if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendButtonGlassmorphic
        } else {
            voiceButtonGlassmorphic
        }
    }
    
    private var voiceButtonGlassmorphic: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            handleVoiceButtonTap()
        } label: {
            ZStack {
                // Dark pill background - Smaller
                Capsule()
                    .fill(Color.black.opacity(isVoiceListening ? 0.8 : 0.7))
                    .frame(width: 80, height: 40)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )

                // Pulsing animation when listening
                if isVoiceListening {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(width: 80, height: 40)
                        .scaleEffect(isVoiceListening ? 1.15 : 1.0)
                        .opacity(isVoiceListening ? 0 : 1)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: isVoiceListening)
                }

                // Waveform icon - Smaller
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor, options: .repeating, isActive: isVoiceListening)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(isVoiceListening ? "Stop voice input" : "Start voice input")
    }
    
    private var sendButtonGlassmorphic: some View {
        Button {
            guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()

            sendMessage(messageText)
        } label: {
            ZStack {
                // Dark pill background - Smaller
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )

                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .transition(.scale.combined(with: .opacity))
        .animation(.easeOut(duration: 0.15), value: !messageText.isEmpty)
        .accessibilityLabel("Send message")
    }
    
    private var stopButtonGlassmorphic: some View {
        Button {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)

            stopGeneration()
        } label: {
            ZStack {
                // Dark red pill background - Smaller
                Capsule()
                    .fill(.red.opacity(0.25))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Capsule()
                            .stroke(.red.opacity(0.4), lineWidth: 1.5)
                    )

                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .transition(.scale.combined(with: .opacity))
        .animation(.easeOut(duration: 0.15), value: isGenerating)
        .accessibilityLabel("Stop generating")
    }
    
    private var largeGlassmorphicBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.25),
                                .white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Group {
                    // Regular border
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    // ✅ Siri-like looping animation when generating
                    if isGenerating {
                        Capsule()
                            .trim(from: siriAnimationProgress, to: siriAnimationProgress + 0.3)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.8),
                                        Color.purple.opacity(0.6),
                                        Color.pink.opacity(0.5),
                                        Color.clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2.5
                            )
                            .animation(
                                .linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                                value: siriAnimationProgress
                            )
                    }
                }
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            .shadow(color: .white.opacity(0.2), radius: 2, x: 0, y: -1)
            .onChange(of: isGenerating) { oldValue, newValue in
                if newValue {
                    // Start looping animation
                    siriAnimationProgress = 1.0
                } else {
                    // Reset animation
                    siriAnimationProgress = 0
                }
            }
    }
    
    // MARK: - Input Bar Action Handlers
    
    /// Handle plus button tap (add attachments/options)
    private func handlePlusButtonTap() {
        #if DEBUG
        print("➕ Plus button tapped - Show attachment options")
        #endif
        
        // Show quick actions menu
        withAnimation(.easeOut(duration: 0.2)) {
            showPlusMenu = true
        }
    }
    
    /// Handle voice button tap (start/stop voice input)
    private func handleVoiceButtonTap() {
        Task {
            guard let recognizer = speechRecognizer else { return }
            
            if isVoiceListening {
                // Stop recording
                recognizer.stopRecording()
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVoiceListening = false
                    }
                    
                    // Use transcribed text
                    if !recognizer.transcribedText.isEmpty {
                        messageText = recognizer.transcribedText
                    }
                }
            } else {
                // Request authorization
                let authorized = await recognizer.requestAuthorization()
                
                guard authorized else {
                    await MainActor.run {
                        showError = .unknown("Speech recognition permission denied. Please enable in Settings.")
                        showErrorBanner = true
                    }
                    return
                }
                
                // Start recording
                do {
                    try recognizer.startRecording()
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isVoiceListening = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        showError = .unknown("Failed to start voice input: \(error.localizedDescription)")
                        showErrorBanner = true
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// Check if onboarding should be shown
    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "berean_onboarding_completed")
        
        if !hasCompletedOnboarding {
            // Delay slightly to ensure view is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showOnboarding = true
            }
        }
    }
    
    /// Setup keyboard observers for smooth animations.
    /// Uses token-based addObserver so that the returned tokens can be passed to
    /// removeObserver(_:) on cleanup. Calling setupKeyboardObservers more than once
    /// is safe because existing tokens are removed first.
    private func setupKeyboardObservers() {
        // Always tear down any existing observers before registering new ones to
        // prevent stacking when the view appears multiple times (e.g., modal re-presentation).
        removeKeyboardObservers()

        keyboardShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }

        keyboardHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    /// Remove keyboard observers using the stored tokens.
    /// `removeObserver(self, name:)` is a no-op for closure-based observers;
    /// the token returned by addObserver(forName:object:queue:using:) must be used.
    private func removeKeyboardObservers() {
        if let token = keyboardShowObserver {
            NotificationCenter.default.removeObserver(token)
            keyboardShowObserver = nil
        }
        if let token = keyboardHideObserver {
            NotificationCenter.default.removeObserver(token)
            keyboardHideObserver = nil
        }
    }
    
    /// Retry the last failed message
    private func retryLastMessage() {
        // Check network before retrying
        guard networkMonitor.isConnected else {
            print("❌ Cannot retry - no network connection")
            showError = .networkUnavailable
            showErrorBanner = true
            return
        }
        
        // ✅ P0-4: Use preserved failed message text, or fallback to last user message
        let messageToRetry: String
        if !lastFailedMessageText.isEmpty {
            messageToRetry = lastFailedMessageText
        } else if let lastUserMessage = viewModel.messages.last(where: { $0.role == .user }) {
            messageToRetry = lastUserMessage.content
        } else {
            print("⚠️ No message to retry")
            return
        }
        
        // Clear error banner
        withAnimation(.easeOut(duration: 0.2)) {
            showErrorBanner = false
            showError = nil
        }
        
        // Remove the last assistant message if it exists and was an error
        if let lastAssistantIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }) {
            // Only remove if it's empty or an error placeholder
            let assistantMessage = viewModel.messages[lastAssistantIndex]
            if assistantMessage.content.isEmpty || assistantMessage.content.contains("error") {
                viewModel.messages.remove(at: lastAssistantIndex)
            }
        }
        
        print("🔄 Retrying message: \(messageToRetry.prefix(50))...")
        
        // ✅ Implement exponential backoff for retries
        let backoffDelay = pow(2.0, Double(min(retryAttempts, maxRetryAttempts))) * 0.5
        retryAttempts += 1
        
        if retryAttempts > maxRetryAttempts {
            print("⚠️ Max retry attempts reached, resetting counter")
            retryAttempts = 0
        }
        
        // Delay retry with exponential backoff
        DispatchQueue.main.asyncAfter(deadline: .now() + backoffDelay) {
            self.sendMessage(messageToRetry, isRetry: true)
        }
    }
    
    /// Refresh the current conversation with pull-to-refresh
    @MainActor
    private func refreshConversation() async {
        print("🔄 Refreshing conversation...")
        
        // Add small delay for smooth pull-to-refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Note: Current messages are already live-updated through @Published properties
        // This refresh mainly provides user feedback that the action was acknowledged
        
        // Haptic feedback to indicate refresh completion
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        print("✅ Conversation refreshed")
    }
    
    /// Start a new conversation
    private func startNewConversation() {
        withAnimation(.easeOut(duration: 0.25)) {
            // Save current conversation if it has messages
            if !viewModel.messages.isEmpty {
                viewModel.saveCurrentConversation()
            }
            
            // Clear messages
            viewModel.clearMessages()
            
            // Reset UI state
            showSuggestions = true
            messageText = ""
            isThinking = false
            isGenerating = false
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("✅ New conversation started")
    }
    
    /// Clear all data
    private func clearAllData() {
        withAnimation(.easeOut(duration: 0.25)) {
            viewModel.clearAllData()
            
            // Reset UI state
            showSuggestions = true
            messageText = ""
            isThinking = false
            isGenerating = false
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        
        print("✅ All data cleared successfully")
    }
    
    /// Handle image upload for OCR/analysis
    private func handleImageUpload(_ image: UIImage) {
        // In production: Use Vision API for OCR
        // For now, prompt user to describe the image
        messageText = "I've uploaded an image. "
        isInputFocused = true
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("📸 Image uploaded - ready for analysis")
    }
    
    /// Handle verse reference tap to show full verse
    func handleVerseTap(_ reference: String) {
        selectedVerse = reference
        showVerseDetail = true
    }
    
    /// Stop AI generation
    private func stopGeneration() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) {
                isGenerating = false
                isThinking = false
            }
            
            viewModel.stopGeneration()
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            
            // Dismiss keyboard
            isInputFocused = false
        }
    }
    
    private func sendMessage(_ text: String, isRetry: Bool = false) {
        // Trim whitespace and check if empty
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            print("⚠️ Cannot send empty message")
            return
        }
        
        // ✅ P0-1: Enhanced duplicate protection with request ID
        if !isRetry {
            // Check if this is a duplicate of the last sent message
            if trimmedText == lastSentMessageText {
                print("⚠️ Duplicate message detected, ignoring")
                return
            }
            
            // Check debounce interval
            if let lastTime = lastSentTime, Date().timeIntervalSince(lastTime) < sendDebounceInterval {
                print("⚠️ Message sent too quickly, debouncing")
                return
            }
        }
        
        // ✅ P0-2: Prevent sending if already generating
        guard !isGenerating else {
            print("⚠️ Already generating response, ignoring new message")
            return
        }
        
        // ✅ Check if there's a pending request in the ViewModel
        guard viewModel.pendingRequestId == nil else {
            print("⚠️ Request already in flight, ignoring duplicate")
            return
        }
        
        // ✅ Check Premium limits FIRST
        guard premiumManager.canSendMessage() else {
            print("❌ Message limit reached")
            showError = .rateLimitExceeded
            showErrorBanner = true
            
            // Show upgrade prompt after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showPremiumUpgrade = true
                }
            }
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            return
        }
        
        // Validate message length
        guard trimmedText.count <= 2000 else {
            showError = .unknown("Message is too long. Please keep it under 2000 characters.")
            showErrorBanner = true
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            return
        }
        
        // Check network connectivity
        guard networkMonitor.isConnected else {
            print("❌ No network connection")
            showError = .networkUnavailable
            showErrorBanner = true
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
            return
        }
        
        // ✅ Update tracking variables
        if !isRetry {
            lastSentMessageText = trimmedText
            lastSentTime = Date()
        }
        
        // ✅ Performance monitoring: Start tracking
        performanceMetrics.lastRequestStartTime = Date()
        
        // ✅ Dismiss keyboard
        isInputFocused = false
        
        let userMessage = BereanMessage(
            content: trimmedText,
            role: .user,
            timestamp: Date()
        )
        
        withAnimation(.easeOut(duration: 0.25)) {
            // ✅ P0-5: Use appendMessage instead of direct append
            viewModel.appendMessage(userMessage)
            messageText = ""
            showSuggestions = false
            isThinking = true
            isGenerating = true  // ✅ Set generating state
        }
        
        // Subtle haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Create placeholder message for streaming response
        let placeholderMessage = BereanMessage(
            content: "",
            role: .assistant,
            timestamp: Date()
        )
        
        // Add placeholder immediately so user sees thinking indicator
        withAnimation(.easeOut(duration: 0.25)) {
            // ✅ P0-5: Use appendMessage for placeholder
            viewModel.appendMessage(placeholderMessage)
        }
        
        // ✅ P0-1: Generate unique request ID for idempotency
        let requestId = UUID()
        
        // Call Genkit with streaming and comprehensive error handling
        viewModel.generateResponseStreaming(
            for: trimmedText,
            requestId: requestId,  // ✅ Pass request ID
            responseMode: responseMode,  // ✅ Pass response mode for cost control
            personalityPrefix: personalityMode.systemPromptPrefix,  // ✅ Pass personality voice
            onChunk: { chunk in
                // ✅ P1-1: Update UI efficiently (SwiftUI will batch updates automatically)
                if let lastIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }) {
                    let existingMessage = viewModel.messages[lastIndex]
                    let updatedMessage = BereanMessage(
                        content: existingMessage.content + chunk,
                        role: .assistant,
                        timestamp: existingMessage.timestamp,
                        verseReferences: existingMessage.verseReferences
                    )
                    viewModel.messages[lastIndex] = updatedMessage
                }
            },
            onComplete: { finalMessage in
                // ✅ P0-5: Preserve message ID during streaming completion
                Task { @MainActor in
                    if let lastIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }) {
                        let existingId = viewModel.messages[lastIndex].id
                        let preservedMessage = BereanMessage(
                            id: existingId,  // Preserve the original ID
                            content: finalMessage.content,
                            role: finalMessage.role,
                            timestamp: finalMessage.timestamp,
                            verseReferences: finalMessage.verseReferences
                        )
                        viewModel.messages[lastIndex] = preservedMessage
                    }
                    
                    // ✅ Track usage for free tier users
                    premiumManager.incrementMessageCount()
                    print("📊 Message count updated: \(premiumManager.freeMessagesUsed)/\(premiumManager.FREE_MESSAGES_PER_DAY)")
                    
                    withAnimation(.easeOut(duration: 0.3)) {
                        isThinking = false
                        isGenerating = false  // ✅ Clear generating state
                    }
                    
                    // ✅ P0-6: Auto-save conversation after successful message
                    if viewModel.messages.count >= 2 {  // At least one exchange
                        Task {
                            await MainActor.run {
                                viewModel.saveCurrentConversation()
                            }
                        }
                    }
                    
                    // ✅ Reset retry counter on success
                    retryAttempts = 0
                    lastFailedMessageText = ""
                    
                    // ✅ Performance monitoring: Track response time
                    if let startTime = performanceMetrics.lastRequestStartTime {
                        let responseTime = Date().timeIntervalSince(startTime)
                        performanceMetrics.messageCount += 1
                        performanceMetrics.totalResponseTime += responseTime
                        performanceMetrics.fastestResponse = min(performanceMetrics.fastestResponse, responseTime)
                        performanceMetrics.slowestResponse = max(performanceMetrics.slowestResponse, responseTime)
                        
                        print("⚡ Performance: Response time: \(String(format: "%.2f", responseTime))s | Avg: \(String(format: "%.2f", performanceMetrics.averageResponseTime))s | Fastest: \(String(format: "%.2f", performanceMetrics.fastestResponse))s | Slowest: \(String(format: "%.2f", performanceMetrics.slowestResponse))s")
                        
                        // ✅ Log warning if response is slow (> 5s)
                        if responseTime > 5.0 {
                            print("⚠️ Slow response detected: \(String(format: "%.2f", responseTime))s")
                        }
                    }
                    
                    // Success haptic
                    let successHaptic = UINotificationFeedbackGenerator()
                    successHaptic.notificationOccurred(.success)
                    
                    print("✅ Message sent and response received successfully")
                }
            },
            onError: { error in
                Task { @MainActor in
                    print("❌ Error generating response: \(error.localizedDescription)")
                    
                    // ✅ P0-4: Preserve failed message for retry
                    lastFailedMessageText = trimmedText
                    
                    // Remove the placeholder message on error
                    if let lastIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }),
                       viewModel.messages[lastIndex].content.isEmpty {
                        viewModel.messages.remove(at: lastIndex)
                    }
                    
                    withAnimation(.easeOut(duration: 0.3)) {
                        isThinking = false
                        isGenerating = false  // ✅ Clear generating state
                    }
                    
                    // ✅ Enhanced error handling with specific user-friendly messages
                    let bereanError: BereanError
                    if let openAIError = error as? OpenAIError {
                        switch openAIError {
                        case .missingAPIKey:
                            bereanError = .unknown("API key configuration error. Please check your settings.")
                        case .invalidResponse:
                            bereanError = .invalidResponse
                        case .httpError(let statusCode):
                            switch statusCode {
                            case 401, 403:
                                bereanError = .unknown("Authentication failed. Please check your API key in settings.")
                            case 429:
                                bereanError = .rateLimitExceeded
                            case 500...599:
                                bereanError = .unknown("Server error. The AI service is experiencing issues. Please try again in a moment.")
                            default:
                                bereanError = .unknown("Server error (\(statusCode)). Please try again.")
                            }
                        }
                    } else if let urlError = error as? URLError {
                        switch urlError.code {
                        case .notConnectedToInternet, .networkConnectionLost:
                            bereanError = .networkUnavailable
                        case .timedOut:
                            bereanError = .unknown("Request timed out. The AI is taking too long to respond. Try a shorter question.")
                        case .cannotFindHost, .cannotConnectToHost:
                            bereanError = .unknown("Cannot connect to AI service. Please check your internet connection.")
                        default:
                            bereanError = .unknown("Network error: \(urlError.localizedDescription)")
                        }
                    } else {
                        bereanError = .aiServiceUnavailable
                    }
                    
                    // Show error
                    showError = bereanError
                    showErrorBanner = true
                    
                    // Error haptic
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        )
    }
}

// MARK: - Berean Quick Action Card

struct BereanQuickActionCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        }) {
            VStack(spacing: 14) {
                // Icon container
                ZStack {
                    // Soft gradient background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    color.opacity(0.15),
                                    color.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: 30
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(0.2), lineWidth: 1)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.3))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                    )
                    .shadow(color: color.opacity(0.1), radius: 15, y: 5)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Square Action Card

struct SquareActionCard: View {
    let icon: String
    let title: String
    let gradient: LinearGradient
    let textColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        } label: {
            VStack(spacing: 8) {
                // Icon with subtle shadow
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(textColor)
                    .shadow(color: textColor.opacity(0.3), radius: 4, y: 2)
                
                Spacer().frame(height: 4)
                
                // Title with elegant typography
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1.0, contentMode: .fit)
            .padding(16)
            .background(
                ZStack {
                    // Gradient background (no white base for full color)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(gradient)
                    
                    // Subtle noise/grain texture overlay for premium feel
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            Color.white.opacity(0.05)
                        )
                        .blendMode(.overlay)
                    
                    // Soft border
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.3),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Suggested Prompt Card

struct SuggestedPromptCard: View {
    let prompt: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color(white: 0.5))
                
                Text(prompt)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.3))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: BereanMessage
    var onOpenSelah: ((BereanMessage) -> Void)? = nil
    @State private var showActions = false
    @State private var lightbulbPressed = false
    @State private var praisePressed = false
    @State private var messageToReport: BereanMessage?
    @State private var showReportIssue = false
    @Environment(\.messageShareHandler) private var shareHandler
    @EnvironmentObject private var dataManager: BereanDataManager
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer(minLength: 20)
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    if !message.isFromUser {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    
                    Text(message.isFromUser ? "You" : "Berean")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                        .textCase(.uppercase)
                        .tracking(1.5)
                }
                
                // Message content
                Text(message.content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.2))
                    .lineSpacing(8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                message.isFromUser ?
                                    AnyShapeStyle(Color.white.opacity(0.6)) :
                                    AnyShapeStyle(LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.7),
                                            Color.white.opacity(0.6)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
                    )
                
                // Smart reaction buttons (only for AI responses)
                if !message.isFromUser {
                    HStack(spacing: 10) {
                        // Lightbulb - "Helpful" reaction
                        SmartReactionButton(
                            icon: "lightbulb.fill",
                            activeColor: Color(red: 1.0, green: 0.7, blue: 0.5),
                            isActive: lightbulbPressed
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                lightbulbPressed.toggle()
                            }
                        }
                        
                        // Praise hands - "Amen" reaction
                        SmartReactionButton(
                            icon: "hands.clap.fill",
                            activeColor: Color(red: 0.5, green: 0.6, blue: 0.9),
                            isActive: praisePressed
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                praisePressed.toggle()
                            }
                        }

                        // Selah button — shown for long responses
                        if message.content.count > 400 {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onOpenSelah?(message)
                            } label: {
                                HStack(spacing: 3) {
                                    Image("amen-logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 13, height: 13)
                                        .blendMode(.multiply)
                                    Text("Selah")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        Spacer()
                        
                        // Share to Feed button
                        Button {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            shareHandler?(message)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.5))
                                .frame(width: 28, height: 28)
                        }
                        
                        // More options
                        Menu {
                            Button {
                                // ✅ P1-4: Offload clipboard operations to background thread
                                let content = message.content
                                Task.detached(priority: .userInitiated) {
                                    await MainActor.run {
                                        UIPasteboard.general.string = content
                                        
                                        let haptic = UINotificationFeedbackGenerator()
                                        haptic.notificationOccurred(.success)
                                        
                                        print("✅ Message copied to clipboard")
                                    }
                                }
                            } label: {
                                Label("Copy Text", systemImage: "doc.on.doc")
                            }
                            
                            Button {
                                // Save for later
                                dataManager.saveMessage(message)
                                
                                let haptic = UINotificationFeedbackGenerator()
                                haptic.notificationOccurred(.success)
                                
                                print("✅ Message saved for later")
                            } label: {
                                Label("Save for Later", systemImage: "bookmark")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                // Report issue
                                messageToReport = message
                                showReportIssue = true
                            } label: {
                                Label("Report Issue", systemImage: "exclamationmark.triangle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.5))
                                .frame(width: 28, height: 28)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Verse references if any
                if !message.verseReferences.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(message.verseReferences, id: \.self) { reference in
                            VerseReferenceChip(reference: reference)
                        }
                    }
                }
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(white: 0.5))
            }
            
            if !message.isFromUser {
                Spacer(minLength: 20)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func openVerse() {
        // ✅ Navigate to Bible view with verse reference
        guard let reference = message.verseReferences.first, !reference.isEmpty else {
            print("⚠️ No verse reference available")
            return
        }
        
        // Use the navigation helper to open the verse
        BereanNavigationHelper.openBibleVerse(reference: reference)
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        print("📖 Navigating to verse: \(reference)")
    }
}

// MARK: - Message Share Handler Environment Key

private struct MessageShareHandlerKey: EnvironmentKey {
    static let defaultValue: ((BereanMessage) -> Void)? = nil
}

extension EnvironmentValues {
    var messageShareHandler: ((BereanMessage) -> Void)? {
        get { self[MessageShareHandlerKey.self] }
        set { self[MessageShareHandlerKey.self] = newValue }
    }
}

// MARK: - Smart Reaction Button

struct SmartReactionButton: View {
    let icon: String
    let activeColor: Color
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? activeColor : Color(white: 0.5))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.12) : Color.white.opacity(0.6))
                        .overlay(
                            Circle()
                                .stroke(isActive ? activeColor.opacity(0.3) : Color.black.opacity(0.04), lineWidth: 0.5)
                        )
                        .shadow(color: isActive ? activeColor.opacity(0.15) : Color.clear, radius: 8)
                )
                .scaleEffect(isActive ? 1.1 : 1.0)
                .symbolEffect(.bounce, value: isActive)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Verse Reference Chip

struct VerseReferenceChip: View {
    let reference: String
    let action: (() -> Void)?
    
    @State private var isPressed = false
    
    init(reference: String, action: (() -> Void)? = nil) {
        self.reference = reference
        self.action = action
    }
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            if let action = action {
                action()
            } else {
                openVerseReference()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 9, weight: .medium))
                
                Text(reference)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(red: 0.5, green: 0.6, blue: 0.9).opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 0.5, green: 0.6, blue: 0.9).opacity(0.25), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
    
    private func openVerseReference() {
        // ✅ Navigate to Bible view with verse reference
        BereanNavigationHelper.openBibleVerse(reference: reference)
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        print("📖 Navigating to verse: \(reference)")
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicatorView: View {
    @State private var dotCount = 0
    @State private var animationPhase = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color(white: 0.5))
                    .symbolEffect(.pulse)
                
                Text("Berean")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
                    .textCase(.uppercase)
                    .tracking(1.5)
            }
            
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color(white: 0.4))
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotCount == index ? 1.3 : 0.8)
                        .opacity(dotCount == index ? 1.0 : 0.4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
            )
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    dotCount = (dotCount + 1) % 3
                }
            }
        }
    }
}

// MARK: - Berean Send Button

struct BereanSendButton: View {
    let action: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            
            withAnimation(.easeOut(duration: 0.2)) {
                isAnimating = true
            }
            
            action()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = false
            }
        }) {
            ZStack {
                // Background
                Circle()
                    .fill(.white)
                    .frame(width: 44, height: 44)
                
                // Subtle inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 22
                        )
                    )
                    .frame(width: 44, height: 44)
                    .opacity(isAnimating ? 0.6 : 1.0)
                
                // Icon
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .scaleEffect(isAnimating ? 0.85 : 1.0)
                    .offset(y: isAnimating ? -2 : 0)
            }
            .scaleEffect(isAnimating ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .shadow(
            color: Color.white.opacity(0.3),
            radius: isAnimating ? 20 : 15,
            y: isAnimating ? 8 : 4
        )
    }
}

// MARK: - Berean Message Model

// ✅ P1-3: Equatable conformance for efficient diffing
struct BereanMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let role: MessageRole
    let timestamp: Date
    var verseReferences: [String]
    
    // Convenience computed property for backward compatibility
    var isFromUser: Bool {
        return role == .user
    }
    
    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }
    
    // ✅ Equatable conformance for performance optimization
    static func == (lhs: BereanMessage, rhs: BereanMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.role == rhs.role &&
               lhs.verseReferences == rhs.verseReferences
    }
    
    init(id: UUID = UUID(), content: String, role: MessageRole, timestamp: Date, verseReferences: [String] = []) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.verseReferences = verseReferences
    }
}

// MARK: - Smart Feature

enum SmartFeature: String, CaseIterable {
    case crossReference = "Cross-References"
    case greekHebrew = "Greek/Hebrew"
    case historicalTimeline = "Timeline"
    case characterStudy = "Character Study"
    case theologicalThemes = "Themes"
    case verseOfDay = "Verse of Day"
    
    var icon: String {
        switch self {
        case .crossReference: return "link.circle.fill"
        case .greekHebrew: return "character.book.closed.fill"
        case .historicalTimeline: return "calendar.circle.fill"
        case .characterStudy: return "person.crop.circle.fill"
        case .theologicalThemes: return "books.vertical.circle.fill"
        case .verseOfDay: return "sun.horizon.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .crossReference: return Color(red: 0.5, green: 0.6, blue: 0.9) // Soft blue
        case .greekHebrew: return Color(red: 0.6, green: 0.5, blue: 0.8) // Soft purple
        case .historicalTimeline: return Color(red: 1.0, green: 0.7, blue: 0.5) // Soft orange
        case .characterStudy: return Color(red: 0.95, green: 0.7, blue: 0.6) // Soft peach
        case .theologicalThemes: return Color(red: 0.85, green: 0.6, blue: 0.7) // Soft rose
        case .verseOfDay: return Color(red: 1.0, green: 0.85, blue: 0.5) // Soft yellow
        }
    }
}

// MARK: - Smart Features Panel

struct SmartFeaturesPanel: View {
    @Binding var isShowing: Bool
    let onFeatureSelect: (SmartFeature) -> Void
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isShowing = false
                    }
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 12)
                    
                    // Title
                    Text("Smart Features")
                        .font(.custom("Georgia", size: 24))
                        .fontWeight(.light)
                        .foregroundStyle(Color(white: 0.2))
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    
                    Text("AI-powered Bible study tools")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.5))
                        .padding(.bottom, 24)
                    
                    // Features Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 16) {
                        ForEach(SmartFeature.allCases, id: \.self) { feature in
                            SmartFeatureButton(feature: feature) {
                                onFeatureSelect(feature)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.97, blue: 0.96),
                                    Color(red: 0.96, green: 0.95, blue: 0.97)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 30, y: -10)
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

// MARK: - Smart Feature Button

struct SmartFeatureButton: View {
    let feature: SmartFeature
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        }) {
            VStack(spacing: 10) {
                ZStack {
                    // Soft glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    feature.color.opacity(0.2),
                                    feature.color.opacity(0.08),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: 30
                            )
                        )
                        .frame(width: 54, height: 54)
                    
                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .stroke(feature.color.opacity(0.3), lineWidth: 0.5)
                        )
                    
                    Image(systemName: feature.icon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(feature.color)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                Text(feature.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.3))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Berean ViewModel

class BereanViewModel: ObservableObject {
    @Published var messages: [BereanMessage] = []
    @Published var selectedTranslation: String = "ESV"  // ✅ Default translation
    @Published var savedConversations: [SavedConversation] = []  // ✅ Conversation history
    
    private let genkitService = BereanGenkitService.shared
    private var currentTask: Task<Void, Never>?  // ✅ Track current generation task
    
    // ✅ P0-1: Idempotency tracking
    var pendingRequestId: UUID?
    private var completedRequestIds: Set<UUID> = []
    
    // Timeout configuration
    private let requestTimeout: TimeInterval = 60.0  // 60 seconds
    
    // ✅ P0-5: Memory management
    private let maxMessagesInMemory = 100
    private let maxSavedConversations = 50
    
    // ✅ Available Bible translations
    let availableTranslations = [
        "ESV", "NIV", "NKJV", "KJV", "NLT",
        "NASB", "CSB", "MSG", "AMP", "NET"
    ]
    
    let suggestedPrompts = [
        "What does John 3:16 mean?",
        "Explain the parable of the prodigal son",
        "What's the historical context of Romans?",
        "Compare translations of Psalm 23",
        "Tell me about Paul's missionary journeys",
        "What does it mean to have faith like a mustard seed?",
        "Explain the Sermon on the Mount in simple terms",
        "How do I apply Proverbs 3:5-6 to my daily life?"
    ]
    
    // Smart features: Conversation topics
    let smartTopics = [
        "Cross-references",
        "Greek/Hebrew insights",
        "Historical timeline",
        "Character study",
        "Theological themes"
    ]
    
    init() {
        loadSavedConversations()
        loadSelectedTranslation()
    }
    
    // MARK: - Conversation Management
    
    /// Save current conversation to history
    func saveCurrentConversation() {
        guard !messages.isEmpty else {
            print("⚠️ No messages to save")
            return
        }
        
        let conversation = SavedConversation(
            title: generateConversationTitle(),
            messages: messages,
            date: Date(),
            translation: selectedTranslation
        )
        
        savedConversations.insert(conversation, at: 0)
        saveConversationsToUserDefaults()
        
        print("✅ Conversation saved: \(conversation.title)")
    }
    
    /// Load a saved conversation
    func loadConversation(_ conversation: SavedConversation) {
        messages = conversation.messages
        selectedTranslation = conversation.translation
        print("📖 Loaded conversation: \(conversation.title)")
    }
    
    /// Delete a conversation
    func deleteConversation(_ conversation: SavedConversation) {
        savedConversations.removeAll { $0.id == conversation.id }
        saveConversationsToUserDefaults()
        print("🗑️ Deleted conversation: \(conversation.title)")
    }
    
    /// Update conversation title
    func updateConversationTitle(_ conversation: SavedConversation, newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ Cannot update with empty title")
            return
        }
        
        if let index = savedConversations.firstIndex(where: { $0.id == conversation.id }) {
            let updatedConversation = SavedConversation(
                id: conversation.id,
                title: newTitle,
                messages: conversation.messages,
                date: conversation.date,
                translation: conversation.translation
            )
            savedConversations[index] = updatedConversation
            saveConversationsToUserDefaults()
            print("✏️ Updated conversation title: \(newTitle)")
        }
    }
    
    /// Clear current messages
    func clearMessages() {
        messages = []
        print("🗑️ Messages cleared")
    }
    
    /// Clear all data (conversations + messages)
    func clearAllData() {
        messages = []
        savedConversations = []
        UserDefaults.standard.removeObject(forKey: "berean_conversations")
        print("🗑️ All data cleared")
    }
    
    /// Generate a title from the first user message
    private func generateConversationTitle() -> String {
        let firstUserMessage = messages.first(where: { $0.role == .user })
        let content = firstUserMessage?.content ?? "Conversation"
        
        // Take first 50 chars or first sentence
        let title = String(content.prefix(50))
        if title.count < content.count {
            return title + "..."
        }
        return title
    }
    
    // MARK: - Persistence
    
    private func saveConversationsToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(savedConversations)
            UserDefaults.standard.set(data, forKey: "berean_conversations")
            print("💾 Saved \(savedConversations.count) conversations to UserDefaults")
        } catch {
            print("❌ Failed to save conversations: \(error.localizedDescription)")
            // Don't throw - this is a best-effort persistence
        }
    }
    
    private func loadSavedConversations() {
        guard let data = UserDefaults.standard.data(forKey: "berean_conversations") else {
            print("ℹ️ No saved conversations found")
            return
        }
        
        do {
            savedConversations = try JSONDecoder().decode([SavedConversation].self, from: data)
            print("📖 Loaded \(savedConversations.count) conversations")
        } catch {
            print("❌ Failed to load conversations: \(error.localizedDescription)")
            // Reset to empty array on corruption
            savedConversations = []
        }
    }
    
    private func loadSelectedTranslation() {
        if let saved = UserDefaults.standard.string(forKey: "berean_translation") {
            // Validate that it's a known translation
            if availableTranslations.contains(saved) {
                selectedTranslation = saved
                print("📖 Loaded translation preference: \(saved)")
            } else {
                print("⚠️ Invalid saved translation '\(saved)', using default")
                selectedTranslation = "ESV"
            }
        } else {
            print("ℹ️ No saved translation preference, using default: ESV")
        }
    }
    
    private func saveSelectedTranslation() {
        UserDefaults.standard.set(selectedTranslation, forKey: "berean_translation")
        print("💾 Saved translation preference: \(selectedTranslation)")
    }
    
    // MARK: - Stop Generation
    
    /// Stop the current AI generation
    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        pendingRequestId = nil  // ✅ P0-1: Clear pending request
        print("⏸️ Stopped AI generation")
    }
    
    // MARK: - Message Management
    
    /// Append message with automatic trimming
    func appendMessage(_ message: BereanMessage) {
        messages.append(message)
        
        // ✅ P0-5: Trim if exceeds limit
        if messages.count > maxMessagesInMemory {
            // Keep first 2 (system context if any) + last 98
            let systemMessages = messages.prefix(2).filter { $0.role == .system }
            let recentMessages = messages.suffix(maxMessagesInMemory - systemMessages.count)
            messages = Array(systemMessages) + recentMessages
            print("📉 Trimmed conversation history to \(messages.count) messages")
        }
    }
    
    // MARK: - Generate Response with Genkit AI (Streaming)
    
    // ✅ P0-2: Query complexity analysis
    enum QueryComplexity {
        case simple      // 0-2 messages context
        case followUp    // 2-4 messages context
        case study       // 4-6 messages context
    }
    
    private func analyzeQueryComplexity(_ query: String) -> QueryComplexity {
        let wordCount = query.split(separator: " ").count
        let queryLower = query.lowercased()
        
        // Check for follow-up indicators
        let followUpWords = ["also", "and", "what about", "tell me more", "continue", "expand", "elaborate"]
        let hasFollowUpWords = followUpWords.contains { queryLower.contains($0) }
        
        // Simple query patterns
        let simplePatterns = ["what is", "who is", "define", "explain briefly", "what does", "who was"]
        let isSimplePattern = simplePatterns.contains { queryLower.hasPrefix($0) }
        
        if (wordCount < 10 && !hasFollowUpWords) || isSimplePattern {
            return .simple
        } else if hasFollowUpWords || wordCount < 25 {
            return .followUp
        } else {
            return .study
        }
    }
    
    private func selectContextWindow(for complexity: QueryComplexity) -> Int {
        switch complexity {
        case .simple: return 2
        case .followUp: return 4
        case .study: return 6
        }
    }
    
    func generateResponseStreaming(
        for query: String,
        requestId: UUID = UUID(),  // ✅ P0-1: Add request ID for idempotency
        responseMode: BereanResponseMode = .balanced,  // ✅ P0-2: Response mode for cost control
        personalityPrefix: String = "",  // ✅ Personality mode prefix injected from view
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (BereanMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // ✅ P0-1: Idempotency check
        guard !completedRequestIds.contains(requestId) else {
            print("⏭️ Skipping duplicate request: \(requestId)")
            return
        }
        
        guard pendingRequestId == nil || pendingRequestId == requestId else {
            print("⚠️ Request already in flight, ignoring duplicate")
            return
        }
        
        pendingRequestId = requestId
        
        // Validate input
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ Cannot generate response for empty query")
            onError(NSError(
                domain: "BereanViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Query cannot be empty"]
            ))
            return
        }
        
        // ✅ P0-2: Use response mode context window (more predictable than query complexity)
        let contextWindow = responseMode.contextWindow
        let recentHistory = Array(messages.suffix(contextWindow))
        
        let savedMessages = max(0, messages.count - contextWindow)
        print("📊 Context: \(responseMode.rawValue) mode → \(contextWindow) messages (saved ~\(savedMessages) messages)")
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Create new task with timeout
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                var fullResponse = ""
                let startTime = Date()
                
                // Stream response from Genkit with timeout monitoring
                // ⚡ Use limited history and response mode parameters for cost control
                for try await chunk in genkitService.sendMessage(
                    query,
                    conversationHistory: recentHistory,
                    maxTokens: responseMode.maxTokens,
                    temperature: responseMode.temperature,
                    // Combine personality prefix (voice/tone) with response mode suffix (depth/format).
                    // The personality prefix is injected by the view at call time.
                    systemPromptSuffix: (personalityPrefix.isEmpty ? "" : personalityPrefix + " ") + responseMode.systemPromptSuffix
                ) {
                    // ✅ Check if task was cancelled
                    if Task.isCancelled {
                        print("⏸️ Generation cancelled by user")
                        await MainActor.run {
                            self.pendingRequestId = nil
                        }
                        return
                    }
                    
                    // Check timeout
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > requestTimeout {
                        print("⏱️ Request timeout after \(elapsed) seconds")
                        throw NSError(
                            domain: "BereanViewModel",
                            code: -3,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Request timed out",
                                NSLocalizedRecoverySuggestionErrorKey: "The AI took too long to respond. Please try again with a simpler question."
                            ]
                        )
                    }
                    
                    fullResponse += chunk
                    await MainActor.run {
                        onChunk(chunk)
                    }
                }
                
                // ✅ Check again before completing
                guard !Task.isCancelled else {
                    print("⏸️ Generation cancelled before completion")
                    await MainActor.run {
                        self.pendingRequestId = nil
                    }
                    return
                }
                
                // Validate response
                guard !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("❌ Received empty response from AI")
                    await MainActor.run {
                        self.pendingRequestId = nil
                    }
                    throw NSError(
                        domain: "BereanViewModel",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "AI returned empty response"]
                    )
                }
                
                // ✅ P0-4: Extract and validate verse references
                let verseReferences = extractAndValidateVerseReferences(from: fullResponse)
                let finalMessage = BereanMessage(
                    content: fullResponse,
                    role: .assistant,
                    timestamp: Date(),
                    verseReferences: verseReferences
                )
                
                let duration = Date().timeIntervalSince(startTime)
                print("✅ Response generation completed in \(String(format: "%.2f", duration))s")
                print("📊 Context used: \(contextWindow) messages | References found: \(verseReferences.count)")
                
                await MainActor.run {
                    // ✅ P0-1: Mark request as completed
                    self.completedRequestIds.insert(requestId)
                    self.pendingRequestId = nil
                    
                    // Cleanup old IDs (keep last 50)
                    if self.completedRequestIds.count > 50 {
                        let sortedIds = Array(self.completedRequestIds)
                        self.completedRequestIds = Set(sortedIds.suffix(50))
                    }
                    
                    onComplete(finalMessage)
                }
                
            } catch is CancellationError {
                // Task was cancelled - don't report as error
                print("⏸️ Generation task cancelled")
                await MainActor.run {
                    self.pendingRequestId = nil
                }
                return
            } catch let error as OpenAIError {
                // ✅ Don't show error if cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.pendingRequestId = nil
                    }
                    return
                }
                
                print("❌ OpenAI error: \(error.localizedDescription)")
                await MainActor.run {
                    self.pendingRequestId = nil
                    onError(error)
                }
                
                // ✅ Production: No mock responses - show real errors to users
            } catch {
                // ✅ Don't show error if cancelled
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.pendingRequestId = nil
                    }
                    return
                }
                
                print("❌ Unexpected error during streaming: \(error.localizedDescription)")
                await MainActor.run {
                    self.pendingRequestId = nil
                    onError(error)
                }
                
                // ✅ Production: No mock responses - show real errors to users
            }
        }
    }
    
    // MARK: - Helper: Extract and Validate Verse References (P0-4)
    
    // ✅ P0-4: Valid Bible books
    private let validBooks = Set([
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
        "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
        "Zephaniah", "Haggai", "Zechariah", "Malachi",
        "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
        "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
        "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John",
        "Jude", "Revelation"
    ])
    
    private let bookChapterCounts: [String: Int] = [
        "Genesis": 50, "Exodus": 40, "Leviticus": 27, "Numbers": 36, "Deuteronomy": 34,
        "Joshua": 24, "Judges": 21, "Ruth": 4, "1 Samuel": 31, "2 Samuel": 24,
        "1 Kings": 22, "2 Kings": 25, "1 Chronicles": 29, "2 Chronicles": 36,
        "Ezra": 10, "Nehemiah": 13, "Esther": 10, "Job": 42, "Psalms": 150, "Proverbs": 31,
        "Ecclesiastes": 12, "Song of Solomon": 8, "Isaiah": 66, "Jeremiah": 52,
        "Lamentations": 5, "Ezekiel": 48, "Daniel": 12, "Hosea": 14, "Joel": 3,
        "Amos": 9, "Obadiah": 1, "Jonah": 4, "Micah": 7, "Nahum": 3, "Habakkuk": 3,
        "Zephaniah": 3, "Haggai": 2, "Zechariah": 14, "Malachi": 4,
        "Matthew": 28, "Mark": 16, "Luke": 24, "John": 21, "Acts": 28, "Romans": 16,
        "1 Corinthians": 16, "2 Corinthians": 13, "Galatians": 6, "Ephesians": 6,
        "Philippians": 4, "Colossians": 4, "1 Thessalonians": 5, "2 Thessalonians": 3,
        "1 Timothy": 6, "2 Timothy": 4, "Titus": 3, "Philemon": 1, "Hebrews": 13,
        "James": 5, "1 Peter": 5, "2 Peter": 3, "1 John": 5, "2 John": 1, "3 John": 1,
        "Jude": 1, "Revelation": 22
    ]
    
    private func extractAndValidateVerseReferences(from text: String) -> [String] {
        var references: [String] = []
        
        // Simple regex to find Bible references like "John 3:16" or "Romans 8:28-30"
        let pattern = #"([1-3]?\s?[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s+(\d+):(\d+)(?:-(\d+))?"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let reference = String(text[range])
                    
                    // ✅ P0-4: Validate reference before adding
                    if isValidReference(reference) {
                        if !references.contains(reference) {
                            references.append(reference)
                        }
                    } else {
                        print("⚠️ Invalid scripture reference detected and filtered: \(reference)")
                    }
                }
            }
        }
        
        return references
    }
    
    private func isValidReference(_ reference: String) -> Bool {
        // Parse book name and chapter — trim whitespace/newlines first so leading
        // newlines from regex captures don't produce empty components.
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        guard components.count >= 2 else { return false }
        
        // Handle multi-word book names (e.g., "1 Corinthians", "Song of Solomon")
        var bookName = ""
        var chapterVerse = ""
        
        // Try to find the chapter:verse part (contains ":")
        for (index, component) in components.enumerated() {
            if component.contains(":") {
                bookName = components[..<index].joined(separator: " ")
                chapterVerse = component
                break
            }
        }
        
        guard !bookName.isEmpty, !chapterVerse.isEmpty else { return false }
        
        // Validate book exists
        guard validBooks.contains(bookName) else {
            print("⚠️ Invalid book name: \(bookName)")
            return false
        }
        
        // Extract chapter number
        let chapterComponents = chapterVerse.split(separator: ":")
        guard let chapterStr = chapterComponents.first,
              let chapter = Int(chapterStr) else {
            return false
        }
        
        // Validate chapter range
        if let maxChapter = bookChapterCounts[bookName],
           chapter > maxChapter {
            print("⚠️ Invalid chapter: \(bookName) only has \(maxChapter) chapters, got \(chapter)")
            return false
        }
        
        return true
    }
    
    // MARK: - Helper: Extract Verse References (Old - Deprecated)
    
    private func extractVerseReferences(from text: String) -> [String] {
        var references: [String] = []
        
        // Simple regex to find Bible references like "John 3:16" or "Romans 8:28-30"
        let pattern = #"([1-3]?\s?[A-Z][a-z]+)\s+(\d+):(\d+)(?:-(\d+))?"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let reference = String(text[range])
                    if !references.contains(reference) {
                        references.append(reference)
                    }
                }
            }
        }
        
        return references
    }
    
    // MARK: - Mock Fallback Response (when Genkit is unavailable)
    
    private func generateMockResponse(for query: String) -> BereanMessage {
        let responses: [String: (content: String, verses: [String])] = [
            "john 3:16": (
                "John 3:16 is one of the most profound verses in Scripture. It encapsulates the essence of God's redemptive love.\n\n\"For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.\"\n\nKey insights:\n• **Divine love**: God's love extends to all humanity\n• **Sacrificial gift**: Jesus as the ultimate expression of love\n• **Universal offer**: Salvation available to \"whoever believes\"\n• **Eternal promise**: Transition from perishing to eternal life\n\nThis verse is often called \"the gospel in miniature\" because it captures Christianity's central message in a single sentence.",
                ["John 3:16", "John 3:17"]
            ),
            "prodigal": (
                "The parable of the prodigal son (Luke 15:11-32) is a powerful story about God's unconditional love and forgiveness.\n\n**The Story:**\n• Younger son demands inheritance early\n• Squanders everything in wild living\n• Returns home broken and repentant\n• Father runs to embrace him with joy\n\n**Key Themes:**\n• **Grace**: The father's love despite rebellion\n• **Repentance**: The son's humble return\n• **Celebration**: Heaven's joy over one sinner who repents\n• **Resentment**: The older brother's struggle with grace\n\nThis parable reveals the heart of God—always watching, always ready to receive us back with open arms.",
                ["Luke 15:11-32"]
            ),
            "explain": (
                "I'd be delighted to explain any Scripture passage for you.\n\nI can provide:\n• **Context**: Historical and cultural background\n• **Language**: Original Greek/Hebrew insights\n• **Theology**: Doctrinal significance\n• **Application**: How it applies today\n• **Cross-references**: Related passages\n\nWhich verse or passage would you like me to explain?",
                []
            ),
            "compare": (
                "Comparing Bible translations is a valuable study tool. I can help you see:\n\n• **Literal translations** (NASB, ESV, NKJV)\n  → Word-for-word accuracy\n\n• **Dynamic equivalence** (NIV, CSB, NLT)\n  → Thought-for-thought clarity\n\n• **Paraphrases** (MSG, TLB)\n  → Contemporary language\n\n• **Original languages**\n  → Hebrew/Greek word studies\n\nWhich passage would you like to compare?",
                []
            ),
            "context": (
                "Biblical context is crucial for proper interpretation. I can explore:\n\n📖 **Literary Context**\n• Genre and structure\n• Surrounding chapters\n• Author's argument flow\n\n🌍 **Historical Context**\n• Cultural practices\n• Political situation\n• Religious environment\n\n✍️ **Authorial Context**\n• Who wrote it\n• To whom\n• Why it was written\n\nWhat passage interests you?",
                []
            ),
            "paul": (
                "Paul's missionary journeys transformed the ancient world and established Christianity throughout the Roman Empire.\n\n**Journey Overview:**\n\n**First Journey** (Acts 13-14)\n• Cyprus, Pisidian Antioch, Iconium\n• Established churches in Galatia\n\n**Second Journey** (Acts 15:36-18:22)\n• Macedonia and Greece\n• Founded Philippian and Corinthian churches\n• Wrote 1 & 2 Thessalonians\n\n**Third Journey** (Acts 18:23-21:16)\n• Ephesus (3 years ministry)\n• Wrote Romans, Corinthians\n\nPaul traveled over 10,000 miles, establishing churches that would shape Christian theology for millennia.",
                ["Acts 13:1-3", "Acts 16:9-10", "Acts 19:10"]
            ),
            "cross": (
                "Cross-references help illuminate Scripture by connecting related passages. Let me show you how themes, promises, and prophecies weave throughout the Bible.\n\n**Why Cross-References Matter:**\n• Scripture interprets Scripture\n• Shows thematic connections\n• Reveals prophetic fulfillment\n• Deepens understanding\n\nWhat passage would you like cross-references for?",
                []
            ),
            "greek": (
                "Exploring the original languages adds rich depth to Bible study.\n\n**Greek (New Testament):**\n• Precise theological terms\n• Verb tenses reveal timing\n• Word order shows emphasis\n\n**Hebrew (Old Testament):**\n• Poetic structures\n• Names carry meaning\n• Wordplay and double meanings\n\nWhich word or phrase would you like to explore?",
                []
            ),
            "timeline": (
                "Biblical history spans thousands of years. Here's a simplified overview:\n\n📅 **Major Periods:**\n\n**Patriarchs** (2000-1800 BC)\n• Abraham, Isaac, Jacob\n\n**Exodus** (1446 BC)\n• Moses leads Israel from Egypt\n\n**Kingdom Era** (1050-586 BC)\n• Saul, David, Solomon\n• Divided Kingdom\n\n**Exile** (586-538 BC)\n• Babylonian captivity\n\n**Return** (538 BC+)\n• Temple rebuilt\n\n**Jesus** (4 BC - 30 AD)\n• Ministry, death, resurrection\n\n**Early Church** (30-100 AD)\n• Apostles spread gospel\n\nWhich period would you like to explore deeper?",
                []
            ),
            "character": (
                "Character studies reveal how God works through imperfect people.\n\n**Popular Characters:**\n• **David**: Man after God's heart despite failures\n• **Peter**: Passionate disciple who denied then led\n• **Moses**: Reluctant leader who freed a nation\n• **Mary**: Young woman chosen for divine purpose\n• **Paul**: Persecutor turned apostle\n\nWhich Biblical character interests you?",
                []
            ),
            "theme": (
                "Theological themes connect Scripture into a unified story:\n\n**Major Themes:**\n\n🔹 **Covenant**: God's promises to His people\n🔹 **Redemption**: Salvation through Christ\n🔹 **Kingdom**: God's reign and rule\n🔹 **Grace**: Unmerited favor\n🔹 **Love**: God's character and command\n🔹 **Justice**: God's righteousness\n🔹 **Hope**: Future promises\n\nWhich theme would you like to explore?",
                []
            ),
            "verse": (
                "Here's an encouraging verse for you today:\n\n**Philippians 4:13**\n\"I can do all things through Christ who strengthens me.\"\n\n**Reflection:**\nPaul wrote this from prison, yet he found strength not in circumstances but in Christ. Whatever challenges you face today, His power is sufficient. Your weakness becomes the canvas for His strength to be displayed.\n\n**Prayer:**\nLord, help me trust in Your strength today, not my own. Amen.",
                ["Philippians 4:13", "2 Corinthians 12:9"]
            )
        ]
        
        // Smart keyword matching (in production, use actual AI)
        let lowercaseQuery = query.lowercased()
        
        for (keyword, response) in responses {
            if lowercaseQuery.contains(keyword) {
                return BereanMessage(
                    content: response.content,
                    role: .assistant,
                    timestamp: Date(),
                    verseReferences: response.verses
                )
            }
        }
        
        // Default intelligent response
        return BereanMessage(
            content: "That's a thought-provoking question! I'm here to help you explore God's Word deeply.\n\n**I can assist with:**\n\n📖 Explaining passages and theology\n🔍 Providing historical/cultural context\n📚 Comparing translations\n💡 Cross-referencing related Scriptures\n🗺️ Exploring Biblical geography\n✍️ Original language insights\n\nFeel free to ask anything about the Bible!",
            role: .assistant,
            timestamp: Date()
        )
    }
}

// MARK: - Share to Feed Sheet

struct ShareToFeedSheet: View {
    let message: BereanMessage
    @Binding var isShowing: Bool
    let onShare: (String) -> Void
    
    @State private var shareText: String = ""
    @State private var addPersonalNote = false
    @State private var personalNote = ""
    
    var body: some View {
        ZStack {
            backdropView
            
            VStack {
                Spacer()
                sheetContentView
            }
        }
    }
    
    private var backdropView: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowing = false
                }
            }
    }
    
    private var sheetContentView: some View {
        VStack(spacing: 0) {
            handleBar
            headerSection
            subtitleText
            scrollableContent
            shareButton
        }
        .frame(maxWidth: .infinity)
        .background(sheetBackground)
        .ignoresSafeArea(edges: .bottom)
    }
    
    private var handleBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
    }
    
    private var headerSection: some View {
        HStack {
            Text("Share to OpenTable")
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(.white)
            
            Spacer()
            
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowing = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
    
    private var subtitleText: some View {
        Text("Share this insight with your faith community")
            .font(.custom("OpenSans-Regular", size: 13))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
    }
    
    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                messagePreview
                personalNoteToggle
                
                if addPersonalNote {
                    personalNoteField
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxHeight: 400)
    }
    
    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            messagePreviewHeader
            
            Text(message.content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(5)
                .lineLimit(6)
            
            if !message.verseReferences.isEmpty {
                verseReferencesView
            }
        }
        .padding(16)
        .background(messagePreviewBackground)
    }
    
    private var messagePreviewHeader: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
            
            Text("Berean AI Insight")
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(.white.opacity(0.9))
            
            Spacer()
        }
    }
    
    private var verseReferencesView: some View {
        HStack(spacing: 8) {
            ForEach(message.verseReferences.prefix(3), id: \.self) { reference in
                Text(reference)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.15))
                    )
            }
        }
    }
    
    private var messagePreviewBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
    
    private var personalNoteToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                addPersonalNote.toggle()
            }
        } label: {
            HStack {
                Image(systemName: addPersonalNote ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(addPersonalNote ? Color(red: 0.4, green: 0.85, blue: 0.7) : .white.opacity(0.5))
                
                Text("Add personal note")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                
                Spacer()
            }
            .padding(16)
            .background(personalNoteToggleBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var personalNoteToggleBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
    
    private var personalNoteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your thoughts")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.white.opacity(0.6))
            
            TextEditor(text: $personalNote)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding(12)
                .background(personalNoteFieldBackground)
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }
    
    private var personalNoteFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
    
    private var shareButton: some View {
        Button {
            let finalText = addPersonalNote && !personalNote.isEmpty ?
                "\(personalNote)\n\n---\n\(message.content)" :
                message.content
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            onShare(finalText)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Share to Feed")
                    .font(.custom("OpenSans-Bold", size: 16))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(shareButtonBackground)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private var shareButtonBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.white)
            .shadow(color: .white.opacity(0.3), radius: 15, y: 5)
    }
    
    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(white: 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: -10)
    }
}

// MARK: - Premium Upgrade View (OLD - Use new standalone PremiumUpgradeView.swift instead)

struct BereanPremiumUpgradeView: View {
    @Binding var isShowing: Bool
    
    let premiumFeatures: [(icon: String, title: String, description: String, color: Color)] = [
        ("infinity.circle.fill", "Unlimited Conversations", "No daily message limits - ask as much as you want", Color(red: 0.4, green: 0.7, blue: 1.0)),
        ("brain.head.profile.fill", "Advanced AI Model", "Access to the most sophisticated Bible study AI", Color(red: 0.6, green: 0.5, blue: 1.0)),
        ("book.pages.fill", "Multi-Translation Analysis", "Compare unlimited translations side-by-side", Color(red: 1.0, green: 0.7, blue: 0.4)),
        ("globe.americas.fill", "Original Languages", "Deep Hebrew & Greek word studies with etymology", Color(red: 0.4, green: 0.85, blue: 0.7)),
        ("waveform.badge.mic.fill", "Voice Conversations", "Natural voice interaction with AI assistant", Color(red: 1.0, green: 0.6, blue: 0.7)),
        ("bookmark.circle.fill", "Save & Organize", "Unlimited saved conversations and insights", Color(red: 1.0, green: 0.85, blue: 0.4)),
        ("arrow.triangle.branch", "Cross-Reference Maps", "Visual connections between passages", Color(red: 0.4, green: 0.7, blue: 1.0)),
        ("doc.richtext.fill", "Study Guides", "AI-generated personalized study plans", Color(red: 0.6, green: 0.5, blue: 1.0)),
        ("person.2.circle.fill", "Group Study Mode", "Collaborative Bible study with others", Color(red: 1.0, green: 0.7, blue: 0.4)),
        ("chart.line.uptrend.xyaxis.circle.fill", "Progress Tracking", "Track your spiritual growth journey", Color(red: 0.4, green: 0.85, blue: 0.7)),
        ("bell.badge.circle.fill", "Daily Insights", "Personalized devotionals and verse notifications", Color(red: 1.0, green: 0.6, blue: 0.7)),
        ("star.leadinghalf.filled", "Priority Support", "Fast response times and dedicated assistance", Color(red: 1.0, green: 0.85, blue: 0.4))
    ]
    
    var body: some View {
        ZStack {
            premiumBackdrop
            
            VStack(spacing: 0) {
                closeButtonHeader
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        heroSection
                        pricingSection
                        featuresSection
                        ctaButton
                    }
                }
            }
        }
    }
    
    private var premiumBackdrop: some View {
        Color.black.opacity(0.85)
            .ignoresSafeArea()
    }
    
    private var closeButtonHeader: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowing = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.trailing, 20)
            .padding(.top, 20)
        }
    }
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Premium badge
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 28))
                Text("Berean Pro")
                    .font(.custom("OpenSans-Bold", size: 32))
            }
            .foregroundStyle(.white)
            .shadow(color: .white.opacity(0.3), radius: 20)
            
            Text("Unlock the full power of AI-assisted Bible study")
                .font(.custom("OpenSans-Regular", size: 17))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 30)
        }
        .padding(.top, 20)
    }
    
    private var pricingSection: some View {
        VStack(spacing: 12) {
            PremiumPricingCard(
                title: "Annual",
                price: "$49.99",
                period: "per year",
                savings: "Save 60%",
                isRecommended: true
            )
            
            PremiumPricingCard(
                title: "Monthly",
                price: "$9.99",
                period: "per month",
                savings: nil,
                isRecommended: false
            )
        }
        .padding(.horizontal, 20)
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything Included")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(Array(premiumFeatures.enumerated()), id: \.offset) { index, feature in
                    PremiumFeatureCard(
                        icon: feature.icon,
                        title: feature.title,
                        description: feature.description,
                        color: feature.color
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var ctaButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            // Handle purchase
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .bold))
                    
                    Text("Upgrade to Pro")
                        .font(.custom("OpenSans-Bold", size: 18))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                )
                .shadow(color: .white.opacity(0.3), radius: 20, y: 10)
                
                Text("7-day free trial • Cancel anytime")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
}

// MARK: - Premium Pricing Card

struct PremiumPricingCard: View {
    let title: String
    let price: String
    let period: String
    let savings: String?
    let isRecommended: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let savings = savings {
                    Text(savings)
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.2))
                        )
                }
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.white)
                
                Text(period)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            Text(price)
                .font(.custom("OpenSans-Bold", size: 26))
                .foregroundStyle(.white)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(isRecommended ? 0.12 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isRecommended ?
                                Color.white.opacity(0.5) :
                                Color.white.opacity(0.1),
                            lineWidth: isRecommended ? 2 : 1
                        )
                )
        )
    }
}

// MARK: - Premium Feature Card

struct PremiumFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
            }
            
            Text(title)
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(description)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

#Preview {
    BereanAIAssistantView()
}

// MARK: - SavedConversation Model

struct SavedConversation: Identifiable, Codable {
    let id: UUID
    let title: String
    let messages: [BereanMessage]
    let date: Date
    let translation: String
    
    init(id: UUID = UUID(), title: String, messages: [BereanMessage], date: Date, translation: String) {
        self.id = id
        self.title = title
        self.messages = messages
        self.date = date
        self.translation = translation
    }
}

// MARK: - Bible Translation Picker

struct BibleTranslationPicker: View {
    @Binding var selectedTranslation: String
    @Binding var isShowing: Bool
    @Environment(\.dismiss) private var dismiss
    
    let translations = [
        ("ESV", "English Standard Version", "Word-for-word, literal"),
        ("NIV", "New International Version", "Thought-for-thought, balanced"),
        ("NKJV", "New King James Version", "Modern language, traditional"),
        ("KJV", "King James Version", "Classic, traditional"),
        ("NLT", "New Living Translation", "Easy to read, dynamic"),
        ("NASB", "New American Standard", "Very literal, accurate"),
        ("CSB", "Christian Standard Bible", "Optimal balance"),
        ("MSG", "The Message", "Paraphrase, contemporary"),
        ("AMP", "Amplified Bible", "Expanded meanings"),
        ("NET", "New English Translation", "Extensive notes")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(translations, id: \.0) { translation in
                            TranslationRow(
                                code: translation.0,
                                name: translation.1,
                                description: translation.2,
                                isSelected: selectedTranslation == translation.0
                            ) {
                                selectedTranslation = translation.0
                                UserDefaults.standard.set(translation.0, forKey: "berean_translation")
                                
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                
                                // Auto-dismiss after selection
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Bible Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

struct TranslationRow: View {
    let code: String
    let name: String
    let description: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.white)
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                        }
                    }
                    
                    Text(name)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Conversation History View

struct ConversationHistoryView: View {
    let conversations: [SavedConversation]
    let onSelect: (SavedConversation) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
                    .ignoresSafeArea()
                
                if conversations.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(conversations) { conversation in
                                ConversationHistoryRow(conversation: conversation) {
                                    onSelect(conversation)
                                    dismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Conversation History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.3))
            
            Text("No Saved Conversations")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.white)
            
            Text("Your conversation history will appear here")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct ConversationHistoryRow: View {
    let conversation: SavedConversation
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(conversation.title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                
                HStack(spacing: 12) {
                    Label(conversation.translation, systemImage: "book.fill")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Text("•")
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Text(conversation.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Text("•")
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Text("\(conversation.messages.count) messages")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Berean Quick Actions Menu

struct BereanQuickActionsMenu: View {
    @Binding var isShowing: Bool
    let onNewConversation: () -> Void
    let onSavedMessages: () -> Void
    let onHistory: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Quick action buttons
            VStack(spacing: 0) {
                QuickActionButton(
                    icon: "plus.message.fill",
                    title: "New Chat",
                    subtitle: "Start fresh",
                    gradient: LinearGradient(
                        colors: [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.5, blue: 0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ) {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onNewConversation()
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                QuickActionButton(
                    icon: "bookmark.fill",
                    title: "Saved",
                    subtitle: "View bookmarks",
                    gradient: LinearGradient(
                        colors: [Color(red: 1.0, green: 0.7, blue: 0.5), Color(red: 1.0, green: 0.5, blue: 0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ) {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onSavedMessages()
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                QuickActionButton(
                    icon: "clock.fill",
                    title: "History",
                    subtitle: "Past chats",
                    gradient: LinearGradient(
                        colors: [Color(red: 0.6, green: 0.5, blue: 0.9), Color(red: 0.5, green: 0.4, blue: 0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ) {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onHistory()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            )
            .padding(.horizontal, 12)
        }
        .offset(x: 0, y: 50)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(gradient)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isPressed ? Color.black.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Berean Response Mode (Cost Optimization)

enum BereanResponseMode: String, CaseIterable {
    case quick = "Quick Answer"
    case balanced = "Balanced"
    case study = "Deep Study"
    case devotional = "Devotional"
    
    var maxTokens: Int {
        switch self {
        case .quick: return 500        // ~$0.0025 per response
        case .balanced: return 1000    // ~$0.005 per response
        case .study: return 2000       // ~$0.01 per response
        case .devotional: return 800   // ~$0.004 per response
        }
    }
    
    var temperature: Double {
        switch self {
        case .quick: return 0.5        // More deterministic
        case .balanced: return 0.7     // Balanced
        case .study: return 0.7        // Balanced for study
        case .devotional: return 0.8   // More creative for devotionals
        }
    }
    
    var contextWindow: Int {
        switch self {
        case .quick: return 2          // Minimal context
        case .balanced: return 4       // Standard context
        case .study: return 8          // More context for study
        case .devotional: return 3     // Moderate context
        }
    }
    
    var systemPromptSuffix: String {
        switch self {
        case .quick:
            return "Keep answers brief and direct (2-3 sentences). Focus on the core answer."
        case .balanced:
            return "Provide clear, balanced answers with key scripture references."
        case .study:
            return "Provide detailed explanations with historical context, cross-references, and theological insights."
        case .devotional:
            return "Provide encouraging, reflective content focused on personal application and spiritual growth."
        }
    }
    
    var icon: String {
        switch self {
        case .quick: return "bolt.fill"
        case .balanced: return "equal.circle.fill"
        case .study: return "book.fill"
        case .devotional: return "heart.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .quick: return .orange
        case .balanced: return .blue
        case .study: return .purple
        case .devotional: return .pink
        }
    }
}

// MARK: - Berean Personality Mode

/// Controls the persona/voice of Berean AI (not the response depth — that's BereanResponseMode).
/// The selected mode is injected as a prefix in the system prompt so the AI's tone and focus shift.
enum BereanPersonalityMode: String, CaseIterable, Identifiable {
    case shepherd   = "Shepherd"
    case scholar    = "Scholar"
    case coach      = "Coach"
    case builder    = "Builder"
    case strategist = "Strategist"
    case creator    = "Creator"
    case debater    = "Debater"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .shepherd:   return "person.crop.circle.fill"
        case .scholar:    return "graduationcap.fill"
        case .coach:      return "figure.run"
        case .builder:    return "hammer.fill"
        case .strategist: return "checklist"
        case .creator:    return "paintbrush.fill"
        case .debater:    return "text.bubble.fill"
        }
    }

    var description: String {
        switch self {
        case .shepherd:   return "Gentle pastoral guidance"
        case .scholar:    return "Deep theological analysis"
        case .coach:      return "Practical daily application"
        case .builder:    return "Faith-building encouragement"
        case .strategist: return "Structured study planning"
        case .creator:    return "Creative devotional content"
        case .debater:    return "Socratic faith exploration"
        }
    }

    /// Injected at the start of the system prompt to set tone and focus.
    var systemPromptPrefix: String {
        switch self {
        case .shepherd:
            return "You are Berean in Shepherd mode: warm, pastoral, and comforting. " +
                   "Respond like a caring pastor who listens first and grounds every answer in " +
                   "Scripture's comfort and grace."
        case .scholar:
            return "You are Berean in Scholar mode: precise, rigorous, and academically thorough. " +
                   "Prioritize original language insights, historical-grammatical context, and " +
                   "citations from credible theological sources."
        case .coach:
            return "You are Berean in Coach mode: practical, action-oriented, and encouraging. " +
                   "Connect every Scripture answer to a concrete step the user can take today."
        case .builder:
            return "You are Berean in Builder mode: constructive, discipleship-focused, and " +
                   "progressive. Help the user build their faith systematically, brick by brick."
        case .strategist:
            return "You are Berean in Strategist mode: structured, analytical, and goal-oriented. " +
                   "Provide well-organized frameworks for Bible study, prayer plans, or spiritual " +
                   "growth goals."
        case .creator:
            return "You are Berean in Creator mode: imaginative, reflective, and devotional. " +
                   "Craft responses that inspire worship, creativity, and personal meditation on " +
                   "God's Word."
        case .debater:
            return "You are Berean in Debater mode: intellectually rigorous and Socratic. " +
                   "Engage theological questions with careful reasoning, present multiple " +
                   "perspectives fairly, and always anchor conclusions in Scripture."
        }
    }
}



