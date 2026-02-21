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
import FirebaseFirestore

// MARK: - Unified Chat View

struct UnifiedChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @StateObject private var networkMonitor = NetworkStatusMonitor.shared
    @StateObject private var toastManager = ToastManager.shared
    @StateObject private var linkPreviewService = LinkPreviewService.shared
    
    let conversation: ChatConversation
    
    @State private var messageText = ""
    @State private var messages: [AppMessage] = []
    @State private var pendingMessages: [String: AppMessage] = [:]
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
    @State private var showAttachmentMenu = false
    @State private var isMediaSectionExpanded = false
    @State private var isInputBarFocused = false
    @State private var showUserProfile = false
    @State private var placeholderText = ""
    @State private var firstUnreadMessageId: String?
    @State private var showJumpToUnread = false
    @State private var showGroupInfo = false

    // Failed message tracking for retry
    @State private var failedMessageId: String?
    @State private var failedMessageText: String?

    // Real-time profile photo
    @State private var otherUserProfilePhoto: String?
    @State private var otherUserId: String?
    @State private var profilePhotoListener: ListenerRegistration?

    // Reaction picker state
    @State private var showReactionPicker = false
    @State private var selectedMessageForReaction: AppMessage?
    @State private var reactionPickerOffset: CGPoint = .zero
    
    // P0-1 FIX: Prevent duplicate message sends
    @State private var isSendingMessage = false
    @State private var inFlightMessageRequests: Set<Int> = []
    
    // P0-2 FIX: Listener lifecycle management
    @State private var listenerTask: Task<Void, Never>?
    
    // P0-4 FIX: Track optimistic messages by content hash
    @State private var optimisticMessageHashes: [String: Int] = [:]
    
    // P1-2 FIX: Scroll position preservation
    @State private var isNearBottom = true
    @Namespace private var bottomID
    
    // P1-3 FIX: Pagination state
    @State private var isLoadingMoreMessages = false

    var body: some View {
        ZStack {
            // Clean gradient background - black and white theme
            liquidGlassBackground

            VStack(spacing: 0) {
                // Header
                liquidGlassHeader

                // Messages
                messagesScrollView
            }
            .safeAreaInset(edge: .bottom) {
                // Floating input bar - Automatically anchors to keyboard
                VStack(spacing: 0) {
                    // Collapsible media section
                    if isMediaSectionExpanded {
                        collapsibleMediaSection
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }
                    
                    // Compact input bar
                    compactInputBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                .background(Color.clear)
            }

            // Reaction picker overlay
            if showReactionPicker, let message = selectedMessageForReaction {
                ReactionPickerOverlay(
                    message: message,
                    isShowing: $showReactionPicker,
                    onReaction: { emoji in
                        addReaction(to: message, emoji: emoji)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showReactionPicker = false
                        }
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
        .withToast()
        .sheet(isPresented: $showUserProfile) {
            ChatUserProfileSheet(conversation: conversation)
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupInfoView(conversation: conversation)
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            if !oldValue && newValue {
                // Just came back online
                toastManager.showSuccess("Back online")
                
                // Retry failed message if exists
                if let failedId = failedMessageId, let failedText = failedMessageText {
                    retryFailedMessage(messageId: failedId, text: failedText)
                }
            } else if oldValue && !newValue {
                // Just went offline
                toastManager.showWarning("You're offline. Messages will send when connection is restored.")
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedImages,
            maxSelectionCount: 5,
            matching: .any(of: [.images])
        )
        .alert("Message Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            setupChatView()
            generateRandomPlaceholder()
            
            // P1-1 FIX: Clear unread badge immediately when opening thread
            Task {
                try? await messagingService.clearUnreadCount(conversationId: conversation.id)
            }
        }
        .onDisappear {
            cleanupChatView()
        }
        .onChange(of: messageText) { _, newValue in
            handleTypingIndicator(isTyping: !newValue.isEmpty)
        }
        .onChange(of: isInputFocused) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isInputBarFocused = newValue
                if newValue {
                    // Auto-collapse media section when keyboard appears
                    isMediaSectionExpanded = false
                }
            }
        }
    }
    
    // MARK: - Computed Properties

    private var inputBarHeight: CGFloat {
        if isMediaSectionExpanded {
            return 120 // Expanded with media
        } else {
            return 60 // Compact
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            conversation.avatarColor.opacity(0.8),
                            conversation.avatarColor.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

            Text(String(conversation.name.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Background
    
    private var liquidGlassBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.95, green: 0.95, blue: 0.95),
                Color(red: 0.97, green: 0.97, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    
    private var liquidGlassHeader: some View {
        HStack(spacing: 12) {
            // Back button - blends with background
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Avatar with real-time profile photo
            Button {
                showUserProfile = true
            } label: {
                if let photoURL = otherUserProfilePhoto ?? conversation.profilePhotoURL,
                   !photoURL.isEmpty,
                   let url = URL(string: photoURL) {
                    CachedAsyncImage(
                        url: url,
                        content: { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        },
                        placeholder: {
                            fallbackAvatar
                        }
                    )
                } else {
                    fallbackAvatar
                }
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Name with cleaner typography and network status
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                
                // Network status indicator
                if !networkMonitor.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        
                        Text("Offline")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Info button - blends with background
            Button {
                if conversation.isGroup {
                    showGroupInfo = true
                } else {
                    showUserProfile = true
                }
            } label: {
                Image(systemName: conversation.isGroup ? "person.3.fill" : "info.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
    
    // MARK: - Messages
    
    private var messagesScrollView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        // P1-3 FIX: Pagination load more button
                        if messagingService.canLoadMoreMessages(conversationId: conversation.id) {
                            Button {
                                loadMoreMessages()
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoadingMoreMessages {
                                        ProgressView()
                                            .tint(.secondary)
                                    } else {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.system(size: 16))
                                    }
                                    Text(isLoadingMoreMessages ? "Loading..." : "Load older messages")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .disabled(isLoadingMoreMessages)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            VStack(spacing: 0) {
                                // Unread separator
                                if message.id == firstUnreadMessageId {
                                    unreadSeparator
                                        .padding(.vertical, 8)
                                        .id("unread-separator")
                                }
                                
                                LiquidGlassMessageBubble(
                                    message: message,
                                    isFromCurrentUser: message.senderId == Auth.auth().currentUser?.uid,
                                    onReply: {
                                        replyingTo = message
                                        isInputFocused = true
                                    },
                                    onReact: { emoji in
                                        addReaction(to: message, emoji: emoji)
                                    },
                                    onLongPress: {
                                        selectedMessageForReaction = message
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            showReactionPicker = true
                                        }
                                    },
                                    onDelete: {
                                        deleteMessage(message: message)
                                    },
                                    onRetry: message.isSendFailed ? {
                                        retryFailedMessage(messageId: message.id, text: message.text)
                                    } : nil
                                )
                                .id(message.id)
                            }
                        }
                        
                        // Typing indicator (REMOVED as requested - keeping structure for reference)
                        // if isTyping && messages.last?.senderId != Auth.auth().currentUser?.uid {
                        //     LiquidGlassTypingIndicator()
                        //         .transition(.scale.combined(with: .opacity))
                        // }
                        
                        // P1-2 FIX: Bottom anchor for scroll tracking
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120) // Extra padding so messages don't hide under input bar
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    // P1-2 FIX: Only auto-scroll if near bottom
                    if isNearBottom && newCount > oldCount {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom on first load
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                    
                    // Then scroll to unread if exists
                    if let firstUnreadId = firstUnreadMessageId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                proxy.scrollTo("unread-separator", anchor: .top)
                            }
                        }
                    }
                }
                .onChange(of: firstUnreadMessageId) { _, newValue in
                    // Show/hide jump to unread button
                    showJumpToUnread = newValue != nil
                }
            }
            
            // Jump to unread button
            if showJumpToUnread {
                jumpToUnreadButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 130)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Unread Separator
    
    private var unreadSeparator: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.red.opacity(0.5))
                .frame(height: 1)
            
            Text("New Messages")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.1))
                )
            
            Rectangle()
                .fill(Color.red.opacity(0.5))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Jump to Unread Button
    
    private var jumpToUnreadButton: some View {
        Button {
            // Scroll to unread separator
            // This will be implemented in the ScrollViewReader above
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            
            // Hide button after jumping
            withAnimation(.easeOut(duration: 0.3)) {
                showJumpToUnread = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("New")
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Collapsible Media Section
    
    private var collapsibleMediaSection: some View {
        VStack(spacing: 0) {
            // Media buttons grid with refined black/white design
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MediaButton(
                    icon: "photo.fill",
                    title: "Photos",
                    color: Color(red: 0.15, green: 0.15, blue: 0.15)
                ) {
                    showingPhotoPicker = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isMediaSectionExpanded = false
                    }
                }
                
                MediaButton(
                    icon: "video.fill",
                    title: "Video",
                    color: Color(red: 0.15, green: 0.15, blue: 0.15)
                ) {
                    // Handle video
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isMediaSectionExpanded = false
                    }
                }
                
                MediaButton(
                    icon: "doc.fill",
                    title: "Files",
                    color: Color(red: 0.15, green: 0.15, blue: 0.15)
                ) {
                    // Handle files
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isMediaSectionExpanded = false
                    }
                }
                
                MediaButton(
                    icon: "link",
                    title: "Link",
                    color: Color(red: 0.15, green: 0.15, blue: 0.15)
                ) {
                    // Handle link
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isMediaSectionExpanded = false
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                Rectangle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: -2)
            )
        }
    }
    
    // MARK: - Compact Input Bar
    
    private var compactInputBar: some View {
        HStack(spacing: 12) {
            // Plus button - frosted glass style
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isMediaSectionExpanded.toggle()
                    if isMediaSectionExpanded {
                        isInputFocused = false
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    Image(systemName: isMediaSectionExpanded ? "xmark" : "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            .buttonStyle(SpringButtonStyle())
            
            // Text input - frosted glass with visible text and subtle border
            HStack(spacing: 10) {
                TextField("", text: $messageText, axis: .vertical)
                    .font(.system(size: 16, weight: .regular))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .tint(Color.primary)
                    .foregroundColor(Color.primary)
                    .placeholder(when: messageText.isEmpty) {
                        Text(placeholderText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.primary.opacity(0.4))
                    }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(.systemBackground).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
            )
            
            // Send/Voice button - dark circular design
            Button {
                if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Start voice recording
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } else {
                    sendMessage()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [
                                    Color(red: 0.2, green: 0.2, blue: 0.2),
                                    Color(red: 0.2, green: 0.2, blue: 0.2)
                                ] : [
                                    Color(red: 0.15, green: 0.15, blue: 0.15),
                                    Color(red: 0.05, green: 0.05, blue: 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    
                    if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Voice/waveform icon
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    } else {
                        // Send arrow
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(SpringButtonStyle())
            .disabled(isSendingMessage) // P0-1 FIX: Prevent duplicate sends
            .opacity(isSendingMessage ? 0.5 : 1.0) // Visual feedback while sending
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 66)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: messageText)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isInputBarFocused)
    }
    
    // MARK: - Actions
    
    private func setupChatView() {
        print("🎬 Chat view opened: \(conversation.name)")
        
        // P0-2 FIX: Cancel any existing listener task before starting new one
        listenerTask?.cancel()
        
        // P0-2 FIX: Wrap listeners in a Task for proper lifecycle management
        listenerTask = Task {
            loadMessages()
            startListeningToTypingStatus()
            detectFirstUnreadMessage()
            startListeningToProfilePhotoUpdates()
        }
    }
    
    private func detectFirstUnreadMessage() {
        // Find first unread message from another user
        if let currentUserId = Auth.auth().currentUser?.uid {
            firstUnreadMessageId = messages.first { message in
                !message.isRead && message.senderId != currentUserId
            }?.id
        }
    }
    
    private func cleanupChatView() {
        print("👋 Chat view closed: \(conversation.name)")
        
        // P0-2 FIX: Cancel listener task immediately to prevent memory leaks
        listenerTask?.cancel()
        listenerTask = nil
        
        messagingService.stopListeningToMessages(conversationId: conversation.id)
        typingDebounceTimer?.invalidate()
        typingDebounceTimer = nil
        
        // Remove profile photo listener
        profilePhotoListener?.remove()
        profilePhotoListener = nil
        
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
                // P0 FIX: Avoid capturing self strongly (struct - no leak but good practice)
                try await messagingService.startListeningToMessages(
                    conversationId: conversation.id
                ) { fetchedMessages in
                    Task { @MainActor in
                        // P0-4 FIX: Match messages by content hash instead of ID
                        // Build hash map for fetched messages
                        var fetchedMessagesByHash: [Int: AppMessage] = [:]
                        for message in fetchedMessages {
                            let contentHash = message.text.hashValue
                            fetchedMessagesByHash[contentHash] = message
                        }
                        
                        // Remove optimistic messages that have been confirmed by Firebase
                        var optimisticIdsToRemove: [String] = []
                        for (optimisticId, contentHash) in optimisticMessageHashes {
                            if fetchedMessagesByHash[contentHash] != nil {
                                // Found matching real message - remove optimistic version
                                if let pendingMessage = pendingMessages[optimisticId] {
                                    let latencyMs = Int(Date().timeIntervalSince(pendingMessage.timestamp) * 1000)
                                    print("⏱️ [P0-4] Message confirmed (hash: \(contentHash)): \(latencyMs)ms")
                                }
                                pendingMessages.removeValue(forKey: optimisticId)
                                optimisticIdsToRemove.append(optimisticId)
                            }
                        }
                        
                        // Clean up confirmed messages from hash tracking
                        for id in optimisticIdsToRemove {
                            optimisticMessageHashes.removeValue(forKey: id)
                        }
                        
                        // Also check for ID-based matches (backward compatibility)
                        let fetchedIds = Set(fetchedMessages.map { $0.id })
                        for id in fetchedIds {
                            if pendingMessages[id] != nil {
                                pendingMessages.removeValue(forKey: id)
                                optimisticMessageHashes.removeValue(forKey: id)
                            }
                        }

                        // Merge: real messages + any remaining optimistic messages
                        var mergedMessages = fetchedMessages
                        for (id, pendingMessage) in pendingMessages {
                            // Only add pending if not already in fetched (double-check)
                            if !fetchedIds.contains(id) {
                                mergedMessages.append(pendingMessage)
                            }
                        }
                        mergedMessages.sort { $0.timestamp < $1.timestamp }
                        self.messages = mergedMessages
                        
                        // Detect first unread message
                        detectFirstUnreadMessage()
                        
                        // Mark messages as read when they're fetched
                        let messageIds = fetchedMessages.map { $0.id }
                        if !messageIds.isEmpty {
                            Task {
                                try? await messagingService.markMessagesAsRead(
                                    conversationId: conversation.id,
                                    messageIds: messageIds
                                )
                            }
                        }
                    }
                }
                
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
    
    // P1-3 FIX: Load more messages (pagination)
    private func loadMoreMessages() {
        guard !isLoadingMoreMessages else { return }
        
        isLoadingMoreMessages = true
        
        Task {
            do {
                try await messagingService.loadMoreMessages(
                    conversationId: conversation.id
                ) { olderMessages in
                    Task { @MainActor in
                        // Prepend older messages to beginning
                        self.messages.insert(contentsOf: olderMessages, at: 0)
                        print("✅ [P1-3] Loaded \(olderMessages.count) older messages")
                    }
                }
            } catch {
                print("❌ [P1-3] Error loading more messages: \(error)")
            }
            
            await MainActor.run {
                isLoadingMoreMessages = false
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // P0-1 FIX: Prevent duplicate in-flight requests
        let contentHash = messageText.hashValue
        guard !inFlightMessageRequests.contains(contentHash) else {
            print("⚠️ [P0-1] Duplicate send blocked: \(contentHash)")
            return
        }
        
        guard !isSendingMessage else {
            print("⚠️ [P0-1] Already sending message")
            return
        }
        
        isSendingMessage = true
        inFlightMessageRequests.insert(contentHash)
        
        let textToSend = messageText
        let conversationId = conversation.id
        let messageId = UUID().uuidString
        
        // Detect URLs in message
        let detectedURLs = linkPreviewService.detectURLs(in: textToSend)
        
        let optimisticMessage = AppMessage(
            id: messageId,
            text: textToSend,
            isFromCurrentUser: true,
            timestamp: Date(),
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            isSent: false,
            isDelivered: false,
            isSendFailed: false
        )
        pendingMessages[messageId] = optimisticMessage
        messages.append(optimisticMessage)
        
        // P0-4 FIX: Track optimistic message by content hash
        optimisticMessageHashes[messageId] = contentHash
        
        // Clear input immediately
        messageText = ""
        isInputFocused = false
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        Task {
            defer {
                Task { @MainActor in
                    isSendingMessage = false
                    inFlightMessageRequests.remove(contentHash)
                }
            }
            // Fetch link previews in background if URLs detected
            if !detectedURLs.isEmpty {
                print("🔗 Detected \(detectedURLs.count) URL(s) in message")
                
                for url in detectedURLs.prefix(3) { // Limit to first 3 URLs
                    do {
                        let metadata = try await linkPreviewService.fetchMetadata(for: url)
                        
                        // Update message with link preview
                        await MainActor.run {
                            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                                let preview = MessageLinkPreview(
                                    url: url,
                                    title: metadata.title,
                                    description: metadata.description,
                                    imageUrl: metadata.imageURL?.absoluteString
                                )
                                messages[index].linkPreviews.append(preview)
                            }
                            if var pendingMsg = pendingMessages[messageId] {
                                let preview = MessageLinkPreview(
                                    url: url,
                                    title: metadata.title,
                                    description: metadata.description,
                                    imageUrl: metadata.imageURL?.absoluteString
                                )
                                pendingMsg.linkPreviews.append(preview)
                                pendingMessages[messageId] = pendingMsg
                            }
                        }
                    } catch {
                        print("⚠️ Failed to fetch link preview: \(error)")
                    }
                }
            }
            
            do {
                print("📤 Sending message to: \(conversationId)")
                
                try await messagingService.sendMessage(
                    conversationId: conversationId,
                    text: textToSend,
                    clientMessageId: messageId
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
                    // Mark message as failed instead of removing
                    if var failedMsg = pendingMessages[messageId] {
                        failedMsg.isSendFailed = true
                        pendingMessages[messageId] = failedMsg
                        
                        // Update in messages array
                        if let index = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[index].isSendFailed = true
                        }
                    }
                    
                    // Store failed message for retry
                    failedMessageId = messageId
                    failedMessageText = textToSend
                    
                    // Show error toast with retry button
                    let errorMsg = (error as? FirebaseMessagingError)?.localizedDescription ?? "Failed to send message"
                    
                    if !networkMonitor.isConnected {
                        toastManager.showWarning("No internet connection. Message will send when you're back online.")
                    } else {
                        toastManager.showError(errorMsg) {
                            // Retry action
                            self.retryFailedMessage(messageId: messageId, text: textToSend)
                        }
                    }
                    
                    // Error haptic
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    private func retryFailedMessage(messageId: String, text: String) {
        print("🔄 Retrying failed message: \(messageId)")
        
        // Clear failed state
        failedMessageId = nil
        failedMessageText = nil
        
        // Remove failed message from UI
        pendingMessages.removeValue(forKey: messageId)
        messages.removeAll { $0.id == messageId }
        
        // Create new message with new ID
        let newMessageId = UUID().uuidString
        let optimisticMessage = AppMessage(
            id: newMessageId,
            text: text,
            isFromCurrentUser: true,
            timestamp: Date(),
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            isSent: false,
            isDelivered: false,
            isSendFailed: false
        )
        pendingMessages[newMessageId] = optimisticMessage
        messages.append(optimisticMessage)
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Send message
        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    text: text,
                    clientMessageId: newMessageId
                )
                
                print("✅ Message retry successful!")
                
                await MainActor.run {
                    toastManager.showSuccess("Message sent")
                }
            } catch {
                print("❌ Message retry failed: \(error)")
                
                await MainActor.run {
                    // Mark as failed again
                    if var failedMsg = pendingMessages[newMessageId] {
                        failedMsg.isSendFailed = true
                        pendingMessages[newMessageId] = failedMsg
                        
                        if let index = messages.firstIndex(where: { $0.id == newMessageId }) {
                            messages[index].isSendFailed = true
                        }
                    }
                    
                    failedMessageId = newMessageId
                    failedMessageText = text
                    
                    let errorMsg = (error as? FirebaseMessagingError)?.localizedDescription ?? "Failed to send message"
                    toastManager.showError(errorMsg) {
                        self.retryFailedMessage(messageId: newMessageId, text: text)
                    }
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
    
    private func startListeningToProfilePhotoUpdates() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot start profile photo listener - no current user")
            return
        }
        
        // Extract the other user's ID from conversation participants
        guard !conversation.isGroup else {
            print("📷 Skipping profile photo listener for group conversation")
            return
        }
        
        // Get the other user's ID
        let otherUserId = conversation.id.replacingOccurrences(of: currentUserId, with: "").replacingOccurrences(of: "_", with: "")
        
        guard !otherUserId.isEmpty, otherUserId != currentUserId else {
            print("⚠️ Could not determine other user ID")
            return
        }
        
        self.otherUserId = otherUserId
        
        // Set up Firestore listener for user's profile photo
        let db = Firestore.firestore()
        profilePhotoListener = db.collection("users").document(otherUserId).addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening to profile photo updates: \(error)")
                return
            }
            
            guard let data = snapshot?.data() else {
                print("⚠️ No user data found for profile photo")
                return
            }
            
            // Update profile photo if it changed - check both field names
            let photoURL = data["profilePhotoURL"] as? String ?? data["profileImageURL"] as? String
            
            if let photoURL = photoURL, !photoURL.isEmpty {
                Task { @MainActor in
                    self.otherUserProfilePhoto = photoURL
                    print("📷 Profile photo updated: \(photoURL)")
                }
            } else {
                Task { @MainActor in
                    self.otherUserProfilePhoto = nil
                    print("📷 Profile photo removed or not found")
                }
            }
        }
        
        print("📷 Started listening to profile photo updates for user: \(otherUserId)")
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

                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } catch {
                print("❌ Error adding reaction: \(error)")
                await MainActor.run {
                    toastManager.showError("Failed to add reaction")
                }
            }
        }
    }

    private func deleteMessage(message: AppMessage) {
        Task {
            do {
                try await messagingService.deleteMessage(
                    conversationId: conversation.id,
                    messageId: message.id
                )
                print("✅ Message deleted: \(message.id)")

                // Remove from local messages
                await MainActor.run {
                    messages.removeAll { $0.id == message.id }
                    toastManager.showSuccess("Message deleted")

                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("❌ Error deleting message: \(error)")
                await MainActor.run {
                    toastManager.showError("Failed to delete message")
                }
            }
        }
    }

    // MARK: - Keyboard Handling
    

    
    private func getSafeAreaBottom() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 8
        }
        return window.safeAreaInsets.bottom
    }
    
    // MARK: - Placeholder Generation
    
    private func generateRandomPlaceholder() {
        let placeholders = [
            "Type a new message here...",
            "Send a message...",
            "What's on your mind?",
            "Say something...",
            "Start typing...",
            "Write your message...",
            "Share your thoughts..."
        ]
        placeholderText = placeholders.randomElement() ?? "Type a new message here..."
    }
}

// MARK: - Chat User Profile Sheet

struct ChatUserProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conversation: ChatConversation
    
    @StateObject private var userService = LegacyUserService.shared
    @StateObject private var messagingService = FirebaseMessagingService.shared
    
    @State private var otherUserProfile: User?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var messageCount: Int = 0
    @State private var averageResponseTime: String = "N/A"
    @State private var showShareSheet = false
    
    var body: some View {
        ZStack {
            // Clean gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.98),
                    Color(red: 0.95, green: 0.95, blue: 0.95),
                    Color(red: 0.97, green: 0.97, blue: 0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    Text("Loading profile...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
            } else if let userProfile = otherUserProfile {
                // Profile content
                ScrollView {
                    VStack(spacing: 0) {
                        // Top bar with close and share buttons
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                                    )
                            }
                            .padding(.leading, 24)
                            
                            Spacer()
                            
                            Button {
                                showShareSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                                    )
                            }
                            .padding(.trailing, 24)
                        }
                        .padding(.top, 20)
                        
                        // Profile card
                        VStack(spacing: 24) {
                            // Avatar
                            if let profileImageURL = userProfile.profileImageURL, !profileImageURL.isEmpty {
                                AsyncImage(url: URL(string: profileImageURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                                } placeholder: {
                                    avatarPlaceholder(initials: userProfile.initials)
                                }
                            } else {
                                avatarPlaceholder(initials: userProfile.initials)
                            }
                            
                            // Name and Username
                            VStack(spacing: 4) {
                                Text(userProfile.displayName)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                                
                                Text("@\(userProfile.username)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            }
                            
                            // Bio (if available)
                            if !userProfile.bio.isEmpty {
                                Text(userProfile.bio)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .padding(.horizontal, 32)
                            }
                            
                            // Member since date
                            Text("Member since \(formattedJoinDate(userProfile.createdAt))")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            
                            // Interests tags (if available)
                            if !userProfile.interests.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(userProfile.interests.prefix(3), id: \.self) { interest in
                                            ProfileTagPill(text: interest)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .padding(.top, 8)
                            }
                            
                            // Stats
                            HStack(spacing: 40) {
                                // Posts count
                                ProfileStatItem(
                                    icon: "doc.text.fill",
                                    value: "\(userProfile.postsCount)",
                                    label: "Posts"
                                )
                                
                                // Followers
                                ProfileStatItem(
                                    icon: "person.2.fill",
                                    value: formatCount(userProfile.followersCount),
                                    label: "Followers"
                                )
                                
                                // Messages sent in this conversation
                                ProfileStatItem(
                                    icon: "message.fill",
                                    value: "\(messageCount)",
                                    label: "Messages"
                                )
                            }
                            .padding(.top, 24)
                            
                            // Additional info section
                            HStack(spacing: 8) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                
                                Text("Avg. response: \(averageResponseTime)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            }
                            .padding(.top, 12)
                            
                            // Action buttons
                            HStack(spacing: 16) {
                                // Primary action button
                                Button {
                                    dismiss()
                                } label: {
                                    Text("Continue Chat")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .background(
                                            RoundedRectangle(cornerRadius: 28)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.15, green: 0.15, blue: 0.15),
                                                            Color(red: 0.05, green: 0.05, blue: 0.05)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                                        )
                                }
                                .buttonStyle(SpringButtonStyle())
                                
                                // More options menu
                                Menu {
                                    Button {
                                        // Block/Report user
                                    } label: {
                                        Label("Report User", systemImage: "exclamationmark.triangle")
                                    }
                                    
                                    Button(role: .destructive) {
                                        // Block user
                                    } label: {
                                        Label("Block User", systemImage: "hand.raised")
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 56, height: 56)
                                            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                                        
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 32)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            } else {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0.8, green: 0.3, blue: 0.3))
                    
                    Text("Unable to load profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Button {
                        loadUserProfile()
                    } label: {
                        Text("Try Again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            )
                    }
                    .buttonStyle(SpringButtonStyle())
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadUserProfile()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Helper Views
    
    private func avatarPlaceholder(initials: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.15),
                            Color(red: 0.05, green: 0.05, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            
            Text(initials.uppercased())
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Data Loading
    
    private func loadUserProfile() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // For 1-on-1 chats, extract the other user's ID from conversation ID
                // Conversation ID format: "user1ID_user2ID" (sorted alphabetically)
                guard let currentUserId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "ChatUserProfileSheet", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
                }
                
                // Extract other user's ID from conversation (with Firebase fallback)
                let otherUserId = try await getOtherUserId(from: conversation.id, currentUserId: currentUserId)
                
                print("📱 Loading profile for user: \(otherUserId)")
                
                // Fetch user profile
                let profile = try await userService.fetchUser(userId: otherUserId)
                
                // Fetch conversation stats
                await loadConversationStats(conversationId: conversation.id, otherUserId: otherUserId)
                
                await MainActor.run {
                    self.otherUserProfile = profile
                    self.isLoading = false
                }
                
                print("✅ Profile loaded successfully: \(profile.displayName)")
                
            } catch {
                print("❌ Error loading profile: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadConversationStats(conversationId: String, otherUserId: String) async {
        // This would ideally fetch from Firebase, but for now we'll use placeholder logic
        // In a production app, you'd query messages and calculate these stats
        
        await MainActor.run {
            // Placeholder values - replace with real Firebase queries
            self.messageCount = 0 // Would be fetched from Firestore
            self.averageResponseTime = "< 1h" // Would be calculated from message timestamps
        }
    }
    
    private func getOtherUserId(from conversationId: String, currentUserId: String) async throws -> String {
        // Conversation ID format: "user1ID_user2ID" (sorted alphabetically)
        let userIds = conversationId.components(separatedBy: "_")
        
        if userIds.count == 2 {
            // Return the ID that's NOT the current user
            return userIds[0] == currentUserId ? userIds[1] : userIds[0]
        }
        
        // Fallback: Fetch conversation document from Firebase to get participant IDs
        print("⚠️ Conversation ID doesn't match expected format, fetching from Firebase...")
        
        do {
            let db = Firestore.firestore()
            let conversationDoc = try await db.collection("conversations").document(conversationId).getDocument()
            
            guard conversationDoc.exists else {
                throw NSError(domain: "ChatUserProfileSheet", code: 404, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
            }
            
            // Get participantIds array from conversation document
            if let participantIds = conversationDoc.data()?["participantIds"] as? [String],
               let otherUserId = participantIds.first(where: { $0 != currentUserId }) {
                print("✅ Found other user ID from Firebase: \(otherUserId)")
                return otherUserId
            }
            
            throw NSError(domain: "ChatUserProfileSheet", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not determine other user ID from conversation"])
        } catch {
            print("❌ Error fetching conversation: \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Functions
    
    private func formattedJoinDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return "\(year)"
    }
    
    private func formatCount(_ count: Int) -> String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<1_000_000:
            let value = Double(count) / 1000
            return String(format: "%.1fK", value).replacingOccurrences(of: ".0K", with: "K")
        default:
            let value = Double(count) / 1_000_000
            return String(format: "%.1fM", value).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

// MARK: - Supporting Components

struct ProfileTagPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
            )
    }
}

struct ProfileStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
        }
    }
}

// MARK: - Liquid Glass Message Bubble

struct LiquidGlassMessageBubble: View {
    let message: AppMessage
    let isFromCurrentUser: Bool
    var onReply: () -> Void
    var onReact: (String) -> Void
    var onLongPress: () -> Void
    var onDelete: () -> Void
    var onRetry: (() -> Void)? = nil

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
                        // Sender avatar (for group chats) - with profile image support
                        if let profileImageURL = message.senderProfileImageURL,
                           !profileImageURL.isEmpty,
                           let url = URL(string: profileImageURL) {
                            CachedAsyncImage(
                                url: url,
                                content: { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                },
                                placeholder: {
                                    senderInitialsAvatar
                                }
                            )
                        } else {
                            senderInitialsAvatar
                        }
                    }
                    
                    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                        // Sender name (for group chats)
                        if !isFromCurrentUser, let senderName = message.senderName {
                            Text(senderName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                        }
                        
                        HStack(spacing: 8) {
                            // Message text
                            Text(message.text)
                                .font(.system(size: 15))
                                .foregroundColor(isFromCurrentUser ? .white : .primary)
                            
                            // Failed message indicator with retry button
                            if isFromCurrentUser && message.isSendFailed {
                                Button(action: {
                                    onRetry?()
                                }) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if isFromCurrentUser {
                                    // Sent message - refined black gradient
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: message.isSendFailed ? [
                                                    Color.red.opacity(0.3),
                                                    Color.red.opacity(0.2)
                                                ] : [
                                                    Color(red: 0.15, green: 0.15, blue: 0.15),
                                                    Color(red: 0.05, green: 0.05, blue: 0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                                    
                                    // Failed message border
                                    if message.isSendFailed {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(Color.red.opacity(0.5), lineWidth: 1.5)
                                    }
                                } else {
                                    // Received message - clean white frosted glass
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                        )
                                }
                            }
                        )
                    }
                }
                .onTapGesture(count: 2) {
                    // Double-tap to show reactions (like Instagram)
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    onLongPress()
                }
                .contextMenu {
                    // React button at the top
                    Button {
                        onLongPress()
                    } label: {
                        Label("React", systemImage: "face.smiling")
                    }

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
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                
                // Link Previews
                if !message.linkPreviews.isEmpty {
                    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 8) {
                        ForEach(message.linkPreviews.prefix(2)) { preview in
                            let url = preview.url
                            Button(action: {
                                if UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if let title = preview.title {
                                            Text(title)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                        
                                        if let description = preview.description {
                                            Text(description)
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            
                                            Text(url.host ?? url.absoluteString)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: 240, alignment: .leading)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                }
                
                // Reactions
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        // Group reactions by emoji
                        let groupedReactions = Dictionary(grouping: message.reactions, by: { $0.emoji })
                        ForEach(Array(groupedReactions.keys.sorted()), id: \.self) { emoji in
                            let count = groupedReactions[emoji]?.count ?? 0
                            HStack(spacing: 2) {
                                Text(emoji)
                                    .font(.system(size: 14))
                                if count > 1 {
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
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
    
    // MARK: - Sender Initials Avatar (Fallback)
    
    private var senderInitialsAvatar: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(message.senderName?.prefix(1) ?? "?").uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
            )
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

// MARK: - Custom Button Styles

/// Spring-based button style with smooth scale animation
struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .brightness(configuration.isPressed ? -0.05 : 0)
    }
}

// MARK: - Media Button Component

struct MediaButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.08))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray)
            }
        }
        .buttonStyle(SpringButtonStyle())
    }
}

// Note: ScaleButtonStyle is defined in SharedUIComponents.swift
// Note: placeholder(when:alignment:placeholder:) extension is defined in SharedUIComponents.swift

// MARK: - Reaction Picker Overlay (iMessage/Instagram Style)

struct ReactionPickerOverlay: View {
    let message: AppMessage
    @Binding var isShowing: Bool
    var onReaction: (String) -> Void

    // 5 black and white reaction emojis
    private let reactions = ["🙏", "❤️", "🔥", "👍", "😊"]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Semi-transparent background - tap to dismiss
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isShowing = false
                        }
                    }

                // Reaction buttons hovering near top (like iMessage/Instagram)
                HStack(spacing: 8) {
                    ForEach(reactions, id: \.self) { emoji in
                        Button(action: {
                            onReaction(emoji)
                        }) {
                            ZStack {
                                // Black and white circle background
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.15, green: 0.15, blue: 0.15),
                                                Color(red: 0.05, green: 0.05, blue: 0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)

                                // White border
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 48, height: 48)

                                // Emoji
                                Text(emoji)
                                    .font(.system(size: 24))
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
                .scaleEffect(isShowing ? 1.0 : 0.5)
                .opacity(isShowing ? 1.0 : 0.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isShowing)
                .position(x: geometry.size.width / 2, y: 100) // Positioned near top, hovering
            }
            .ignoresSafeArea(.keyboard)
        }
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
