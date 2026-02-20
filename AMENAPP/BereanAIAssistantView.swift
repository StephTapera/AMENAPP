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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BereanViewModel()
    @State private var messageText = ""
    @State private var showSuggestions = true
    @State private var isThinking = false
    @FocusState private var isInputFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var showSmartFeatures = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isVoiceListening = false
    @State private var showContextMenu = false
    @State private var showShareSheet = false
    @State private var messageToShare: BereanMessage?
    @State private var showPremiumUpgrade = false
    @State private var isGenerating = false  // ✅ Track if AI is generating
    
    // ✅ New state variables for enhancements
    @State private var showTranslationPicker = false
    @State private var showHistoryView = false
    @State private var showClearAllAlert = false
    @State private var showNewConversationAlert = false
    
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
    
    var body: some View {
        ZStack {
            // Elegant gradient background inspired by modern design
            ZStack {
                // Base gradient - soft warm to cool tones
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.94), // Soft cream
                        Color(red: 0.95, green: 0.94, blue: 0.96), // Subtle lavender
                        Color(red: 0.96, green: 0.95, blue: 0.94)  // Warm white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Floating gradient orbs for depth
                GeometryReader { geometry in
                    ZStack {
                        // Orange glow (top right)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.6, blue: 0.4).opacity(0.4),
                                        Color(red: 1.0, green: 0.7, blue: 0.5).opacity(0.2),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 300
                                )
                            )
                            .frame(width: 600, height: 600)
                            .offset(x: geometry.size.width * 0.6, y: -200)
                            .blur(radius: 60)
                        
                        // Blue-purple glow (bottom left)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.5, green: 0.6, blue: 0.9).opacity(0.3),
                                        Color(red: 0.6, green: 0.5, blue: 0.8).opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 300
                                )
                            )
                            .frame(width: 500, height: 500)
                            .offset(x: -100, y: geometry.size.height * 0.7)
                            .blur(radius: 50)
                        
                        // Accent peach glow (center-right)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.95, green: 0.7, blue: 0.6).opacity(0.25),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 30,
                                    endRadius: 200
                                )
                            )
                            .frame(width: 400, height: 400)
                            .offset(x: geometry.size.width * 0.5, y: geometry.size.height * 0.4)
                            .blur(radius: 40)
                    }
                }
            }
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
                                    MessageBubbleView(message: message)
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
                        .padding(.bottom, 80) // Reduced space for smaller floating input bar
                    }
                    .refreshable {
                        await refreshConversation()
                    }
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
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
                onSelect: { conversation in
                    viewModel.loadConversation(conversation)
                    showHistoryView = false
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
        // ✅ Saved Messages
        .sheet(isPresented: $showSavedMessages) {
            BereanSavedMessagesView()
        }
        // ✅ Report Issue
        .sheet(isPresented: $showReportIssue) {
            if let message = messageToReport {
                ReportIssueView(message: message, isPresented: $showReportIssue)
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
        .onAppear {
            checkOnboardingStatus()
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
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
                closeButton
                
                bereanBranding
                
                Spacer()
                
                smartFeaturesButton
                
                premiumBadgeButton
                
                settingsMenuButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(headerBackground)
        }
    }
    
    private var closeButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(white: 0.4))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
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
        VStack(spacing: 32) {
            // Minimal Animated Icon
            ZStack {
                // Soft gradient rings
                ForEach(0..<2) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.7, blue: 0.5).opacity(0.15),
                                    Color(red: 0.6, green: 0.5, blue: 0.9).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 70 + CGFloat(index * 30), height: 70 + CGFloat(index * 30))
                        .scaleEffect(1.0 + CGFloat(index) * 0.05)
                }
                
                // Central glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.7, blue: 0.5).opacity(0.2),
                                Color(red: 0.6, green: 0.5, blue: 0.9).opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 40
                        )
                    )
                    .frame(width: 70, height: 70)
                
                // Icon
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(Color(white: 0.3))
                    .symbolEffect(.pulse.byLayer)
            }
            .padding(.top, 60)
            
            VStack(spacing: 16) {
                Text("Berean AI")
                    .font(.custom("Georgia", size: 48))
                    .fontWeight(.light)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(white: 0.2),
                                Color(white: 0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .tracking(1)
                
                Text("Your intelligent Bible study companion. Ask questions, explore context, and deepen your understanding of Scripture.")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .textCase(.uppercase)
                .tracking(2)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                BereanQuickActionCard(
                    icon: "book.closed.fill",
                    title: "Study Passage",
                    color: Color(red: 0.5, green: 0.6, blue: 0.9)
                ) {
                    messageText = "Help me study "
                    isInputFocused = true
                }
                
                BereanQuickActionCard(
                    icon: "lightbulb.fill",
                    title: "Explain Verse",
                    color: Color(red: 1.0, green: 0.7, blue: 0.5)
                ) {
                    messageText = "Explain "
                    isInputFocused = true
                }
                
                BereanQuickActionCard(
                    icon: "doc.text.fill",
                    title: "Compare",
                    color: Color(red: 0.95, green: 0.7, blue: 0.6)
                ) {
                    sendMessage("Compare Bible translations for a verse")
                }
                
                BereanQuickActionCard(
                    icon: "map.fill",
                    title: "Context",
                    color: Color(red: 0.6, green: 0.5, blue: 0.8)
                ) {
                    sendMessage("Tell me about Biblical context")
                }
            }
        }
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
            
            VStack(spacing: 8) {
                ForEach(viewModel.suggestedPrompts, id: \.self) { prompt in
                    SuggestedPromptCard(prompt: prompt) {
                        sendMessage(prompt)
                    }
                }
            }
        }
        .padding(.top, 24)
    }
    
    // MARK: - Input Bar (Glassmorphic - Bottom Fixed)
    
    private var inputBarView: some View {
        VStack(spacing: 0) {
            // Compact glassmorphic pill - smaller and closer to bottom
            HStack(alignment: .center, spacing: 12) {
                // Plus button (left side) - WHITE/LIGHT - Smaller
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    handlePlusButtonTap()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
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
    
    private var textInputFieldGlassmorphic: some View {
        TextField("Ask AI", text: $messageText, axis: .vertical)
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
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Message input field")
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
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            .shadow(color: .white.opacity(0.2), radius: 2, x: 0, y: -1)
    }
    
    // MARK: - Input Bar Action Handlers
    
    /// Handle plus button tap (add attachments/options)
    private func handlePlusButtonTap() {
        // Production-ready: Show action sheet for attachment options
        #if DEBUG
        print("➕ Plus button tapped - Show attachment options")
        #endif
        
        // Future: Show action sheet with options like:
        // - Upload image
        // - Search Bible passage
        // - Smart features
        // - Saved prompts
    }
    
    /// Handle voice button tap (start/stop voice input)
    private func handleVoiceButtonTap() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVoiceListening.toggle()
        }
        
        #if DEBUG
        print(isVoiceListening ? "🎤 Voice listening started" : "🎤 Voice listening stopped")
        #endif
        
        // Production-ready: Integrate with Speech framework
        if isVoiceListening {
            // Start speech recognition
            // Future: Use SFSpeechRecognizer
        } else {
            // Stop speech recognition
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
    
    /// Setup keyboard observers for smooth animations
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
    
    /// Remove keyboard observers
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
        
        guard let lastUserMessage = viewModel.messages.last(where: { $0.role == .user }) else {
            print("⚠️ No user message to retry")
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
        
        print("🔄 Retrying last message: \(lastUserMessage.content.prefix(50))...")
        
        // Resend the message
        sendMessage(lastUserMessage.content)
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
    
    /// Stop AI generation
    private func stopGeneration() {
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
    
    private func sendMessage(_ text: String) {
        // Trim whitespace and check if empty
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            print("⚠️ Cannot send empty message")
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
        
        // ✅ Dismiss keyboard
        isInputFocused = false
        
        let userMessage = BereanMessage(
            content: trimmedText,
            role: .user,
            timestamp: Date()
        )
        
        withAnimation(.easeOut(duration: 0.25)) {
            viewModel.messages.append(userMessage)
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
            viewModel.messages.append(placeholderMessage)
        }
        
        // Call Genkit with streaming and comprehensive error handling
        viewModel.generateResponseStreaming(
            for: trimmedText,
            onChunk: { chunk in
                // Update the last message with new chunk
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
                // Replace placeholder with final message
                if let lastIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }) {
                    viewModel.messages[lastIndex] = finalMessage
                }
                
                // ✅ Track usage for free tier users
                premiumManager.incrementMessageCount()
                print("📊 Message count updated: \(premiumManager.freeMessagesUsed)/\(premiumManager.FREE_MESSAGES_PER_DAY)")
                
                withAnimation(.easeOut(duration: 0.3)) {
                    isThinking = false
                    isGenerating = false  // ✅ Clear generating state
                }
                
                // Success haptic
                let successHaptic = UINotificationFeedbackGenerator()
                successHaptic.notificationOccurred(.success)
                
                print("✅ Message sent and response received successfully")
            },
            onError: { error in
                print("❌ Error generating response: \(error.localizedDescription)")
                
                // Remove the placeholder message on error
                if let lastIndex = viewModel.messages.lastIndex(where: { $0.role == .assistant }),
                   viewModel.messages[lastIndex].content.isEmpty {
                    viewModel.messages.remove(at: lastIndex)
                }
                
                withAnimation(.easeOut(duration: 0.3)) {
                    isThinking = false
                    isGenerating = false  // ✅ Clear generating state
                }
                
                // Determine error type
                let bereanError: BereanError
                if let openAIError = error as? OpenAIError {
                    switch openAIError {
                    case .missingAPIKey:
                        bereanError = .invalidResponse
                    case .invalidResponse:
                        bereanError = .invalidResponse
                    case .httpError(let statusCode):
                        if statusCode == 429 {
                            bereanError = .rateLimitExceeded
                        } else if statusCode >= 500 {
                            bereanError = .aiServiceUnavailable
                        } else {
                            bereanError = .unknown("Server error (\(statusCode))")
                        }
                    }
                } else if let urlError = error as? URLError {
                    if urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                        bereanError = .networkUnavailable
                    } else if urlError.code == .timedOut {
                        bereanError = .aiServiceUnavailable
                    } else {
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
                                do {
                                    // Copy text
                                    UIPasteboard.general.string = message.content
                                    
                                    let haptic = UINotificationFeedbackGenerator()
                                    haptic.notificationOccurred(.success)
                                    
                                    print("✅ Message copied to clipboard")
                                } catch {
                                    print("❌ Failed to copy to clipboard: \(error.localizedDescription)")
                                    
                                    let haptic = UINotificationFeedbackGenerator()
                                    haptic.notificationOccurred(.error)
                                }
                            } label: {
                                Label("Copy Text", systemImage: "doc.on.doc")
                            }
                            
                            Button {
                                do {
                                    // Save for later
                                    dataManager.saveMessage(message)
                                    
                                    let haptic = UINotificationFeedbackGenerator()
                                    haptic.notificationOccurred(.success)
                                    
                                    print("✅ Message saved for later")
                                } catch {
                                    print("❌ Failed to save message: \(error.localizedDescription)")
                                    
                                    let haptic = UINotificationFeedbackGenerator()
                                    haptic.notificationOccurred(.error)
                                }
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
        // Copy to clipboard for now
        UIPasteboard.general.string = message.verseReferences.first ?? ""
        print("📖 Opening verse: \(message.verseReferences.first ?? "")")
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
        UIPasteboard.general.string = reference
        print("📖 Opening verse: \(reference)")
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

struct BereanMessage: Identifiable, Codable {
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
    
    // Timeout configuration
    private let requestTimeout: TimeInterval = 60.0  // 60 seconds
    
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
        "Tell me about Paul's missionary journeys"
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
        print("⏸️ Stopped AI generation")
    }
    
    // MARK: - Generate Response with Genkit AI (Streaming)
    
    func generateResponseStreaming(
        for query: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (BereanMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
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
        
        // ⚡ SPEED OPTIMIZATION: Limit conversation history to last 10 messages
        // This reduces payload size and AI processing time significantly
        let recentHistory = Array(messages.suffix(10))
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Create new task with timeout
        currentTask = Task {
            do {
                var fullResponse = ""
                let startTime = Date()
                
                // Stream response from Genkit with timeout monitoring
                // ⚡ Use limited history for faster processing
                for try await chunk in genkitService.sendMessage(query, conversationHistory: recentHistory) {
                    // ✅ Check if task was cancelled
                    if Task.isCancelled {
                        print("⏸️ Generation cancelled by user")
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
                    return
                }
                
                // Validate response
                guard !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("❌ Received empty response from AI")
                    throw NSError(
                        domain: "BereanViewModel",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "AI returned empty response"]
                    )
                }
                
                // Create final message with verse references extracted
                let verseReferences = extractVerseReferences(from: fullResponse)
                let finalMessage = BereanMessage(
                    content: fullResponse,
                    role: .assistant,
                    timestamp: Date(),
                    verseReferences: verseReferences
                )
                
                await MainActor.run {
                    onComplete(finalMessage)
                }
                
                let duration = Date().timeIntervalSince(startTime)
                print("✅ Response generation completed successfully in \(String(format: "%.2f", duration))s")
                
            } catch is CancellationError {
                // Task was cancelled - don't report as error
                print("⏸️ Generation task cancelled")
                return
            } catch let error as OpenAIError {
                // ✅ Don't show error if cancelled
                guard !Task.isCancelled else { return }
                
                print("❌ OpenAI error: \(error.localizedDescription)")
                await MainActor.run {
                    onError(error)
                }
                
                // ✅ Production: No mock responses - show real errors to users
            } catch {
                // ✅ Don't show error if cancelled
                guard !Task.isCancelled else { return }
                
                print("❌ Unexpected error during streaming: \(error.localizedDescription)")
                await MainActor.run {
                    onError(error)
                }
                
                // ✅ Production: No mock responses - show real errors to users
            }
        }
    }
    
    // MARK: - Helper: Extract Verse References
    
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


