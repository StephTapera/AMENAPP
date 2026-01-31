//
//  AIBibleStudyView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct AIBibleStudyView: View {
    @Environment(\.dismiss) var dismiss
    @State var selectedTab: AIStudyTab = .chat
    @State private var userInput = ""
    @State var messages: [AIStudyMessage] = []
    @State private var isProcessing = false
    @State private var showProUpgrade = false
    @State private var hasProAccess = false // Set to true if user has Pro
    @State private var showVoiceInput = false
    @State private var isListening = false
    @State private var pulseAnimation = false
    @State private var shimmerPhase: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var savedMessages: [AIStudyMessage] = []
    @State var conversationHistory: [[AIStudyMessage]] = []
    @State var showHistory = false
    @State private var showSettings = false
    @State private var currentStreak = 7
    
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
            ZStack {
                VStack(spacing: 0) {
                    // Enhanced Header with Pro Badge
                    headerView
                    
                    // Enhanced Tab selector with icons
                    tabSelector
                    
                    Divider()
                    
                    // Content with ScrollViewReader for keyboard handling
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 20) {
                                // Streak Banner (only for chat tab)
                                if selectedTab == .chat && hasProAccess {
                                    StreakBanner(currentStreak: $currentStreak)
                                        .padding(.horizontal)
                                        .padding(.top)
                                }
                                
                                switch selectedTab {
                                case .chat:
                                    ChatContent(
                                        messages: $messages,
                                        isProcessing: $isProcessing,
                                        savedMessages: $savedMessages
                                    )
                                        .id("chatContent")
                                case .insights:
                                    InsightsContent()
                                case .questions:
                                    QuestionsContent(onQuestionTap: { question in
                                        selectedTab = .chat
                                        userInput = question
                                        isInputFocused = true
                                    })
                                case .devotional:
                                    DevotionalContent(savedMessages: $savedMessages)
                                case .study:
                                    StudyPlansContent()
                                case .analysis:
                                    AnalysisContent()
                                case .memorize:
                                    MemorizeContent()
                                }
                                
                                // Bottom spacer to prevent keyboard overlap
                                if selectedTab == .chat {
                                    Color.clear
                                        .frame(height: 120)
                                        .id("bottomSpacer")
                                }
                            }
                            .padding(.vertical)
                        }
                        .onChange(of: messages.count) { _, _ in
                            // Scroll to bottom when new message appears
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottomSpacer", anchor: .bottom)
                            }
                        }
                        .onChange(of: isInputFocused) { _, focused in
                            // Scroll to bottom when keyboard appears
                            if focused {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("bottomSpacer", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Input area (only for chat tab)
                    if selectedTab == .chat {
                        ChatInputArea(
                            userInput: $userInput,
                            isProcessing: $isProcessing,
                            isInputFocused: $isInputFocused,
                            onSend: sendMessage,
                            onClear: clearConversation
                        )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // History button
                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                        }
                        
                        // Settings button
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeSheet(hasProAccess: $hasProAccess)
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
        .onAppear {
            setupKeyboardObservers()
            
            // Shimmer animation
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerPhase = 200
            }
            
            if messages.isEmpty {
                // Animated message appearance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        messages.append(AIStudyMessage(
                            text: "Hello! I'm your AI Bible Study assistant. 🙏\n\nI can help you:\n• Understand Scripture passages\n• Answer theological questions\n• Provide biblical guidance\n• Explore original Greek & Hebrew\n• Generate personalized devotionals\n• Create custom study plans\n• Analyze biblical themes\n• Help you memorize verses\n\nHow can I assist you today?",
                            isUser: false
                        ))
                    }
                }
            }
        }
        .onDisappear {
            removeKeyboardObservers()
            saveCurrentConversation()
        }
    }
    
    // MARK: - Extracted Views
    
    private var headerView: some View {
        HStack {
            // AI Bible Study Icon + Title
            HStack(spacing: 12) {
                // Stylish "B" Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.purple.opacity(0.4), radius: 8, y: 3)
                    
                    Text("B")
                        .font(.custom("OpenSans-Bold", size: 26))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.white.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Bible Study")
                        .font(.custom("OpenSans-Bold", size: 28))
                    
                    Text("Powered by Biblical AI")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Pro Badge Button - Modern Sparkle Design
            proButton
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 12)
    }
    
    private var proButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showProUpgrade = true
            }
        } label: {
            HStack(spacing: 6) {
                if hasProAccess {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                }
                
                Text(hasProAccess ? "PRO" : "Go Pro")
                    .font(.custom("OpenSans-Bold", size: 13))
            }
            .foregroundStyle(
                hasProAccess ?
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        colors: [.white, .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: hasProAccess ?
                                    [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15), Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.1)] :
                                    [Color(red: 0.5, green: 0.3, blue: 1.0), Color(red: 0.7, green: 0.4, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Shimmer effect for non-pro
                    if !hasProAccess {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0),
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerPhase)
                            .mask(Capsule())
                    }
                }
            )
            .shadow(
                color: hasProAccess ?
                    Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.4) :
                    Color.purple.opacity(0.4),
                radius: 8,
                y: 2
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: hasProAccess ?
                                [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.6), Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.4)] :
                                [Color.white.opacity(0.4), Color.white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AIStudyTab.allCases, id: \.self) { tab in
                    Button {
                        if tab.requiresPro && !hasProAccess {
                            showProUpgrade = true
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = tab
                                // Dismiss keyboard when switching tabs
                                isInputFocused = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                            
                            if tab.requiresPro && !hasProAccess {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? 
                                    LinearGradient(
                                        colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) : 
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(
                                    color: selectedTab == tab ? Color.purple.opacity(0.3) : .clear,
                                    radius: 8,
                                    y: 2
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
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
    
    private func sendMessage() {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let message = AIStudyMessage(text: userInput, isUser: true)
        messages.append(message)
        let questionText = userInput
        userInput = ""
        
        isProcessing = true
        
        // Call real AI API
        Task {
            do {
                let response = try await callBibleChatAPI(message: questionText)
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
        let url = URL(string: "http://localhost:3400/bibleChat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert message history to API format
        let history = messages.map { msg in
            ["role": msg.isUser ? "user" : "assistant", "content": msg.text]
        }
        
        let body: [String: Any] = [
            "data": [
                "message": message,
                "history": history
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse response
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [String: Any],
           let response = result["response"] as? String {
            return response
        }
        
        throw NSError(domain: "BibleChatAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
    }
    
    // Functions are now defined in AIBibleStudyExtensions.swift
}

struct ChatContent: View {
    @Binding var messages: [AIStudyMessage]
    @Binding var isProcessing: Bool
    @Binding var savedMessages: [AIStudyMessage]
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(messages) { message in
                AIStudyMessageBubble(message: message)
            }
            
            if isProcessing {
                HStack(alignment: .top, spacing: 10) {
                    // AI Avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.4, green: 0.2, blue: 0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: Color.purple.opacity(0.3), radius: 4, y: 2)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                    
                    // Animated typing indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: 8, height: 8)
                                .scaleEffect(isProcessing ? 1.0 : 0.5)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                    value: isProcessing
                                )
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
                    )
                    
                    Spacer()
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
}

struct AIStudyMessageBubble: View {
    let message: AIStudyMessage
    @State private var appeared = false
    @State private var isLongPressed = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer()
            } else {
                // AI Avatar with pulse animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.4, green: 0.2, blue: 0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.purple.opacity(0.3), radius: 4, y: 2)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(appeared ? 1.0 : 0)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                message.isUser ?
                                    LinearGradient(
                                        colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .shadow(
                                color: message.isUser ? Color.purple.opacity(0.25) : Color.black.opacity(0.05),
                                radius: isLongPressed ? 12 : 8,
                                y: 2
                            )
                    )
                    .scaleEffect(isLongPressed ? 0.98 : 1.0)
                    .contextMenu {
                        Button {
                            // Copy to clipboard
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        
                        if !message.isUser {
                            Button {
                                // Share
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            
                            Button {
                                // Save to notes
                            } label: {
                                Label("Save", systemImage: "bookmark")
                            }
                        }
                    }
            }
            .frame(maxWidth: .infinity * 0.8, alignment: message.isUser ? .trailing : .leading)
            .offset(x: appeared ? 0 : (message.isUser ? 50 : -50))
            .opacity(appeared ? 1.0 : 0)
            
            if message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}

struct ChatInputArea: View {
    @Binding var userInput: String
    @Binding var isProcessing: Bool
    @FocusState.Binding var isInputFocused: Bool
    let onSend: () -> Void
    let onClear: () -> Void
    @State private var showQuickActions = false
    @State private var isListening = false
    
    let quickActions = [
        ("Explain verse", "book.closed.fill"),
        ("Find passage", "magnifyingglass"),
        ("Greek/Hebrew", "globe"),
        ("Application", "lightbulb.fill")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Quick Actions Bar
            if showQuickActions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(quickActions, id: \.0) { action in
                            Button {
                                userInput = action.0
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showQuickActions = false
                                }
                                isInputFocused = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: action.1)
                                        .font(.system(size: 12))
                                    Text(action.0)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Divider()
            
            HStack(spacing: 12) {
                // Quick Actions Button
                Button {
                    isInputFocused = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showQuickActions.toggle()
                    }
                } label: {
                    Image(systemName: showQuickActions ? "chevron.down.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                        .symbolEffect(.bounce, value: showQuickActions)
                }
                
                // Input field with focused state
                HStack(spacing: 8) {
                    TextField("Ask about Scripture...", text: $userInput, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .padding(.leading, 4)
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            // Send on keyboard return and dismiss keyboard
                            if !userInput.isEmpty && !isProcessing {
                                onSend()
                                isInputFocused = false
                            }
                        }
                    
                    // Voice Input Button
                    Button {
                        isInputFocused = false
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            isListening.toggle()
                        }
                        // In real app, trigger speech recognition
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    } label: {
                        ZStack {
                            if isListening {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                    .scaleEffect(isListening ? 1.3 : 1.0)
                                    .opacity(isListening ? 0 : 1)
                                    .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isListening)
                            }
                            
                            Image(systemName: isListening ? "waveform" : "mic.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(isListening ? .red : Color(red: 0.5, green: 0.3, blue: 0.9))
                                .symbolEffect(.variableColor.iterative, options: .repeating, value: isListening)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isInputFocused ? Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.4) : Color.clear, lineWidth: 2)
                        )
                )
                
                // Send button with enhanced animation
                Button(action: {
                    if !userInput.isEmpty && !isProcessing {
                        onSend()
                        isInputFocused = false // Dismiss keyboard after send
                    }
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: userInput.isEmpty ?
                                        [Color.gray.opacity(0.3), Color.gray.opacity(0.3)] :
                                        [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(
                                color: userInput.isEmpty ? .clear : Color.purple.opacity(0.4),
                                radius: 8,
                                y: 2
                            )
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: !userInput.isEmpty)
                    }
                }
                .disabled(userInput.isEmpty || isProcessing)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
}

struct InsightsContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(aiInsights) { insight in
                AIInsightCard(insight: insight)
            }
        }
    }
}

struct AIInsightCard: View {    let insight: AIInsight
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
                            .fill(insight.color.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: insight.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(insight.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        Text(insight.verse)
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.blue)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                
                if isExpanded {
                    Divider()
                    
                    Text(insight.content)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
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
                    .foregroundStyle(.cyan)
                
                Text(question)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
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

// Note: AIInsight is defined in BibleAIService.swift - using that version

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
    ),
    AIInsight(
        title: "Finding Peace",
        verse: "Philippians 4:6-7",
        content: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and minds in Christ Jesus.",
        icon: "leaf.fill",
        color: .green
    ),
    AIInsight(
        title: "Spiritual Armor",
        verse: "Ephesians 6:10-11",
        content: "Be strong in the Lord and in his mighty power. Put on the full armor of God, so that you can take your stand against the devil's schemes. We're equipped for spiritual battle through prayer, truth, righteousness, and faith.",
        icon: "shield.fill",
        color: .blue
    )
]

let suggestedQuestions = [
    "What does the Bible say about overcoming anxiety?",
    "How can I grow stronger in my faith?",
    "What is the meaning of grace in the New Testament?",
    "How do I know God's will for my life?",
    "What does it mean to be a new creation in Christ?",
    "How can I better understand the book of Revelation?",
    "What does the Bible teach about prayer?",
    "How do I develop a deeper relationship with God?",
    "What is the significance of the cross?",
    "How can I overcome temptation?"
]

// MARK: - New Content Views

struct DevotionalContent: View {
    @Binding var savedMessages: [AIStudyMessage]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Daily Devotional")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("AI-generated devotionals based on your spiritual journey")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Today's Devotional
            VStack(alignment: .leading, spacing: 16) {
                Text("Today's Word")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text("\"Trust in the LORD with all your heart\"")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                
                Text("Proverbs 3:5-6")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.blue)
                
                Text("""
                In times of uncertainty, we're called to lean not on our own understanding but on God's wisdom. This doesn't mean we stop thinking—it means we recognize that God's perspective is infinitely greater than ours.
                
                Today, identify one area where you've been relying solely on your own understanding. Bring it to God in prayer and ask Him to guide you according to His will.
                
                **Reflection Questions:**
                • Where am I trying to control outcomes instead of trusting God?
                • How has God been faithful in the past?
                • What does it look like to acknowledge Him in this situation?
                """)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .lineSpacing(6)
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        // Save devotional
                    } label: {
                        HStack {
                            Image(systemName: "bookmark.fill")
                            Text("Save")
                        }
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 0.9)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    
                    Button {
                        // Share devotional
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .stroke(Color(red: 0.5, green: 0.3, blue: 0.9), lineWidth: 2)
                        )
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
            .padding(.horizontal)
        }
    }
}

struct StudyPlansContent: View {
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("AI Study Plans")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Personalized Bible study plans tailored to your growth")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Study Plans
            ForEach(studyPlans) { plan in
                StudyPlanCard(plan: plan)
            }
        }
    }
}

struct StudyPlanCard: View {
    let plan: StudyPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(plan.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: plan.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(plan.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.custom("OpenSans-Bold", size: 17))
                    
                    Text(plan.duration)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            Text(plan.description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Progress")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(plan.progress)%")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(plan.color)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [plan.color, plan.color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(plan.progress) / 100, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

struct ProUpgradeSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var hasProAccess: Bool
    @State private var selectedPlan: PricingPlan = .monthly
    @State private var animateGradient = false
    
    enum PricingPlan {
        case monthly
        case yearly
        
        var price: String {
            switch self {
            case .monthly: return "$9.99"
            case .yearly: return "$79.99"
            }
        }
        
        var period: String {
            switch self {
            case .monthly: return "/month"
            case .yearly: return "/year"
            }
        }
        
        var savings: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Save 33%"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header with animated gradient
                    VStack(spacing: 16) {
                        ZStack {
                            // Animated background circles
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3), Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.1)],
                                        startPoint: animateGradient ? .topLeading : .bottomTrailing,
                                        endPoint: animateGradient ? .bottomTrailing : .topLeading
                                    )
                                )
                                .frame(width: 120, height: 120)
                                .blur(radius: 20)
                            
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.2), Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            // Modern sparkles icon
                            Image(systemName: "sparkles")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.6, green: 0.4, blue: 1.0), Color(red: 0.5, green: 0.3, blue: 0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.purple.opacity(0.3), radius: 8)
                                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Unlock AI Bible Study Pro")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .multilineTextAlignment(.center)
                            
                            Text("Experience the full power of AI-enhanced Bible study")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 32)
                    .padding(.horizontal)
                    
                    // Pricing Toggle
                    HStack(spacing: 12) {
                        ForEach([PricingPlan.monthly, PricingPlan.yearly], id: \.self) { plan in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedPlan = plan
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    if let savings = plan.savings {
                                        Text(savings)
                                            .font(.custom("OpenSans-Bold", size: 11))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(Color.green.opacity(0.15))
                                            )
                                    } else {
                                        Color.clear.frame(height: 20)
                                    }
                                    
                                    Text(plan.price)
                                        .font(.custom("OpenSans-Bold", size: 24))
                                    
                                    Text(plan.period)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedPlan == plan ? Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.1) : Color.gray.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    selectedPlan == plan ?
                                                        LinearGradient(
                                                            colors: [Color(red: 0.6, green: 0.4, blue: 1.0), Color(red: 0.5, green: 0.3, blue: 0.9)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ) :
                                                        LinearGradient(colors: [Color.clear, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                    lineWidth: 2
                                                )
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    // Enhanced Features with categories
                    VStack(spacing: 24) {
                        // AI Features
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI-Powered Tools")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                ProFeatureRow(
                                    icon: "sparkles",
                                    title: "Unlimited AI Conversations",
                                    description: "Ask unlimited questions and get instant biblical insights"
                                )
                                
                                ProFeatureRow(
                                    icon: "book.fill",
                                    title: "Daily AI Devotionals",
                                    description: "Personalized devotionals crafted for your spiritual journey"
                                )
                                
                                ProFeatureRow(
                                    icon: "list.bullet.clipboard.fill",
                                    title: "Custom Study Plans",
                                    description: "AI-generated plans tailored to your goals and pace"
                                )
                            }
                        }
                        
                        // Advanced Features
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Advanced Study Tools")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                ProFeatureRow(
                                    icon: "chart.bar.doc.horizontal.fill",
                                    title: "Scripture Analysis",
                                    description: "Deep contextual, thematic, and linguistic analysis"
                                )
                                
                                ProFeatureRow(
                                    icon: "globe",
                                    title: "Original Languages",
                                    description: "Greek & Hebrew word studies with transliteration"
                                )
                                
                                ProFeatureRow(
                                    icon: "brain.head.profile",
                                    title: "Memory Assistant",
                                    description: "Interactive verse memorization with spaced repetition"
                                )
                            }
                        }
                        
                        // Extra Features
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Premium Extras")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                ProFeatureRow(
                                    icon: "waveform",
                                    title: "Voice Input",
                                    description: "Ask questions naturally with speech recognition"
                                )
                                
                                ProFeatureRow(
                                    icon: "arrow.down.circle.fill",
                                    title: "Export & Share",
                                    description: "Download conversations, devotionals, and notes"
                                )
                                
                                ProFeatureRow(
                                    icon: "bell.badge.fill",
                                    title: "Smart Notifications",
                                    description: "AI-powered reminders for study and devotion time"
                                )
                                
                                ProFeatureRow(
                                    icon: "person.2.fill",
                                    title: "Group Study Mode",
                                    description: "Collaborate with friends on Bible studies"
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // CTA Button with animation
                    VStack(spacing: 12) {
                        Button {
                            // In real app, trigger purchase flow
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                hasProAccess = true
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .bold))
                                    .symbolEffect(.pulse.byLayer, options: .repeating)
                                
                                Text("Start 7-Day Free Trial")
                                    .font(.custom("OpenSans-Bold", size: 18))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color.purple.opacity(0.4), radius: 12, y: 4)
                            )
                        }
                        
                        VStack(spacing: 4) {
                            Text(selectedPlan == .monthly ? "Then $9.99/month" : "Then $79.99/year")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.primary)
                            
                            Text("Cancel anytime • No commitment")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Trust badges
                    HStack(spacing: 20) {
                        TrustBadge(icon: "lock.shield.fill", text: "Secure")
                        TrustBadge(icon: "star.fill", text: "Top Rated")
                        TrustBadge(icon: "heart.fill", text: "10K+ Users")
                    }
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

struct TrustBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
            
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

struct ProFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
        }
    }
}

// Note: StudyPlan is defined in BibleAIService.swift - using that version

// MARK: - Analysis Content

struct AnalysisContent: View {
    let selectedVerse = "John 3:16"
    @State private var showingAnalysis = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Scripture Analysis")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Deep dive into biblical context, themes, and connections")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Analysis Types
            VStack(spacing: 12) {
                AnalysisCard(
                    icon: "book.pages.fill",
                    title: "Contextual Analysis",
                    description: "Historical and cultural background",
                    color: .blue
                )
                
                AnalysisCard(
                    icon: "link.circle.fill",
                    title: "Cross-References",
                    description: "Find related passages throughout Scripture",
                    color: .green
                )
                
                AnalysisCard(
                    icon: "character.textbox",
                    title: "Original Languages",
                    description: "Greek and Hebrew word studies",
                    color: .purple
                )
                
                AnalysisCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Theme Tracking",
                    description: "Trace themes across the Bible",
                    color: .orange
                )
                
                AnalysisCard(
                    icon: "person.3.fill",
                    title: "Character Study",
                    description: "Explore biblical figures in depth",
                    color: .cyan
                )
            }
            .padding(.horizontal)
        }
    }
}

struct AnalysisCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    @State private var isPressed = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(isPressed ? 0.02 : 0.05), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 2)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Memorize Content

struct MemorizeContent: View {
    @State private var currentVerseIndex = 0
    @State private var showAnswer = false
    @State private var progressValue: CGFloat = 0.0
    
    let memoryVerses = [
        MemoryVerse(
            reference: "Philippians 4:13",
            text: "I can do all things through Christ who strengthens me.",
            category: "Strength",
            difficulty: .beginner
        ),
        MemoryVerse(
            reference: "Jeremiah 29:11",
            text: "For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you, plans to give you hope and a future.",
            category: "Hope",
            difficulty: .intermediate
        ),
        MemoryVerse(
            reference: "Proverbs 3:5-6",
            text: "Trust in the LORD with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
            category: "Trust",
            difficulty: .intermediate
        )
    ]
    
    var currentVerse: MemoryVerse {
        memoryVerses[currentVerseIndex]
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Scripture Memory")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Strengthen your faith through memorization")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Progress
            VStack(spacing: 8) {
                HStack {
                    Text("Weekly Progress")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("5/7 verses")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * 0.71, height: 8)
                            .shadow(color: Color.purple.opacity(0.3), radius: 4, y: 2)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal)
            
            // Current Verse Card
            VStack(spacing: 20) {
                // Reference
                HStack {
                    Text(currentVerse.reference)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                    
                    Spacer()
                    
                    // Difficulty badge
                    Text(currentVerse.difficulty.rawValue.capitalized)
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(currentVerse.difficulty.color)
                        )
                }
                
                // Verse text (with blur effect when hidden)
                Text(currentVerse.text)
                    .font(.custom("OpenSans-Regular", size: 17))
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .blur(radius: showAnswer ? 0 : 8)
                    .overlay(
                        !showAnswer ?
                            Text("Tap to reveal")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            : nil
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showAnswer.toggle()
                        }
                    }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showAnswer = false
                            currentVerseIndex = (currentVerseIndex + 1) % memoryVerses.count
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Next Verse")
                        }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.5, green: 0.3, blue: 0.9), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    
                    Button {
                        // Mark as learned
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(Color.green.opacity(0.1))
                            )
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
            .padding(.horizontal)
            
            Spacer()
        }
    }
}

struct MemoryVerse: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
    let category: String
    let difficulty: Difficulty
    
    enum Difficulty: String {
        case beginner
        case intermediate
        case advanced
        
        var color: Color {
            switch self {
            case .beginner: return .green
            case .intermediate: return .orange
            case .advanced: return .red
            }
        }
    }
}

let studyPlans = [
    StudyPlan(
        id: UUID().uuidString,
        title: "Gospel of John Deep Dive",
        duration: "30 days",
        description: "Explore the life and teachings of Jesus through John's Gospel with daily AI insights",
        icon: "book.pages.fill",
        color: Color(red: 0.4, green: 0.2, blue: 0.8),
        progress: 45
    ),
    StudyPlan(
        id: UUID().uuidString,
        title: "Psalms for Peace",
        duration: "21 days",
        description: "Find comfort and strength in the Psalms with guided meditation and reflection",
        icon: "heart.text.square.fill",
        color: .blue,
        progress: 12
    ),
    StudyPlan(
        id: UUID().uuidString,
        title: "Romans Theology Study",
        duration: "60 days",
        description: "Comprehensive exploration of Paul's letter to the Romans with theological depth",
        icon: "graduationcap.fill",
        color: .orange,
        progress: 78
    ),
    StudyPlan(
        id: UUID().uuidString,
        title: "Proverbs Wisdom Track",
        duration: "31 days",
        description: "Practical wisdom for daily living from the book of Proverbs",
        icon: "lightbulb.max.fill",
        color: Color(red: 0.6, green: 0.3, blue: 0.9),
        progress: 0
    )
]

// MARK: - Streak Banner

struct StreakBanner: View {
    @Binding var currentStreak: Int
    @State private var animateFlame = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Flame icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.2), Color.red.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "flame.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(animateFlame ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateFlame)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(currentStreak) Day Streak!")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                }
                
                Text("Keep your daily study habit going")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.08), Color.red.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.3), Color.red.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            animateFlame = true
        }
    }
}

#Preview {
    AIBibleStudyView()
}
