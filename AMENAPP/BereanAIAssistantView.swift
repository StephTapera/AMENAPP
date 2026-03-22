//
//  BereanAIAssistantView.swift
//  AMENAPP
//
//  Created by Steph on 1/16/26.
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Berean AI Assistant - Your intelligent Bible study companion
struct BereanAIAssistantView: View {
    /// Optional initial query — when set, sent automatically on appear (e.g. from testimony sparkle button)
    var initialQuery: String? = nil
    /// Optional seed message — when set, pre-populates the input field on appear without auto-sending.
    /// Used by BereanInsightCard tap in PostDetailView.
    var seedMessage: String? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase  // FIX 4: Detect background/foreground
    @StateObject private var viewModel = BereanViewModel()
    @StateObject private var notesService = ChurchNotesService()
    @State private var messageText = ""
    @State private var selectedQuickActionCardType: BereanCardType = .generic
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
    @State private var showBereanChatsView = false
    
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
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "bereanOnboardingComplete")
    @State private var showSavedMessages = false
    @State private var showReportIssue = false
    @State private var messageToReport: BereanMessage?
    @State private var showError: BereanError?
    @State private var showErrorBanner = false
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared
    @ObservedObject private var dataManager = BereanDataManager.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    @ObservedObject private var userPreferences = BereanUserPreferences.shared
    
    // Advanced AI features
    @State private var showDevotionalGenerator = false
    @State private var showStudyPlanner = false
    @State private var showScriptureAnalyzer = false
    

    
    // Selah reading view
    @State private var selahMessage: BereanMessage?
    @State private var showSelahView = false
    @State private var selahQuery = ""

    // Folder nav drawer
    @State private var showConversationDrawer = false

    // ✅ Plus button menu
    @State private var showPlusMenu = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?

    // Sermon Snap
    @State private var snapDraft: ChurchNote?
    @State private var showSnapPreview = false
    @State private var showSnapError = false
    @State private var snapErrorMessage = ""
    @StateObject private var snapService = BereanSnapService.shared

    // Sermon Recorder
    @State private var showSermonRecorder = false

    // ✅ Voice input
    @State private var speechRecognizer: SpeechRecognitionService?

    // MARK: - Smart Feature state (PROMPT 1–5)
    @State private var memoryNodes: [BereanMemoryNode] = []
    @State private var followUpSuggestions: [BereanFollowUp] = []
    @State private var showFollowUps = false
    @State private var messageClaims: [UUID: [FactClaim]] = [:]
    
    // ✅ Verse details
    @State private var showVerseDetail = false
    @State private var selectedVerse: String?
    
    // ✅ Response mode for cost-effective AI
    @State private var responseMode: BereanResponseMode = .balanced

    // ✅ Personality mode — controls Berean's voice/tone via system prompt prefix
    @State private var personalityMode: BereanPersonalityMode = .shepherd

    // ✅ Memory status banner
    @State private var showClearSessionConfirm = false
    
    // Regenerate / edit state
    @State private var editingMessage: BereanMessage? = nil  // message currently being edited

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
    @AppStorage("berean_composer_draft") private var composerDraft = ""
    // FIX 4: Persist streaming state across background/foreground transitions
    @AppStorage("berean_partial_response") private var persistedPartialResponse = ""
    @AppStorage("berean_interrupted_query") private var persistedInterruptedQuery = ""
    @State private var streamWasInterrupted = false
    
    // Welcome section animations
    @State private var bibleIconScale: CGFloat = 0.5
    @State private var bibleIconRotation: Double = 0
    @State private var bibleIconOpacity: Double = 0
    @State private var currentWelcomeTextIndex = 0
    @State private var scrollViewOffset: CGFloat = 0
    @State private var shouldCollapseBibleIcon = false
    private let welcomeTexts = [
        "Your intelligent Bible study companion",
        "Ask me anything about Scripture",
        "Deep insights from God's Word",
        "Explore the Bible with AI assistance"
    ]
    
    // Atmospheric background orb animations
    @State private var orbAnimation = false
    @State private var orb2Animation = false
    
    // ✅ Smart contextual suggestions
    @State private var showContextualSuggestions = false
    @State private var contextualSuggestions: [String] = []
    @State private var isTyping = false

    // ── Morphing input bar state ───────────────────────────────────────────
    // Drives the idle pill → expanded text area → searching shimmer capsule
    // → results transition, matching the reference prompt state machine.
    @State private var inputBarExpanded = false    // true when user has typed text
    @State private var shimmerOffset: CGFloat = -1 // animates 0→1 for the searching shimmer
    @State private var inputPulseOn = false        // breathing border pulse when idle
    
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

    // MARK: - Smart Feature helpers (PROMPT 3–5)

    private func buildMemoryNodes() {
        let aiMessages = viewModel.messages.filter { !$0.isFromUser }
        memoryNodes = aiMessages.enumerated().map { index, msg in
            let meta = bereanTopicMeta(for: msg.content)
            return BereanMemoryNode(
                id: msg.id, emoji: meta.emoji, label: meta.label,
                messageIndex: index, color: meta.color, borderColor: meta.border
            )
        }
    }

    private func generateFollowUps(from message: BereanMessage) {
        let lower = message.content.lowercased()
        var suggestions: [BereanFollowUp] = []
        if lower.contains("pray") || lower.contains("prayer") {
            suggestions.append(BereanFollowUp(id: UUID(), icon: "🙏", text: "Daily prayer habit", prompt: "How can I build a consistent daily prayer habit?"))
        }
        if lower.contains("verse") || lower.contains("scripture") || lower.contains("bible") {
            suggestions.append(BereanFollowUp(id: UUID(), icon: "📖", text: "More verses", prompt: "Show me more related Bible verses on this topic."))
        }
        if lower.contains("faith") || lower.contains("trust") || lower.contains("believe") {
            suggestions.append(BereanFollowUp(id: UUID(), icon: "✝️", text: "Strengthen faith", prompt: "How can I strengthen my faith based on what you shared?"))
        }
        if lower.contains("sin") || lower.contains("forgiv") || lower.contains("repent") {
            suggestions.append(BereanFollowUp(id: UUID(), icon: "💚", text: "Forgiveness", prompt: "What does the Bible say about forgiveness and redemption?"))
        }
        if lower.contains("church") || lower.contains("community") || lower.contains("fellowship") {
            suggestions.append(BereanFollowUp(id: UUID(), icon: "🏛️", text: "Church life", prompt: "How can I apply this in my church community?"))
        }
        suggestions.append(BereanFollowUp(id: UUID(), icon: "💡", text: "Go deeper", prompt: "Can you go deeper on what you just shared?"))
        suggestions.append(BereanFollowUp(id: UUID(), icon: "✏️", text: "Summarize", prompt: "Give me a brief summary of the key points."))
        followUpSuggestions = Array(suggestions.prefix(4))
    }

    private func extractClaims(from message: BereanMessage) -> [FactClaim] {
        let sentences = message.content
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 35 }
            .prefix(3)
        return sentences.map { sentence in
            let lower = sentence.lowercased()
            let confidence: Double
            let badge: FactBadge
            if lower.contains("scripture") || lower.contains("verse") || lower.contains("says") || lower.contains("written") || lower.contains("according to") {
                confidence = 0.88; badge = .verified
            } else if lower.contains("often") || lower.contains("many") || lower.contains("traditionally") || lower.contains("generally") {
                confidence = 0.62; badge = .likely
            } else {
                confidence = 0.45; badge = .checkSource
            }
            return FactClaim(id: UUID(), text: String(sentence.prefix(80)), confidence: confidence, badge: badge)
        }
    }

    // Extracted to help the compiler type-check the body expression within time limits.
    private var scrollOffsetTracker: some View {
        BereanScrollOffsetTracker()
    }

    // Base ScrollView with non-proxy modifiers — split out to reduce type-checker load.
    private var chatScrollView: some View {
        let base = SwiftUI.ScrollView(.vertical) {
            chatMessageList
        }
        .coordinateSpace(name: "bereanScroll")
        .refreshable {
            await refreshConversation()
        }
        .onTapGesture {
            isInputFocused = false
        }
        return base
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let scrolledDown = value < -10
                let backAtTop = value > -50
                let collapse = value < -110
                let expand = value > -50
                if collapse && !shouldCollapseBibleIcon {
                    withAnimation(.easeInOut(duration: 0.25)) { shouldCollapseBibleIcon = true }
                } else if expand && shouldCollapseBibleIcon {
                    withAnimation(.easeInOut(duration: 0.25)) { shouldCollapseBibleIcon = false }
                }
                if scrolledDown { userHasScrolledUp = true }
                else if backAtTop { userHasScrolledUp = false }
            }
    }

    // Extracted ScrollView + proxy-dependent modifiers to avoid compiler type-check timeout.
    @ViewBuilder
    private func chatScrollContent(proxy: ScrollViewProxy) -> some View {
        chatScrollView
        .onChange(of: viewModel.messages.count) { _, _ in
            if !userHasScrolledUp, let lastMessage = viewModel.messages.last {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            // PROMPT 3: rebuild memory nodes
            buildMemoryNodes()
            // PROMPT 4 & 5: generate follow-ups and extract claims for new AI messages
            if let last = viewModel.messages.last, !last.isFromUser {
                generateFollowUps(from: last)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showFollowUps = true }
                messageClaims[last.id] = extractClaims(from: last)
            } else {
                withAnimation(.easeOut(duration: 0.2)) { showFollowUps = false }
            }
        }
        .onChange(of: viewModel.messages.last?.content.count) { _, _ in
            guard isGenerating, !userHasScrolledUp,
                  let lastMessage = viewModel.messages.last else { return }
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
        .onChange(of: isInputFocused) { _, newValue in
            if newValue, let lastMessage = viewModel.messages.last {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // Extracted chat message list to avoid compiler type-check timeout in ScrollView body.
    private var chatMessageList: some View {
        VStack(spacing: 20) {
            if viewModel.messages.isEmpty {
                GeometryReader { geo in
                    bereanEmptyStateView
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height * 0.65)
            } else {
                ForEach(viewModel.messages) { message in
                    messageBubbleRow(message: message)
                }
                .environment(\.messageShareHandler) { message in
                    messageToShare = message
                    withAnimation(.easeOut(duration: 0.2)) {
                        showShareSheet = true
                    }
                }
                .environment(\.bereanQuickActionHandler, BereanResponseActionHandler { message, action in
                    handleBereanQuickAction(message: message, action: action)
                })
                .environmentObject(dataManager)
                if isThinking {
                    ThinkingIndicatorView()
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 120)
        .background(scrollOffsetTracker)
    }

    // Extracted ForEach row to avoid compiler type-check timeout in the body.
    @ViewBuilder
    private func messageBubbleRow(message: BereanMessage) -> some View {
        let isLastBerean = !message.isFromUser &&
            viewModel.messages.last(where: { !$0.isFromUser })?.id == message.id &&
            !isGenerating
        MessageBubbleView(
            message: message,
            onOpenSelah: { msg in
                selahQuery = viewModel.messages
                    .last(where: { $0.isFromUser })?.content ?? ""
                selahMessage = msg
                showSelahView = true
            },
            onFollowUp: isLastBerean ? { prompt in
                sendMessage(prompt)
            } : nil,
            onRegenerate: isLastBerean ? {
                regenerateLastResponse()
            } : nil,
            onEdit: message.isFromUser ? { msg in
                beginEditMessage(msg)
            } : nil,
            claims: messageClaims[message.id] ?? []
        )
        .id(message.id)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(.easeOut(duration: 0.2), value: viewModel.messages.count)
    }

    var body: some View {
        ZStack {
            // Clean white background — matches reference image design language
            Color(white: 0.97)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Chat Content
                ScrollViewReader { proxy in
                    chatScrollContent(proxy: proxy)
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
            
            // Conversation Drawer Overlay
            if showConversationDrawer {
                BereanConversationDrawer(
                    isShowing: $showConversationDrawer,
                    conversations: $viewModel.savedConversations,
                    onNewChat: {
                        startNewConversation()
                        showConversationDrawer = false
                    },
                    onSelectConversation: { conversation in
                        viewModel.loadConversation(conversation)
                        showConversationDrawer = false
                    },
                    onDeleteConversation: { conversation in
                        viewModel.deleteConversation(conversation)
                    },
                    onPinConversation: { conversation in
                        viewModel.togglePin(conversation)
                    },
                    onStarConversation: { conversation in
                        viewModel.toggleStar(conversation)
                    },
                    onShowSaved: {
                        showConversationDrawer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showSavedMessages = true
                        }
                    },
                    onShowTranslation: {
                        showConversationDrawer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTranslationPicker = true
                        }
                    },
                    onShowOnboarding: {
                        showConversationDrawer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOnboarding = true
                        }
                    },
                    onClearAll: {
                        showConversationDrawer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showClearAllAlert = true
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(20)
            }
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
        .sheet(isPresented: $showBereanChatsView) {
            BereanChatsListView()
        }
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
            BereanOnboardingView {
                showOnboarding = false
            }
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
                        dlog("Saved prompts tapped")
                    },
                    onSermonRecord: {
                        showSermonRecorder = true
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1000)
            }
        }
        // ✅ Voice Listening Overlay
        .overlay {
            if isVoiceListening, let recognizer = speechRecognizer {
                BereanVoiceListeningOverlay(
                    recognizer: recognizer,
                    onStop: {
                        recognizer.stopRecording()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isVoiceListening = false
                        }
                        if !recognizer.transcribedText.isEmpty {
                            messageText = recognizer.transcribedText
                        }
                    },
                    onCancel: {
                        recognizer.stopRecording()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isVoiceListening = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                .zIndex(2000)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVoiceListening)
        // ✅ Image Picker
        .sheet(isPresented: $showImagePicker) {
            BereanImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                handleImageUpload(image)
            }
        }
        // Sermon Snap preview
        .sheet(isPresented: $showSnapPreview) {
            if let draft = snapDraft {
                SermonNotePreviewSheet(
                    draft: draft,
                    source: .snap,
                    onSave: { savedNote in
                        Task { try? await notesService.createNote(savedNote) }
                        showSnapPreview = false
                    },
                    onDiscard: { showSnapPreview = false }
                )
            }
        }
        .alert("Sermon Snap Error", isPresented: $showSnapError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(snapErrorMessage)
        }
        // Sermon Recorder
        .sheet(isPresented: $showSermonRecorder) {
            SermonRecordingSheet(
                onSave: { draft in
                    guard let uid = Auth.auth().currentUser?.uid else { return }
                    let note = draft.toChurchNote(userId: uid)
                    Task { try? await notesService.createNote(note) }
                    showSermonRecorder = false
                },
                onDismiss: { showSermonRecorder = false }
            )
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

            // Restore composer draft (only when no initialQuery or seedMessage is provided)
            if initialQuery == nil, seedMessage == nil, messageText.isEmpty, !composerDraft.isEmpty {
                messageText = composerDraft
                composerDraft = ""  // clear stored draft once restored
            }

            // Pre-populate input field from seedMessage (does NOT auto-send).
            if let seed = seedMessage, !seed.isEmpty, messageText.isEmpty {
                messageText = seed
                isInputFocused = true
            }

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
            // Persist composer draft so it survives navigation
            composerDraft = messageText
        }
        // FIX 4: Handle streaming reconnect on background/foreground transitions.
        // When the app is backgrounded mid-stream, URLSession is suspended and the
        // response terminates. We save enough state to surface a "Resume" prompt on return.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // If a stream is active, stop generation and persist the partial response
                // so the user doesn't lose context on foreground.
                if isGenerating {
                    // Capture partial content from the last assistant message
                    let partial = viewModel.messages.last(where: { $0.role == .assistant })?.content ?? ""
                    let query = viewModel.messages.last(where: { $0.role == .user })?.content ?? ""
                    if !partial.isEmpty {
                        persistedPartialResponse = partial
                        persistedInterruptedQuery = query
                        streamWasInterrupted = true
                    }
                    viewModel.stopGeneration()
                    withAnimation(.easeOut(duration: 0.3)) {
                        isThinking = false
                        isGenerating = false
                    }
                }
            case .active:
                // If stream was interrupted, show "Tap to continue" so user can re-ask.
                // We don't auto-restart because the stream state is gone; a fresh request
                // is required. The persisted query is restored to the input field so a
                // single tap re-sends it.
                if streamWasInterrupted {
                    streamWasInterrupted = false
                    let savedQuery = persistedInterruptedQuery
                    let savedPartial = persistedPartialResponse
                    persistedPartialResponse = ""
                    persistedInterruptedQuery = ""

                    // Only prompt resume if there was a meaningful partial response
                    if !savedQuery.isEmpty, !savedPartial.isEmpty {
                        messageText = savedQuery
                        // Brief delay so the view is fully active before showing the toast/banner
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showError = .unknown("Response was interrupted. Tap Send to continue.")
                            showErrorBanner = true
                        }
                    }
                }
            default:
                break
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
                dlog("❌ Berean error sharing to feed: \(error.localizedDescription)")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
                
                await MainActor.run {
                    showError = error
                    showErrorBanner = true
                }
            } catch {
                dlog("❌ Failed to share to feed: \(error.localizedDescription)")
                
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
            case .goals:
                sendMessage("Help me set spiritual growth goals")
            case .shield:
                sendMessage("Show me how to guard my heart spiritually")
            case .tabSwitcher:
                sendMessage("Help me organize my Bible study tabs")
            case .compassAlert:
                sendMessage("Guide me in my spiritual direction")
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left: chevron dismiss — ghost button, low-key
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .frame(minWidth: 52, alignment: .leading)

                Spacer()

                // Center: minimal wordmark or thinking state
                VStack(spacing: 2) {
                    if isGenerating || isThinking {
                        HStack(spacing: 5) {
                            HStack(spacing: 3) {
                                ForEach(0..<3, id: \.self) { i in
                                    HeaderThinkingDot(index: i, isActive: isGenerating || isThinking)
                                }
                            }
                            Text("Thinking")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BereanDesign.coral)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.90)))
                    } else {
                        // Dia-style: just the name, clean serif, no orb dot when in conversation
                        Text("Berean")
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundStyle(Color(white: 0.18))
                            .tracking(0.2)
                            // Show brand name in header only when scrolled (conversation active)
                            // In welcome state the hero headline already shows the name
                            .opacity(shouldCollapseBibleIcon ? 1 : 0)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.80), value: isGenerating || isThinking)
                .animation(.easeInOut(duration: 0.22), value: shouldCollapseBibleIcon)

                Spacer()

                // Right: folder / conversations
                settingsMenuButton
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Header backdrop appears only when scrolled — matches Dia's transparent-to-glass transition
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(shouldCollapseBibleIcon ? 0.88 : 0.0)
                    .animation(.easeInOut(duration: 0.28), value: shouldCollapseBibleIcon)
                    .ignoresSafeArea(edges: .top)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(shouldCollapseBibleIcon ? 0.05 : 0.0))
                    .frame(height: 0.5)
                    .animation(.easeInOut(duration: 0.28), value: shouldCollapseBibleIcon)
            }
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
    
    // MARK: - Folder Nav Button (replaces 3-dot menu)

    private var settingsMenuButton: some View {
        HStack(spacing: 8) {
            // Chats history — opens BereanChatsView
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showBereanChatsView = true
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(white: 0.26))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.07), radius: 5, y: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open chat history")

            folderNavButton
        }
    }

    private var folderNavButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                showConversationDrawer = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(white: 0.26))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
                    )

                // Unread badge — shows when there are saved conversations
                if !viewModel.savedConversations.isEmpty {
                    Circle()
                        .fill(BereanDesign.coral)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: -1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open conversation organizer")
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
    
    // MARK: - Empty State (centered animation shown before first message)

    private var bereanEmptyStateView: some View {
        BereanPremiumLandingView(
            personalityMode: $personalityMode,
            onQuickAction: { prompt in
                if prompt.isEmpty {
                    isInputFocused = true
                } else {
                    sendMessage(prompt)
                }
            },
            isActive: isGenerating || isThinking,
            onOrbTap: {
                if isGenerating || isThinking {
                    stopGeneration()
                } else {
                    isInputFocused = true
                }
            }
        )
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
                        .foregroundStyle(personalityMode == mode ? .white : Color(white: 0.38))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(personalityMode == mode
                                    ? LinearGradient(
                                        colors: [
                                            Color(red: 0.88, green: 0.38, blue: 0.28),
                                            Color(red: 0.72, green: 0.28, blue: 0.45)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                      )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.75)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                      )
                                )
                                .shadow(
                                    color: personalityMode == mode
                                        ? Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.25)
                                        : .clear,
                                    radius: 6, y: 2
                                )
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
            // PROMPT 3: Memory nodes strip — shown above session counter when there are AI messages
            if !memoryNodes.isEmpty && messageText.isEmpty {
                BereanMemoryStripView(nodes: memoryNodes) { node in
                    // Scroll to the referenced message index if possible
                }
            }

            // Memory status banner — shown when there are messages and input is empty
            if !viewModel.messages.isEmpty && messageText.isEmpty {
                memoryStatusBanner
            }

            // PROMPT 4: Smart follow-up chips — shown above composer after AI responds
            if showFollowUps && !followUpSuggestions.isEmpty && messageText.isEmpty {
                BereanFollowUpView(suggestions: followUpSuggestions) { item in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    messageText = item.prompt
                    isInputFocused = true
                    withAnimation(.easeOut(duration: 0.2)) { showFollowUps = false }
                }
            }

            // Quick Action chips — shown above composer when no conversation is active
            if viewModel.messages.isEmpty && messageText.isEmpty {
                BereanQuickActionsView(
                    inputText: $messageText,
                    selectedCardType: $selectedQuickActionCardType
                ) { chip in
                    messageText = chip.prompt
                    isInputFocused = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Smart Contextual Suggestions — rises from input when typing
            if showContextualSuggestions && !contextualSuggestions.isEmpty && viewModel.messages.isEmpty {
                contextualSuggestionsView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // PROMPT 2: Live waveform bar — overlays input area during voice recording
            BereanWaveformBar(isActive: isVoiceListening)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            // ── Composer card — matches reference image design ─────────────
            premiumComposerCard
                .padding(.horizontal, 10)
        }
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .animation(.spring(response: 0.40, dampingFraction: 0.80), value: messageText.isEmpty)
    }

    // Composer card — exact match to reference images:
    // white card, text area top, hairline divider, icon tray + Liquid Glass send button bottom
    @ViewBuilder
    private var premiumComposerCard: some View {
        VStack(spacing: 0) {
            // Upper zone — text input, expands vertically
            textInputFieldGlassmorphic
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Hairline divider
            composerDivider

            // Lower zone — icon tray + send/voice/stop button
            composerIconRow
        }
        .background(composerBackground)
        // Breathing pulse border when idle, sharp border when focused
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isInputFocused
                        ? Color.black.opacity(0.22)
                        : Color.black.opacity(inputPulseOn ? 0.14 : 0.0),
                    lineWidth: 1.5
                )
                .animation(
                    isInputFocused
                        ? .easeOut(duration: 0.3)
                        : .easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                    value: isInputFocused ? isInputFocused : inputPulseOn
                )
        )
        // Subtle glow on focus
        .shadow(
            color: Color.black.opacity(isInputFocused ? 0.06 : 0),
            radius: isInputFocused ? 8 : 0, x: 0, y: 0
        )
        .animation(.easeOut(duration: 0.35), value: isInputFocused)
        .onChange(of: isInputFocused) { _, focused in
            if focused {
                inputPulseOn = false
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    inputPulseOn = true
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                inputPulseOn = true
            }
        }
    }

    private var composerDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 0)
    }

    private var composerIconRow: some View {
        HStack(spacing: 0) {
            // Paperclip / attachment — matches reference image left icon
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handlePlusButtonTap()
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(white: 0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isGenerating)
            .opacity(isGenerating ? 0.3 : 1.0)
            .accessibilityLabel("Add attachment")

            // Globe / search — matches reference image second icon
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSmartFeatures = true
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(white: 0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isGenerating)
            .opacity(isGenerating ? 0.3 : 1.0)
            .accessibilityLabel("Search scripture")

            Spacer()

            // Send / Voice / Stop — Liquid Glass blue pill (right-anchored)
            actionButtonGlassmorphic
                .padding(.trailing, 8)
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
    }

    private var composerBackground: some View {
        // Clean white card matching reference images — subtle border + soft shadow
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.09), radius: 18, y: 5)
            .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
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
                    .foregroundStyle(responseMode == mode ? .white : .black.opacity(0.55))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                responseMode == mode
                                    ? AnyShapeStyle(mode.color)
                                    : AnyShapeStyle(Color.white.opacity(0.6))
                            )
                            .shadow(
                                color: responseMode == mode ? mode.color.opacity(0.3) : .clear,
                                radius: 5, y: 2
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
    
    private var textInputFieldGlassmorphic: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Berean...", text: $messageText, axis: .vertical)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(white: 0.10))
                // Grows up to 6 lines — elastic spring handles the container expansion
                .lineLimit(1...6)
                .focused($isInputFocused)
                .disabled(isGenerating)
                .tint(Color(red: 0.35, green: 0.62, blue: 0.98))
                .onSubmit {
                    if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage(messageText)
                    }
                }
                .submitLabel(.send)
                .accessibilityLabel("Message input field")
                .onChange(of: messageText) { _, newValue in
                    // Update expanded state — drives the elastic container growth
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.80)) {
                        inputBarExpanded = !newValue.isEmpty
                    }
                    isTyping = !newValue.isEmpty
                    // Debounce suggestions — 400ms
                    suggestionDebounceTask?.cancel()
                    suggestionDebounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        generateContextualSuggestions(for: newValue)
                    }
                }

            // Sparkle indicator — appears when AI has suggestions ready
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
        // Elastic vertical growth — the container animates its height as lineLimit expands
        .animation(.spring(response: 0.50, dampingFraction: 0.80), value: messageText)
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
                // Dark circle — clean, matches the card's minimal style
                Circle()
                    .fill(Color(white: isVoiceListening ? 0.08 : 0.14))
                    .frame(width: 36, height: 36)

                // Listening pulse ring
                if isVoiceListening {
                    Circle()
                        .stroke(Color(red: 0.35, green: 0.62, blue: 0.98).opacity(0.55), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(1.25)
                        .opacity(0)
                        .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isVoiceListening)
                }

                Image(systemName: isVoiceListening ? "waveform" : "mic")
                    .font(.system(size: 15, weight: .medium))
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
            // Liquid Glass blue pill — matches reference images (IMG_1207, IMG_1326)
            ZStack {
                // Glass base: radial gradient from light blue center to deeper blue edge
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.82, blue: 1.00),
                                Color(red: 0.35, green: 0.62, blue: 0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        // Inner highlight — top specular reflection (glassy sheen)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        // Outer ring — subtle blue border
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(red: 0.30, green: 0.58, blue: 0.95).opacity(0.5), lineWidth: 1.0)
                    )
                    .shadow(color: Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.35), radius: 8, y: 3)
                    .frame(width: 72, height: 36)

                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: !messageText.isEmpty)
        .accessibilityLabel("Send message")
    }

    private var stopButtonGlassmorphic: some View {
        Button {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            stopGeneration()
        } label: {
            ZStack {
                // Outlined circle — white fill, thin border, matches the card's clean style
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .frame(width: 36, height: 36)

                // Square stop icon
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(white: 0.15))
                    .frame(width: 13, height: 13)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isGenerating)
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
        dlog("➕ Plus button tapped - Show attachment options")
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
            dlog("❌ Cannot retry - no network connection")
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
            dlog("⚠️ No message to retry")
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
        
        dlog("🔄 Retrying message: \(messageToRetry.prefix(50))...")
        
        // ✅ Implement exponential backoff for retries
        let backoffDelay = pow(2.0, Double(min(retryAttempts, maxRetryAttempts))) * 0.5
        retryAttempts += 1
        
        if retryAttempts > maxRetryAttempts {
            dlog("⚠️ Max retry attempts reached, resetting counter")
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
        dlog("🔄 Refreshing conversation...")
        
        // Add small delay for smooth pull-to-refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Note: Current messages are already live-updated through @Published properties
        // This refresh mainly provides user feedback that the action was acknowledged
        
        // Haptic feedback to indicate refresh completion
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        dlog("✅ Conversation refreshed")
    }
    
    /// Regenerate the last Berean response
    private func regenerateLastResponse() {
        guard !isGenerating else { return }
        if let query = viewModel.popLastAssistantMessage(), !query.isEmpty {
            // Remove any optimistic user-message duplicate then re-send
            sendMessage(query, isRetry: true)
        }
    }

    /// Begin editing a user message: rewind thread and populate the composer
    private func beginEditMessage(_ message: BereanMessage) {
        guard !isGenerating else { return }
        let content = message.content
        viewModel.editUserMessage(at: message.id, newContent: content)
        messageText = content
        isInputFocused = true
        editingMessage = message
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
        
        dlog("✅ New conversation started")
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
        
        dlog("✅ All data cleared successfully")
    }
    
    /// Handle Berean quick-action chip taps
    private func handleBereanQuickAction(message: BereanMessage, action: BereanResponseAction) {
        switch action {
        case .saveToNotes:
            // Save to BereanDataManager saved messages with a "notes" tag
            dataManager.saveMessage(message, tags: ["notes"])
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .shareAsPost:
            messageToShare = message
            withAnimation(.easeOut(duration: 0.2)) {
                showShareSheet = true
            }

        case .turnIntoPrayer, .applyPractically, .journalPrompt:
            // Send the associated follow-up prompt as a new message
            let prompt = action.followUpPrompt
            guard !prompt.isEmpty else { return }
            sendMessage(prompt)
        }
    }

    /// Handle image upload via Sermon Snap: uploads to Storage → Claude vision → preview sheet
    private func handleImageUpload(_ image: UIImage) {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        Task {
            do {
                let draft = try await BereanSnapService.shared.processSermonImage(image)
                await MainActor.run {
                    snapDraft = draft
                    showSnapPreview = true
                }
            } catch {
                await MainActor.run {
                    snapErrorMessage = error.localizedDescription
                    showSnapError = true
                }
            }
        }
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
            dlog("⚠️ Cannot send empty message")
            return
        }
        
        // ✅ P0-1: Enhanced duplicate protection with request ID
        if !isRetry {
            // Check if this is a duplicate of the last sent message
            if trimmedText == lastSentMessageText {
                dlog("⚠️ Duplicate message detected, ignoring")
                return
            }
            
            // Check debounce interval
            if let lastTime = lastSentTime, Date().timeIntervalSince(lastTime) < sendDebounceInterval {
                dlog("⚠️ Message sent too quickly, debouncing")
                return
            }
        }
        
        // ✅ P0-2: Prevent sending if already generating
        guard !isGenerating else {
            dlog("⚠️ Already generating response, ignoring new message")
            return
        }
        
        // ✅ Check if there's a pending request in the ViewModel
        guard viewModel.pendingRequestId == nil else {
            dlog("⚠️ Request already in flight, ignoring duplicate")
            return
        }
        
        // ✅ Check Premium limits FIRST
        guard premiumManager.canSendMessage() else {
            dlog("❌ Message limit reached")
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
            dlog("❌ No network connection")
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
            composerDraft = ""  // clear saved draft on successful send
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
            // Combine personality voice with personalization preferences suffix
            personalityPrefix: [personalityMode.systemPromptPrefix, userPreferences.systemPromptSuffix]
                .filter { !$0.isEmpty }.joined(separator: " "),
            onChunk: { chunk in
                // Preserve the existing message ID so SwiftUI treats this as an in-place
                // update rather than a remove+insert cycle. Without preserving the ID,
                // MessageBubbleView is destroyed and recreated on every chunk, which
                // triggers the .onAppear entrance animation and causes the blink.
                // NOTE: onChunk is always called on MainActor by generateResponseStreaming.
                if let lastIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }) {
                    let existingMessage = viewModel.messages[lastIndex]
                    let updatedMessage = BereanMessage(
                        id: existingMessage.id,  // preserve ID — prevents view recreation
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
                    dlog("📊 Message count updated: \(premiumManager.freeMessagesUsed)/\(premiumManager.FREE_MESSAGES_PER_DAY)")
                    
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
                        
                        dlog("⚡ Performance: Response time: \(String(format: "%.2f", responseTime))s | Avg: \(String(format: "%.2f", performanceMetrics.averageResponseTime))s | Fastest: \(String(format: "%.2f", performanceMetrics.fastestResponse))s | Slowest: \(String(format: "%.2f", performanceMetrics.slowestResponse))s")
                        
                        // ✅ Log warning if response is slow (> 5s)
                        if responseTime > 5.0 {
                            dlog("⚠️ Slow response detected: \(String(format: "%.2f", responseTime))s")
                        }
                    }
                    
                    // Success haptic
                    let successHaptic = UINotificationFeedbackGenerator()
                    successHaptic.notificationOccurred(.success)
                    
                    dlog("✅ Message sent and response received successfully")
                }
            },
            onError: { error in
                Task { @MainActor in
                    dlog("❌ Error generating response: \(error.localizedDescription)")
                    
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

// MARK: - Berean Light Action Card (editorial, minimal)

// MARK: - Berean Quick Chip (horizontal scroll action)

struct BereanQuickChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.30))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.22))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.80))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.07), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { isPressed = pressing }
        }, perform: {})
    }
}

struct BereanLightActionCard: View {
    let icon: String
    let title: String
    let accentColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.85))
                
                Spacer()
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.22))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 96)
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.055), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
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
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: 12) {
                Text(prompt)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.25))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 0.75, dash: [4, 3])
                            )
                            .foregroundStyle(Color.black.opacity(0.10))
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.82 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.18)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: BereanMessage
    var onOpenSelah: ((BereanMessage) -> Void)? = nil
    /// Called when user taps a follow-up action chip. Receives the pre-composed prompt text.
    var onFollowUp: ((String) -> Void)? = nil
    /// Called when user taps "Regenerate" on the last assistant message.
    var onRegenerate: (() -> Void)? = nil
    /// Called when user taps "Edit" on a user message.
    var onEdit: ((BereanMessage) -> Void)? = nil
    /// PROMPT 5: fact confidence claims extracted from this message
    var claims: [FactClaim] = []
    @State private var showActions = false
    @State private var lightbulbPressed = false
    @State private var praisePressed = false
    @State private var messageToReport: BereanMessage?
    @State private var showReportIssue = false
    @State private var appeared = false
    @State private var showFollowUpRow = false
    @State private var copied = false   // brief checkmark flash after copy
    @State private var showQuickActions = false
    // PROMPT 1: long-press action menu
    @State private var showMessageMenu = false
    @State private var menuScale: CGFloat = 0.92
    @State private var menuOpacity: Double = 0
    @Environment(\.messageShareHandler) private var shareHandler
    @Environment(\.bereanQuickActionHandler) private var quickActionEnv
    @EnvironmentObject private var dataManager: BereanDataManager

    var body: some View {
        // User messages: right-aligned bubble. Berean messages: full-width editorial layout.
        Group {
            if message.isFromUser {
                userMessageBubble
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : 24)
                    .scaleEffect(appeared ? 1 : 0.94, anchor: .bottomTrailing)
            } else {
                bereanMessageBlock
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -24)
                    .scaleEffect(appeared ? 1 : 0.94, anchor: .bottomLeading)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: appeared)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }

    // MARK: User bubble — compact, right-aligned
    private var userMessageBubble: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 56)

            VStack(alignment: .trailing, spacing: 4) {
                // Label
                Text("You")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.trailing, 2)

                // Bubble
                Text(message.content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(white: 0.14))
                    .lineSpacing(6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.black.opacity(0.045), lineWidth: 0.6)
                            )
                            .shadow(color: Color.black.opacity(0.055), radius: 10, y: 3)
                    )

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(white: 0.52))
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 18)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22).delay(0.04)) {
                appeared = true
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if let onEdit {
                Button {
                    onEdit(message)
                } label: {
                    Label("Edit Message", systemImage: "pencil")
                }
            }
        }
    }

    // MARK: Berean message — full-width, editorial layout
    private var bereanMessageBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Berean label + scripture chip
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(BereanDesign.coralSoft.opacity(0.80))
                    Text("Berean")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.42))
                        .textCase(.uppercase)
                        .tracking(1.4)
                }
                // Scripture-based chip — shown for every Berean response
                BereanStatusChip(style: .scripture)
            }
            .padding(.bottom, 10)

            // Main content — no bubble, full-width editorial text
            VStack(alignment: .leading, spacing: 0) {
                // Message text — clean, readable
                Text(message.content)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.14))
                    .lineSpacing(9)
                    .fixedSize(horizontal: false, vertical: true)

                // Verse references — shown below content as tappable chips
                if !message.verseReferences.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(message.verseReferences, id: \.self) { reference in
                                VerseReferenceChip(reference: reference)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.top, 14)
                }

                // Action row — reactions, share, more
                HStack(spacing: 8) {
                    // Lightbulb
                    SmartReactionButton(
                        icon: "lightbulb.fill",
                        activeColor: Color(red: 1.0, green: 0.7, blue: 0.4),
                        isActive: lightbulbPressed
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            lightbulbPressed.toggle()
                        }
                    }

                    // Amen / praise
                    SmartReactionButton(
                        icon: "hands.clap.fill",
                        activeColor: Color(red: 0.5, green: 0.6, blue: 0.9),
                        isActive: praisePressed
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            praisePressed.toggle()
                        }
                    }

                    // Selah — for longer responses
                    if message.content.count > 400 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onOpenSelah?(message)
                        } label: {
                            HStack(spacing: 3) {
                                Image("amen-logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
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

                    // Copy — visible inline button with flash feedback
                    Button {
                        UIPasteboard.general.string = message.content
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.15)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.2)) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(copied ? Color(red: 0.3, green: 0.75, blue: 0.5) : Color(white: 0.5))
                            .frame(width: 28, height: 28)
                            .animation(.easeOut(duration: 0.15), value: copied)
                    }

                    // Share to feed
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        shareHandler?(message)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 28, height: 28)
                    }

                    // Regenerate (only shown when callback is provided, i.e., last message)
                    if let onRegenerate {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onRegenerate()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.5))
                                .frame(width: 28, height: 28)
                        }
                    }

                    // More options
                    Menu {
                        Button {
                            let content = message.content
                            Task.detached(priority: .userInitiated) {
                                await MainActor.run {
                                    UIPasteboard.general.string = content
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            }
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                        }

                        Button {
                            dataManager.saveMessage(message)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label("Save for Later", systemImage: "bookmark")
                        }

                        Divider()

                        Button(role: .destructive) {
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
                .padding(.top, 14)
            }

            // Timestamp
            Text(message.timestamp, style: .time)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color(white: 0.52))
                .padding(.top, 6)

            // Follow-up action row — appears after a brief settle delay
            if showFollowUpRow, let followUp = onFollowUp {
                BereanFollowUpActionsRow(
                    onExplainMore: { followUp("Can you explain that in more depth?") },
                    onShowVerses:  { followUp("Show me related Bible verses for this.") },
                    onSummarize:   { followUp("Can you give me a brief summary?") },
                    onReflect:     { followUp("Help me reflect personally on what you just shared.") }
                )
                .padding(.horizontal, -22) // bleed to edge so pills don't feel inset
            }

            // Berean quick-action row — spiritual actions on this response
            if showQuickActions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BereanResponseAction.allCases, id: \.self) { action in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                quickActionEnv(message, action)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: action.icon)
                                        .font(.system(size: 11, weight: .medium))
                                    Text(action.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(Color(white: 0.3))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color(white: 0.93))
                                        .overlay(Capsule().stroke(Color(white: 0.86), lineWidth: 0.5))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -22)
                .padding(.top, 6)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // PROMPT 5: Fact Shield — confidence indicators
            if !claims.isEmpty {
                BereanFactShieldView(claims: claims)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28).delay(0.03)) {
                appeared = true
            }
            // Delay follow-up row so it doesn't compete visually with the entrance
            if onFollowUp != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showFollowUpRow = true
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showQuickActions = true
                    }
                }
            }
        }
        // Report issue sheet
        .sheet(isPresented: $showReportIssue) {
            if let msg = messageToReport {
                BereanReportIssueView(message: msg, isPresented: $showReportIssue)
            }
        }
        // PROMPT 1: Long-press message action menu
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !message.isFromUser else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            menuScale = 0.88
            menuOpacity = 0
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                showMessageMenu = true
                menuScale = 1.0
                menuOpacity = 1.0
            }
        }
        .overlay(alignment: .topLeading) {
            if showMessageMenu && !message.isFromUser {
                BereanMessageMenuView(
                    message: message.content,
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showMessageMenu = false
                        }
                    },
                    onPostToAMEN: { _ in }
                )
                .scaleEffect(menuScale, anchor: .bottomLeading)
                .opacity(menuOpacity)
                .offset(x: 22, y: -54)
                .zIndex(100)
            }
        }
        .onTapGesture {
            if showMessageMenu {
                withAnimation(.easeOut(duration: 0.18)) { showMessageMenu = false }
            }
        }
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

// MARK: - Berean Response Action (quick-action chips on responses)

enum BereanResponseAction: String, CaseIterable {
    case turnIntoPrayer   = "Turn into prayer"
    case saveToNotes      = "Save to Notes"
    case applyPractically = "Apply this"
    case journalPrompt    = "Journal prompt"
    case shareAsPost      = "Share insight"

    var icon: String {
        switch self {
        case .turnIntoPrayer:   return "hands.sparkles"
        case .saveToNotes:      return "note.text.badge.plus"
        case .applyPractically: return "figure.walk"
        case .journalPrompt:    return "pencil.and.scribble"
        case .shareAsPost:      return "arrow.up.circle"
        }
    }

    var followUpPrompt: String {
        switch self {
        case .turnIntoPrayer:
            return "Turn the insight you just shared into a heartfelt prayer I can pray."
        case .saveToNotes:
            return "" // handled specially in the view (saves, no new query)
        case .applyPractically:
            return "Give me 3 practical ways I can apply what you just shared to my daily life."
        case .journalPrompt:
            return "Give me a meaningful journal reflection prompt based on what you just shared."
        case .shareAsPost:
            return "" // handled specially (opens share sheet)
        }
    }
}

// MARK: - Berean Response Action Environment Key

private struct BereanResponseActionHandlerKey: EnvironmentKey {
    static let defaultValue: BereanResponseActionHandler = .init(nil)
}

struct BereanResponseActionHandler {
    let action: ((BereanMessage, BereanResponseAction) -> Void)?
    init(_ action: ((BereanMessage, BereanResponseAction) -> Void)?) {
        self.action = action
    }
    func callAsFunction(_ message: BereanMessage, _ responseAction: BereanResponseAction) {
        action?(message, responseAction)
    }
}

extension EnvironmentValues {
    var bereanQuickActionHandler: BereanResponseActionHandler {
        get { self[BereanResponseActionHandlerKey.self] }
        set { self[BereanResponseActionHandlerKey.self] = newValue }
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
        
        dlog("📖 Navigating to verse: \(reference)")
    }
}

// MARK: - Thinking Indicator

// MARK: - Header thinking dot (tiny, for header status bar)

struct HeaderThinkingDot: View {
    let index: Int
    let isActive: Bool
    @State private var phase = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.88, green: 0.38, blue: 0.28))
            .frame(width: 4, height: 4)
            .scaleEffect(phase ? 1.4 : 0.7)
            .opacity(phase ? 1.0 : 0.35)
            .onAppear {
                guard isActive else { return }
                let delay = Double(index) * 0.18
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(
                        .easeInOut(duration: 0.55)
                        .repeatForever(autoreverses: true)
                    ) { phase = true }
                }
            }
            .onChange(of: isActive) { _, active in
                if !active { withAnimation { phase = false } }
            }
    }
}

// MARK: - Thinking Indicator (3-dot typing animation)
//
// Simple ChatGPT-style three-dot bouncing indicator.
// Each dot fades and shifts up in sequence with a staggered delay.

struct ThinkingIndicatorView: View {

    @State private var animating = false

    private let dotSize: CGFloat = 8
    private let dotSpacing: CGFloat = 5
    private let bounceHeight: CGFloat = 5
    private let dotColor = Color(white: 0.55)

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Left-aligned like a received message
            HStack(spacing: dotSpacing) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .offset(y: animating ? -bounceHeight : 0)
                        .opacity(animating ? 1.0 : 0.45)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.16),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

// MARK: - Voice Listening Overlay

struct BereanVoiceListeningOverlay: View {
    @ObservedObject var recognizer: SpeechRecognitionService
    let onStop: () -> Void
    let onCancel: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var appeared = false

    private let coral = Color(red: 0.88, green: 0.38, blue: 0.28)

    var body: some View {
        ZStack {
            // Background blur + tint
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                Spacer()

                // Orb + atmospheric pulse rings
                ZStack {
                    // Outermost soft ring
                    Circle()
                        .stroke(Color(white: 0.78).opacity(0.18), lineWidth: 1)
                        .frame(width: 230, height: 230)
                        .scaleEffect(appeared ? pulseScale * 1.12 : 0.7)
                        .opacity(appeared ? 1 : 0)

                    // Middle ring
                    Circle()
                        .stroke(Color(white: 0.70).opacity(0.22), lineWidth: 1.2)
                        .frame(width: 168, height: 168)
                        .scaleEffect(appeared ? pulseScale * 1.06 : 0.7)
                        .opacity(appeared ? 1 : 0)

                    // Soft lavender glow disc behind orb — intensifies when recording
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.80, green: 0.78, blue: 0.96)
                                        .opacity(recognizer.isRecording ? 0.28 : 0.12),
                                    Color.clear
                                ],
                                center: .center, startRadius: 0, endRadius: 58
                            )
                        )
                        .frame(width: 118, height: 118)
                        .scaleEffect(appeared ? 1.0 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: recognizer.isRecording)

                    // Pearl orb — active (shimmer + faster pulse) while recording
                    BereanOrbView(isActive: recognizer.isRecording)
                        .scaleEffect(appeared ? 1.0 : 0.5)
                        .opacity(appeared ? 1 : 0)
                }
                .padding(.bottom, 36)

                // Live transcription or prompt
                VStack(spacing: 8) {
                    if recognizer.transcribedText.isEmpty {
                        Text("Listening…")
                            .font(.system(size: 22, weight: .light, design: .serif))
                            .foregroundStyle(Color(white: 0.18))
                    } else {
                        Text(recognizer.transcribedText)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color(white: 0.15))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(.horizontal, 40)
                            .transition(.opacity)
                    }

                    Text("Speak your question")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(white: 0.55))
                        .opacity(recognizer.transcribedText.isEmpty ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.25), value: recognizer.transcribedText)
                .padding(.bottom, 52)

                // Action buttons
                HStack(spacing: 20) {
                    // Cancel
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 13)
                            .background(
                                Capsule()
                                    .fill(Color(white: 0.92))
                            )
                    }

                    // Stop / use result
                    Button(action: onStop) {
                        HStack(spacing: 6) {
                            Image(systemName: recognizer.transcribedText.isEmpty ? "stop.circle" : "checkmark")
                                .font(.system(size: 14, weight: .medium))
                            Text(recognizer.transcribedText.isEmpty ? "Stop" : "Use")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(coral)
                                .shadow(color: coral.opacity(0.35), radius: 10, y: 4)
                        )
                    }
                }
                .padding(.bottom, 60)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                appeared = true
            }
            withAnimation(
                .easeInOut(duration: 1.6)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.08
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
struct BereanMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let content: String
    let role: MessageRole
    let timestamp: Date
    var verseReferences: [String]
    /// User feedback on this message: nil = no feedback yet, true = thumbs up, false = thumbs down
    var feedback: Bool?
    /// Whether the user has bookmarked this specific response for quick reference
    var isBookmarked: Bool

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
               lhs.verseReferences == rhs.verseReferences &&
               lhs.feedback == rhs.feedback &&
               lhs.isBookmarked == rhs.isBookmarked
    }

    init(id: UUID = UUID(), content: String, role: MessageRole, timestamp: Date,
         verseReferences: [String] = [], feedback: Bool? = nil, isBookmarked: Bool = false) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.feedback = feedback
        self.isBookmarked = isBookmarked
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
    case goals = "Goals"
    case shield = "Shield"
    case tabSwitcher = "Tab Switcher"
    case compassAlert = "Compass"
    
    var icon: String {
        switch self {
        case .crossReference: return "link.circle.fill"
        case .greekHebrew: return "character.book.closed.fill"
        case .historicalTimeline: return "calendar.circle.fill"
        case .characterStudy: return "person.crop.circle.fill"
        case .theologicalThemes: return "books.vertical.circle.fill"
        case .verseOfDay: return "sun.horizon.circle.fill"
        case .goals: return "target"
        case .shield: return "shield.fill"
        case .tabSwitcher: return "square.grid.2x2.fill"
        case .compassAlert: return "location.circle.fill"
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
        case .goals: return Color(red: 0.4, green: 0.8, blue: 0.6) // Soft green
        case .shield: return Color(red: 0.3, green: 0.5, blue: 0.9) // Deep blue
        case .tabSwitcher: return Color(red: 0.7, green: 0.5, blue: 0.9) // Purple
        case .compassAlert: return Color(red: 0.9, green: 0.5, blue: 0.5) // Soft red
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

@MainActor
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
    
    /// Save current conversation to history (uses a fast fallback title,
    /// then patches it asynchronously with an AI-generated title).
    func saveCurrentConversation() {
        guard !messages.isEmpty else {
            dlog("⚠️ No messages to save")
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
        dlog("✅ Conversation saved: \(conversation.title)")

        // Kick off AI title generation in background; it will patch the stored record when done
        generateAITitle(for: conversation.id)
    }
    
    /// Load a saved conversation
    func loadConversation(_ conversation: SavedConversation) {
        messages = conversation.messages
        selectedTranslation = conversation.translation
        dlog("📖 Loaded conversation: \(conversation.title)")
    }
    
    /// Delete a conversation
    func deleteConversation(_ conversation: SavedConversation) {
        savedConversations.removeAll { $0.id == conversation.id }
        saveConversationsToUserDefaults()
        deleteConversationFromFirestore(conversation)
        dlog("🗑️ Deleted conversation: \(conversation.title)")
    }

    /// Toggle pin state for a conversation
    func togglePin(_ conversation: SavedConversation) {
        guard let index = savedConversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        savedConversations[index].isPinned.toggle()
        // Re-sort: pinned first, then by date descending
        savedConversations.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.date > $1.date
        }
        saveConversationsToUserDefaults()
    }

    /// Toggle star state for a conversation
    func toggleStar(_ conversation: SavedConversation) {
        guard let index = savedConversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        savedConversations[index].isStarred.toggle()
        saveConversationsToUserDefaults()
    }
    
    /// Update conversation title
    func updateConversationTitle(_ conversation: SavedConversation, newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dlog("⚠️ Cannot update with empty title")
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
            dlog("✏️ Updated conversation title: \(newTitle)")
        }
    }
    
    /// Clear current messages
    func clearMessages() {
        messages = []
        dlog("🗑️ Messages cleared")
    }

    /// Remove the last assistant message so the caller can re-run generation.
    /// Returns the last user query string (to re-send), or nil if nothing to regenerate.
    @discardableResult
    func popLastAssistantMessage() -> String? {
        // Remove trailing assistant message(s)
        while messages.last?.role == .assistant {
            messages.removeLast()
        }
        // Return the user query that preceded them
        return messages.last(where: { $0.role == .user })?.content
    }

    /// Edit the most recent user message: trims messages back to that point
    /// and returns the edited text so the caller can re-send.
    func editUserMessage(at messageId: UUID, newContent: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        // Keep everything up to (but not including) the target message
        messages = Array(messages.prefix(idx))
        dlog("✏️ User message edited — thread rewound to \(idx) messages")
    }
    
    /// Clear all data (conversations + messages)
    func clearAllData() {
        messages = []
        savedConversations = []
        UserDefaults.standard.removeObject(forKey: "berean_conversations")
        dlog("🗑️ All data cleared")
    }
    
    /// Generate a short fallback title from the first user message (no network needed)
    private func generateConversationTitle() -> String {
        let firstUserMessage = messages.first(where: { $0.role == .user })
        let content = firstUserMessage?.content ?? "Conversation"
        let title = String(content.prefix(50))
        return title.count < content.count ? title + "..." : title
    }

    /// Ask the AI to produce a 4-6 word title for the current conversation,
    /// then update the most-recent saved conversation in place.
    func generateAITitle(for conversationId: UUID) {
        // Build a compact summary of the exchange (first user + first assistant turn)
        let userSnippet  = messages.first(where: { $0.role == .user })?.content.prefix(300) ?? ""
        let replySnippet = messages.first(where: { $0.role == .assistant })?.content.prefix(300) ?? ""
        guard !userSnippet.isEmpty else { return }

        Task {
            let prompt = """
            Create a 4–6 word title for this conversation. Return ONLY the title, no quotes, no punctuation at the end.

            User: \(userSnippet)
            Assistant: \(replySnippet)
            """
            do {
                let raw = try await genkitService.sendMessageSync(prompt, mode: .shepherd)
                let title = raw
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\n").first ?? raw
                await MainActor.run {
                    if let idx = self.savedConversations.firstIndex(where: { $0.id == conversationId }) {
                        self.savedConversations[idx].title = String(title.prefix(80))
                        self.saveConversationsToUserDefaults()
                    }
                }
            } catch {
                // Non-critical — fallback title already set
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveConversationsToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(savedConversations)
            UserDefaults.standard.set(data, forKey: "berean_conversations")
            dlog("💾 Saved \(savedConversations.count) conversations to UserDefaults")
        } catch {
            dlog("❌ Failed to save conversations: \(error.localizedDescription)")
        }
        // Fire-and-forget cloud sync
        syncConversationsToFirestore()
    }

    private func loadSavedConversations() {
        guard let data = UserDefaults.standard.data(forKey: "berean_conversations") else {
            dlog("ℹ️ No saved conversations found locally")
            // Try cloud fallback
            fetchConversationsFromFirestore()
            return
        }

        do {
            savedConversations = try JSONDecoder().decode([SavedConversation].self, from: data)
            dlog("📖 Loaded \(savedConversations.count) conversations from local cache")
            // Merge newer cloud data in background (non-blocking)
            fetchConversationsFromFirestore()
        } catch {
            dlog("❌ Failed to decode local conversations — clearing cache: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: "berean_conversations")
            savedConversations = []
            fetchConversationsFromFirestore()
        }
    }

    // MARK: - Firestore Sync

    /// Firestore collection path: users/{uid}/bereanConversations
    private var firestoreCollection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("bereanConversations")
    }

    /// Write all conversations to Firestore in the background. Each conversation is
    /// stored as its own document (id = conversation.id.uuidString) so individual
    /// deletes/updates are cheap. Large message arrays are JSON-encoded as a string
    /// field to avoid Firestore's 1 MiB document limit issues with deeply nested arrays.
    private func syncConversationsToFirestore() {
        guard let col = firestoreCollection else { return }
        // Snapshot on MainActor before handing off to detached task —
        // avoids "MainActor-isolated conformance used in nonisolated context" warnings.
        let toSync = Array(savedConversations.prefix(maxSavedConversations))
        Task.detached(priority: .background) {
            for conversation in toSync {
                guard let encoded = try? JSONEncoder().encode(conversation),
                      let json = String(data: encoded, encoding: .utf8) else { continue }
                let docRef = col.document(conversation.id.uuidString)
                try? await docRef.setData([
                    "id":          conversation.id.uuidString,
                    "title":       conversation.title,
                    "translation": conversation.translation,
                    "date":        Timestamp(date: conversation.date),
                    "isPinned":    conversation.isPinned,
                    "isStarred":   conversation.isStarred,
                    "messageCount": conversation.messages.count,
                    "payload":     json   // full JSON blob for restoration
                ], merge: true)
            }
            dlog("☁️ Synced \(toSync.count) conversations to Firestore")
        }
    }

    /// Fetch conversations from Firestore and merge them with local data.
    /// Cloud wins for any conversation not present locally.
    private func fetchConversationsFromFirestore() {
        guard let col = firestoreCollection else { return }
        Task.detached(priority: .background) {
            guard let snapshot = try? await col
                .order(by: "date", descending: true)
                .limit(to: 50)
                .getDocuments() else { return }

            var cloudConversations: [SavedConversation] = []
            for doc in snapshot.documents {
                guard let payload = doc.data()["payload"] as? String,
                      let data = payload.data(using: .utf8),
                      let conv = try? JSONDecoder().decode(SavedConversation.self, from: data)
                else { continue }
                cloudConversations.append(conv)
            }

            // Snapshot into a `let` before crossing into MainActor to avoid
            // "captured var in concurrently-executing code" warnings.
            let fetchedConversations = cloudConversations
            await MainActor.run {
                guard !fetchedConversations.isEmpty else { return }
                // Merge: keep local + add any cloud-only conversations
                let localIds = Set(self.savedConversations.map { $0.id })
                let newFromCloud = fetchedConversations.filter { !localIds.contains($0.id) }
                if !newFromCloud.isEmpty {
                    self.savedConversations.append(contentsOf: newFromCloud)
                    self.savedConversations.sort {
                        if $0.isPinned != $1.isPinned { return $0.isPinned }
                        return $0.date > $1.date
                    }
                    self.saveConversationsToUserDefaults()
                    dlog("☁️ Merged \(newFromCloud.count) conversations from Firestore")
                }
            }
        }
    }

    /// Delete a single conversation from Firestore
    private func deleteConversationFromFirestore(_ conversation: SavedConversation) {
        guard let col = firestoreCollection else { return }
        Task.detached(priority: .background) {
            try? await col.document(conversation.id.uuidString).delete()
        }
    }
    
    private func loadSelectedTranslation() {
        if let saved = UserDefaults.standard.string(forKey: "berean_translation") {
            // Validate that it's a known translation
            if availableTranslations.contains(saved) {
                selectedTranslation = saved
                dlog("📖 Loaded translation preference: \(saved)")
            } else {
                dlog("⚠️ Invalid saved translation '\(saved)', using default")
                selectedTranslation = "ESV"
            }
        } else {
            dlog("ℹ️ No saved translation preference, using default: ESV")
        }
    }
    
    private func saveSelectedTranslation() {
        UserDefaults.standard.set(selectedTranslation, forKey: "berean_translation")
        dlog("💾 Saved translation preference: \(selectedTranslation)")
    }
    
    // MARK: - Stop Generation
    
    /// Stop the current AI generation
    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        pendingRequestId = nil  // ✅ P0-1: Clear pending request
        dlog("⏸️ Stopped AI generation")
    }

    // MARK: - Continue Generating

    /// Asks the AI to continue from where it left off on the last assistant response.
    /// Useful when a response was truncated or the user wants more depth.
    func continueGenerating(
        responseMode: BereanResponseMode,
        personalityPrefix: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (BereanMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }),
              !lastAssistant.content.isEmpty else {
            onError(NSError(domain: "BereanViewModel", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No response to continue"]))
            return
        }
        let continuePrompt = "Please continue your previous response from where you left off."
        let requestId = UUID()
        generateResponseStreaming(
            for: continuePrompt,
            requestId: requestId,
            responseMode: responseMode,
            personalityPrefix: personalityPrefix,
            onChunk: onChunk,
            onComplete: onComplete,
            onError: onError
        )
    }

    // MARK: - Feedback & Bookmark

    /// Record thumbs up/down on an assistant message. Persists via conversation save.
    func setFeedback(_ feedback: Bool?, on messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let m = messages[idx]
        messages[idx] = BereanMessage(
            id: m.id, content: m.content, role: m.role, timestamp: m.timestamp,
            verseReferences: m.verseReferences, feedback: feedback, isBookmarked: m.isBookmarked
        )
    }

    /// Toggle the bookmarked state of a message.
    @discardableResult
    func toggleBookmark(on messageId: UUID) -> Bool {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return false }
        let m = messages[idx]
        let newState = !m.isBookmarked
        messages[idx] = BereanMessage(
            id: m.id, content: m.content, role: m.role, timestamp: m.timestamp,
            verseReferences: m.verseReferences, feedback: m.feedback, isBookmarked: newState
        )
        return newState
    }

    /// All bookmarked messages across the current in-session thread.
    var bookmarkedMessages: [BereanMessage] {
        messages.filter { $0.isBookmarked }
    }

    // MARK: - Conversation Search

    /// Search across all saved conversations by title, message content, or verse references.
    /// Returns results sorted by recency, with the matching snippet for each.
    struct ConversationSearchResult: Identifiable {
        let id = UUID()
        let conversation: SavedConversation
        /// The first message snippet that matched the query (nil if only the title matched).
        let matchingSnippet: String?
    }

    func searchConversations(query: String) -> [ConversationSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        return savedConversations.compactMap { conv in
            // Title match
            if conv.title.lowercased().contains(trimmed) {
                return ConversationSearchResult(conversation: conv, matchingSnippet: nil)
            }
            // Message content match — find the first matching message body
            if let matchingMsg = conv.messages.first(where: {
                $0.content.lowercased().contains(trimmed)
            }) {
                // Return a short snippet around the match
                let snippet = String(matchingMsg.content.prefix(120))
                return ConversationSearchResult(conversation: conv, matchingSnippet: snippet)
            }
            // Verse reference match
            if conv.messages.contains(where: { msg in
                msg.verseReferences.contains(where: { $0.lowercased().contains(trimmed) })
            }) {
                return ConversationSearchResult(conversation: conv, matchingSnippet: "Verse reference match")
            }
            return nil
        }
        .sorted { $0.conversation.date > $1.conversation.date }
    }

    // MARK: - Folder Management

    /// All unique folder tags currently in use across saved conversations.
    var allFolderTags: [String] {
        let tags = savedConversations.compactMap { $0.folderTag }
        return Array(Set(tags)).sorted()
    }

    /// Conversations grouped by folder tag. Untagged conversations are under key "".
    var conversationsByFolder: [String: [SavedConversation]] {
        Dictionary(grouping: savedConversations, by: { $0.folderTag ?? "" })
    }

    /// Assign a folder tag to a saved conversation.
    func setFolderTag(_ tag: String?, on conversationId: UUID) {
        guard let idx = savedConversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let c = savedConversations[idx]
        savedConversations[idx] = SavedConversation(
            id: c.id, title: c.title, messages: c.messages, date: c.date,
            translation: c.translation, isPinned: c.isPinned, isStarred: c.isStarred,
            folderTag: tag
        )
        saveConversationsToUserDefaults()
    }

    // MARK: - Offline Retry Queue

    private struct QueuedMessage: Codable {
        let id: UUID
        let text: String
        let timestamp: Date
    }

    private let retryQueueKey = "berean_offline_retry_queue"

    /// Add a failed message to the offline retry queue so it can be resent when connectivity restores.
    func enqueueForRetry(_ messageText: String) {
        var queue = loadRetryQueue()
        let entry = QueuedMessage(id: UUID(), text: messageText, timestamp: Date())
        queue.append(entry)
        // Cap queue at 20 entries to avoid unbounded growth
        if queue.count > 20 { queue = Array(queue.suffix(20)) }
        saveRetryQueue(queue)
        dlog("📥 Queued for retry: \"\(String(messageText.prefix(40)))…\"")
    }

    /// Returns the oldest queued message and removes it from the queue.
    func dequeueNextRetry() -> String? {
        var queue = loadRetryQueue()
        guard !queue.isEmpty else { return nil }
        let entry = queue.removeFirst()
        saveRetryQueue(queue)
        return entry.text
    }

    var hasQueuedMessages: Bool { !loadRetryQueue().isEmpty }

    private func loadRetryQueue() -> [QueuedMessage] {
        guard let data = UserDefaults.standard.data(forKey: retryQueueKey),
              let decoded = try? JSONDecoder().decode([QueuedMessage].self, from: data) else { return [] }
        return decoded
    }

    private func saveRetryQueue(_ queue: [QueuedMessage]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: retryQueueKey)
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
            dlog("📉 Trimmed conversation history to \(messages.count) messages")
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
            dlog("⏭️ Skipping duplicate request: \(requestId)")
            return
        }
        
        guard pendingRequestId == nil || pendingRequestId == requestId else {
            dlog("⚠️ Request already in flight, ignoring duplicate")
            return
        }
        
        pendingRequestId = requestId
        
        // Validate input
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dlog("⚠️ Cannot generate response for empty query")
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
        dlog("📊 Context: \(responseMode.rawValue) mode → \(contextWindow) messages (saved ~\(savedMessages) messages)")
        
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
                        dlog("⏸️ Generation cancelled by user")
                        await MainActor.run {
                            self.pendingRequestId = nil
                        }
                        return
                    }
                    
                    // Check timeout
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > requestTimeout {
                        dlog("⏱️ Request timeout after \(elapsed) seconds")
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
                    dlog("⏸️ Generation cancelled before completion")
                    await MainActor.run {
                        self.pendingRequestId = nil
                    }
                    return
                }
                
                // Validate response
                guard !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    dlog("❌ Received empty response from AI")
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
                dlog("✅ Response generation completed in \(String(format: "%.2f", duration))s")
                dlog("📊 Context used: \(contextWindow) messages | References found: \(verseReferences.count)")
                
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
                dlog("⏸️ Generation task cancelled")
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
                
                dlog("❌ OpenAI error: \(error.localizedDescription)")
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
                
                dlog("❌ Unexpected error during streaming: \(error.localizedDescription)")
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
                        dlog("⚠️ Invalid scripture reference detected and filtered: \(reference)")
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
            dlog("⚠️ Invalid book name: \(bookName)")
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
            dlog("⚠️ Invalid chapter: \(bookName) only has \(maxChapter) chapters, got \(chapter)")
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

struct SavedConversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let messages: [BereanMessage]
    let date: Date
    let translation: String
    var isPinned: Bool
    var isStarred: Bool
    /// Optional folder/project tag for grouping conversations (e.g. "Sermon Prep", "Daily Study")
    var folderTag: String?

    init(id: UUID = UUID(), title: String, messages: [BereanMessage], date: Date, translation: String,
         isPinned: Bool = false, isStarred: Bool = false, folderTag: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.date = date
        self.translation = translation
        self.isPinned = isPinned
        self.isStarred = isStarred
        self.folderTag = folderTag
    }
}

// MARK: - Berean User Preferences

/// Lightweight UserDefaults-backed store for Berean AI personalization settings.
/// Persists across sessions without requiring authentication.
/// Values feed into the system prompt suffix at request time.
final class BereanUserPreferences: ObservableObject {

    static let shared = BereanUserPreferences()
    private init() { loadFromDefaults() }

    // MARK: Translation preference
    @Published var preferredTranslation: String = "ESV" {
        didSet { UserDefaults.standard.set(preferredTranslation, forKey: "berean_pref_translation") }
    }

    // MARK: Response length
    enum ResponseLength: String, CaseIterable, Codable {
        case concise    = "concise"
        case balanced   = "balanced"
        case thorough   = "thorough"

        var label: String {
            switch self {
            case .concise:  return "Concise"
            case .balanced: return "Balanced"
            case .thorough: return "Thorough"
            }
        }

        var systemPromptHint: String {
            switch self {
            case .concise:  return "Keep responses brief (1-3 sentences). Be direct."
            case .balanced: return ""
            case .thorough: return "Provide comprehensive, thorough answers with full context."
            }
        }
    }

    @Published var responseLength: ResponseLength = .balanced {
        didSet { UserDefaults.standard.set(responseLength.rawValue, forKey: "berean_pref_length") }
    }

    // MARK: Tone preference
    enum TonePreference: String, CaseIterable, Codable {
        case scholarly      = "scholarly"
        case pastoral       = "pastoral"
        case conversational = "conversational"

        var label: String {
            switch self {
            case .scholarly:      return "Scholarly"
            case .pastoral:       return "Pastoral"
            case .conversational: return "Conversational"
            }
        }

        var systemPromptHint: String {
            switch self {
            case .scholarly:      return "Use a scholarly, precise tone with theological terminology where appropriate."
            case .pastoral:       return ""
            case .conversational: return "Use a warm, conversational tone as if talking with a friend."
            }
        }
    }

    @Published var tone: TonePreference = .pastoral {
        didSet { UserDefaults.standard.set(tone.rawValue, forKey: "berean_pref_tone") }
    }

    // MARK: Discipleship maturity
    enum DiscipleshipMaturity: String, CaseIterable, Codable {
        case newBeliever = "newBeliever"
        case growing     = "growing"
        case mature      = "mature"

        var label: String {
            switch self {
            case .newBeliever: return "New Believer"
            case .growing:     return "Growing"
            case .mature:      return "Mature Believer"
            }
        }

        var systemPromptHint: String {
            switch self {
            case .newBeliever: return "The user is a new believer — avoid jargon, explain theological terms simply."
            case .growing:     return ""
            case .mature:      return "The user has a strong theological foundation — engage at a mature level."
            }
        }
    }

    @Published var discipleshipMaturity: DiscipleshipMaturity = .growing {
        didSet { UserDefaults.standard.set(discipleshipMaturity.rawValue, forKey: "berean_pref_maturity") }
    }

    // MARK: Verse-first mode
    /// When true, Berean leads every answer with a Scripture reference before the prose explanation.
    @Published var verseFirstMode: Bool = false {
        didSet { UserDefaults.standard.set(verseFirstMode, forKey: "berean_pref_verseFirst") }
    }

    // MARK: Wisdom mode
    /// When true, frames all answers through a "biblical wisdom for everyday life" lens.
    @Published var wisdomMode: Bool = false {
        didSet { UserDefaults.standard.set(wisdomMode, forKey: "berean_pref_wisdomMode") }
    }

    // MARK: Composed system prompt additions
    /// Extra text to append to the system prompt, derived from current preferences.
    var systemPromptSuffix: String {
        var parts: [String] = []
        if !responseLength.systemPromptHint.isEmpty    { parts.append(responseLength.systemPromptHint) }
        if !tone.systemPromptHint.isEmpty               { parts.append(tone.systemPromptHint) }
        if !discipleshipMaturity.systemPromptHint.isEmpty { parts.append(discipleshipMaturity.systemPromptHint) }
        if verseFirstMode { parts.append("Lead every answer with a direct Scripture reference before explaining.") }
        if wisdomMode     { parts.append("Frame answers through the lens of biblical wisdom applied to everyday life.") }
        return parts.joined(separator: " ")
    }

    // MARK: Persistence
    private func loadFromDefaults() {
        if let t = UserDefaults.standard.string(forKey: "berean_pref_translation") {
            preferredTranslation = t
        }
        if let r = UserDefaults.standard.string(forKey: "berean_pref_length"),
           let v = ResponseLength(rawValue: r) { responseLength = v }
        if let t = UserDefaults.standard.string(forKey: "berean_pref_tone"),
           let v = TonePreference(rawValue: t) { tone = v }
        if let m = UserDefaults.standard.string(forKey: "berean_pref_maturity"),
           let v = DiscipleshipMaturity(rawValue: m) { discipleshipMaturity = v }
        verseFirstMode = UserDefaults.standard.bool(forKey: "berean_pref_verseFirst")
        wisdomMode     = UserDefaults.standard.bool(forKey: "berean_pref_wisdomMode")
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

// MARK: - Design Tokens

private enum BereanDesign {
    // Palette
    static let coral       = Color(red: 0.88, green: 0.38, blue: 0.28)
    static let coralSoft   = Color(red: 0.95, green: 0.45, blue: 0.32)
    static let surface     = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let cardWhite   = Color.white.opacity(0.85)
    static let cardStroke  = Color.black.opacity(0.055)
    static let textPrimary = Color(white: 0.12)
    static let textSecond  = Color(white: 0.46)
    static let textTertiary = Color(white: 0.62)

    // Radii
    static let outerRadius: CGFloat = 24
    static let cardRadius: CGFloat  = 16
    static let chipRadius: CGFloat  = 100   // capsule

    // Spacing
    static let pagePad: CGFloat     = 18
    static let sectionGap: CGFloat  = 14
}

// MARK: - BereanWorkspacePanel
/// Large-radius white card — the primary module container.
/// Wraps hero area, prompt sections, or response modules.

struct BereanWorkspacePanel<Content: View>: View {
    var padding: EdgeInsets = .init(top: 22, leading: 20, bottom: 22, trailing: 20)
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: BereanDesign.outerRadius, style: .continuous)
                    .fill(BereanDesign.cardWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: BereanDesign.outerRadius, style: .continuous)
                            .stroke(BereanDesign.cardStroke, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 14, y: 4)
            )
    }
}

// MARK: - BereanDashedModuleCard
/// Inner dashed-border card — used selectively for prompts, study modules,
/// follow-up sections. Lower visual weight than the workspace panel.

struct BereanDashedModuleCard<Content: View>: View {
    var cornerRadius: CGFloat = BereanDesign.cardRadius
    var dashPattern: [CGFloat] = [5, 3.5]
    var strokeOpacity: Double = 0.13
    var fillOpacity: Double = 0.0
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.0, dash: dashPattern)
                            )
                            .foregroundStyle(Color.black.opacity(strokeOpacity))
                    )
            )
    }
}

// MARK: - BereanStatusChip
/// Inline status pill. Used sparingly — generating state, saved, scripture-based, etc.

struct BereanStatusChip: View {
    enum ChipStyle {
        case generating, saved, scripture, followUp, reflection, neutral(String)

        var label: String {
            switch self {
            case .generating:          return "Reflecting"
            case .saved:               return "Saved"
            case .scripture:           return "Scripture-Based"
            case .followUp:            return "Follow-Up Ready"
            case .reflection:          return "Reflection"
            case .neutral(let l):      return l
            }
        }
        var icon: String {
            switch self {
            case .generating:    return "ellipsis"
            case .saved:         return "bookmark.fill"
            case .scripture:     return "book.closed.fill"
            case .followUp:      return "arrow.turn.down.right"
            case .reflection:    return "heart.text.square"
            case .neutral:       return "circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .generating:    return BereanDesign.coral
            case .saved:         return Color(red: 0.35, green: 0.62, blue: 0.90)
            case .scripture:     return Color(red: 0.42, green: 0.68, blue: 0.48)
            case .followUp:      return Color(red: 0.58, green: 0.42, blue: 0.82)
            case .reflection:    return Color(red: 0.88, green: 0.55, blue: 0.28)
            case .neutral:       return Color(white: 0.55)
            }
        }
    }

    let style: ChipStyle
    var animated: Bool = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            if style.label == ChipStyle.generating.label && animated {
                // Pulsing dot for live generating state
                Circle()
                    .fill(style.color)
                    .frame(width: 5, height: 5)
                    .scaleEffect(pulse ? 1.35 : 0.85)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            } else {
                Image(systemName: style.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(style.color)
            }
            Text(style.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.color)
                .tracking(0.2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(style.color.opacity(0.10))
                .overlay(
                    Capsule()
                        .stroke(style.color.opacity(0.18), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - BereanSectionHeader
/// Compact section header used above workspace modules in the scroll view.

struct BereanSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var accentBar: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if accentBar {
                Capsule()
                    .fill(BereanDesign.coral.opacity(0.40))
                    .frame(width: 2.5, height: 13)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BereanDesign.textPrimary)
                    .tracking(0.1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(BereanDesign.textTertiary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - BereanPillButton
/// Soft pill-shaped action button — "Ask Berean," "Add follow-up," "Save insight," etc.

struct BereanPillButton: View {
    let label: String
    var icon: String? = nil
    var style: ButtonStyle = .primary
    let action: () -> Void

    @State private var isPressed = false

    enum ButtonStyle {
        case primary, secondary, ghost
        var foreground: Color {
            switch self {
            case .primary:   return .white
            case .secondary: return BereanDesign.textPrimary
            case .ghost:     return BereanDesign.textSecond
            }
        }
        var fill: AnyShapeStyle {
            switch self {
            case .primary:
                return AnyShapeStyle(LinearGradient(
                    colors: [BereanDesign.coral, Color(red: 0.78, green: 0.30, blue: 0.44)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            case .secondary:
                return AnyShapeStyle(Color.white.opacity(0.90))
            case .ghost:
                return AnyShapeStyle(Color.clear)
            }
        }
        var strokeColor: Color {
            switch self {
            case .primary:   return .clear
            case .secondary: return Color.black.opacity(0.08)
            case .ghost:     return Color.black.opacity(0.10)
            }
        }
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: icon != nil ? 5 : 0) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(style.fill)
                    .overlay(
                        Capsule()
                            .stroke(style.strokeColor, lineWidth: 0.75)
                    )
                    .shadow(
                        color: style == .primary ? BereanDesign.coral.opacity(0.22) : .clear,
                        radius: 8, y: 3
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - BereanFollowUpActionsRow
/// Horizontal pill-button row shown below a Berean message response.
/// Gives the user one-tap follow-up actions relevant to the current response.

struct BereanFollowUpActionsRow: View {
    let onExplainMore: () -> Void
    let onShowVerses: () -> Void
    let onSummarize: () -> Void
    let onReflect: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BereanPillButton(label: "Explain more", icon: "arrow.down.doc", style: .secondary, action: onExplainMore)
                BereanPillButton(label: "Show verses", icon: "book.closed", style: .secondary, action: onShowVerses)
                BereanPillButton(label: "Summarize", icon: "text.alignleft", style: .secondary, action: onSummarize)
                BereanPillButton(label: "Reflect", icon: "heart.text.square", style: .ghost, action: onReflect)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
        }
        .padding(.top, 10)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - BereanConversationDrawer
/// Slide-in panel from trailing edge — ChatGPT/Claude-style conversation organizer.
/// Houses New Chat, search, recent conversations, saved messages, and utility controls.

struct BereanConversationDrawer: View {
    @Binding var isShowing: Bool
    @Binding var conversations: [SavedConversation]

    let onNewChat: () -> Void
    let onSelectConversation: (SavedConversation) -> Void
    let onDeleteConversation: (SavedConversation) -> Void
    let onPinConversation: (SavedConversation) -> Void
    let onStarConversation: (SavedConversation) -> Void
    let onShowSaved: () -> Void
    let onShowTranslation: () -> Void
    let onShowOnboarding: () -> Void
    let onClearAll: () -> Void

    @State private var searchText = ""
    @State private var showDeleteConfirm: SavedConversation? = nil
    @State private var showFolderView = false
    @State private var folderPickerTarget: SavedConversation? = nil
    @State private var expandedFolders: Set<String> = []

    private var filteredConversations: [SavedConversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // All unique folder tags across conversations, plus "" bucket for untagged.
    private var folderGroups: [(tag: String, conversations: [SavedConversation])] {
        var groups: [String: [SavedConversation]] = [:]
        for conv in filteredConversations {
            let key = conv.folderTag ?? ""
            groups[key, default: []].append(conv)
        }
        // Sort: named folders alphabetically, then untagged last
        let named = groups.keys
            .filter { !$0.isEmpty }
            .sorted()
            .map { (tag: $0, conversations: groups[$0]!) }
        let untagged = groups[""].map { (tag: "", conversations: $0) }
        return named + (untagged.map { [$0] } ?? [])
    }

    private var drawerWidth: CGFloat {
        let screenWidth = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 390
        return min(screenWidth * 0.82, 340)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Scrim
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        isShowing = false
                    }
                }

            // Drawer panel
            drawerPanel
                .frame(width: drawerWidth)
        }
    }

    private var drawerPanel: some View {
        VStack(spacing: 0) {
            drawerHeader
            Divider().opacity(0.08)
            searchBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    newChatButton
                    if !filteredConversations.isEmpty {
                        conversationsSection
                    } else if !searchText.isEmpty {
                        emptySearchState
                    } else {
                        emptyConversationsState
                    }
                    Divider()
                        .opacity(0.07)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    utilitySection
                }
                .padding(.bottom, 32)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.98, green: 0.97, blue: 0.96))
                .shadow(color: Color.black.opacity(0.14), radius: 32, x: -8, y: 0)
                .ignoresSafeArea(edges: .vertical)
        )
        .alert("Delete Conversation?", isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let c = showDeleteConfirm { onDeleteConversation(c) }
                showDeleteConfirm = nil
            }
            Button("Cancel", role: .cancel) { showDeleteConfirm = nil }
        } message: {
            Text("This conversation will be permanently removed.")
        }
        .sheet(item: $folderPickerTarget) { target in
            BereanFolderPickerSheet(
                conversation: target,
                currentTag: target.folderTag,
                onAssign: { tag in
                    if let idx = conversations.firstIndex(where: { $0.id == target.id }) {
                        conversations[idx] = SavedConversation(
                            id: target.id,
                            title: target.title,
                            messages: target.messages,
                            date: target.date,
                            translation: target.translation,
                            isPinned: target.isPinned,
                            isStarred: target.isStarred,
                            folderTag: tag
                        )
                    }
                    folderPickerTarget = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var drawerHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BereanDesign.coral.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: showFolderView ? "folder.fill" : "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BereanDesign.coral)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(showFolderView ? "Folders" : "Conversations")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.14))
                Text("\(conversations.count) saved")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
            }
            Spacer()
            // Folder/list toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    showFolderView.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: showFolderView ? "list.bullet" : "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showFolderView ? BereanDesign.coral : Color(white: 0.45))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(showFolderView ? BereanDesign.coral.opacity(0.10) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isShowing = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.5))
            TextField("Search conversations...", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.2))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.75)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: New Chat Button

    private var newChatButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onNewChat()
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BereanDesign.coral, BereanDesign.coral.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("New Conversation")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.14))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: BereanDesign.coral.opacity(0.12), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Conversations Section

    private var pinnedConversations: [SavedConversation] {
        filteredConversations.filter { $0.isPinned }
    }
    private var unpinnedConversations: [SavedConversation] {
        filteredConversations.filter { !$0.isPinned }
    }

    private var conversationsSection: some View {
        Group {
            if showFolderView {
                folderGroupedSection
            } else {
                flatConversationsSection
            }
        }
    }

    // MARK: Flat (default) layout — Pinned + Recent sections
    private var flatConversationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned section
            if !pinnedConversations.isEmpty {
                Text("Pinned")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BereanDesign.coral.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                VStack(spacing: 4) {
                    ForEach(pinnedConversations) { conversation in
                        conversationRow(conversation)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Recent section
            if !unpinnedConversations.isEmpty {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.horizontal, 20)
                    .padding(.top, pinnedConversations.isEmpty ? 18 : 14)
                    .padding(.bottom, 8)
                VStack(spacing: 4) {
                    ForEach(unpinnedConversations) { conversation in
                        conversationRow(conversation)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Folder grouped layout
    private var folderGroupedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if folderGroups.isEmpty {
                emptyConversationsState
            } else {
                ForEach(folderGroups, id: \.tag) { group in
                    folderSection(tag: group.tag, conversations: group.conversations)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func folderSection(tag: String, conversations: [SavedConversation]) -> some View {
        let displayName = tag.isEmpty ? "Uncategorised" : tag
        let isExpanded = expandedFolders.contains(tag) || tag.isEmpty
        let mostRecent = conversations.max(by: { $0.date < $1.date })?.date
        let msgCount = conversations.reduce(0) { $0 + $1.messages.count }

        VStack(alignment: .leading, spacing: 0) {
            // Folder header row (tappable to expand/collapse)
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if expandedFolders.contains(tag) {
                        expandedFolders.remove(tag)
                    } else {
                        expandedFolders.insert(tag)
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    // Folder icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tag.isEmpty ? Color(white: 0.92) : BereanDesign.coral.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: tag.isEmpty ? "tray" : "folder.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tag.isEmpty ? Color(white: 0.5) : BereanDesign.coral)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tag.isEmpty ? Color(white: 0.45) : Color(white: 0.16))

                        HStack(spacing: 6) {
                            // Conversation count badge
                            Text("\(conversations.count) thread\(conversations.count == 1 ? "" : "s")")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(BereanDesign.coral.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(BereanDesign.coral.opacity(0.10)))

                            // Message count
                            Text("\(msgCount) msg\(msgCount == 1 ? "" : "s")")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.55))

                            // Most recent date
                            if let date = mostRecent {
                                Text("· \(relativeDate(date))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.55))
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, isExpanded ? 4 : 0)

            // Conversation rows under this folder (collapsible)
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(conversations) { conversation in
                        conversationRow(conversation)
                            .padding(.leading, 10) // indent under folder
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func conversationRow(_ conversation: SavedConversation) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelectConversation(conversation)
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(conversation.isPinned ? BereanDesign.coral.opacity(0.12) : Color(white: 0.94))
                        .frame(width: 32, height: 32)
                    Image(systemName: conversation.isPinned ? "pin.fill" : "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(conversation.isPinned ? BereanDesign.coral : Color(white: 0.45))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(conversation.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: 0.18))
                            .lineLimit(1)
                        if conversation.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.2))
                        }
                    }
                    HStack(spacing: 4) {
                        Text(conversation.translation)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BereanDesign.coral.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(BereanDesign.coral.opacity(0.10))
                            )
                        Text(relativeDate(conversation.date))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onPinConversation(conversation)
            } label: {
                Label(conversation.isPinned ? "Unpin" : "Pin to Top", systemImage: conversation.isPinned ? "pin.slash" : "pin")
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onStarConversation(conversation)
            } label: {
                Label(conversation.isStarred ? "Unstar" : "Star", systemImage: conversation.isStarred ? "star.slash" : "star")
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                folderPickerTarget = conversation
            } label: {
                Label(
                    conversation.folderTag != nil ? "Move Folder (\(conversation.folderTag!))" : "Add to Folder",
                    systemImage: "folder.badge.plus"
                )
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirm = conversation
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Empty States

    private var emptySearchState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color(white: 0.7))
            Text("No results for \"\(searchText)\"")
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyConversationsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30))
                .foregroundStyle(Color(white: 0.72))
            Text("No saved conversations yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
            Text("Start a chat to begin exploring Scripture")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
    }

    // MARK: Utility Section

    private var utilitySection: some View {
        VStack(spacing: 4) {
            Text("Tools")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.5))
                .textCase(.uppercase)
                .tracking(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                utilityRow(icon: "bookmark.fill", label: "Saved Messages", color: Color(red: 0.4, green: 0.6, blue: 1.0), action: onShowSaved)
                utilityRow(icon: "text.book.closed.fill", label: "Bible Translation", color: BereanDesign.coral, action: onShowTranslation)
                utilityRow(icon: "questionmark.circle", label: "Berean Tutorial", color: Color(red: 0.4, green: 0.75, blue: 0.55), action: onShowOnboarding)
            }
            .padding(.horizontal, 16)

            if !conversations.isEmpty {
                Button(action: onClearAll) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.7))
                        }
                        Text("Clear All Conversations")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.75))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
        .padding(.top, 6)
    }

    private func utilityRow(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.22))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(white: 0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - BereanFolderPickerSheet
//
// Half-sheet for assigning or changing a conversation's folder tag.
// Shows preset folder chips and a "Create new…" text field.
// Conforms to View (not Identifiable) — presented via .sheet(item:) on SavedConversation.

struct BereanFolderPickerSheet: View {
    let conversation: SavedConversation
    let currentTag: String?
    let onAssign: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customFolderName: String = ""
    @State private var showCustomInput: Bool = false
    @FocusState private var isCustomInputFocused: Bool

    private let presets: [String] = [
        "Study", "Prayer", "Sermon Prep", "Daily Devotion",
        "Church Notes", "Discipleship", "Questions", "Favorites"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Conversation title preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add to Folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(conversation.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal)

                    // Preset folder chips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Folders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(presets, id: \.self) { preset in
                                folderChip(preset)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Create new folder input
                    VStack(alignment: .leading, spacing: 10) {
                        if showCustomInput {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundStyle(Color(red: 0.93, green: 0.4, blue: 0.3))
                                    .font(.system(size: 15))
                                TextField("Folder name…", text: $customFolderName)
                                    .font(.subheadline)
                                    .focused($isCustomInputFocused)
                                    .onSubmit { commitCustomFolder() }
                                if !customFolderName.isEmpty {
                                    Button(action: commitCustomFolder) {
                                        Text("Add")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color(red: 0.93, green: 0.4, blue: 0.3))
                                    }
                                }
                            }
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        } else {
                            Button {
                                showCustomInput = true
                                isCustomInputFocused = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.badge.plus")
                                    Text("Create new folder…")
                                        .font(.subheadline)
                                }
                                .foregroundStyle(Color(red: 0.93, green: 0.4, blue: 0.3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Remove from folder option
                    if currentTag != nil {
                        Button {
                            onAssign(nil)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.minus")
                                Text("Remove from folder")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func folderChip(_ name: String) -> some View {
        let isSelected = currentTag == name
        Button {
            onAssign(name)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 12))
                Text(name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color(red: 0.93, green: 0.4, blue: 0.3) : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? Color(red: 0.93, green: 0.4, blue: 0.3).opacity(0.12)
                    : Color(.systemGray5),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color(red: 0.93, green: 0.4, blue: 0.3).opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
    }

    private func commitCustomFolder() {
        let trimmed = customFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAssign(trimmed)
        dismiss()
    }
}

// MARK: - BereanPremiumLandingView
//
// Premium editorial landing screen for Berean AI.
// Shows a time-aware typewriter greeting, quick action cards, and suggested prompts.
// Replaces the old minimal cross/pulse empty state.

struct BereanPremiumLandingView: View {
    @Binding var personalityMode: BereanPersonalityMode
    let onQuickAction: (String) -> Void
    /// Passed from parent — true while AI is generating or thinking.
    var isActive: Bool = false
    /// Called when the user taps the orb (focus input or stop generation).
    var onOrbTap: (() -> Void)? = nil

    @State private var heroVisible = false

    @Environment(\.accessibilityReduceMotion) private var shouldReduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Berean orb ────────────────────────────────────────────────
            BereanOrbView(isActive: isActive, onTap: onOrbTap)
                .opacity(heroVisible ? 1 : 0)
                .scaleEffect(heroVisible ? 1 : (shouldReduceMotion ? 1 : 0.82))
                .animation(
                    shouldReduceMotion
                        ? .none
                        : .spring(response: 0.55, dampingFraction: 0.72),
                    value: heroVisible
                )
                .padding(.bottom, 28)

            // ── Hero greeting (vertically centered like ChatGPT/Claude) ───
            BereanTypographyHero()
                .opacity(heroVisible ? 1 : 0)
                .offset(y: heroVisible ? 0 : (shouldReduceMotion ? 0 : 14))
                .animation(
                    shouldReduceMotion
                        ? .none
                        : .spring(response: 0.60, dampingFraction: 0.80),
                    value: heroVisible
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, BereanDesign.pagePad)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            heroVisible = true
        }
        .onDisappear {
            heroVisible = false
        }
    }
}

// MARK: - BereanTypographyHero
// Editorial center-focused text hero with typewriter greeting and subheadline.

struct BereanTypographyHero: View {

    // ── Greeting logic ────────────────────────────────────────────────────────
    private static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default:      return "Still up?"
        }
    }

    private static func followUp() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "What would you like to understand?"
        case 12..<17: return "How can I help today?"
        case 17..<22: return "What wisdom are you seeking?"
        default:      return "Let's think through it together."
        }
    }

    @State private var greetingText = ""
    @State private var followUpText = ""
    @State private var showFollowUp = false
    @State private var cursorVisible = true
    @State private var typingDone = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let greeting = BereanTypographyHero.greeting()
    private let followUp = BereanTypographyHero.followUp()

    var body: some View {
        VStack(alignment: .center, spacing: 8) {

            // Primary greeting — typewriter
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(greetingText)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundStyle(Color(white: 0.08))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                // Blinking cursor — only while typing, settles after done
                if !typingDone || (showFollowUp && followUpText.count < followUp.count) {
                    Rectangle()
                        .fill(BereanDesign.coral)
                        .frame(width: 2, height: 32)
                        .cornerRadius(1)
                        .opacity(cursorVisible ? 1 : 0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                            value: cursorVisible
                        )
                        .padding(.leading, 2)
                }
            }

            // Follow-up line — fades/types in after greeting finishes
            if showFollowUp {
                Text(followUpText)
                    .font(.system(size: 22, weight: .regular, design: .default))
                    .foregroundStyle(Color(white: 0.38))
                    .tracking(-0.3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.animation(.easeIn(duration: 0.25)))
            }


        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            cursorVisible = true
            if reduceMotion {
                greetingText = greeting
                followUpText = followUp
                showFollowUp = true
                typingDone = true
            } else {
                typewriterSequence()
            }
        }
    }

    private func typewriterSequence() {
        // Phase 1: type greeting
        let greetingChars = Array(greeting)
        let charInterval: TimeInterval = 0.042

        for (i, char) in greetingChars.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * charInterval) {
                greetingText.append(char)
            }
        }

        let greetingDuration = Double(greetingChars.count) * charInterval

        // Phase 2: brief pause, then show follow-up
        DispatchQueue.main.asyncAfter(deadline: .now() + greetingDuration + 0.30) {
            typingDone = true
            withAnimation { showFollowUp = true }

            let followChars = Array(followUp)
            let followInterval: TimeInterval = 0.036
            for (i, char) in followChars.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * followInterval) {
                    followUpText.append(char)
                }
            }
        }
    }
}

// MARK: - BereanOrbView
// Pearl white orb with layered ridges, inspired by Apple Intelligence orb.
// Idles with a slow breath; responds to AI activity with shimmer + glow.

struct BereanOrbView: View {

    /// When true the orb pulses faster and gains a lavender shimmer.
    var isActive: Bool = false
    /// Optional tap action (e.g. focus input or cancel generation).
    var onTap: (() -> Void)? = nil

    @State private var breathScale: CGFloat = 1.0
    @State private var shimmerAngle: Double = 0
    @State private var glowOpacity: Double = 0

    private let size: CGFloat = 110

    var body: some View {
        ZStack {
            // ── Soft outer glow — intensifies when active ─────────────────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.80, green: 0.78, blue: 0.92).opacity(isActive ? 0.55 : 0.20),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.85
                    )
                )
                .frame(width: size * 1.55, height: size * 1.55)
                .scaleEffect(breathScale * 1.05)
                .opacity(glowOpacity)

            // ── Main sphere body ──────────────────────────────────────────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color(white: 0.91),
                            Color(red: 0.87, green: 0.86, blue: 0.93)
                        ],
                        center: UnitPoint(x: 0.38, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.72
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    // Layered curved ridges — the signature detail from the reference image
                    ZStack {
                        ForEach(0..<5, id: \.self) { i in
                            RidgeShape(index: i)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(white: 0.72).opacity(0.60 - Double(i) * 0.09),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blendMode(.multiply)
                        }
                    }
                    .clipShape(Circle())
                )
                .overlay(
                    // Specular highlight — top-left bright spot
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.90), .white.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.28
                            )
                        )
                        .frame(width: size * 0.42, height: size * 0.32)
                        .offset(x: -size * 0.15, y: -size * 0.18)
                )
                .overlay(
                    // Active shimmer sweep — rotates when generating
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    Color.white.opacity(isActive ? 0.35 : 0),
                                    Color(red: 0.78, green: 0.76, blue: 0.96).opacity(isActive ? 0.25 : 0),
                                    Color.white.opacity(0)
                                ],
                                center: .center,
                                startAngle: .degrees(shimmerAngle),
                                endAngle: .degrees(shimmerAngle + 160)
                            )
                        )
                        .blendMode(.screen)
                        .opacity(isActive ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: isActive)
                )
                .shadow(color: Color(white: 0.60).opacity(0.30), radius: 18, x: 0, y: 8)
                .shadow(color: Color(white: 0.85).opacity(0.80), radius: 4, x: -3, y: -3)
                .scaleEffect(breathScale)
                .animation(
                    isActive
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                    value: breathScale
                )
        }
        .onAppear {
            breathScale = isActive ? 1.06 : 1.032
            glowOpacity = isActive ? 1 : 0.6
            if isActive {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    shimmerAngle = 360
                }
            }
        }
        .onChange(of: isActive) { _, active in
            withAnimation(.easeInOut(duration: 0.45)) {
                breathScale = active ? 1.06 : 1.032
                glowOpacity = active ? 1 : 0.6
            }
            if active {
                shimmerAngle = 0
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    shimmerAngle = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    shimmerAngle = 0
                }
            }
        }
        .onTapGesture {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            onTap?()
        }
        .accessibilityLabel(isActive ? "Berean is thinking" : "Berean AI")
        .accessibilityAddTraits(.isButton)
    }
}

// Crescent-arc ridge shape used inside BereanOrbView to replicate the layered
// "pages" look of the reference orb image.
private struct RidgeShape: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r  = rect.width * 0.5

        // Each ridge is a thick crescent arc swept through the lower-left quadrant,
        // offset slightly so they fan out like pages.
        let offset = CGFloat(index) * 0.07
        let thickness: CGFloat = r * 0.22
        let outerR = r * (0.55 + offset)
        let innerR = outerR - thickness

        let startAngle = Angle.degrees(125 + Double(index) * 8)
        let endAngle   = Angle.degrees(270 + Double(index) * 6)

        // Outer arc
        path.addArc(center: CGPoint(x: cx, y: cy),
                    radius: outerR,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        // Inner arc (reversed to close the crescent)
        path.addArc(center: CGPoint(x: cx, y: cy),
                    radius: innerR,
                    startAngle: endAngle,
                    endAngle: startAngle,
                    clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - BereanLandingQuickGrid
// 2-column grid of tappable quick-action cards with icon badge + label.

struct BereanLandingQuickGrid: View {

    let onTap: (String) -> Void

    private struct QuickAction: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let prompt: String
        let tint: Color
    }

    private let actions: [QuickAction] = [
        QuickAction(icon: "book.closed",         label: "Study Scripture",     prompt: "Help me study a Scripture passage in depth.",                            tint: BereanDesign.coral),
        QuickAction(icon: "lightbulb",            label: "Explain a Verse",     prompt: "Explain this verse and its meaning:",                                    tint: Color(red: 0.28, green: 0.56, blue: 0.90)),
        QuickAction(icon: "figure.walk",          label: "Help Me Discern",     prompt: "Help me discern a decision I'm facing from a biblical perspective.",     tint: Color(red: 0.30, green: 0.68, blue: 0.54)),
        QuickAction(icon: "heart.text.square",    label: "Help Me Pray",        prompt: "Help me pray through something I'm carrying.",                           tint: Color(red: 0.68, green: 0.32, blue: 0.72)),
        QuickAction(icon: "briefcase",            label: "Faith & Work",        prompt: "What does Scripture say about work, purpose, and calling?",              tint: Color(red: 0.72, green: 0.48, blue: 0.22)),
        QuickAction(icon: "sparkles",             label: "Ask Anything",        prompt: "",                                                                       tint: BereanDesign.coral),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    @State private var visibleCards: Set<UUID> = []

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                BereanLandingActionCard(
                    icon: action.icon,
                    label: action.label,
                    tint: action.tint
                ) {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred(intensity: 0.7)
                    if action.prompt.isEmpty {
                        // "Ask Anything" — just focus the input, no pre-fill
                        onTap("")
                    } else {
                        onTap(action.prompt)
                    }
                }
                .opacity(visibleCards.contains(action.id) ? 1 : 0)
                .offset(y: visibleCards.contains(action.id) ? 0 : 8)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.80)
                        .delay(Double(idx) * 0.06),
                    value: visibleCards.contains(action.id)
                )
            }
        }
        .padding(.horizontal, BereanDesign.pagePad)
        .onAppear {
            for (i, action) in actions.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                    visibleCards.insert(action.id)
                }
            }
        }
    }
}

// MARK: - BereanLandingActionCard
// Single tappable card: icon badge left, bold label right. White surface, subtle shadow.

struct BereanLandingActionCard: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.13))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(pressed ? 0.76 : 0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.065), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.055), radius: 8, x: 0, y: 3)
            )
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        ._onButtonGesture { pressing in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                pressed = pressing
            }
        } perform: {}
        .accessibilityLabel(label)
    }
}

// MARK: - BereanLandingSuggestedPrompts
// Soft white card listing curated suggested prompts with hairline dividers.

struct BereanLandingSuggestedPrompts: View {
    let onTap: (String) -> Void

    private let prompts: [(icon: String, text: String)] = [
        ("text.book.closed",   "What does Scripture say about anxiety?"),
        ("figure.2.arms.open", "How do I forgive someone who hurt me?"),
        ("briefcase",          "Give me a biblical lens on my work situation."),
        ("moon.stars",         "Help me understand the book of Psalms."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Section label
            Text("Try asking")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.50))
                .tracking(1.0)
                .textCase(.uppercase)
                .padding(.horizontal, BereanDesign.pagePad)
                .padding(.bottom, 10)

            // Rows inside white card
            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { idx, item in
                    BereanLandingPromptRow(
                        icon: item.icon,
                        text: item.text,
                        isLast: idx == prompts.count - 1,
                        onTap: { onTap(item.text) }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 14, y: 4)
            )
            .padding(.horizontal, BereanDesign.pagePad)
        }
    }
}

// MARK: - BereanLandingPromptRow
// Single row in the suggested prompts card: dot accent + text + arrow.

struct BereanLandingPromptRow: View {
    let icon: String
    let text: String
    let isLast: Bool
    let onTap: () -> Void

    @State private var highlighted = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            onTap()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BereanDesign.coral.opacity(0.75))
                    .frame(width: 18)

                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.14))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.48))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(highlighted ? Color.black.opacity(0.03) : Color.clear)
        }
        .buttonStyle(.plain)
        ._onButtonGesture { pressing in
            withAnimation(.easeOut(duration: 0.14)) { highlighted = pressing }
        } perform: {}
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.055))
                    .frame(height: 0.5)
                    .padding(.leading, 46)
            }
        }
        .accessibilityLabel(text)
    }
}

// MARK: - BereanHeroWelcomeSection
/// Reference-inspired hero card: large white rounded container, "Ask Berean" coral
/// title, gradient mode-capsule with floating chrome badge, large pill actions below.
/// All logic preserved — only the visual hierarchy has been elevated.

struct BereanHeroWelcomeSection: View {
    let shouldCollapse: Bool
    let bibleIconScale: CGFloat
    let bibleIconOpacity: Double
    let welcomeText: String
    let welcomeTextIndex: Int
    @Binding var personalityMode: BereanPersonalityMode
    let onAskTapped: () -> Void

    @State private var heroVisible = false
    @State private var badgePressed = false
    @State private var orbPulse: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            if !shouldCollapse {
                // ── Large white rounded hero card (reference: white card, big radius) ──
                VStack(alignment: .leading, spacing: 0) {

                    // ── Title row: "Ask Berean" + gradient mode capsule ──────
                    HStack(alignment: .center, spacing: 12) {

                        // Large coral title — mirrors "Auto-Do" treatment
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ask Berean")
                                .font(.system(size: 30, weight: .semibold, design: .serif))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            BereanDesign.coral,
                                            Color(red: 0.92, green: 0.42, blue: 0.32)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .tracking(-0.5)

                            Text("Scripture, wisdom & guidance")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(BereanDesign.textSecond)
                        }

                        Spacer()

                        // ── Gradient mode capsule + floating chrome badge ──────
                        // Inspired by reference: pink→orange gradient toggle pill
                        // with an oversized chrome circle badge that bleeds out.
                        // Bound to real `personalityMode` state.
                        BereanModeCapsule(personalityMode: $personalityMode)
                    }
                    .padding(.top, 22)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .opacity(heroVisible ? 1 : 0)
                    .offset(y: heroVisible ? 0 : 10)
                    .animation(.spring(response: 0.68, dampingFraction: 0.78).delay(0.06), value: heroVisible)

                    // ── Hairline divider ─────────────────────────────────────
                    Rectangle()
                        .fill(Color.black.opacity(0.055))
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)

                    // ── Rotating subtitle ────────────────────────────────────
                    Text(welcomeText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BereanDesign.textSecond)
                        .multilineTextAlignment(.leading)
                        .transition(.opacity.animation(.easeInOut(duration: 0.40)))
                        .id(welcomeTextIndex)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .opacity(heroVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.46).delay(0.18), value: heroVisible)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    // Reference: pure white surface, very large corner radius
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.97))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(0.07), radius: 22, y: 6)
                        .shadow(color: BereanDesign.coral.opacity(0.04), radius: 28, y: 10)
                )
                .transition(.opacity.combined(with: .offset(y: -6)))

            } else {
                // ── Collapsed: compact pill showing active mode
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.50, blue: 0.32), BereanDesign.coral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 8, height: 8)
                    Text("Berean · \(personalityMode.rawValue)")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(BereanDesign.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            heroVisible = true
            orbPulse = 1.06
        }
        .animation(.spring(response: 0.40, dampingFraction: 0.78), value: shouldCollapse)
    }
}

// MARK: - BereanModeCapsule
/// Reference-inspired gradient toggle pill + floating chrome badge.
/// The gradient pill (pink→coral) selects the next personality mode on tap.
/// The chrome badge overlapping the right edge shows the active mode icon,
/// mimicking the silver-ringed circle badge in the reference image.

struct BereanModeCapsule: View {
    @Binding var personalityMode: BereanPersonalityMode
    @State private var badgeScale: CGFloat = 1.0
    @State private var shimmerPhase: CGFloat = 0

    // Warm pink → coral gradient — mirrors reference's pink→orange toggle
    private let capsuleGradient = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.40, blue: 0.60),
            Color(red: 0.98, green: 0.52, blue: 0.28),
            BereanDesign.coral
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        // The ZStack lets the chrome badge bleed outside the pill track,
        // exactly matching the reference's overlapping chrome circle.
        ZStack(alignment: .trailing) {

            // ── Gradient pill track ────────────────────────────────────────
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // Advance to next personality mode (cycles through all cases)
                let allCases = BereanPersonalityMode.allCases
                if let idx = allCases.firstIndex(of: personalityMode) {
                    let next = allCases[(idx + 1) % allCases.count]
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        personalityMode = next
                        badgeScale = 0.80
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.58)) {
                            badgeScale = 1.06
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                            badgeScale = 1.0
                        }
                    }
                }
            } label: {
                // Pill track with inner shimmer sweep
                ZStack {
                    Capsule()
                        .fill(capsuleGradient)
                        .frame(width: 68, height: 34)

                    // Subtle inner shimmer — sweeps left-to-right on appear
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .white.opacity(0.30), location: 0.4),
                                    .init(color: .white.opacity(0.30), location: 0.6),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .init(x: shimmerPhase - 0.3, y: 0),
                                endPoint: .init(x: shimmerPhase + 0.3, y: 0)
                            )
                        )
                        .frame(width: 68, height: 34)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            // Extend touch target rightward into badge area
            .frame(width: 68 + 14)

            // ── Floating chrome badge ─────────────────────────────────────
            // Mimics the reference's silver/chrome circle that bleeds out of the pill
            ZStack {
                // Outer chrome ring — two-stop silver gradient, like a UI button cap
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.92),
                                Color(white: 0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(white: 1.0), Color(white: 0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)

                // Inner inset — slightly darker, gives the "beveled" depth
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.84), Color(white: 0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)

                // Mode icon — warm coral/gold, matches reference's gold person icon
                Image(systemName: personalityMode.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.78, blue: 0.42),
                                BereanDesign.coral
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: personalityMode)
            }
            .scaleEffect(badgeScale)
            // Bleed 10pt outside the pill (matches reference)
            .offset(x: 10)
            .allowsHitTesting(false)
        }
        // Total frame: pill width (68) + badge bleed (10) + slight margin (4)
        .frame(width: 68 + 24, height: 46, alignment: .trailing)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.3
            }
        }
    }
}

// MARK: - BereanHeroScriptureChip
/// Small pill showing "Scripture-grounded · Theologically aware"
/// Conveys Berean's guiding principle at a glance.

struct BereanHeroScriptureChip: View {
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BereanDesign.coral)

            Text("Scripture-grounded · Theologically aware")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.30))
                .tracking(0.1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.80))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.07), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
        )
    }
}

// MARK: - BereanGroundedQuickSection
/// Large pill action buttons below the hero card — inspired by the reference "Assign" pill style.
/// Two-column grid so each pill feels prominent and tappable.

struct BereanGroundedQuickSection: View {
    let onStudyPassage: () -> Void
    let onExplainVerse: () -> Void
    let onCompareTranslations: () -> Void
    let onHistoricalContext: () -> Void
    let onDailyDevotion: () -> Void
    let onNewPrompt: () -> Void

    @State private var visible = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            BereanQuickPill(icon: "book.closed",       label: "Study Scripture",  tint: BereanDesign.coral,                         action: onStudyPassage)
            BereanQuickPill(icon: "lightbulb",         label: "Explain a Verse",  tint: Color(red: 0.28, green: 0.56, blue: 0.90),  action: onExplainVerse)
            BereanQuickPill(icon: "doc.text",          label: "Compare Versions", tint: Color(red: 0.30, green: 0.72, blue: 0.58),  action: onCompareTranslations)
            BereanQuickPill(icon: "map",               label: "History & Context",tint: Color(red: 0.72, green: 0.48, blue: 0.28),  action: onHistoricalContext)
            BereanQuickPill(icon: "heart.text.square", label: "Daily Devotion",   tint: Color(red: 0.68, green: 0.32, blue: 0.72),  action: onDailyDevotion)
            BereanQuickPill(icon: "sparkles",          label: "Ask Anything",     tint: BereanDesign.coral,                         action: onNewPrompt)
        }
        .padding(.horizontal, BereanDesign.pagePad)
        .padding(.top, 12)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 12)
        .animation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.18), value: visible)
        .onAppear { visible = true }
    }
}

// MARK: - BereanQuickPill
/// Large rounded pill button — reference "Assign" style: prominent icon badge + bold label.
/// Full-width within its grid cell so it fills the available space.

struct BereanQuickPill: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Tinted icon badge — larger and more prominent
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(pressed ? 0.78 : 0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.07), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        ._onButtonGesture { pressing in
            withAnimation(.spring(response: 0.26, dampingFraction: 0.68)) {
                pressed = pressing
            }
        } perform: {}
    }
}

// MARK: - BereanGroundedPromptsSection
/// Clean editorial card housing suggested prompts — white surface, divider rows,
/// subtle accent dots. Premium, spacious, minimal.

struct BereanGroundedPromptsSection: View {
    let prompts: [String]
    let onSelectPrompt: (String) -> Void
    let onNewPrompt: () -> Void

    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("Try asking")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.50))
                    .tracking(1.0)
                    .textCase(.uppercase)
                Spacer()
                Button(action: onNewPrompt) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(BereanDesign.coral)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BereanDesign.pagePad)
            .padding(.bottom, 10)

            // Prompt rows — frosted glass card, Dia premium
            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { idx, prompt in
                    BereanGroundedPromptRow(
                        prompt: prompt,
                        isLast: idx == prompts.count - 1,
                        onTap: { onSelectPrompt(prompt) }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 14, y: 4)
            )
            .padding(.horizontal, BereanDesign.pagePad)
        }
        .padding(.vertical, 16)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 12)
        .animation(.spring(response: 0.60, dampingFraction: 0.80).delay(0.18), value: visible)
        .onAppear { visible = true }
    }
}

// MARK: - BereanGroundedPromptRow
/// Single tappable prompt row inside the grounded prompts panel.

struct BereanGroundedPromptRow: View {
    let prompt: String
    let isLast: Bool
    let onTap: () -> Void

    @State private var highlighted = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Leading scripture-tone accent dot
                Circle()
                    .fill(BereanDesign.coral.opacity(0.55))
                    .frame(width: 5, height: 5)

                Text(prompt)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.16))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.50))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(highlighted ? Color.black.opacity(0.03) : Color.clear)
        }
        .buttonStyle(.plain)
        ._onButtonGesture { pressing in
            withAnimation(.easeOut(duration: 0.15)) {
                highlighted = pressing
            }
        } perform: {}
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.055))
                    .frame(height: 0.5)
                    .padding(.leading, 32)
            }
        }
    }
}




