//
//  UnifiedChatView.swift
//  AMENAPP
//
//  Created by Steph on 2/1/26.
//
//  Production-ready unified chat view with liquid glass design
//  Single source of truth for all chat interfaces in the app
//

import SwiftUI
import PhotosUI
import FirebaseAuth

// MARK: - Unified Chat View

struct UnifiedChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var messagingService = FirebaseMessagingService.shared
    
    let conversation: ChatConversation
    
    @State private var messageText = ""
    @State private var messages: [AppMessage] = []
    @FocusState private var isInputFocused: Bool
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var isRecording = false
    @State private var selectedMessage: AppMessage?
    @State private var replyingTo: AppMessage?
    @State private var isTyping = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingMessageOptions = false
    @State private var typingDebounceTimer: Timer?
    
    var body: some View {
        ZStack {
            // Subtle gradient background
            liquidGlassBackground
            
            VStack(spacing: 0) {
                // Header
                liquidGlassHeader
                
                // Messages
                messagesScrollView
                
                Spacer(minLength: 0)
            }
            
            // Floating input bar
            VStack {
                Spacer()
                liquidGlassInputBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .navigationBarHidden(true)
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedImages,
            maxSelectionCount: 5,
            matching: .images
        )
        .alert("Message Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupChatView()
        }
        .onDisappear {
            cleanupChatView()
        }
        .onChange(of: messageText) { _, newValue in
            handleTypingIndicator(isTyping: !newValue.isEmpty)
        }
    }
    
    // MARK: - Background
    
    private var liquidGlassBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.96, blue: 0.98),
                Color(red: 0.94, green: 0.95, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    
    private var liquidGlassHeader: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                dismiss()
            } label: {
                ZStack {
                    // Liquid glass effect
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                conversation.avatarColor.opacity(0.8),
                                conversation.avatarColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: conversation.avatarColor.opacity(0.3), radius: 8, y: 2)
                
                Text(String(conversation.name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                if isTyping {
                    Text("typing...")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .transition(.opacity)
                } else {
                    Text("Active now")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Info button (optional)
            Button {
                // Show conversation info
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 0)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 2)
    }
    
    // MARK: - Messages
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        LiquidGlassMessageBubble(
                            message: message,
                            isFromCurrentUser: message.senderId == Auth.auth().currentUser?.uid,
                            onReply: {
                                replyingTo = message
                                isInputFocused = true
                            },
                            onReact: { emoji in
                                addReaction(to: message, emoji: emoji)
                            }
                        )
                        .id(message.id)
                    }
                    
                    // Typing indicator
                    if isTyping && messages.last?.senderId != Auth.auth().currentUser?.uid {
                        LiquidGlassTypingIndicator()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input Bar
    
    private var liquidGlassInputBar: some View {
        HStack(spacing: 12) {
            // Attachment buttons
            HStack(spacing: 8) {
                // Photo
                Button {
                    showingPhotoPicker = true
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }
                
                // File
                Button {
                    // Handle file attachment
                } label: {
                    Image(systemName: "doc")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }
                
                // Camera
                Button {
                    // Handle camera
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.leading, 4)
            
            // Text input
            TextField("Message \(conversation.name)...", text: $messageText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            
            // Send button with liquid glass effect
            Button {
                sendMessage()
            } label: {
                ZStack {
                    // Liquid glass pill shape
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                    [Color.gray.opacity(0.3), Color.gray.opacity(0.2)] :
                                    [Color.blue.opacity(0.8), Color.cyan.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 44)
                        .shadow(
                            color: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                .clear : .blue.opacity(0.3),
                            radius: 12,
                            y: 4
                        )
                    
                    // Arrow icon
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: messageText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func setupChatView() {
        print("🎬 Chat view opened: \(conversation.name)")
        loadMessages()
        startListeningToTypingStatus()
    }
    
    private func cleanupChatView() {
        print("👋 Chat view closed: \(conversation.name)")
        messagingService.stopListeningToMessages(conversationId: conversation.id)
        typingDebounceTimer?.invalidate()
        typingDebounceTimer = nil
        
        Task {
            try? await messagingService.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: false
            )
        }
    }
    
    private func loadMessages() {
        Task {
            do {
                // Start real-time listener
                try await messagingService.startListeningToMessages(
                    conversationId: conversation.id
                ) { [self] fetchedMessages in
                    Task { @MainActor in
                        self.messages = fetchedMessages
                    }
                }
                
                // Mark as read
                try await messagingService.markConversationAsRead(conversationId: conversation.id)
                
                print("✅ Messages loaded for conversation: \(conversation.id)")
            } catch {
                print("❌ Error loading messages: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to load messages"
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let textToSend = messageText
        let conversationId = conversation.id
        
        // Clear input immediately
        messageText = ""
        isInputFocused = false
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        Task {
            do {
                print("📤 Sending message to: \(conversationId)")
                
                try await messagingService.sendMessage(
                    conversationId: conversationId,
                    text: textToSend
                )
                
                print("✅ Message sent successfully!")
                
                // Success haptic
                await MainActor.run {
                    let successHaptic = UINotificationFeedbackGenerator()
                    successHaptic.notificationOccurred(.success)
                }
                
            } catch {
                print("❌ Error sending message: \(error)")
                
                await MainActor.run {
                    // Restore message text
                    messageText = textToSend
                    
                    // Show error
                    errorMessage = "Failed to send message. Please try again."
                    showErrorAlert = true
                    
                    // Error haptic
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func handleTypingIndicator(isTyping: Bool) {
        typingDebounceTimer?.invalidate()
        
        Task {
            try? await messagingService.updateTypingStatus(
                conversationId: conversation.id,
                isTyping: isTyping
            )
        }
        
        if isTyping {
            typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                Task {
                    try? await messagingService.updateTypingStatus(
                        conversationId: conversation.id,
                        isTyping: false
                    )
                }
            }
        }
    }
    
    private func startListeningToTypingStatus() {
        // Listen for other user's typing status
        Task {
            // Implementation depends on your Firebase structure
            // This is a placeholder for typing status listening
        }
    }
    
    private func addReaction(to message: AppMessage, emoji: String) {
        Task {
            do {
                try await messagingService.addReaction(
                    conversationId: conversation.id,
                    messageId: message.id,
                    emoji: emoji
                )
                print("✅ Reaction added: \(emoji)")
            } catch {
                print("❌ Error adding reaction: \(error)")
            }
        }
    }
}

// MARK: - Liquid Glass Message Bubble

struct LiquidGlassMessageBubble: View {
    let message: AppMessage
    let isFromCurrentUser: Bool
    var onReply: () -> Void
    var onReact: (String) -> Void
    
    @State private var showReactions = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Message bubble
                HStack(alignment: .bottom, spacing: 8) {
                    if !isFromCurrentUser && message.senderName != nil {
                        // Sender avatar (for group chats)
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(message.senderName?.prefix(1) ?? "?").uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            )
                    }
                    
                    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                        // Sender name (for group chats)
                        if !isFromCurrentUser, let senderName = message.senderName {
                            Text(senderName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                        }
                        
                        // Message text
                        Text(message.text)
                            .font(.system(size: 15))
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                ZStack {
                                    if isFromCurrentUser {
                                        // Sent message - blue liquid glass
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.blue.opacity(0.8),
                                                        Color.cyan.opacity(0.6)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                                    } else {
                                        // Received message - frosted glass
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                            )
                    }
                }
                .contextMenu {
                    Button {
                        onReply()
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    
                    if isFromCurrentUser {
                        Button(role: .destructive) {
                            // Delete message
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                
                // Reactions
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(message.reactions.keys), id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: 14))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                }
                
                // Timestamp
                Text(message.formattedTimestamp)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            }
            
            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showReactions)
    }
}

// MARK: - Liquid Glass Typing Indicator

struct LiquidGlassTypingIndicator: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            
            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Message Model Extension

extension AppMessage {
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        UnifiedChatView(
            conversation: ChatConversation(
                id: "preview_123",
                name: "John Doe",
                lastMessage: "Hey, how are you?",
                timestamp: "2:30 PM",
                isGroup: false,
                unreadCount: 0,
                avatarColor: .blue
            )
        )
    }
}
