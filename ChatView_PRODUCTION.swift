//
//  ChatView.swift
//  AMENAPP
//
//  Production-ready chat view with all features working
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

struct ChatViewProduction: View {
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader
            
            // Messages
            messagesList
            
            // Input
            messageInputBar
        }
        .background(Color(.systemGroupedBackground))
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
    
    // MARK: - Header
    
    private var chatHeader: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 4)
                    )
            }
            
            // Avatar
            Circle()
                .fill(conversation.avatarColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(conversation.initials)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(conversation.avatarColor)
                )
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.name)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                
                if isTyping {
                    Text("typing...")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
    
    // MARK: - Messages List
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if isLoadingMessages {
                    ProgressView()
                        .padding()
                } else if messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            ChatMessageBubbleView(
                                message: message,
                                isFromCurrentUser: message.senderId == currentUserId,
                                showSenderName: conversation.isGroup
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }
            }
            .onChange(of: messages.count) {
                // Scroll to bottom when new message arrives
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "message")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text("No messages yet")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text("Send a message to start the conversation")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Message Input
    
    private var messageInputBar: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Message", text: $messageText, axis: .vertical)
                .font(.custom("OpenSans-Regular", size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .lineLimit(1...5)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                )
                .focused($isInputFocused)
                .onChange(of: messageText) { _, newValue in
                    handleTypingIndicator(isTyping: !newValue.isEmpty)
                }
            
            // Send button
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
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
            messages = newMessages.sorted { $0.timestamp < $1.timestamp }
            isLoadingMessages = false
            
            print("📬 Received \(newMessages.count) messages")
        }
    }
    
    private func startListeningToTyping() {
        messagingService.startListeningToTyping(conversationId: conversation.id) { typingUsers in
            isTyping = !typingUsers.isEmpty
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else { return }
        
        // Clear input immediately
        messageText = ""
        
        // Hide keyboard
        isInputFocused = false
        
        print("📤 Sending message: \(text)")
        
        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    text: text
                )
                
                print("✅ Message sent successfully")
                
                // Haptic feedback
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

// MARK: - Chat Message Bubble View
struct ChatMessageBubbleView: View {
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
                
                // Message bubble
                Text(message.text)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isFromCurrentUser ? Color.blue : Color(.systemGray5))
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


