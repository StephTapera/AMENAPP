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
import FirebaseFunctions
import Combine

// MARK: - Unified Chat View

struct UnifiedChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @ObservedObject private var networkMonitor = NetworkStatusMonitor.shared
    @ObservedObject private var toastManager = ToastManager.shared
    @ObservedObject private var linkPreviewService = LinkPreviewService.shared
    @StateObject private var chatLinkController = ComposerLinkPreviewController()
    
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

    // Attachment tray — animated spring tray
    @State private var isAttachTrayOpen = false

    // Video attachment
    @State private var showVideoPicker = false
    @State private var activeVideoUploadId: String? = nil

    // File attachment
    @State private var showDocumentPicker = false
    @State private var activeFileUploadId: String? = nil

    // Link attachment
    @State private var showLinkSheet = false

    // Quick reply chips (shown when messages.isEmpty)
    @State private var isChipsExpanded = true
    @State private var dismissedChipIds: Set<String> = []
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

    // Mutual follow state — resolved async on appear; used by MinorSafetyService
    @State private var isMutualFollow: Bool = false
    @State private var isFollowingOtherUser: Bool = false
    @State private var isFollowButtonLoading: Bool = false
    @State private var isFollowedByOtherUser: Bool = false  // they follow us

    // Request accept/decline in-progress
    @State private var isAcceptingRequest: Bool = false
    @State private var isDecliningRequest: Bool = false

    // Reaction picker state
    @State private var showReactionPicker = false
    @State private var selectedMessageForReaction: AppMessage?
    @State private var reactionPickerOffset: CGPoint = .zero
    
    // Prevent duplicate in-flight sends: keyed by client message ID (UUID), not content hash.
    // hashValue is session-unstable and collision-prone for short strings.
    @State private var isSendingMessage = false
    @State private var inFlightMessageIDs: Set<String> = []

    // Smart reply chips
    @State private var smartReplySuggestions: [String] = []
    @State private var isLoadingSmartReplies = false

    // Listener lifecycle management
    @State private var listenerTask: Task<Void, Never>?
    @State private var isViewActive = false  // guard against listener leak on rapid dismiss

    // Track confirmed message IDs received from Firestore for O(1) dedupe.
    // Key = clientMessageId (UUID). Optimistic message is removed once its ID appears in snapshot.
    @State private var seenMessageIDs: Set<String> = []
    
    // P1-2 FIX: Scroll position preservation
    @State private var isNearBottom = true
    @Namespace private var bottomID
    
    // P1-3 FIX: Pagination state
    @State private var isLoadingMoreMessages = false

    // MARK: — Safety Reporting state
    @State private var isSubmittingReport = false
    @State private var reportConfirmationMessage: String?
    @State private var messageToReport: AppMessage?
    @State private var showReportConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var userIdToBlock: String?

    // MARK: — Berean AI Streaming state
    @State private var isBereanStreaming = false
    @State private var bereanStreamingText = ""
    @State private var bereanStreamingTokenCount = 0
    @State private var bereanStreamTask: Task<Void, Never>?
    @State private var bereanTriggeredByMessageId = ""

    // MARK: — Safety Gateway state
    @State private var safetyStrikeCount = 0
    @State private var safetyStrikeReason = ""
    @State private var showStrikeNotice = false
    @State private var showAccountFrozen = false
    @State private var accountFrozenReason = ""
    @State private var showCrisisInterstitial = false
    @State private var pendingCrisisMessageText = ""
    @State private var pendingCrisisMessageId = ""
    // messageId → safety warning signals for recipient-side banner
    @State private var messageWarnings: [String: [SafetySignal]] = [:]

    // PERF: Computed once per render cycle rather than inline in the gradient,
    // preventing repeated trimmingCharacters calls on every keystroke.
    private var isMessageEmpty: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            // Clean gradient background - black and white theme
            liquidGlassBackground

            VStack(spacing: 0) {
                // Header
                liquidGlassHeader
                
                // Incoming message request banner (enhanced)
                if isIncomingRequest {
                    ChatRequestBanner(
                        conversation: conversation,
                        followRelationship: followRelationship,
                        isFollowLoading: isFollowButtonLoading,
                        isAccepting: isAcceptingRequest,
                        isDeclining: isDecliningRequest,
                        onViewProfile: { showUserProfile = true },
                        onFollow: { followOtherUser() },
                        onAccept: { acceptMessageRequest() },
                        onDecline: { declineMessageRequest() },
                        onRestrict: { restrictSender() },
                        onBlock: {
                            userIdToBlock = otherUserId
                            showBlockConfirmation = true
                        },
                        onReport: {
                            // Report the conversation
                            Task {
                                try? await messagingService.reportSpam(
                                    conversation.id,
                                    reason: "Message request report"
                                )
                                await MainActor.run {
                                    toastManager.showSuccess("Reported")
                                }
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }

                // Messages
                messagesScrollView
            }
            .safeAreaInset(edge: .bottom) {
                // Floating input bar - Automatically anchors to keyboard
                VStack(spacing: 0) {
                    // Safety: strike notice (shown after a message is blocked)
                    if showStrikeNotice {
                        StrikeNoticeView(
                            strikeCount: safetyStrikeCount,
                            reason: safetyStrikeReason,
                            onDismiss: {
                                withAnimation(.spring(response: 0.3)) {
                                    showStrikeNotice = false
                                }
                            },
                            onFollowThem: otherUserId.map { uid in
                                {
                                    guard !isFollowButtonLoading else { return }
                                    isFollowButtonLoading = true
                                    Task {
                                        do {
                                            try await FollowService.shared.followUser(userId: uid)
                                            // Re-check follow status so the policy reflects the new follow
                                            let followStatus = try await FirebaseMessagingService.shared.checkFollowStatus(userId1: Auth.auth().currentUser?.uid ?? "", userId2: uid)
                                            await MainActor.run {
                                                isFollowingOtherUser = followStatus.user1FollowsUser2
                                                isFollowedByOtherUser = followStatus.user2FollowsUser1
                                                isMutualFollow = followStatus.user1FollowsUser2 && followStatus.user2FollowsUser1
                                                isFollowButtonLoading = false
                                                // Dismiss the notice — they can now send a message request
                                                withAnimation(.spring(response: 0.3)) {
                                                    showStrikeNotice = false
                                                    // Don't increment strike — following is not a safety violation
                                                    safetyStrikeCount = max(0, safetyStrikeCount - 1)
                                                }
                                            }
                                        } catch {
                                            await MainActor.run { isFollowButtonLoading = false }
                                        }
                                    }
                                }
                            },
                            isFollowLoading: isFollowButtonLoading
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Safety: account frozen notice (replaces input bar)
                    if showAccountFrozen {
                        AccountFrozenNoticeView(
                            reason: accountFrozenReason,
                            onContactSupport: {
                                // Open support — placeholder for now
                            }
                        )
                        .transition(.opacity)
                    } else {
                        // Collapsible media section
                        if isMediaSectionExpanded {
                            collapsibleMediaSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                ))
                        }

                        // Live link preview above input
                        ComposerLinkPreview(controller: chatLinkController)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: chatLinkController.activeURL)

                        // Smart reply chips — aligned with the text field inside the input bar
                        // Leading: 12 (outer hPad) + 40 (+ button) + 12 (spacing) = 64
                        if messageText.isEmpty && !smartReplySuggestions.isEmpty {
                            smartReplyChipsRow
                                .padding(.leading, 64)
                                .padding(.trailing, 12)
                                .padding(.bottom, 4)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Compact input bar
                        compactInputBar
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                .background(Color.clear)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showStrikeNotice)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showAccountFrozen)
            }

            // Premium iMessage-quality reaction tray overlay (AMENReactionSystem)
            ReactionTrayOverlay(state: ReactionPresentationState.shared)
        }
        .navigationBarHidden(true)
        .withToast()
        .sheet(isPresented: $showUserProfile) {
            ChatUserProfileSheet(
                conversation: conversation,
                resolvedUserId: otherUserId ?? conversation.otherParticipantId
            )
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupInfoView(conversation: conversation)
        }
        // Safety: crisis support interstitial — shown before sending, after message cleared
        .sheet(isPresented: $showCrisisInterstitial) {
            SelfHarmCrisisInterstitial(
                onSendAnyway: {
                    showCrisisInterstitial = false
                    // Re-send the held crisis message with crisis flag set
                    let text = pendingCrisisMessageText
                    let id = pendingCrisisMessageId
                    pendingCrisisMessageText = ""
                    pendingCrisisMessageId = ""
                    Task {
                        try? await messagingService.sendMessage(
                            conversationId: conversation.id,
                            text: text,
                            clientMessageId: id
                        )
                    }
                },
                onClose: {
                    showCrisisInterstitial = false
                    pendingCrisisMessageText = ""
                    pendingCrisisMessageId = ""
                    // Remove the optimistic message that was held
                    messages.removeAll { $0.id == pendingCrisisMessageId }
                    pendingMessages.removeValue(forKey: pendingCrisisMessageId)
                }
            )
            .presentationDetents([.medium, .large])
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
        // Video picker sheet
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(conversationId: conversation.id) { videoURL in
                handleVideoSelected(videoURL)
            }
        }
        // Document picker sheet
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { fileURL, fileName, fileSize in
                handleFileSelected(fileURL: fileURL, fileName: fileName, fileSize: fileSize)
            }
        }
        // Link attach sheet
        .sheet(isPresented: $showLinkSheet) {
            LinkAttachSheet(
                conversationId: conversation.id,
                senderId: Auth.auth().currentUser?.uid ?? "",
                senderName: messagingService.currentUserName
            ) { msg in
                appendAttachmentMessage(msg)
            }
        }
        .alert("Message Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Report Message", isPresented: $showReportConfirmation) {
            Button("Report", role: .destructive) {
                if let msg = messageToReport {
                    reportMessage(msg)
                }
                messageToReport = nil
            }
            Button("Cancel", role: .cancel) { messageToReport = nil }
        } message: {
            Text("This message will be reported for review. Thank you for helping keep AMEN safe.")
        }
        .alert("Block User", isPresented: $showBlockConfirmation) {
            Button("Block", role: .destructive) {
                if let uid = userIdToBlock {
                    blockSender(userId: uid)
                }
                userIdToBlock = nil
            }
            Button("Cancel", role: .cancel) { userIdToBlock = nil }
        } message: {
            Text("You will no longer receive messages from this person.")
        }
        .task {
            // P0 FIX: Move all setup to async task for instant view appearance
            await setupChatViewAsync()
        }
        .onAppear {
            isViewActive = true
            // Only do lightweight, synchronous work here
            generateRandomPlaceholder()
            NotificationAggregationService.shared.trackConversationViewing(conversation.id)
        }
        .onDisappear {
            isViewActive = false
            cleanupChatView()

            // ✅ Reset screen tracking
            NotificationAggregationService.shared.updateCurrentScreen(.messages)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // FIX: Re-attach message listener when app returns to foreground.
            // .task{} only runs once when the view first appears; if the app is backgrounded
            // while the chat is open and then foregrounded, the listener is gone. Re-attach it.
            if newPhase == .active {
                Task { await setupChatViewAsync() }
            } else if newPhase == .background {
                cleanupChatView()
            }
        }
        .onChange(of: messageText) { _, newValue in
            handleTypingIndicator(isTyping: !newValue.isEmpty)
            chatLinkController.handleTextChange(newValue)
            if !newValue.isEmpty { smartReplySuggestions = [] }
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

    /// Derived from the resolved follow-status flags.
    private var followRelationship: ChatFollowRelationship {
        if otherUserId == nil { return .loading }
        switch (isFollowingOtherUser, isFollowedByOtherUser) {
        case (true,  true):  return .mutual
        case (false, true):  return .theyFollowYou
        case (true,  false): return .youFollowThem
        case (false, false): return .noFollowRelationship
        }
    }

    /// True when this is the first meaningful exchange (pending request or empty accepted chat).
    private var isFirstTimeChat: Bool {
        // Show identity card for incoming pending, outgoing pending, or accepted but no messages yet.
        let isIncomingRequest = conversation.status == "pending"
            && conversation.requesterId != Auth.auth().currentUser?.uid
        let isOutgoingRequest = conversation.status == "pending"
            && conversation.requesterId == Auth.auth().currentUser?.uid
        let isEmptyAccepted = conversation.status == "accepted" && messages.isEmpty
        return isIncomingRequest || isOutgoingRequest || isEmptyAccepted
    }

    /// True when the current user is the requester (outgoing pending).
    private var isOutgoingPending: Bool {
        conversation.status == "pending"
            && conversation.requesterId == Auth.auth().currentUser?.uid
    }

    /// True when we should show the incoming request banner.
    private var isIncomingRequest: Bool {
        conversation.status == "pending"
            && conversation.requesterId != Auth.auth().currentUser?.uid
    }

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
                    LazyVStack(spacing: 0) {
                        // ── Identity card (first-time / empty chat) ──────────────────
                        if isFirstTimeChat && !isIncomingRequest {
                            ChatIdentityCard(
                                conversation: conversation,
                                followRelationship: followRelationship,
                                isFollowLoading: isFollowButtonLoading,
                                onViewProfile: { showUserProfile = true },
                                onFollow: { followOtherUser() },
                                onSendPrayer: {
                                    let firstName = conversation.name.components(separatedBy: " ").first ?? "you"
                                    messageText = "🙏 Praying for you, \(firstName)"
                                    isInputFocused = true
                                },
                                overridePhotoURL: otherUserProfilePhoto
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // ── Outgoing pending state ────────────────────────────────────
                        if isOutgoingPending {
                            ChatOutgoingPendingBanner(conversation: conversation)
                                .transition(.opacity)
                        }

                        // ── Conversation source context banner ────────────────────────
                        if isFirstTimeChat && conversation.source != .direct {
                            ChatSourceBanner(source: conversation.source)
                                .padding(.horizontal, 16)
                        }

                        // ── Empty state prompt (accepted, no messages) ────────────────
                        if conversation.status == "accepted" && messages.isEmpty {
                            ChatEmptyState(
                                conversation: conversation,
                                followRelationship: followRelationship,
                                onStarterTapped: { starter in
                                    messageText = starter
                                    isInputFocused = true
                                }
                            )

                            // Quick reply chips shown when conversation has no messages
                            QuickReplyChipsView(
                                isExpanded: $isChipsExpanded,
                                dismissedChipIds: $dismissedChipIds,
                                onChipTapped: { text in
                                    sendQuickReply(text)
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

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
                            let currentUID = Auth.auth().currentUser?.uid
                            let isFromCurrentUser = message.senderId == currentUID
                            // A message is last in its group when the next message is from a different sender
                            // or when it's the last message overall.
                            let nextMessage: AppMessage? = index + 1 < messages.count ? messages[index + 1] : nil
                            let isLastInGroup = nextMessage == nil || nextMessage?.senderId != message.senderId
                            // Show read receipt only on the very last outgoing message
                            let isLastOutgoing = isFromCurrentUser && (nextMessage == nil || nextMessage?.senderId != currentUID)
                            // Show date header when the day changes between messages
                            let prevMessage: AppMessage? = index > 0 ? messages[index - 1] : nil
                            let showDateHeader = prevMessage.map { !Calendar.current.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? true

                            VStack(spacing: 0) {
                                // Date group header
                                if showDateHeader {
                                    messageDateHeader(date: message.timestamp)
                                        .padding(.vertical, 10)
                                }

                                // Unread separator
                                if message.id == firstUnreadMessageId {
                                    unreadSeparator
                                        .padding(.vertical, 8)
                                        .id("unread-separator")
                                }

                                // Safety: warning banner shown to recipient above flagged messages
                                let isFromOther = !isFromCurrentUser
                                if isFromOther, let warnings = messageWarnings[message.id], !warnings.isEmpty {
                                    MessageSafetyWarningBanner(
                                        signals: warnings,
                                        onReport: {
                                            guard let reportedId = otherUserId,
                                                  let currentId = currentUID,
                                                  !isSubmittingReport else { return }
                                            isSubmittingReport = true
                                            let evidenceIds = messages.suffix(5).map { $0.id }
                                            let submission = ReportSubmission(
                                                reporterId: currentId,
                                                reportedUserId: reportedId,
                                                conversationId: conversation.id,
                                                reason: .harassment,
                                                evidenceMessageIds: evidenceIds,
                                                additionalContext: "Flagged by in-chat safety scanner",
                                                blockImmediately: false
                                            )
                                            Task {
                                                _ = await SafetyReportingService.shared.submitReport(submission)
                                                isSubmittingReport = false
                                                reportConfirmationMessage = "Report submitted. Thank you for keeping the community safe."
                                            }
                                        },
                                        onBlock: {
                                            guard let reportedId = otherUserId,
                                                  let currentId = currentUID,
                                                  !isSubmittingReport else { return }
                                            isSubmittingReport = true
                                            let evidenceIds = messages.suffix(5).map { $0.id }
                                            let submission = ReportSubmission(
                                                reporterId: currentId,
                                                reportedUserId: reportedId,
                                                conversationId: conversation.id,
                                                reason: .harassment,
                                                evidenceMessageIds: evidenceIds,
                                                additionalContext: "One-tap block from in-chat safety banner",
                                                blockImmediately: true
                                            )
                                            Task {
                                                _ = await SafetyReportingService.shared.submitReport(submission)
                                                isSubmittingReport = false
                                            }
                                        }
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                // Safety: held message indicator for sender's own held messages
                                if isFromCurrentUser
                                    && !message.isSent && !message.isSendFailed
                                    && message.text == pendingCrisisMessageText {
                                    HeldMessageIndicator()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                } else {
                                    VStack(spacing: 4) {
                                        LiquidGlassMessageBubble(
                                            message: message,
                                            isFromCurrentUser: isFromCurrentUser,
                                            isLastInGroup: isLastInGroup,
                                            showReadReceipt: isLastOutgoing,
                                            // FIX 1: Reflect auto-retry state in bubble UI
                                            isRetrying: messagingService.retryingMessageIds.contains(message.id),
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
                                            } : nil,
                                            onReport: !isFromCurrentUser ? {
                                                messageToReport = message
                                                showReportConfirmation = true
                                            } : nil,
                                            onBlock: !isFromCurrentUser ? {
                                                userIdToBlock = message.senderId
                                                showBlockConfirmation = true
                                            } : nil,
                                            onMute: !isFromCurrentUser ? {
                                                muteSender(userId: message.senderId)
                                            } : nil
                                        )
                                        // Link preview cards below the bubble
                                        if let firstPreview = message.linkPreviews.first {
                                            let previewMeta: LinkPreviewMetadata = LinkPreviewService.shared.getCached(for: firstPreview.url)
                                                ?? LinkPreviewMetadata(url: firstPreview.url, title: firstPreview.title, siteName: firstPreview.url.host)
                                            FeedLinkPreviewCard(url: firstPreview.url, metadata: previewMeta)
                                                .frame(maxWidth: 280)
                                                .padding(.horizontal, 8)
                                        }
                                    }
                                    .padding(.bottom, isLastInGroup ? 6 : 2)
                                    .id(message.id)
                                }
                            }
                        }

                        // Typing indicator — shown when the other person is typing
                        if isTyping {
                            LiquidGlassTypingIndicator()
                                .padding(.horizontal, 16)
                                .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                        }

                        // Berean AI: typing indicator (before first token) or streaming bubble
                        if isBereanStreaming {
                            if bereanStreamingText.isEmpty {
                                BereanTypingIndicatorBubble()
                                    .padding(.horizontal, 16)
                                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                                    .id("berean-typing")
                            } else {
                                BereanStreamingBubble(text: bereanStreamingText)
                                    .padding(.horizontal, 16)
                                    .transition(.opacity)
                                    .id("berean-streaming")
                            }
                        }

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
                    // Refresh smart reply chips when a new incoming message arrives
                    if newCount > oldCount {
                        refreshSmartReplies()
                    }
                }
                // Berean: scroll to bottom when typing indicator appears
                .onChange(of: isBereanStreaming) { _, isStreaming in
                    if isStreaming {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
                // Berean: throttled scroll-to-bottom every 5 tokens
                .onChange(of: bereanStreamingTokenCount) { _, count in
                    if isNearBottom && count % 5 == 0 {
                        proxy.scrollTo(bottomID, anchor: .bottom)
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
                    if firstUnreadMessageId != nil {
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
    
    // MARK: - Date Group Header

    // Hoisted to avoid allocating a new DateFormatter on every render pass.
    private static let messageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func messageDateHeader(date: Date) -> some View {
        let calendar = Calendar.current
        let label: String
        if calendar.isDateInToday(date) {
            label = "Today"
        } else if calendar.isDateInYesterday(date) {
            label = "Yesterday"
        } else {
            label = Self.messageDateFormatter.string(from: date)
        }
        return Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
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
    
    // MARK: - Collapsible Media Section (Animated Attachment Tray)

    private var collapsibleMediaSection: some View {
        HStack(spacing: 0) {
            attachTrayCell(icon: "photo.fill",  label: "Photos", iconColor: .blue,   bgColor: Color(red: 0.91, green: 0.96,  blue: 0.996), index: 0) { showingPhotoPicker = true }
            attachTrayCell(icon: "video.fill",  label: "Video",  iconColor: .purple, bgColor: Color(red: 0.94, green: 0.93,  blue: 0.973), index: 1) { showVideoPicker = true }
            attachTrayCell(icon: "doc.fill",    label: "Files",  iconColor: .green,  bgColor: Color(red: 0.94, green: 0.968, blue: 0.929), index: 2) { showDocumentPicker = true }
            attachTrayCell(icon: "link",        label: "Link",   iconColor: .orange, bgColor: Color(red: 1.0,  green: 0.957, blue: 0.925), index: 3) { showLinkSheet = true }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 8, y: -2)
        )
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.05)) {
                isAttachTrayOpen = true
            }
        }
        .onDisappear {
            isAttachTrayOpen = false
        }
    }

    @ViewBuilder
    private func attachTrayCell(
        icon: String,
        label: String,
        iconColor: Color,
        bgColor: Color,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isMediaSectionExpanded = false
                isAttachTrayOpen = false
            }
            action()
        } label: {
            AttachItemView(item: AttachItemView.Item(id: label, icon: icon, label: label, iconColor: iconColor, bgColor: bgColor))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .offset(y: isAttachTrayOpen ? 0 : 20)
        .scaleEffect(isAttachTrayOpen ? 1.0 : 0.85)
        .opacity(isAttachTrayOpen ? 1.0 : 0.0)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.6)
                .delay(Double(index) * 0.04),
            value: isAttachTrayOpen
        )
    }
    
    // MARK: - Compact Input Bar
    
    private var compactInputBar: some View {
        HStack(spacing: 12) {
            // Plus button — rotates 45° when tray is open
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()

                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    isMediaSectionExpanded.toggle()
                    if isMediaSectionExpanded {
                        isInputFocused = false
                        isAttachTrayOpen = true
                    } else {
                        isAttachTrayOpen = false
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

                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .rotationEffect(.degrees(isMediaSectionExpanded ? 45 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isMediaSectionExpanded)
                }
            }
            .buttonStyle(SpringButtonStyle())
            
            // Text input - frosted glass with visible text and subtle border
            // cornerRadius morphs when focused (iMessage-style)
            let inputCornerRadius: CGFloat = isInputFocused ? 14 : 18
            let inputBackground = RoundedRectangle(cornerRadius: inputCornerRadius)
                .fill(Color(.systemBackground).opacity(0.5))
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isInputFocused)
            let inputBorder = RoundedRectangle(cornerRadius: inputCornerRadius)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isInputFocused)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if messageText.isEmpty {
                        Text(placeholderText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.primary.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $messageText, axis: .vertical)
                        .font(.system(size: 16, weight: .regular))
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .tint(Color.primary)
                        .foregroundColor(Color.primary)
                }

                // Voice/Send/Stop button — morphs between states with spring animation
                Button {
                    if isRecording {
                        // Stop recording
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isRecording = false
                        }
                    } else if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    } else {
                        // Mic tap — placeholder for voice recording
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isRecording = true
                        }
                    }
                } label: {
                    ZStack {
                        // Pulse ring when recording
                        if isRecording {
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 36, height: 36)
                                .scaleEffect(isRecording ? 2.1 : 1.0)
                                .opacity(0)
                                .animation(
                                    .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: isRecording
                                )
                        }

                        Circle()
                            .fill(
                                isRecording
                                ? AnyShapeStyle(Color.red)
                                : isMessageEmpty
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [Color(red: 0.25, green: 0.25, blue: 0.25),
                                                 Color(red: 0.25, green: 0.25, blue: 0.25)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.blue)
                            )
                            .frame(width: 32, height: 32)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isMessageEmpty)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)

                        if isRecording {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if isMessageEmpty {
                            Image(systemName: "mic")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isMessageEmpty)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
                }
                .buttonStyle(SpringButtonStyle())
                .disabled(isSendingMessage || isBereanStreaming)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(inputBackground)
            .overlay(inputBorder)
            .opacity((isSendingMessage || isBereanStreaming) ? 0.5 : 1.0) // Visual feedback while sending / Berean streaming
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

    // MARK: - Smart Reply Chips

    private var smartReplyChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(smartReplySuggestions, id: \.self) { suggestion in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        messageText = suggestion
                        isInputFocused = true
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Fetch smart reply suggestions using recent conversation context.
    private func refreshSmartReplies() {
        guard !isLoadingSmartReplies, messageText.isEmpty else {
            if !messageText.isEmpty { smartReplySuggestions = [] }
            return
        }
        // Need at least one incoming message to reply to
        guard messages.contains(where: { !$0.isFromCurrentUser && !$0.text.isEmpty }) else {
            smartReplySuggestions = []
            return
        }

        // Build a short conversation transcript from the last 6 non-empty messages.
        // Format: "Them: ...\nYou: ...\nThem: ..."  (≤300 chars total)
        // This gives the AI enough thread context to generate relevant replies.
        let recentMessages = messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6)

        let otherName = conversation.name.components(separatedBy: " ").first ?? "Them"
        let transcript = recentMessages.map { msg -> String in
            let speaker = msg.isFromCurrentUser ? "You" : otherName
            let snippet = String(msg.text.prefix(80))
            return "\(speaker): \(snippet)"
        }.joined(separator: "\n")

        let contextExcerpt = String(transcript.prefix(300))

        isLoadingSmartReplies = true
        Task {
            let request = SmartReplySuggestionRequest(
                mode: .smartReply,
                contextExcerpt: contextExcerpt,
                actorDisplayName: otherName,
                actorIsMinor: false
            )
            let result = await SmartReplySuggestionService.shared.generate(request: request)
            await MainActor.run {
                var chips: [String] = []
                for s in [result.suggestion1, result.suggestion2, result.suggestion3] {
                    if !s.isEmpty, !chips.contains(s) { chips.append(s) }
                }
                smartReplySuggestions = chips
                isLoadingSmartReplies = false
            }
        }
    }

    // MARK: - Actions
    
    // Start listeners immediately — don't await unread-clear before showing messages.
    private func setupChatViewAsync() async {
        let _perfToken = PerfBegin("chat_open")
        defer { PerfEnd(_perfToken) }
        dlog("🎬 Chat view opened: \(conversation.name)")
        
        // Cancel any existing listener task before starting new one
        listenerTask?.cancel()

        // Start listeners immediately so messages appear without waiting
        listenerTask = Task {
            loadMessages()
            detectFirstUnreadMessage()
            startListeningToProfilePhotoUpdates()
        }

        // Start typing indicator listener — shows "... is typing" bubble when other
        // participant is actively typing. The service already filters out the current
        // user and stale entries (>5s), so the callback contains only remote typers.
        messagingService.startListeningToTyping(conversationId: conversation.id) { typingNames in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isTyping = !typingNames.isEmpty
                }
            }
        }

        // Clear unread badge fire-and-forget — don't block listener startup
        Task {
            try? await messagingService.clearUnreadCount(conversationId: conversation.id)
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
        dlog("👋 Chat view closed: \(conversation.name)")

        // P1 FIX: Reset send gate so user can send messages if they reopen this chat
        isSendingMessage = false
        inFlightMessageIDs.removeAll()

        // P0-2 FIX: Cancel listener task immediately to prevent memory leaks
        listenerTask?.cancel()
        listenerTask = nil
        
        messagingService.stopListeningToMessages(conversationId: conversation.id)
        // Stop typing indicator listener and remove our own typing status
        messagingService.stopListeningToTyping(conversationId: conversation.id)
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
        // startListeningToMessages is synchronous — it attaches a Firestore snapshot listener
        // and returns immediately. Callbacks arrive on the main actor via the closure below.
        messagingService.startListeningToMessages(
            conversationId: conversation.id
        ) { fetchedMessages in
            Task { @MainActor in
                // Build a Set of all IDs returned by the snapshot for O(1) lookup.
                let fetchedIDs = Set(fetchedMessages.map { $0.id })

                // Any pending (optimistic) message whose ID now appears in the snapshot
                // has been confirmed by Firestore — remove the optimistic copy.
                seenMessageIDs.formUnion(fetchedIDs)
                // P1 FIX: Prune seenMessageIDs to prevent unbounded memory growth.
                // Each entry is a Firestore document ID (~28 bytes); 500 entries ≈ 14KB.
                // When we exceed 500, trim to the 250 most recently fetched entries.
                if seenMessageIDs.count > 500 {
                    seenMessageIDs = Set(fetchedIDs.prefix(250))
                }
                for id in fetchedIDs where pendingMessages[id] != nil {
                    pendingMessages.removeValue(forKey: id)
                }

                // Merge: real messages + any remaining optimistic messages.
                // Dictionary keyed by ID collapses duplicates from rapid snapshot updates —
                // the fetched version always wins over the optimistic one.
                var merged: [String: AppMessage] = Dictionary(
                    uniqueKeysWithValues: fetchedMessages.map { ($0.id, $0) }
                )
                for (id, pending) in pendingMessages where merged[id] == nil {
                    merged[id] = pending
                }

                // Sort once, assign once — avoids repeated O(n log n) in SwiftUI body.
                self.messages = merged.values.sorted { $0.timestamp < $1.timestamp }

                detectFirstUnreadMessage()

                // Mark only messages the current user hasn't read yet (not every message every update).
                let newUnread = fetchedMessages.filter { !$0.isFromCurrentUser && !$0.isRead }
                if !newUnread.isEmpty {
                    let ids = newUnread.map { $0.id }
                    Task {
                        try? await messagingService.markMessagesAsRead(
                            conversationId: conversation.id,
                            messageIds: ids
                        )
                    }
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
                        dlog("✅ [P1-3] Loaded \(olderMessages.count) older messages")
                    }
                }
            } catch {
                dlog("❌ [P1-3] Error loading more messages: \(error)")
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

        // Guard: one send at a time. isSendingMessage is the primary gate;
        // inFlightMessageIDs provides per-message dedup on the rare case of concurrent sends.
        guard !isSendingMessage else {
            dlog("⚠️ Send blocked: already sending")
            return
        }

        // ── BEREAN AI ROUTING ─────────────────────────────────────────────────
        // Intercept any message containing "@Berean" and route to Claude streaming.
        // The message is still written to Firestore (both sides) after streaming.
        if messageText.range(of: "@berean", options: [.caseInsensitive]) != nil {
            let userText = messageText
            messageText = ""
            isInputFocused = false
            sendBereanMessage(userText: userText)
            return
        }
        // ── END BEREAN ROUTING ────────────────────────────────────────────────

        isSendingMessage = true

        // Generate the client-side message ID once. This UUID is passed to Firestore as the
        // document ID so that retries (same UUID) are idempotent — no duplicate documents created.
        let messageId = UUID().uuidString

        // Double-check: if this ID is somehow already in-flight (shouldn't happen with UUID), bail.
        guard !inFlightMessageIDs.contains(messageId) else { return }
        inFlightMessageIDs.insert(messageId)

        let textToSend = messageText
        let conversationId = conversation.id

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
        // Append only if not already present (belt-and-suspenders)
        if !messages.contains(where: { $0.id == messageId }) {
            messages.append(optimisticMessage)
        }

        // Clear input immediately for snappy UX
        messageText = ""
        chatLinkController.reset()
        isInputFocused = false

        // Stop typing indicator immediately when message is sent
        typingDebounceTimer?.invalidate()
        typingDebounceTimer = nil
        Task {
            try? await messagingService.updateTypingStatus(
                conversationId: conversationId,
                isTyping: false
            )
        }

        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        Task {
            defer {
                Task { @MainActor in
                    isSendingMessage = false
                    inFlightMessageIDs.remove(messageId)
                }
            }

            // P0-2 FIX: Client-side safety guardrail before Firestore write.
            // Runs inside the Task so `await` is valid. The optimistic message is
            // removed from the UI if content is blocked.
            let guardrailResult = await ThinkFirstGuardrailsService.shared.checkContent(
                textToSend, context: .message
            )
            if guardrailResult.action == .block {
                let reason = guardrailResult.violations.first?.message
                    ?? "This message violates community guidelines."
                await MainActor.run {
                    // Remove the optimistic message and restore input
                    pendingMessages.removeValue(forKey: messageId)
                    messages.removeAll { $0.id == messageId }
                    messageText = textToSend
                    errorMessage = reason
                    showErrorAlert = true
                }
                return
            }

            // Fetch link previews in background if URLs detected
            if !detectedURLs.isEmpty {
                dlog("🔗 Detected \(detectedURLs.count) URL(s) in message")
                
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
                            if pendingMessages[messageId] != nil {
                                let preview = MessageLinkPreview(
                                    url: url,
                                    title: metadata.title,
                                    description: metadata.description,
                                    imageUrl: metadata.imageURL?.absoluteString
                                )
                                pendingMessages[messageId]?.linkPreviews.append(preview)
                            }
                        }
                    } catch {
                        dlog("⚠️ Failed to fetch link preview: \(error)")
                    }
                }
            }
            
            do {
                // ── SAFETY GATEWAY (authoritative enforcement) ──────────────────────
                // Every message send goes through MessageSafetyGateway before any
                // Firestore write. No bypass path exists.
                //
                // Pipeline:
                //   1. Build conversation context (history + sender risk profile)
                //   2. Gateway classifies message + boosts score via ConversationRiskEngine
                //   3. Decision: allow / warnRecipient / holdForReview / blockAndStrike / freezeAccount
                //   4. Act on decision before calling messagingService.sendMessage()
                //   5. Post-delivery async deep scan (fire-and-forget)
                // ────────────────────────────────────────────────────────────────────
                let currentUserId = Auth.auth().currentUser?.uid ?? ""

                // Group chats: skip the 1-on-1 safety gateway pipeline.
                // The pattern-of-behavior engine (ConversationRiskEngine) models
                // grooming/exploitation in private DMs and requires a single
                // recipientId. Groups have multiple recipients, so the DM model
                // doesn't apply and the missing recipientId would cause a false
                // blockAndStrike. Content safety is still enforced by
                // ThinkFirstGuardrailsService above, which runs for all message types.
                if conversation.isGroup {
                    // Skip straight to the Firestore write (below).
                } else {
                // P0 FIX: Guard against empty recipientId. If the other user's ID
                // hasn't resolved yet (async race on first open), fail fast rather than
                // passing an empty string to the safety gateway and Firestore writes.
                guard let recipientId = (otherUserId ?? conversation.requesterId).flatMap({ $0.isEmpty ? nil : $0 }) else {
                    await MainActor.run {
                        pendingMessages.removeValue(forKey: messageId)
                        messages.removeAll { $0.id == messageId }
                        messageText = textToSend
                        errorMessage = "Could not determine recipient. Please go back and reopen the conversation."
                        showErrorAlert = true
                    }
                    return
                }

                let context = await ConversationContextBuilder.build(
                    from: messages,
                    conversationId: conversationId,
                    senderId: currentUserId,
                    recipientId: recipientId,
                    conversationCreatedAt: Date() // approximate — refinable with Firestore metadata
                )

                // Resolve minor safety policy for this sender→recipient pair.
                // This enforces hard age-based blocks (DMs off, media off, etc.)
                // and applies tighter risk thresholds for minor/unknown recipients.
                let textLower = textToSend.lowercased()
                let containsLink = textLower.contains("http://") || textLower.contains("https://")
                let minorPolicy = await MinorSafetyService.shared.resolvePolicy(
                    senderId: currentUserId,
                    recipientId: recipientId,
                    hasMutualFollow: isMutualFollow,
                    messageContainsMedia: false,
                    messageContainsLink: containsLink
                )

                let gatewayDecision = await MessageSafetyGateway.shared.evaluate(
                    text: textToSend,
                    senderId: currentUserId,
                    recipientId: recipientId,
                    conversationId: conversationId,
                    conversationContext: context,
                    messageId: messageId,
                    minorPolicy: minorPolicy
                )

                switch gatewayDecision {

                case .freezeAccount(_, _, let reason):
                    // Immediate account freeze — remove message, lock input
                    await MainActor.run {
                        pendingMessages.removeValue(forKey: messageId)
                        messages.removeAll { $0.id == messageId }
                        accountFrozenReason = reason
                        withAnimation { showAccountFrozen = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                    return

                case .blockAndStrike(_, _, let reason):
                    // Block message + record strike — inform sender clearly
                    await MainActor.run {
                        pendingMessages.removeValue(forKey: messageId)
                        messages.removeAll { $0.id == messageId }
                        safetyStrikeReason = reason
                        safetyStrikeCount += 1
                        withAnimation { showStrikeNotice = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                    return

                case .holdForReview(_, _):
                    // Message held — sender sees a "under review" indicator.
                    // Recipient does NOT receive this message yet (skip the send call).
                    // We write directly to a "held_messages" subcollection for moderation.
                    await MainActor.run {
                        // Update optimistic message to show held state visually
                        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[idx].isSent = false
                            messages[idx].isSendFailed = false
                        }
                    }
                    // Write to held_messages (not the live messages collection)
                    try? await Firestore.firestore()
                        .collection("conversations").document(conversationId)
                        .collection("held_messages").document(messageId)
                        .setData([
                            "id": messageId,
                            "text": textToSend,
                            "senderId": currentUserId,
                            "recipientId": recipientId,
                            "timestamp": FieldValue.serverTimestamp(),
                            "safetyDecision": "hold_for_review",
                            "status": "pending_review"
                        ])
                    return // Do NOT deliver to recipient

                case .warnRecipient(let signals, _):
                    // Deliver but attach warning metadata — recipient sees safety banner
                    await MainActor.run {
                        messageWarnings[messageId] = signals
                    }
                    // Falls through to send below

                case .allow:
                    // Self-harm: special case — show crisis interstitial to SENDER
                    // (classified as .allow so the message can ultimately be sent
                    //  after the sender sees resources)
                    let (selfHarmSignals, _) = await MessageSafetyGateway.shared.classifyPublic(textToSend)
                    if selfHarmSignals.contains(.selfHarmCrisis) {
                        await MainActor.run {
                            pendingMessages.removeValue(forKey: messageId)
                            messages.removeAll { $0.id == messageId }
                            pendingCrisisMessageText = textToSend
                            pendingCrisisMessageId = messageId
                            showCrisisInterstitial = true
                        }
                        return // Interstitial handles re-send or cancel
                    }
                    break
                }
                // ── END SAFETY GATEWAY ─────────────────────────────────────────────

                // Attach warning flag to Firestore message doc (fire-and-forget)
                if case .warnRecipient(let signals, let score) = gatewayDecision {
                    let signalStrings = signals.map { $0.rawValue }
                    Task.detached(priority: .background) {
                        try? await Firestore.firestore()
                            .collection("conversations").document(conversationId)
                            .collection("messages").document(messageId)
                            .updateData([
                                "safetyWarning": true,
                                "safetySignals": signalStrings,
                                "safetyRiskScore": score
                            ])
                    }
                }

                // Post-delivery async deep scan (does not block UI)
                // Only for 1:1 DMs — group chats skip (no single recipientId).
                MessageSafetyGateway.shared.runAsyncDeepScan(
                    messageId: messageId,
                    conversationId: conversationId,
                    text: textToSend,
                    senderId: currentUserId,
                    recipientId: recipientId
                )

                } // end else (1:1 DM safety gateway)

                dlog("📤 Sending message to: \(conversationId)")

                try await messagingService.sendMessage(
                    conversationId: conversationId,
                    text: textToSend,
                    clientMessageId: messageId
                )

                dlog("✅ Message sent successfully!")
                
                // Success haptic
                await MainActor.run {
                    let successHaptic = UINotificationFeedbackGenerator()
                    successHaptic.notificationOccurred(.success)
                }
                
            } catch {
                dlog("❌ Error sending message: \(error)")
                
                await MainActor.run {
                    // Mark message as failed instead of removing
                    if pendingMessages[messageId] != nil {
                        pendingMessages[messageId]?.isSendFailed = true
                        
                        // Update in messages array
                        if let index = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[index].isSendFailed = true
                        }
                    }
                    
                    // Store failed message for manual retry fallback
                    failedMessageId = messageId
                    failedMessageText = textToSend

                    // FIX 1: Schedule auto-retry with exponential backoff.
                    // The service will retry in background every 2^attempt seconds (max 60s),
                    // surviving network reconnects and app foreground transitions.
                    messagingService.scheduleRetry(
                        for: messageId,
                        conversationId: conversation.id,
                        text: textToSend,
                        attempt: 0
                    )

                    // Show error toast with retry button
                    let errorMsg = (error as? FirebaseMessagingError)?.localizedDescription ?? "Failed to send message"

                    if !networkMonitor.isConnected {
                        toastManager.showWarning("No internet connection. Retrying when back online…")
                    } else {
                        toastManager.showError(errorMsg) {
                            // Manual retry action
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
        dlog("🔄 Retrying failed message: \(messageId)")
        
        // Clear failed state
        failedMessageId = nil
        failedMessageText = nil
        
        // Reuse the original messageId so Firestore setData is idempotent.
        // Generating a new UUID on every retry would create a new Firestore document
        // each time, resulting in duplicate messages if the original write actually
        // succeeded (e.g., network timeout after the write committed).
        let retryMessageId = messageId
        
        // Reset the failed message in UI back to "sending" state
        if pendingMessages[retryMessageId] != nil {
            pendingMessages[retryMessageId]?.isSendFailed = false
            pendingMessages[retryMessageId]?.isSent = false
            if let index = messages.firstIndex(where: { $0.id == retryMessageId }) {
                messages[index].isSendFailed = false
                messages[index].isSent = false
            }
        } else {
            // Message was removed from UI — re-insert it
            let optimisticMessage = AppMessage(
                id: retryMessageId,
                text: text,
                isFromCurrentUser: true,
                timestamp: Date(),
                senderId: Auth.auth().currentUser?.uid ?? "",
                senderName: messagingService.currentUserName,
                isSent: false,
                isDelivered: false,
                isSendFailed: false
            )
            pendingMessages[retryMessageId] = optimisticMessage
            messages.append(optimisticMessage)
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Send message using the same messageId — Firestore setData overwrites if doc exists
        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    text: text,
                    clientMessageId: retryMessageId
                )
                
                dlog("✅ Message retry successful!")
                
                await MainActor.run {
                    toastManager.showSuccess("Message sent")
                }
            } catch {
                dlog("❌ Message retry failed: \(error)")
                
                await MainActor.run {
                    // Mark as failed again
                    if pendingMessages[retryMessageId] != nil {
                        pendingMessages[retryMessageId]?.isSendFailed = true
                        
                        if let index = messages.firstIndex(where: { $0.id == retryMessageId }) {
                            messages[index].isSendFailed = true
                        }
                    }
                    
                    failedMessageId = retryMessageId
                    failedMessageText = text
                    
                    let errorMsg = (error as? FirebaseMessagingError)?.localizedDescription ?? "Failed to send message"
                    toastManager.showError(errorMsg) {
                        self.retryFailedMessage(messageId: retryMessageId, text: text)
                    }
                }
            }
        }
    }
    
    private func handleTypingIndicator(isTyping: Bool) {
        typingDebounceTimer?.invalidate()

        if isTyping {
            // FIX 5: Send "typing" immediately so the other person sees it right away.
            Task {
                try? await messagingService.updateTypingStatus(
                    conversationId: conversation.id,
                    isTyping: true
                )
            }
            // Auto-stop after 2.5s of no new keystrokes (debounce increased from 1.0s).
            typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                Task {
                    try? await messagingService.updateTypingStatus(
                        conversationId: conversation.id,
                        isTyping: false
                    )
                }
            }
        } else {
            // FIX 5: Only send "stopped typing" via the debounce timer — never immediately
            // on a keystroke. This prevents false "stopped" events mid-sentence when the
            // user deletes a character and the field is momentarily empty.
            typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                Task {
                    try? await messagingService.updateTypingStatus(
                        conversationId: conversation.id,
                        isTyping: false
                    )
                }
            }
        }
    }
    
    private func startListeningToProfilePhotoUpdates() {
        guard !conversation.isGroup else { return }
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        Task {
            // Resolve the other participant's ID from the Firestore conversation document.
            // This avoids fragile string-manipulation on the conversation ID which breaks
            // for any userId containing underscores.
            let db = Firestore.firestore()
            guard let doc = try? await db.collection("conversations")
                .document(conversation.id)
                .getDocument(),
                  let participantIds = doc.data()?["participantIds"] as? [String]
            else { return }

            guard let resolvedId = participantIds.first(where: { $0 != currentUserId }),
                  !resolvedId.isEmpty else { return }

            await MainActor.run { self.otherUserId = resolvedId }

            // Resolve mutual-follow status for MinorSafetyService policy.
            // Done once on appear; refreshed after user taps "Follow them first".
            if let followStatus = try? await FirebaseMessagingService.shared.checkFollowStatus(
                userId1: currentUserId, userId2: resolvedId
            ) {
                await MainActor.run {
                    self.isFollowingOtherUser = followStatus.user1FollowsUser2
                    self.isFollowedByOtherUser = followStatus.user2FollowsUser1
                    self.isMutualFollow = followStatus.user1FollowsUser2 && followStatus.user2FollowsUser1
                }
            }

            // Attach real-time listener to the resolved user doc.
            let listener = db.collection("users").document(resolvedId)
                .addSnapshotListener { snapshot, error in
                    guard error == nil, let data = snapshot?.data() else { return }
                    let photoURL = data["profilePhotoURL"] as? String
                                ?? data["profileImageURL"] as? String
                    Task { @MainActor in
                        self.otherUserProfilePhoto = photoURL?.isEmpty == false ? photoURL : nil
                    }
                }

            await MainActor.run {
                self.profilePhotoListener?.remove()  // remove old listener before reassigning
                // If view was dismissed before this Task completed, drop the new listener immediately
                guard self.isViewActive else {
                    listener.remove()
                    return
                }
                self.profilePhotoListener = listener
            }
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
                dlog("✅ Reaction added: \(emoji)")

                // Haptic feedback
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } catch {
                dlog("❌ Error adding reaction: \(error)")
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
                dlog("✅ Message deleted: \(message.id)")

                // Remove from local messages
                await MainActor.run {
                    messages.removeAll { $0.id == message.id }
                    toastManager.showSuccess("Message deleted")

                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Error deleting message: \(error)")
                await MainActor.run {
                    toastManager.showError("Failed to delete message")
                }
            }
        }
    }

    // MARK: - Report & Block

    private func reportMessage(_ message: AppMessage) {
        Task {
            do {
                // Report the conversation as spam with the specific message ID as context
                try await messagingService.reportSpam(
                    conversation.id,
                    reason: "Inappropriate message (messageId: \(message.id))"
                )
                await MainActor.run {
                    toastManager.showSuccess("Message reported")
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Error reporting message: \(error)")
                await MainActor.run {
                    toastManager.showError("Failed to report message")
                }
            }
        }
    }

    private func blockSender(userId: String) {
        Task {
            do {
                try await BlockService.shared.blockUser(userId: userId)
                await MainActor.run {
                    toastManager.showSuccess("User blocked")
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Error blocking user: \(error)")
                await MainActor.run {
                    toastManager.showError("Failed to block user")
                }
            }
        }
    }

    private func muteSender(userId: String) {
        Task {
            do {
                try await ModerationService.shared.muteUser(userId: userId)
                await MainActor.run {
                    toastManager.showSuccess("User muted")
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Error muting user: \(error)")
                await MainActor.run {
                    toastManager.showError("Failed to mute user")
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
    
    private func acceptMessageRequest() {
        guard !isAcceptingRequest else { return }
        isAcceptingRequest = true
        Task {
            do {
                try await messagingService.acceptMessageRequest(conversationId: conversation.id)
                dlog("✅ Message request accepted")
                
                await MainActor.run {
                    isAcceptingRequest = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    toastManager.showSuccess("Request accepted")
                    dismiss()
                }
            } catch {
                dlog("❌ Error accepting request: \(error)")
                await MainActor.run {
                    isAcceptingRequest = false
                    toastManager.showError("Failed to accept request")
                }
            }
        }
    }
    
    private func declineMessageRequest() {
        guard !isDecliningRequest else { return }
        isDecliningRequest = true
        Task {
            do {
                // Delete the conversation (Instagram-style decline)
                try await messagingService.deleteConversation(conversationId: conversation.id)
                dlog("✅ Message request declined and deleted")
                
                await MainActor.run {
                    isDecliningRequest = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    toastManager.showSuccess("Request deleted")
                    dismiss()
                }
            } catch {
                dlog("❌ Error declining request: \(error)")
                await MainActor.run {
                    isDecliningRequest = false
                    toastManager.showError("Failed to delete request")
                }
            }
        }
    }

    private func followOtherUser() {
        guard let uid = otherUserId, !isFollowButtonLoading else { return }
        isFollowButtonLoading = true
        Task {
            do {
                try await FollowService.shared.followUser(userId: uid)
                let followStatus = try await FirebaseMessagingService.shared.checkFollowStatus(
                    userId1: Auth.auth().currentUser?.uid ?? "",
                    userId2: uid
                )
                await MainActor.run {
                    isFollowingOtherUser = followStatus.user1FollowsUser2
                    isFollowedByOtherUser = followStatus.user2FollowsUser1
                    isMutualFollow = followStatus.user1FollowsUser2 && followStatus.user2FollowsUser1
                    isFollowButtonLoading = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run { isFollowButtonLoading = false }
            }
        }
    }

    private func restrictSender() {
        guard let uid = otherUserId,
              let currentUid = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                // Write a restriction record so future messages are filtered.
                let db = Firestore.firestore()
                try await db.collection("users").document(currentUid)
                    .collection("restricted").document(uid)
                    .setData(["restrictedAt": FieldValue.serverTimestamp(), "userId": uid])
                await MainActor.run {
                    toastManager.showSuccess("\(conversation.name) restricted")
                }
            } catch {
                await MainActor.run {
                    toastManager.showError("Could not restrict user")
                }
            }
        }
    }

    // MARK: - Attachment Handlers

    /// Send a quick reply chip text as a normal message and animate the chip away.
    private func sendQuickReply(_ text: String) {
        messageText = text
        sendMessage()
    }

    /// Called when the user picks a video from the library.
    private func handleVideoSelected(_ videoURL: URL) {
        let tempId = UUID().uuidString
        activeVideoUploadId = tempId

        // Optimistic message with upload progress
        let optimistic = AppMessage(
            id: tempId,
            text: "",
            isFromCurrentUser: true,
            timestamp: Date(),
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            isSent: false,
            messageType: .video,
            uploadProgress: 0.01
        )
        pendingMessages[tempId] = optimistic
        if !messages.contains(where: { $0.id == tempId }) {
            messages.append(optimistic)
        }

        VideoAttachmentService.uploadAndSend(
            videoURL: videoURL,
            conversationId: conversation.id,
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            onProgress: { progress in
                if let idx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[idx].uploadProgress = progress
                }
            },
            onComplete: { finalMsg in
                self.appendAttachmentMessage(finalMsg)
                self.pendingMessages.removeValue(forKey: tempId)
                self.messages.removeAll { $0.id == tempId }
                self.activeVideoUploadId = nil
            },
            onError: { error in
                dlog("❌ [Video] Upload error: \(error)")
                if let idx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[idx].isSendFailed = true
                    self.messages[idx].uploadProgress = nil
                }
                self.activeVideoUploadId = nil
                self.toastManager.showError("Video upload failed")
            }
        )
    }

    /// Called when the user picks a file from the document picker.
    private func handleFileSelected(fileURL: URL, fileName: String, fileSize: Int) {
        let tempId = UUID().uuidString
        activeFileUploadId = tempId

        let optimistic = AppMessage(
            id: tempId,
            text: "",
            isFromCurrentUser: true,
            timestamp: Date(),
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            isSent: false,
            messageType: .file,
            mediaFileName: fileName,
            mediaFileSize: fileSize,
            mediaFileExtension: (fileName as NSString).pathExtension.lowercased(),
            uploadProgress: 0.01
        )
        pendingMessages[tempId] = optimistic
        if !messages.contains(where: { $0.id == tempId }) {
            messages.append(optimistic)
        }

        FileAttachmentService.uploadAndSend(
            fileURL: fileURL,
            fileName: fileName,
            fileSize: fileSize,
            conversationId: conversation.id,
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            onProgress: { progress in
                if let idx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[idx].uploadProgress = progress
                }
            },
            onComplete: { finalMsg in
                self.appendAttachmentMessage(finalMsg)
                self.pendingMessages.removeValue(forKey: tempId)
                self.messages.removeAll { $0.id == tempId }
                self.activeFileUploadId = nil
            },
            onError: { error in
                dlog("❌ [File] Upload error: \(error)")
                if let idx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[idx].isSendFailed = true
                    self.messages[idx].uploadProgress = nil
                }
                self.activeFileUploadId = nil
                self.toastManager.showError("File upload failed")
            }
        )
    }

    /// Append a fully-uploaded attachment message into the local messages array.
    private func appendAttachmentMessage(_ msg: AppMessage) {
        guard !messages.contains(where: { $0.id == msg.id }) else { return }
        messages.append(msg)
    }

    // MARK: - Berean AI Send

    /// Routes an @Berean message through the Claude streaming API instead of normal Firestore send.
    /// The user's message and Berean's final response are both persisted to Firestore on completion.
    private func sendBereanMessage(userText: String) {
        // Cancel any in-progress Berean stream
        bereanStreamTask?.cancel()

        let userMessageId = UUID().uuidString
        let bereanResponseId = UUID().uuidString
        let prompt = userText
            .replacingOccurrences(of: "@berean", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Optimistic: show the user's @Berean message in the chat immediately
        let currentUID = Auth.auth().currentUser?.uid ?? ""
        let optimisticUserMessage = AppMessage(
            id: userMessageId,
            text: userText,
            isFromCurrentUser: true,
            timestamp: Date(),
            senderId: currentUID,
            senderName: messagingService.currentUserName,
            isSent: false,
            isDelivered: false,
            isSendFailed: false
        )
        pendingMessages[userMessageId] = optimisticUserMessage
        if !messages.contains(where: { $0.id == userMessageId }) {
            messages.append(optimisticUserMessage)
        }

        // Start streaming state
        bereanStreamingText = ""
        bereanStreamingTokenCount = 0
        bereanTriggeredByMessageId = userMessageId
        withAnimation(.easeInOut(duration: 0.2)) { isBereanStreaming = true }

        HapticManager.impact(style: .light)

        bereanStreamTask = Task {
            // Write the user's @Berean message to Firestore
            let conversationId = conversation.id
            Task.detached(priority: .background) {
                try? await Firestore.firestore()
                    .collection("conversations").document(conversationId)
                    .collection("messages").document(userMessageId)
                    .setData([
                        "id": userMessageId,
                        "text": userText,
                        "senderId": currentUID,
                        "timestamp": FieldValue.serverTimestamp(),
                        "isSent": true,
                        "isDelivered": true
                    ])
            }

            // Stream from Claude
            let finalText = await BereanStreamingService.stream(
                prompt: prompt,
                onToken: { token in
                    Task { @MainActor in
                        bereanStreamingText += token
                        bereanStreamingTokenCount += 1
                    }
                }
            )

            await MainActor.run {
                // Mark user message as sent
                pendingMessages.removeValue(forKey: userMessageId)
                if let idx = messages.firstIndex(where: { $0.id == userMessageId }) {
                    messages[idx].isSent = true
                }

                guard !Task.isCancelled else {
                    isBereanStreaming = false
                    bereanStreamingText = ""
                    return
                }

                // Determine final display text
                let displayText: String
                if finalText.hasPrefix("__error__") {
                    displayText = "I wasn't able to reach my source of wisdom right now. Try again in a moment. 🙏"
                    HapticManager.notification(type: .error)
                } else {
                    displayText = finalText
                    HapticManager.notification(type: .success)
                }

                // Inject the Berean response as a real message in the local list
                let bereanMessage = AppMessage(
                    id: bereanResponseId,
                    text: displayText,
                    isFromCurrentUser: false,
                    timestamp: Date(),
                    senderId: "berean_ai",
                    senderName: "Berean",
                    isSent: true,
                    isDelivered: true
                )
                messages.append(bereanMessage)

                // End streaming state
                withAnimation(.easeInOut(duration: 0.2)) {
                    isBereanStreaming = false
                    bereanStreamingText = ""
                }

                messageText = ""
            }

            // Persist Berean response to Firestore
            if !finalText.hasPrefix("__error__") {
                Task.detached(priority: .background) {
                    try? await Firestore.firestore()
                        .collection("conversations").document(conversationId)
                        .collection("messages").document(bereanResponseId)
                        .setData([
                            "id": bereanResponseId,
                            "text": finalText,
                            "senderId": "berean_ai",
                            "timestamp": FieldValue.serverTimestamp(),
                            "isBereanResponse": true,
                            "triggeredBy": userMessageId
                        ])
                }
            }
        }
    }
}

// MARK: - Chat User Profile Sheet

struct ChatUserProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conversation: ChatConversation
    var resolvedUserId: String? = nil  // Pre-resolved otherUserId from UnifiedChatView
    
    @ObservedObject private var userService = LegacyUserService.shared
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    
    @State private var otherUserProfile: User?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var messageCount: Int = 0
    @State private var averageResponseTime: String = "N/A"
    @State private var showShareSheet = false
    @State private var isSubmittingReport = false
    @State private var reportConfirmationMessage: String?
    @State private var showFullProfile = false
    
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
                    AMENLoadingIndicator()
                    
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
                                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
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
                            VStack(spacing: 12) {
                                // View Full Profile button — navigates to the user's real profile
                                if let profileUserId = resolvedUserId ?? otherUserProfile?.id, !profileUserId.isEmpty {
                                    Button {
                                        showFullProfile = true
                                    } label: {
                                        Text("View Full Profile")
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
                                }

                                // Continue Chat row (with more options menu)
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
                                        guard let reportedId = otherUserProfile?.id,
                                              let currentId = Auth.auth().currentUser?.uid,
                                              !isSubmittingReport else { return }
                                        isSubmittingReport = true
                                        let submission = ReportSubmission(
                                            reporterId: currentId,
                                            reportedUserId: reportedId,
                                            conversationId: conversation.id,
                                            reason: .unwantedContact,
                                            evidenceMessageIds: [],
                                            additionalContext: nil,
                                            blockImmediately: false
                                        )
                                        Task {
                                            let result = await SafetyReportingService.shared.submitReport(submission)
                                            isSubmittingReport = false
                                            switch result {
                                            case .success:
                                                reportConfirmationMessage = "Report submitted."
                                            case .alreadyReported:
                                                reportConfirmationMessage = "You've already reported this user recently."
                                            case .failure:
                                                reportConfirmationMessage = "Could not submit report. Please try again."
                                            }
                                        }
                                    } label: {
                                        Label("Report User", systemImage: "exclamationmark.triangle")
                                    }
                                    
                                    Button(role: .destructive) {
                                        guard let reportedId = otherUserProfile?.id,
                                              let currentId = Auth.auth().currentUser?.uid,
                                              !isSubmittingReport else { return }
                                        isSubmittingReport = true
                                        let submission = ReportSubmission(
                                            reporterId: currentId,
                                            reportedUserId: reportedId,
                                            conversationId: conversation.id,
                                            reason: .unwantedContact,
                                            evidenceMessageIds: [],
                                            additionalContext: "User blocked from conversation header",
                                            blockImmediately: true
                                        )
                                        Task {
                                            _ = await SafetyReportingService.shared.submitReport(submission)
                                            isSubmittingReport = false
                                        }
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
                                } // end HStack (Continue Chat row)
                            } // end VStack (action buttons)
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
        .sheet(isPresented: $showFullProfile) {
            if let profileUserId = resolvedUserId ?? otherUserProfile?.id, !profileUserId.isEmpty {
                NavigationStack {
                    UserProfileView(userId: profileUserId)
                }
            }
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
                
                dlog("📱 Loading profile for user: \(otherUserId)")
                
                // Fetch user profile
                let profile = try await userService.fetchUser(userId: otherUserId)
                
                // Fetch conversation stats
                await loadConversationStats(conversationId: conversation.id, otherUserId: otherUserId)
                
                await MainActor.run {
                    self.otherUserProfile = profile
                    self.isLoading = false
                }
                
                dlog("✅ Profile loaded successfully: \(profile.displayName)")
                
            } catch {
                dlog("❌ Error loading profile: \(error)")
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
        dlog("⚠️ Conversation ID doesn't match expected format, fetching from Firebase...")
        
        do {
            let db = Firestore.firestore()
            let conversationDoc = try await db.collection("conversations").document(conversationId).getDocument()
            
            guard conversationDoc.exists else {
                throw NSError(domain: "ChatUserProfileSheet", code: 404, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
            }
            
            // Get participantIds array from conversation document
            if let participantIds = conversationDoc.data()?["participantIds"] as? [String],
               let otherUserId = participantIds.first(where: { $0 != currentUserId }) {
                dlog("✅ Found other user ID from Firebase: \(otherUserId)")
                return otherUserId
            }
            
            throw NSError(domain: "ChatUserProfileSheet", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not determine other user ID from conversation"])
        } catch {
            dlog("❌ Error fetching conversation: \(error)")
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

// MARK: - iMessage-Style Bubble Shape

/// Produces the classic iMessage asymmetric rounded-rectangle with a small "tail"
/// at the bottom corner pointing toward the sender's side.
private struct MessageBubbleShape: Shape {
    let isFromCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18          // large corner radius (most corners)
        let tail: CGFloat = 4        // small tail-corner radius
        var path = Path()

        if isFromCurrentUser {
            // Outgoing: tail at bottom-right
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tail))
            path.addArc(center: CGPoint(x: rect.maxX - tail, y: rect.maxY - tail),
                        radius: tail, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Incoming: tail at bottom-left
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + tail, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + tail, y: rect.maxY - tail),
                        radius: tail, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Liquid Glass Message Bubble

struct LiquidGlassMessageBubble: View {
    let message: AppMessage
    let isFromCurrentUser: Bool
    /// Whether this bubble is the last in a consecutive run from the same sender.
    /// Controls tail visibility and spacing.
    var isLastInGroup: Bool = true
    var showReadReceipt: Bool = false
    // FIX 1: Show "Retrying..." state for messages in the auto-retry queue
    var isRetrying: Bool = false
    var onReply: () -> Void
    var onReact: (String) -> Void
    var onLongPress: () -> Void
    var onDelete: () -> Void
    var onRetry: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onMute: (() -> Void)? = nil

    // Inline double-tap reaction bar state
    @State private var showInlineReactions = false

    // Reactions for inline quick-tap (iMessage style)
    private let quickReactions = ["❤️", "🙏", "🔥", "😂", "😮", "👍"]

    // iMessage outgoing gradient
    private let sentGradient = LinearGradient(
        colors: [
            Color(red: 0.0, green: 0.50, blue: 1.0),
            Color(red: 0.0, green: 0.40, blue: 0.92)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    private let sentColor = Color(red: 0.0, green: 0.48, blue: 1.0)

    // Swipe-to-reply state
    @State private var swipeOffset: CGFloat = 0
    @State private var didTriggerReplyHaptic = false
    private let swipeThreshold: CGFloat = 60

    private var bubbleBackground: some View {
        Group {
            if isFromCurrentUser {
                if message.isSendFailed {
                    MessageBubbleShape(isFromCurrentUser: true)
                        .fill(Color.red.opacity(0.25))
                        .overlay(
                            MessageBubbleShape(isFromCurrentUser: true)
                                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
                        )
                } else {
                    MessageBubbleShape(isFromCurrentUser: true)
                        .fill(sentGradient)
                        .shadow(color: sentColor.opacity(0.25), radius: 6, y: 2)
                }
            } else {
                MessageBubbleShape(isFromCurrentUser: false)
                    .fill(Color(.systemGray6))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            }
        }
    }

    var body: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 0) {
            // Inline reaction bar (appears above bubble on double-tap, no background box)
            if showInlineReactions {
                inlineReactionBar
                    .transition(.scale(scale: 0.7, anchor: isFromCurrentUser ? .bottomTrailing : .bottomLeading)
                                .combined(with: .opacity))
                    .padding(.bottom, 4)
            }

            ZStack(alignment: isFromCurrentUser ? .leading : .trailing) {
                // Swipe-to-reply indicator
                if abs(swipeOffset) > 10 {
                    Image(systemName: "arrowshape.turn.up.left.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(abs(swipeOffset) >= swipeThreshold ? .blue : .secondary)
                        .scaleEffect(abs(swipeOffset) >= swipeThreshold ? 1.1 : 0.8)
                        .opacity(min(1.0, abs(swipeOffset) / swipeThreshold))
                        .animation(.spring(response: 0.2), value: swipeOffset)
                }

            HStack(alignment: .bottom, spacing: 6) {
                if isFromCurrentUser { Spacer(minLength: 52) }

                // Avatar (incoming only, group chats, last in group)
                if !isFromCurrentUser {
                    if isLastInGroup {
                        avatarView
                    } else {
                        Color.clear.frame(width: 28, height: 28) // placeholder to maintain alignment
                    }
                }

                VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 3) {
                    // Sender name (group chats)
                    if !isFromCurrentUser, let name = message.senderName, isLastInGroup {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(isFromCurrentUser ? .trailing : .leading, 14)
                    }

                    // Reply quote
                    if let reply = message.replyTo {
                        replyQuote(replyMessage: reply)
                            .padding(.bottom, 2)
                    }

                    // Bubble
                    HStack(alignment: .bottom, spacing: 6) {
                        // Failed / Retrying indicator (left of bubble for outgoing)
                        if isFromCurrentUser && message.isSendFailed {
                            if isRetrying {
                                // FIX 1: Auto-retry in progress — show spinner instead of tap-to-retry
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Retrying…")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button { onRetry?() } label: {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.red)
                                }
                            }
                        }

                        // ── Message content: branches on messageType ──────────────
                        Group {
                            switch message.messageType {
                            case .video:
                                VideoMessageBubble(message: message, isFromCurrentUser: isFromCurrentUser)
                            case .file:
                                FileMessageBubble(message: message, isFromCurrentUser: isFromCurrentUser)
                            case .link:
                                LinkMessageBubble(message: message, isFromCurrentUser: isFromCurrentUser)
                            case .text, .image:
                                // Default text / photo bubble (existing behavior untouched)
                                Text(message.text)
                                    .font(.system(size: 16))
                                    .foregroundStyle(isFromCurrentUser ? .white : Color(.label))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(bubbleBackground)
                                    .frame(maxWidth: 280, alignment: isFromCurrentUser ? .trailing : .leading)
                            }
                        }
                        .reactionPicker(
                            id: message.id,
                            isFromCurrentUser: isFromCurrentUser,
                            context: .message,
                            selectedEmoji: message.reactions
                                .first(where: { $0.userId == (FirebaseManager.shared.currentUser?.uid ?? "") })?.emoji,
                            onSelect: { emoji in onReact(emoji) }
                        )
                        .onTapGesture(count: 2) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                showInlineReactions.toggle()
                            }
                        }
                        .contextMenu {
                            Button { onReply() } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                            Button { onLongPress() } label: {
                                Label("React", systemImage: "face.smiling")
                            }
                            if message.messageType == .text || message.messageType == .image {
                                Button {
                                    UIPasteboard.general.string = message.text
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                            if isFromCurrentUser {
                                Divider()
                                Button(role: .destructive) { onDelete() } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if !isFromCurrentUser {
                                Divider()
                                if let onReport {
                                    Button(role: .destructive) { onReport() } label: {
                                        Label("Report", systemImage: "exclamationmark.bubble.fill")
                                    }
                                }
                                if let onBlock {
                                    Button(role: .destructive) { onBlock() } label: {
                                        Label("Block", systemImage: "person.slash.fill")
                                    }
                                }
                                if let onMute {
                                    Button { onMute() } label: {
                                        Label("Mute", systemImage: "speaker.slash.fill")
                                    }
                                }
                            }
                        }
                    }

                    // Reactions row (below bubble, no background pill)
                    if !message.reactions.isEmpty {
                        reactionsRow
                    }

                    // Read receipt (outgoing only, last in group)
                    if isFromCurrentUser && isLastInGroup {
                        readReceiptView
                    }
                }

                if !isFromCurrentUser { Spacer(minLength: 52) }
            }
            .offset(x: swipeOffset)
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // Only allow swipe in the reply direction (left for outgoing, right for incoming)
                        let translation = value.translation.width
                        let direction: CGFloat = isFromCurrentUser ? -1 : 1
                        let raw = translation * direction
                        guard raw > 0 else { swipeOffset = 0; return }
                        swipeOffset = translation * 0.6 // dampened
                        if abs(swipeOffset) >= swipeThreshold && !didTriggerReplyHaptic {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            didTriggerReplyHaptic = true
                        }
                    }
                    .onEnded { _ in
                        if abs(swipeOffset) >= swipeThreshold {
                            onReply()
                        }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            swipeOffset = 0
                        }
                        didTriggerReplyHaptic = false
                    }
            )
            } // ZStack
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: showInlineReactions)
    }

    // MARK: - Inline Reaction Bar
    // Legacy path kept for double-tap; the new long-press path uses ReactionTrayOverlay.

    private var inlineReactionBar: some View {
        HStack(spacing: 2) {
            ForEach(quickReactions, id: \.self) { emoji in
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onReact(emoji)
                    withAnimation { showInlineReactions = false }
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .padding(6)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        )
    }

    // MARK: - Reactions row

    private var reactionsRow: some View {
        ReactionBadgeRow(
            reactions: message.reactions.groupedByEmoji,
            currentUserId: FirebaseManager.shared.currentUser?.uid ?? "",
            alignment: isFromCurrentUser ? .trailing : .leading
        ) { emoji in
            onReact(emoji)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Read receipt

    private var readReceiptView: some View {
        Group {
            if message.isSendFailed {
                EmptyView()
            } else if !message.isSent {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if message.isRead {
                HStack(spacing: 1) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(sentColor)
            } else if message.isDelivered {
                HStack(spacing: 1) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 2)
    }

    // MARK: - Reply quote

    private func replyQuote(replyMessage: AppMessage) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isFromCurrentUser ? Color.white.opacity(0.6) : Color.accentColor.opacity(0.7))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                if let name = replyMessage.senderName {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isFromCurrentUser ? .white.opacity(0.85) : Color.accentColor)
                        .lineLimit(1)
                }
                Text(replyMessage.text)
                    .font(.system(size: 12))
                    .foregroundStyle(isFromCurrentUser ? .white.opacity(0.7) : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFromCurrentUser ? Color.white.opacity(0.15) : Color.accentColor.opacity(0.08))
        )
        .frame(maxWidth: 260)
        .padding(.horizontal, 4)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Group {
            if let profileImageURL = message.senderProfileImageURL,
               !profileImageURL.isEmpty,
               let url = URL(string: profileImageURL) {
                CachedAsyncImage(
                    url: url,
                    content: { img in
                        img.resizable().scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    },
                    placeholder: { senderInitialsAvatar }
                )
            } else {
                senderInitialsAvatar
            }
        }
    }

    // MARK: - Sender Initials Avatar (Fallback)

    private var senderInitialsAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.18))
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(message.senderName?.prefix(1) ?? "?").uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
    }
}

// MARK: - Typing Indicator (iMessage 3-dot bounce)

struct LiquidGlassTypingIndicator: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Bubble
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 8, height: 8)
                        .offset(y: phase == i ? -4 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                MessageBubbleShape(isFromCurrentUser: false)
                    .fill(Color(.systemGray6))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            )

            Spacer(minLength: 52)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
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
    var comingSoon: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(color.opacity(comingSoon ? 0.04 : 0.08))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(comingSoon ? Color.gray.opacity(0.5) : color)
                        .frame(width: 52, height: 52)
                    
                    if comingSoon {
                        Text("Soon")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.6))
                            .clipShape(Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(comingSoon ? Color.gray.opacity(0.5) : Color.gray)
            }
        }
        .buttonStyle(SpringButtonStyle())
        .opacity(comingSoon ? 0.75 : 1.0)
    }
}

// Note: ScaleButtonStyle is defined in SharedUIComponents.swift
// Note: placeholder(when:alignment:placeholder:) extension is defined in SharedUIComponents.swift

// MARK: - Attach Item View (tray cell)

/// A single cell in the animated attachment tray.
struct AttachItemView: View {
    struct Item: Identifiable {
        let id: String
        let icon: String
        let label: String
        let iconColor: Color
        let bgColor: Color
    }

    let item: Item

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(item.bgColor)
                    .frame(width: 44, height: 44)
                Image(systemName: item.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(item.iconColor)
            }
            Text(item.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(.systemGray))
        }
    }
}

// MARK: - Quick Reply Chips

private struct QuickReplyModel: Identifiable {
    let id: String
    let emoji: String
    let text: String
}

struct QuickReplyChipsView: View {

    @Binding var isExpanded: Bool
    @Binding var dismissedChipIds: Set<String>
    let onChipTapped: (String) -> Void

    @State private var slidingOutId: String? = nil

    private let quickReplies: [QuickReplyModel] = [
        QuickReplyModel(id: "pray",    emoji: "🙏",  text: "I'll be praying for you"),
        QuickReplyModel(id: "verse",   emoji: "✝️",  text: "Share a verse"),
        QuickReplyModel(id: "believe", emoji: "💬",  text: "What are you believing God for?")
    ]

    private var visibleReplies: [QuickReplyModel] {
        quickReplies.filter { !dismissedChipIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Circle "+" rotates 45° when expanded
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 24, height: 24)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isExpanded)
                    }

                    Text("Quick replies")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isExpanded)
                }
            }
            .buttonStyle(.plain)

            // Chips
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(Array(visibleReplies.enumerated()), id: \.element.id) { index, reply in
                        chipButton(for: reply, index: index)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: visibleReplies.map { $0.id })
            }
        }
    }

    @ViewBuilder
    private func chipButton(for reply: QuickReplyModel, index: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // Animate chip sliding out
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                slidingOutId = reply.id
            }

            onChipTapped(reply.text)

            // Restore after 1.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    slidingOutId = nil
                    dismissedChipIds.insert(reply.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(reply.emoji)
                    .font(.system(size: 16))
                Text(reply.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .offset(x: slidingOutId == reply.id ? 300 : 0)
        .opacity(slidingOutId == reply.id ? 0 : 1)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.08),
            value: isExpanded
        )
    }
}

// MARK: - Berean AI Typing Indicator Bubble

/// Three pulsing dots with the gold BEREAN AI header — shown before the first token arrives.
struct BereanTypingIndicatorBubble: View {
    @State private var animate = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Gold left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.85, green: 0.70, blue: 0.30))
                .frame(width: 3, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                // Header label
                Text("BEREAN AI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.75, green: 0.60, blue: 0.20))

                // Pulsing dots
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color(red: 0.75, green: 0.60, blue: 0.20))
                            .frame(width: 7, height: 7)
                            .scaleEffect(animate ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.55)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.15),
                                value: animate
                            )
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color(red: 0.85, green: 0.70, blue: 0.30).opacity(0.5),
                        lineWidth: 1
                    )
            )

            Spacer()
        }
        .onAppear { animate = true }
    }
}

// MARK: - Berean AI Streaming Bubble

/// Live-updating bubble that shows Berean's response as tokens arrive.
struct BereanStreamingBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Gold left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.85, green: 0.70, blue: 0.30))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                // Header label
                Text("BEREAN AI")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.75, green: 0.60, blue: 0.20))

                Text(text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color(red: 0.85, green: 0.70, blue: 0.30).opacity(0.5),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)

            Spacer()
        }
    }
}

// MARK: - Reaction Picker Overlay (long-press, centered above screen midpoint)

// ReactionPickerOverlay replaced by AMENReactionSystem.ReactionTrayOverlay.
// Kept as thin shim so call sites that check showReactionPicker still compile.
struct ReactionPickerOverlay: View {
    let message: AppMessage
    @Binding var isShowing: Bool
    var onReaction: (String) -> Void
    var body: some View { EmptyView() }
}

// MARK: - Berean Streaming Service

/// Routes Berean chat through the bereanChatProxy Cloud Function.
/// Simulates streaming via local typewriter animation (15 ms/character) so the
/// UX is identical to the previous SSE implementation — no call-site changes needed.
enum BereanStreamingService {

    private static let systemPrompt = """
    You are Berean, a Spirit-filled AI Bible assistant inside the AMEN church community app. \
    Respond with wisdom, scripture, and grace. Keep responses concise and conversational. \
    Always ground answers in Scripture.
    """

    /// Fetches a full response from bereanChatProxy, then plays it back character-by-character
    /// at 15 ms/char via `onToken`. Returns the accumulated full text on success,
    /// or a string prefixed with "__error__" on failure.
    static func stream(
        prompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> String {
        do {
            let functions = Functions.functions()
            let callable = functions.httpsCallable("bereanChatProxy")
            let result = try await callable.call([
                "systemPrompt": systemPrompt,
                "userMessage": prompt,
                "maxTokens": 600,
            ] as [String: Any])

            guard let data = result.data as? [String: Any],
                  let text = data["text"] as? String else {
                print("❌ BereanStreamingService: unexpected proxy response")
                return "__error__: invalid proxy response"
            }

            // Typewriter playback — 15 ms per character
            for char in text {
                if Task.isCancelled { break }
                onToken(String(char))
                try? await Task.sleep(nanoseconds: 15_000_000)
            }

            return text

        } catch is CancellationError {
            print("ℹ️ BereanStreamingService: task cancelled")
            return "__error__: cancelled"
        } catch {
            print("❌ BereanStreamingService: \(error)")
            return "__error__: \(error.localizedDescription)"
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
