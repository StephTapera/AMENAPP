//
//  RealtimeChatView.swift
//  AMENAPP
//
//  Enhanced chat UI with modern design and Firebase Realtime Database
//

import SwiftUI
import FirebaseAuth

struct RealtimeChatView: View {
    let conversationId: String
    let conversationName: String
    let participantInitials: String?
    
    @StateObject private var rtService = RealtimeDatabaseService.shared
    @State private var messageText = ""
    @State private var isTyping = false
    @FocusState private var isInputFocused: Bool
    @State private var showingOptions = false
    @State private var scrollProxy: ScrollViewProxy?
    
    private var messages: [RealtimeMessage] {
        rtService.realtimeMessages[conversationId] ?? []
    }
    
    private var typingUsers: [String] {
        let typingUserIds = rtService.typingUsers[conversationId] ?? []
        return Array(typingUserIds)
    }
    
    init(conversationId: String, conversationName: String, participantInitials: String? = nil) {
        self.conversationId = conversationId
        self.conversationName = conversationName
        self.participantInitials = participantInitials
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGray6).opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                EnhancedMessageBubbleView(message: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            
                            // Typing indicator
                            if !typingUsers.isEmpty {
                                ModernTypingIndicatorView(userNames: typingUsers)
                                    .padding(.horizontal)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding()
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        scrollProxy = proxy
                    }
                    .onChange(of: messages.count) { oldValue, newValue in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if let lastMessage = messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Modern Message Input Bar
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.3)
                    
                    HStack(spacing: 12) {
                        // Plus button for attachments
                        Button {
                            showingOptions = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        // Message input field
                        HStack(spacing: 8) {
                            TextField("Message", text: $messageText, axis: .vertical)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .textFieldStyle(.plain)
                                .focused($isInputFocused)
                                .lineLimit(1...6)
                                .onChange(of: messageText) { oldValue, newValue in
                                    handleTypingChange(newValue)
                                }
                            
                            // Voice message button (placeholder)
                            if messageText.isEmpty {
                                Button {
                                    // Voice message action
                                } label: {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(.systemGray6))
                                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
                        )
                        
                        // Send button
                        Button {
                            sendMessage()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        messageText.isEmpty ?
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) :
                                        LinearGradient(
                                            colors: [Color.blue, Color.blue.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                    .shadow(
                                        color: messageText.isEmpty ? .clear : .blue.opacity(0.3),
                                        radius: 8,
                                        y: 2
                                    )
                                
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .disabled(messageText.isEmpty)
                        .scaleEffect(messageText.isEmpty ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: messageText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color(.systemBackground)
                            .shadow(color: .black.opacity(0.05), radius: 10, y: -2)
                    )
                }
            }
        }
        .navigationTitle(conversationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(conversationName)
                        .font(.custom("OpenSans-Bold", size: 17))
                    
                    if isOtherUserOnline {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Online")
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else if !typingUsers.isEmpty {
                        Text("typing...")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingOptions = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                }
            }
        }
        .confirmationDialog("Chat Options", isPresented: $showingOptions) {
            Button("Search Messages") { }
            Button("Media & Links") { }
            Button("Mute Notifications") { }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            setupRealtimeListeners()
        }
        .onDisappear {
            cleanupRealtimeListeners()
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupRealtimeListeners() {
        rtService.observeMessages(conversationId: conversationId)
        rtService.observeTypingIndicators(conversationId: conversationId)
        
        // Mark messages as read
        Task {
            let unreadMessageIds = messages
                .filter { !$0.isRead }
                .map { $0.id }
            
            if !unreadMessageIds.isEmpty {
                try? await rtService.markMessagesAsRead(
                    conversationId: conversationId,
                    messageIds: unreadMessageIds
                )
            }
        }
        
        // Scroll to bottom after messages load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let lastMessage = messages.last, let proxy = scrollProxy {
                withAnimation {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func cleanupRealtimeListeners() {
        rtService.stopObservingMessages(conversationId: conversationId)
        rtService.stopObservingTypingIndicators(conversationId: conversationId)
        
        // Clear typing indicator
        Task {
            try? await rtService.clearTypingIndicator(conversationId: conversationId)
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Optimistic UI update
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            messageText = ""
        }
        
        Task {
            do {
                try await rtService.sendRealtimeMessage(
                    conversationId: conversationId,
                    text: text
                )
                
                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                // Scroll to bottom
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let lastMessage = messages.last, let proxy = scrollProxy {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            } catch {
                print("❌ Failed to send message: \(error)")
                // Revert on error
                await MainActor.run {
                    messageText = text
                }
            }
        }
    }
    
    private func handleTypingChange(_ newValue: String) {
        let shouldBeTyping = !newValue.isEmpty
        
        if shouldBeTyping != isTyping {
            isTyping = shouldBeTyping
            Task {
                try? await rtService.setTypingIndicator(
                    conversationId: conversationId,
                    isTyping: shouldBeTyping
                )
            }
        }
    }
    
    private var isOtherUserOnline: Bool {
        return !rtService.onlineUsers.isEmpty
    }
}

// MARK: - Enhanced Message Bubble View

struct EnhancedMessageBubbleView: View {
    let message: RealtimeMessage
    @State private var showTime = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            // Avatar for received messages
            if !message.isFromCurrentUser {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(message.senderName.prefix(1))
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.white)
                    )
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name for group chats
                if !message.isFromCurrentUser {
                    Text(message.senderName)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                
                // Message bubble
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showTime.toggle()
                    }
                } label: {
                    Text(message.text)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(message.isFromCurrentUser ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            Group {
                                if message.isFromCurrentUser {
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                } else {
                                    Color(.systemGray5)
                                }
                            }
                        )
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: message.isFromCurrentUser ? 20 : 20,
                                bottomLeadingRadius: message.isFromCurrentUser ? 20 : 4,
                                bottomTrailingRadius: message.isFromCurrentUser ? 4 : 20,
                                topTrailingRadius: message.isFromCurrentUser ? 20 : 20
                            )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                
                // Timestamp and status
                if showTime {
                    HStack(spacing: 4) {
                        Text(formatTimestamp(message.timestamp))
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                        
                        if message.isFromCurrentUser {
                            Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(message.isRead ? .blue : .secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            if !message.isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday, " + formatter.string(from: date)
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Modern Typing Indicator View

private struct ModernTypingIndicatorView: View {
    let userNames: [String]
    
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Text(userNames.first?.prefix(1) ?? "?")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.white)
                )
            
            // Typing animation
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .opacity(animationPhase == index ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray5))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            
            Spacer()
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RealtimeChatView(
            conversationId: "demo123",
            conversationName: "John Doe",
            participantInitials: "JD"
        )
    }
}
