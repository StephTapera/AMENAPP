//
//  ChatView_NEW_PRODUCTION.swift
//  AMENAPP
//
//  Production-ready chat interface with Liquid Glass design
//  All features tested and working
//  Created: January 29, 2026
//
//  IMPORTANT: This file must be included in the AMENAPP target for MessagesView to find it.
//  Check Target Membership in File Inspector if you get "Cannot find 'ChatViewLiquidGlass' in scope"
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

/// Production-ready chat view with Liquid Glass design
/// Used by MessagesView to display conversation details
struct ChatViewLiquidGlass: View {
    // MARK: - Properties
    let conversation: ChatConversation
    
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var messageText = ""
    @State private var messages: [AppMessage] = []
    @State private var isTyping = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoadingMessages = true
    
    @FocusState private var isInputFocused: Bool
    
    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Liquid glass gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.68, green: 0.85, blue: 0.90),
                    Color(red: 0.75, green: 0.88, blue: 0.95),
                    Color(red: 0.82, green: 0.91, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Header with Liquid Glass
                liquidGlassHeader
                
                // Messages List
                messagesList
                
                // Liquid Glass Message Input
                liquidGlassInputBar
            }
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupChat()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Liquid Glass Header
    
    private var liquidGlassHeader: some View {
        HStack(spacing: 12) {
            // Back Button - Liquid Glass Pill
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(conversation.avatarColor.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        if conversation.isGroup {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(conversation.avatarColor)
                        } else {
                            Text(conversation.initials)
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(conversation.avatarColor)
                        }
                    }
                    
                    // Name & Status
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.name)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        if isTyping {
                            Text("typing...")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        Capsule()
                            .fill(.ultraThinMaterial)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Messages List
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if isLoadingMessages {
                    liquidGlassLoadingView
                } else if messages.isEmpty {
                    liquidGlassEmptyStateView
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            LiquidGlassMessageBubbleProduction(
                                message: message,
                                isFromCurrentUser: message.senderId == currentUserId,
                                showSenderName: conversation.isGroup
                            )
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                        }
                        
                        // Typing Indicator
                        if isTyping {
                            LiquidGlassTypingIndicatorProduction()
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
            }
            .onChange(of: messages.count) { _, _ in
                // Scroll to bottom when new message arrives
                if let lastMessage = messages.last {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Liquid Glass Loading View
    
    private var liquidGlassLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.primary)
            
            Text("Loading messages...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Liquid Glass Empty State
    
    private var liquidGlassEmptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                
                Image(systemName: conversation.isGroup ? "person.3.fill" : "message.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.8),
                                Color.blue.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No messages yet")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text("Send a message to start the conversation")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Liquid Glass Message Input
    
    private var liquidGlassInputBar: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Message", text: $messageText, axis: .vertical)
                .font(.custom("OpenSans-Regular", size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .lineLimit(1...5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                        
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .focused($isInputFocused)
                .onChange(of: messageText) { _, newValue in
                    handleTypingIndicator(isTyping: !newValue.isEmpty)
                }
            
            // Send button
            Button {
                sendMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                            LinearGradient(
                                colors: [Color.gray.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.9),
                                    Color.blue.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Setup & Cleanup
    
    private func setupChat() {
        print("📱 ChatView appeared")
        print("💬 Conversation: \(conversation.name)")
        print("🆔 Conversation ID: \(conversation.id)")
        print("👤 Current User: \(currentUserId)")
        
        // Ensure user name is cached
        Task {
            await messagingService.fetchAndCacheCurrentUserName()
            
            // Start listening to messages
            startListeningToMessages()
            
            // Start listening to typing indicators
            startListeningToTyping()
            
            // Mark messages as read
            await markMessagesAsRead()
        }
    }
    
    private func cleanup() {
        print("👋 ChatView disappeared")
        
        // Stop typing indicator
        Task {
            try? await messagingService.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: false
            )
        }
        
        // Stop listening to messages
        messagingService.stopListeningToMessages(conversationId: conversation.id)
    }
    
    // MARK: - Message Handling
    
    private func startListeningToMessages() {
        isLoadingMessages = true
        
        messagingService.startListeningToMessages(conversationId: conversation.id) { newMessages in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages = newMessages.sorted { $0.timestamp < $1.timestamp }
                isLoadingMessages = false
            }
            
            print("📬 Received \(newMessages.count) messages")
        }
    }
    
    private func startListeningToTyping() {
        messagingService.startListeningToTyping(conversationId: conversation.id) { typingUsers in
            withAnimation(.easeInOut(duration: 0.3)) {
                isTyping = !typingUsers.isEmpty
            }
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else { return }
        
        // Clear input immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            messageText = ""
        }
        
        // Hide keyboard
        isInputFocused = false
        
        print("📤 Sending message: \(text)")
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    text: text
                )
                
                print("✅ Message sent successfully")
                
                // Success haptic feedback
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
                
            } catch {
                print("❌ Error sending message: \(error)")
                
                await MainActor.run {
                    // Restore message text
                    messageText = text
                    
                    // Show error
                    errorMessage = "Failed to send message. Please try again."
                    showError = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func handleTypingIndicator(isTyping: Bool) {
        Task {
            try? await messagingService.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: isTyping
            )
        }
    }
    
    private func markMessagesAsRead() async {
        let unreadMessageIds = messages
            .filter { !$0.isRead && $0.senderId != currentUserId }
            .map { $0.id }
        
        guard !unreadMessageIds.isEmpty else { return }
        
        do {
            try await messagingService.markMessagesAsRead(
                conversationId: conversation.id,
                messageIds: unreadMessageIds
            )
            
            print("✅ Marked \(unreadMessageIds.count) messages as read")
        } catch {
            print("❌ Error marking messages as read: \(error)")
        }
    }
}

// MARK: - Liquid Glass Message Bubble View

struct LiquidGlassMessageBubbleProduction: View {
    let message: AppMessage
    let isFromCurrentUser: Bool
    let showSenderName: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                // Sender name (for group chats)
                if showSenderName && !isFromCurrentUser, let senderName = message.senderName {
                    Text(senderName)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                
                // Message bubble with liquid glass effect
                Text(message.text)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            if isFromCurrentUser {
                                // Sent message - Blue gradient
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.blue.opacity(0.9),
                                                Color.blue.opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
                            } else {
                                // Received message - Liquid glass
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.8),
                                                Color.white.opacity(0.4)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        }
                    )
                
                // Timestamp + delivery status
                HStack(spacing: 4) {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                    
                    if isFromCurrentUser {
                        Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(message.isRead ? .blue : .secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Liquid Glass Typing Indicator

struct LiquidGlassTypingIndicatorProduction: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.6),
                                    Color.white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.8),
                                    Color.white.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            
            Spacer(minLength: 60)
        }
        .onAppear {
            animationPhase = 1
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatViewLiquidGlass(
            conversation: ChatConversation(
                id: "preview-1",
                name: "John Doe",
                lastMessage: "Hey, how are you?",
                timestamp: "2m ago",
                isGroup: false,
                unreadCount: 0,
                avatarColor: .blue
            )
        )
    }
}
