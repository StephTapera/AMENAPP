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
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine

private struct UnifiedChatScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct UnifiedChatBottomAnchorKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct UnifiedChatScrollViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct UnifiedChatPhotoAttachmentModifier: ViewModifier {
    @Binding var selectedImages: [PhotosPickerItem]
    @Binding var showingPhotoPicker: Bool
    @Binding var showingCameraPicker: Bool
    @Binding var capturedCameraImage: UIImage?
    @Binding var showCameraPermissionAlert: Bool

    let onPhotoItemsSelected: ([PhotosPickerItem]) -> Void
    let onCameraImageSelected: (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedImages,
                maxSelectionCount: 5,
                matching: .any(of: [.images])
            )
            .onChange(of: selectedImages) { _, newItems in
                guard !newItems.isEmpty else { return }
                onPhotoItemsSelected(newItems)
            }
            .fullScreenCover(isPresented: $showingCameraPicker) {
                ImagePicker(sourceType: .camera, selectedImage: $capturedCameraImage)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedCameraImage) { _, newImage in
                guard let newImage else { return }
                onCameraImageSelected(newImage)
                capturedCameraImage = nil
            }
            .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow camera access in Settings to take a photo for this message.")
            }
    }
}

// MARK: - Unified Chat View

struct UnifiedChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @ObservedObject private var networkMonitor = AMENNetworkMonitor.shared
    @ObservedObject private var toastManager = ToastManager.shared
    @ObservedObject private var linkPreviewService = LinkPreviewService.shared
    @ObservedObject private var smartAttachmentResolver = AmenSmartAttachmentResolverService.shared // PERF: singleton → @ObservedObject
    @StateObject private var chatLinkController = ComposerLinkPreviewController()
    // P0 FIX: These are shared singletons — @StateObject would take ownership and
    // may release them when the view disappears, destroying singleton state.
    // Use @ObservedObject so SwiftUI observes without taking ownership.
    @ObservedObject private var chatMemoryService = ChatMemoryService.shared
    @ObservedObject private var chatExtractionEngine = ChatMemoryExtractionEngine.shared
    @ObservedObject private var chatCalendarBridge = ChatCalendarBridge.shared
    @State private var showMemorySheet = false

    // System 36: Messaging Filters & Smart Inbox — thread-level search/filter sheet
    @State private var showThreadSearch = false
    @State private var threadSearchJumpTargetId: String? = nil
    @ObservedObject private var amenFeatureFlags = AMENFeatureFlags.shared

    let conversation: ChatConversation
    var recipientAccentColor: Color? = nil

    @State private var messageText = ""
    @State private var messages: [AppMessage] = []
    @State private var pendingMessages: [String: AppMessage] = [:]
    @FocusState private var isInputFocused: Bool
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingCameraPicker = false
    @State private var capturedCameraImage: UIImage?
    @State private var showCameraPermissionAlert = false
    @State private var isRecording = false
    @State private var selectedMessage: AppMessage?
    @State private var replyingTo: AppMessage?
    @State private var isTyping = false
    @State private var remoteTypingNames: [String] = []
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
    @State private var showLiquidGlassAttachmentMenu = false

    // Video attachment
    @State private var showVideoPicker = false
    @State private var activeVideoUploadId: String? = nil

    // File attachment
    @State private var showDocumentPicker = false
    @State private var activeFileUploadId: String? = nil

    // Link attachment
    @State private var showLinkSheet = false
    @State private var messageAttachmentState: AmenAttachmentComposerState = .empty
    @State private var messageSmartAttachment: AmenSmartAttachment?
    @State private var messageMentionedLinks: [URL] = []
    @State private var messageAttachmentTask: Task<Void, Never>?

    // Feature 3: Poll creation sheet
    @State private var showCreatePollSheet = false

    @State private var placeholderText = ""
    @State private var firstUnreadMessageId: String?
    @State private var inputShimmerX: CGFloat = -160
    @State private var showJumpToUnread = false
    @State private var showGroupInfo = false

    @StateObject private var successChips = SuccessChipCenter()
    @State private var scrollViewHeight: CGFloat = 0
    @State private var bottomAnchorY: CGFloat = 0
    @State private var contentOffsetY: CGFloat = 0
    @State private var lastContentOffsetY: CGFloat = 0
    @State private var isScrollingDown: Bool = false
    @State private var showJumpToLatest: Bool = false
    @State private var sendSweepTrigger: Bool = false

    /// Normalized 0 (fully expanded) → 1 (fully compact) driven by scroll position.
    /// The composer shrinks smoothly as the user scrolls up through message history.
    @State private var composerCollapseProgress: CGFloat = 0

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

    // @Berean DM one-time AI disclosure (privacy/COPPA compliance)
    @State private var showBereanDMDisclosure = false
    @State private var pendingBereanText: String? = nil
    @StateObject private var messageSeal = SuccessSealController()

    // MARK: — Messaging Intelligence (Phases 4-12)
    @StateObject private var intelligenceCoordinator = AmenMessagingIntelligenceCoordinator()
    @State private var pendingSaveMessage: AmenMessageSaveContext? = nil
    @State private var pendingTranscriptMessage: AppMessage? = nil   // CF-2: voice transcript panel
    @State private var activeMediaActionMessage: AppMessage? = nil   // Phase 11: media action overlay
    @State private var safetyNudgeIsForEdit: Bool = false            // NB-5: edit safety routing

    // MARK: — Communication OS (System 32)
    @State private var showMessageActionCluster: Bool = false
    @State private var actionClusterMessage: AppMessage? = nil
    @State private var showConversationMemorySearch: Bool = false
    @State private var showThreadSummaryPanel: Bool = false
    @State private var showMediaIntelligenceDock: Bool = false
    @State private var mediaDockMessage: AppMessage? = nil
    @State private var showPresencePicker: Bool = false
    @State private var otherUserPresence: SmartPresenceStatus? = nil

    // MARK: — Edit Message state
    @State private var editingMessage: AppMessage? = nil
    @State private var editingOriginalText: String = ""
    @State private var draftBeforeEdit: String = ""

    // MARK: — Schedule Reply state
    @ObservedObject private var scheduledMessagesService = ScheduledMessagesService.shared
    @ObservedObject private var prefsService = AMENUserPreferencesService.shared
    @State private var showSchedulePicker = false
    @State private var scheduledDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var editingScheduledMessage: ScheduledMessage? = nil

    // Smart reply chips
    @State private var smartReplySuggestions: [String] = []
    @State private var isLoadingSmartReplies = false

    // Listener lifecycle management
    @State private var listenerTask: Task<Void, Never>?
    @State private var isViewActive = false  // guard against listener leak on rapid dismiss

    // (seenMessageIDs removed — dedup is handled entirely by the dict-merge in loadMessages)
    
    // P1-2 FIX: Scroll position preservation
    @State private var isNearBottom = true
    @Namespace private var bottomID
    // Stored proxy so jumpToUnreadButton can scroll outside the ScrollViewReader closure
    @State private var chatScrollProxy: ScrollViewProxy?
    
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

    // MARK: — Voice Message Recording
    @StateObject private var voiceViewModel = VoiceMessageViewModel()

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

    private var messageDraftKey: String { "chatDraft_\(conversation.id)" }

    private var headerSofteningProgress: CGFloat {
        min(max(-contentOffsetY / 80, 0), 1)
    }

    @ViewBuilder
    private var mainStack: some View {
        VStack(spacing: 0) {
            // Header
            liquidGlassHeader
                .modifier(SoftStickyHeaderModifier(isActive: headerSofteningProgress > 0.01, intensity: headerSofteningProgress))

            // Chat memory capsule
            ChatMemoryCapsuleView(
                memoryService: chatMemoryService,
                extractionEngine: chatExtractionEngine,
                onTap: { showMemorySheet = true }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Incoming message request banner — Phase 8: Liquid Glass upgrade when flag is ON
            if isIncomingRequest {
                if AMENFeatureFlags.shared.messagingApprovalCardsEnabled {
                    AmenApprovalReviewCard(
                        senderName: conversation.name,
                        senderAvatarURL: otherUserProfilePhoto,
                        mutualFollowerCount: 0,
                        onAccept: { acceptMessageRequest() },
                        onDecline: { declineMessageRequest() },
                        onViewProfile: { showUserProfile = true },
                        onRestrict: { restrictSender() },
                        onBlock: {
                            userIdToBlock = otherUserId
                            showBlockConfirmation = true
                        },
                        onReport: {
                            Task {
                                try? await messagingService.reportSpam(
                                    conversation.id,
                                    reason: "Message request report"
                                )
                                await MainActor.run {
                                    toastManager.showSuccess("Reported")
                                }
                            }
                        },
                        isAccepting: isAcceptingRequest,
                        isDeclining: isDecliningRequest
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else {
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
                }   // end else (legacy ChatRequestBanner)
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
                            withAnimation(Motion.adaptive(.spring(response: 0.3))) {
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
                                            withAnimation(Motion.adaptive(.spring(response: 0.3))) {
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
                    composerInputContent
                }
            }
            .background(Color.clear)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showStrikeNotice)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showAccountFrozen)
        }
    }

    // MARK: - Composer Input Content

    @ViewBuilder
    private var composerInputContent: some View {
        // Collapsible media section
        if isMediaSectionExpanded {
            collapsibleMediaSection
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
        }

        // System 32: Smart Thread Context Bar (decisions/questions/actions/media chips)
        if AMENFeatureFlags.shared.messagesSmartContextEnabled {
            SmartThreadContextBar(
                coordinator: intelligenceCoordinator,
                isScrollingDown: isScrollingDown
            ) { chip in
                handleSmartContextChip(chip)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Phase 9: Catch Me Up tray (shown when unread backlog is large)
        if AMENFeatureFlags.shared.messagingCatchUpEnabled,
           !intelligenceCoordinator.catchUpDismissed {
            let unreadCount = messages.filter { !$0.isRead && !$0.isFromCurrentUser }.count
            if intelligenceCoordinator.catchUpState != .idle
               || unreadCount >= AmenSmartPillPriorityEngine.catchUpUnreadThreshold {
                AmenCatchUpTray(
                    state: intelligenceCoordinator.catchUpState,
                    unreadCount: unreadCount,
                    onRequest: {
                        intelligenceCoordinator.requestCatchUp(
                            conversationId: conversation.id,
                            messages: messages
                        )
                    },
                    onDismiss: { intelligenceCoordinator.dismissCatchUp() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        // Phase 4A: Smart pill row (max 3 context-aware pills)
        if AMENFeatureFlags.shared.messagingSmartPillsEnabled,
           !intelligenceCoordinator.activePills.isEmpty {
            AmenSmartPillRow(pills: intelligenceCoordinator.activePills) { pillType in
                handleSmartPillTap(pillType)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Live link preview above input
        ComposerLinkPreview(controller: chatLinkController)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: chatLinkController.activeURL)
        if case .resolving = messageAttachmentState {
            Text("Analyzing link...")
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else if let attachment = messageSmartAttachment {
            VStack(alignment: .leading, spacing: 8) {
                AmenUniversalLinkCard(attachment: attachment, mode: .composerPreview)
                HStack(spacing: 10) {
                    Button("Open") { openAttachmentURL(attachment) }
                    Button("Save") { saveMessageAttachment(attachment) }
                    Button("Ask Berean") { messageText = "@Berean summarize this link: \(attachment.canonicalUrl)" }
                    Button("Reply Thoughtfully") { messageText += (messageText.isEmpty ? "" : " ") + "Thoughtful response to this: \(attachment.canonicalUrl)" }
                }
                .buttonStyle(.borderless)
                .font(.systemScaled(11, weight: .semibold))
                if !messageMentionedLinks.isEmpty {
                    Text("Mentioned Links (\(messageMentionedLinks.count))")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
        } else if case .blocked = messageAttachmentState {
            Text("Restricted link. Message will send with plain URL.")
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }

        // Smart reply chips — aligned with the text field inside the input bar
        // Leading: 12 (outer hPad) + 40 (+ button) + 12 (spacing) = 64
        if messageText.isEmpty && !smartReplySuggestions.isEmpty {
            smartReplyChipsRow
                .autoHideChips(isScrollingDown || isInputFocused)
                .padding(.leading, 64)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Feature 2: Reply preview strip — shown when replying to a message
        if let replying = replyingTo {
            ReplyPreviewStrip(
                replyToText: replying.text.isEmpty ? "(attachment)" : replying.text,
                replyToAuthor: replying.senderName ?? "Message"
            ) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                    replyingTo = nil
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
        }

        // Scheduled messages + edit mode banners (above input bar)
        scheduledMessagesBanner
        editModeBanner

        // Phase 7: Pre-send safety nudge
        if let nudge = intelligenceCoordinator.pendingSafetyNudge,
           AMENFeatureFlags.shared.messagingSafetyNudgesEnabled {
            AmenSafetyNudgeCard(
                context: nudge,
                onEdit: {
                    AmenMessagingAnalytics.track(.safetyNudgeEdited)
                    intelligenceCoordinator.dismissSafetyNudge()
                    safetyNudgeIsForEdit = false
                },
                onSendAnyway: nudge.canSendAnyway ? {
                    AmenMessagingAnalytics.track(.safetyNudgeSentAnyway)
                    intelligenceCoordinator.dismissSafetyNudge()
                    if safetyNudgeIsForEdit {
                        safetyNudgeIsForEdit = false
                        saveEdit()
                    } else {
                        sendMessage()
                    }
                } : nil,
                onDismiss: {
                    AmenMessagingAnalytics.track(.safetyNudgeCancelled)
                    intelligenceCoordinator.dismissSafetyNudge()
                    if safetyNudgeIsForEdit {
                        safetyNudgeIsForEdit = false
                        cancelEditMode()
                    } else {
                        messageText = ""
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.75), value: nudge)
        }

        // Compact input bar — collapses smoothly when scrolled into history.
        // collapseProgress 0 = fully expanded, 1 = fully compact.
        let p = composerCollapseProgress
        let composerScale = 1.0 - 0.04 * p           // 1.0 → 0.96
        let composerOpacity = 1.0 - 0.12 * p         // 1.0 → 0.88
        let composerHPad = 12.0 + 16.0 * p           // 12 → 28 (narrows toward center)
        let composerBPad = 4.0 - 2.0 * p             // 4 → 2
        compactInputBar
            .composerCompression(isInputFocused || !messageText.isEmpty || isRecording)
            .padding(.horizontal, composerHPad)
            .padding(.bottom, composerBPad)
            .scaleEffect(composerScale)
            .opacity(composerOpacity)
            .amenComposerFocusGlass(
                isFocused: isInputFocused && AMENFeatureFlags.shared.messagingLiquidGlassAnimationsEnabled
            )
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRowView(message: AppMessage, index: Int) -> some View {
        let rowContext = messageRowContext(for: message, at: index)
        let currentUID = rowContext.currentUID
        let isFromCurrentUser = rowContext.isFromCurrentUser
        let isLastInGroup = rowContext.isLastInGroup
        let isLastOutgoing = rowContext.isLastOutgoing
        let showDateHeader = rowContext.showDateHeader

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
                messageBubbleContent(
                    message: message,
                    isFromCurrentUser: isFromCurrentUser,
                    isLastInGroup: isLastInGroup,
                    isLastOutgoing: isLastOutgoing
                )
            }
        }
    }

    @ViewBuilder
    private func messageBubbleContent(
        message: AppMessage,
        isFromCurrentUser: Bool,
        isLastInGroup: Bool,
        isLastOutgoing: Bool
    ) -> some View {
        VStack(spacing: 4) {
            // Feature 3: Poll card — rendered instead of the regular bubble
            if let poll = message.poll {
                GlassPollCard(
                    poll: poll,
                    currentUserId: Auth.auth().currentUser?.uid ?? ""
                ) { optionId in
                    togglePollVote(messageId: message.id, optionId: optionId, allowMultiple: poll.allowMultiple)
                }
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
            } else {
                // Feature 2: Inline reply quote shown inside bubble area
                if let replyText = message.replyToText,
                   let replyAuthor = message.replyToAuthorName {
                    InlineReplyQuote(text: replyText, authorName: replyAuthor)
                        .frame(maxWidth: 280)
                        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                        .padding(.bottom, 2)
                }

                messageBubbleView(
                    message: message,
                    isFromCurrentUser: isFromCurrentUser,
                    isLastInGroup: isLastInGroup,
                    isLastOutgoing: isLastOutgoing
                )
                // Feature 1: AMEN Reaction Capsules row
                if !message.amenReactions.isEmpty {
                    ReactionCapsulesRow(
                        reactions: message.amenReactions,
                        currentUserId: Auth.auth().currentUser?.uid ?? ""
                    ) { reaction in
                        toggleAmenReaction(messageId: message.id, reaction: reaction)
                    }
                    .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                }

                // Feature 2: Reply count badge
                if message.replyCount > 0 {
                    Text("↩ \(message.replyCount) \(message.replyCount == 1 ? "reply" : "replies")")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                        .padding(.horizontal, 4)
                }

                // Link preview cards below the bubble
                if let firstPreview = message.linkPreviews.first {
                    let previewMeta: LinkPreviewMetadata = LinkPreviewService.shared.getCached(for: firstPreview.url)
                        ?? LinkPreviewMetadata(url: firstPreview.url, title: firstPreview.title, siteName: firstPreview.url.host)
                    if AMENFeatureFlags.shared.inAppBrowserEnabled {
                        EnhancedLinkPreviewCard(url: firstPreview.url, metadata: previewMeta)
                            .frame(maxWidth: 280)
                            .padding(.horizontal, 8)
                    } else {
                        FeedLinkPreviewCard(url: firstPreview.url, metadata: previewMeta)
                            .frame(maxWidth: 280)
                            .padding(.horizontal, 8)
                    }
                }

                // Phase 5: Inline translation
                if AMENFeatureFlags.shared.messagingTranslationEnabled,
                   !message.text.isEmpty {
                    let msgId = message.id
                    let tState = intelligenceCoordinator.translationState(for: msgId)
                    if tState != .notNeeded && tState != .disabled {
                        AmenTranslationMessageView(
                            messageId: msgId,
                            state: tState,
                            isShowingOriginal: intelligenceCoordinator.isShowingOriginal(for: msgId),
                            onToggle: {
                                if case .translated = intelligenceCoordinator.translationState(for: msgId) {
                                    intelligenceCoordinator.toggleOriginal(for: msgId)
                                } else {
                                    intelligenceCoordinator.requestTranslation(for: message)
                                }
                            },
                            isFromCurrentUser: message.isFromCurrentUser
                        )
                    }
                }
                // Phase 12: Read receipt chip — outgoing only, behind presence polish flag
                if AMENFeatureFlags.shared.messagingPresencePolishEnabled,
                   isLastOutgoing {
                    AmenMessageReadReceiptChip(
                        isDelivered: message.isDelivered,
                        isRead: message.isRead,
                        readByCount: 0,
                        readerName: conversation.name.components(separatedBy: " ").first
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.bottom, isLastInGroup ? 6 : 2)
        .id(message.id)
        .amenMessageArrival(
            timestamp: message.timestamp,
            isEnabled: AMENFeatureFlags.shared.messagingLiquidGlassAnimationsEnabled
        )
    }

    var body: some View {
        chatBaseView
            // Sheets cluster
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(conversationId: conversation.id) { videoURL in
                    handleVideoSelected(videoURL)
                }
            }
            .sheet(isPresented: $showThreadSearch) {
                if #available(iOS 17.0, *) {
                    MessagingThreadSearchView(
                        messages: messages,
                        currentUserId: Auth.auth().currentUser?.uid ?? "",
                        onJumpToMessage: { messageId in threadSearchJumpTargetId = messageId }
                    )
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showDocumentPicker) { documentPickerSheetView }
            .sheet(isPresented: $showLinkSheet) {
                LinkAttachSheet(
                    conversationId: conversation.id,
                    senderId: Auth.auth().currentUser?.uid ?? "",
                    senderName: messagingService.currentUserName
                ) { msg in appendAttachmentMessage(msg) }
            }
            .sheet(isPresented: $showCreatePollSheet) {
                CreatePollSheet(isPresented: $showCreatePollSheet) { poll in sendPoll(poll) }
            }
            .sheet(isPresented: $showSchedulePicker) {
                ScheduleReplyPickerSheet(text: messageText, selectedDate: $scheduledDate) { confirmedDate in
                    scheduleReply(at: confirmedDate)
                }
            }
            .sheet(isPresented: $showMemorySheet) {
                ChatMemorySheetView(
                    memoryService: chatMemoryService,
                    extractionEngine: chatExtractionEngine,
                    calendarBridge: chatCalendarBridge
                )
            }
            .sheet(isPresented: $showConversationMemorySearch) {
                ConversationMemorySearchView(
                    conversationId: conversation.id,
                    onSelectResult: { _ in showConversationMemorySearch = false },
                    onDismiss: { showConversationMemorySearch = false }
                )
            }
            .sheet(isPresented: $showThreadSummaryPanel) {
                ThreadSummaryPanel(
                    threadId: conversation.id,
                    onOpenSourceMessage: { messageId in
                        showThreadSummaryPanel = false; scrollToMessage(messageId)
                    },
                    onCreateTask: { action in
                        showThreadSummaryPanel = false
                        toastManager.showSuccess("Suggested follow-up ready")
                        dlog("[ThreadSummary] Create task requested: \(action.title)")
                    },
                    onDismiss: { showThreadSummaryPanel = false }
                )
            }
            .overlay(alignment: .bottom) { messageActionClusterOverlay.zIndex(100) }
            .overlay(alignment: .bottom) { mediaIntelligenceDockOverlay.zIndex(99) }
            .sheet(isPresented: $showPresencePicker) { PresenceModePickerSheet() }
            .sheet(item: $pendingSaveMessage) { ctx in
                AmenMessageSaveActionsSheet(context: ctx, flags: AMENFeatureFlags.shared, onDismiss: { pendingSaveMessage = nil })
            }
            .sheet(item: $pendingTranscriptMessage) { _ in unavailableTranscriptPanel }
            .overlay(alignment: .bottom) {
                if let mediaMsg = activeMediaActionMessage {
                    mediaActionOverlayView(for: mediaMsg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 96)
                }
            }
            .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)), value: activeMediaActionMessage?.id)
            // Alerts cluster
            .alert("Add to Calendar?", isPresented: $chatCalendarBridge.showCalendarConfirmation) {
                Button("Add") { Task { await chatCalendarBridge.confirmCalendarAdd() } }
                Button("Not now", role: .cancel) { Task { await chatCalendarBridge.declineCalendarAdd() } }
            } message: {
                if let item = chatCalendarBridge.pendingCalendarItem { Text(item.summary) }
            }
            .alert("Message Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .alert("Report Message", isPresented: $showReportConfirmation) {
                Button("Report", role: .destructive) {
                    if let msg = messageToReport { reportMessage(msg) }
                    messageToReport = nil
                }
                Button("Cancel", role: .cancel) { messageToReport = nil }
            } message: { Text("This message will be reported for review. Thank you for helping keep AMEN safe.") }
            .alert("Block User", isPresented: $showBlockConfirmation) {
                Button("Block", role: .destructive) {
                    if let uid = userIdToBlock { blockSender(userId: uid) }
                    userIdToBlock = nil
                }
                Button("Cancel", role: .cancel) { userIdToBlock = nil }
            } message: { Text("You will no longer receive messages from this person.") }
            .alert("Berean AI in this conversation", isPresented: $showBereanDMDisclosure) {
                Button("Allow") {
                    UserDefaults.standard.set(true, forKey: "berean_dm_ai_disclosed_\(conversation.id)")
                    if let text = pendingBereanText { sendBereanMessage(userText: text); pendingBereanText = nil }
                }
                Button("No thanks", role: .cancel) { pendingBereanText = nil }
            } message: {
                Text("Typing @Berean routes this message to an AI model for a spiritual response. The conversation stays in this chat and is not used for training.")
            }
            // Lifecycle cluster
            .task {
                await setupChatViewAsync()
                await chatMemoryService.loadItems(for: conversation.id)
                chatExtractionEngine.resetSession()
                voiceViewModel.onComplete = handleVoiceRecordingCompletion
            }
            .onAppear {
                isViewActive = true
                generateRandomPlaceholder()
                NotificationAggregationService.shared.trackConversationViewing(conversation.id)
                scheduledMessagesService.startListening()
                if let saved = UserDefaults.standard.string(forKey: messageDraftKey), !saved.isEmpty {
                    messageText = saved
                }
            }
            .onDisappear {
                isViewActive = false
                cleanupChatView()
                scheduledMessagesService.stopListening()
                chatMemoryService.cleanup()
                chatExtractionEngine.clearPending()
                NotificationAggregationService.shared.updateCurrentScreen(.messages)
            }
            .onChange(of: scenePhase) { _, newPhase in handleScenePhaseChange(newPhase) }
            .onChange(of: messages) { _, newMessages in updateSmartPillContext(for: newMessages) }
            .onChange(of: messageText) { _, newValue in handleMessageTextChanged(newValue) }
            .onChange(of: isInputFocused) { _, newValue in
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                    isInputBarFocused = newValue
                    if newValue {
                        isMediaSectionExpanded = false
                        composerCollapseProgress = 0
                    }
                }
            }
    }

    // MARK: - Body decomposition (extracted to reduce type-checker complexity)

    @ViewBuilder
    private var chatBaseView: some View {
        ZStack {
            liquidGlassBackground
            mainStack
            if showLiquidGlassAttachmentMenu {
                AmenAttachmentMenu(
                    items: attachmentMenuItems,
                    onSelect: handleAttachmentMenuAction,
                    onUnavailable: handleUnavailableAttachmentMenuItem,
                    onDismiss: dismissLiquidGlassAttachmentMenu
                )
                .zIndex(70)
            }
            if LiquidGlassEffectsFlags.floatingStatusPill, !networkMonitor.isConnected {
                VStack {
                    Spacer()
                    FloatingStatusPillView(text: "Offline", systemIcon: "wifi.slash")
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            ReactionTrayOverlay(state: ReactionPresentationState.shared)
            // AmenMessageContextMenuOverlay(presenter: AmenMessageContextMenuPresenter.shared)
        }
        .navigationBarHidden(true)
        .withToast()
        .successChips(successChips)
        .modifier(PrimaryChatSheetsModifier(
            showUserProfile: $showUserProfile,
            showGroupInfo: $showGroupInfo,
            showCrisisInterstitial: $showCrisisInterstitial,
            userProfileSheetView: { AnyView(userProfileSheetView) },
            groupInfoSheetView: { AnyView(groupInfoSheetView) },
            onCrisisSendAnyway: handleCrisisSendAnyway,
            onCrisisClose: handleCrisisClose
        ))
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            if !oldValue && newValue {
                toastManager.showSuccess("Back online")
                if let failedId = failedMessageId, let failedText = failedMessageText {
                    retryFailedMessage(messageId: failedId, text: failedText)
                }
                Task { await OfflineMessageQueue.shared.processQueue() }
            } else if oldValue && !newValue {
                toastManager.showWarning("You're offline. Messages will send when connection is restored.")
            }
        }
        .onChange(of: reportConfirmationMessage) { _, newValue in
            if let text = newValue {
                successChips.show(text)
                reportConfirmationMessage = nil
            }
        }
        .modifier(UnifiedChatPhotoAttachmentModifier(
            selectedImages: $selectedImages,
            showingPhotoPicker: $showingPhotoPicker,
            showingCameraPicker: $showingCameraPicker,
            capturedCameraImage: $capturedCameraImage,
            showCameraPermissionAlert: $showCameraPermissionAlert,
            onPhotoItemsSelected: { items in Task { await handleSelectedPhotoItems(items) } },
            onCameraImageSelected: { image in Task { await sendPhotoAttachments([image]) } }
        ))
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
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                        .opacity(0.3)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

            Text(String(conversation.name.prefix(1)).uppercased())
                .font(.systemScaled(16, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Background
    
    private var liquidGlassBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.98),
                    Color(red: 0.95, green: 0.95, blue: 0.95),
                    Color(red: 0.97, green: 0.97, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            RadialGradient(
                colors: [Color.blue.opacity(0.10), Color.clear],
                center: UnitPoint(x: 0.2, y: 0.1),
                startRadius: 10,
                endRadius: 260
            )
            
            RadialGradient(
                colors: [Color.blue.opacity(0.06), Color.clear],
                center: UnitPoint(x: 0.85, y: 0.3),
                startRadius: 10,
                endRadius: 220
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Header

    private var chatHeaderStatus: (text: String, image: String, accessibility: String, isInteractive: Bool) {
        if !remoteTypingNames.isEmpty {
            let text = remoteTypingNames.count == 1 ? "\(remoteTypingNames[0]) is typing..." : "\(remoteTypingNames.count) people are typing..."
            return (text, "ellipsis.message", "Real typing status: \(text)", false)
        }
        if isRecording {
            return ("Recording voice...", "waveform", "Voice note recording is active", false)
        }
        if isIncomingRequest {
            return ("Unknown Contact", "person.crop.circle.badge.questionmark", "This message request is from an unknown contact", true)
        }
        if !networkMonitor.isConnected {
            return ("Offline", "wifi.slash", "Amen Messaging is offline. Messages will send after reconnecting.", false)
        }
        if conversation.isGroup {
            return ("Group Chat", "person.3.fill", "Group chat details are available", true)
        }
        return ("Secure Chat", "lock.fill", "Direct message thread", false)
    }

    private var unreadIncomingCount: Int {
        messages.filter { !$0.isRead && !$0.isFromCurrentUser }.count
    }

    private var liquidGlassHeader: some View {
        HStack(spacing: 12) {
            // Back button - blends with background
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                                    .opacity(0.25)
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        if unreadIncomingCount > 0 {
                            Text(unreadIncomingCount > 99 ? "99+" : "\(unreadIncomingCount)")
                                .font(.systemScaled(9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 7, y: -7)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(unreadIncomingCount > 0 ? "Back, \(unreadIncomingCount) unread messages" : "Back")
            
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
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1)
                                        .opacity(0.3)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
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
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))

                let status = chatHeaderStatus
                AmenChatStatusChip(
                    text: status.text,
                    systemImage: status.image,
                    accessibilityDescription: status.accessibility,
                    isInteractive: status.isInteractive,
                    action: status.isInteractive ? {
                        if conversation.isGroup {
                            showGroupInfo = true
                        } else {
                            showUserProfile = true
                        }
                    } : nil
                )
            }
            
            Spacer()

            // System 36: Thread-level search/filter — flag-gated, no-op when off
            if #available(iOS 17.0, *), amenFeatureFlags.messagingThreadSearchFiltersEnabled {
                Button {
                    AMENAnalyticsService.shared.track(.messageThreadFilterSelected(filter: "search"))
                    showThreadSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1)
                                        .opacity(0.25)
                                )
                        )
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Search this conversation")
            }

            // Info button - blends with background
            Button {
                if conversation.isGroup {
                    showGroupInfo = true
                } else {
                    showUserProfile = true
                }
            } label: {
                Image(systemName: conversation.isGroup ? "person.3.fill" : "info.circle")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                                    .opacity(0.25)
                            )
                    )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.65),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Messages
    
    private var messagesScrollView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: UnifiedChatScrollOffsetKey.self, value: geo.frame(in: .named("UnifiedChatScroll")).minY)
                    }
                    .frame(height: 0)

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
                                            .font(.systemScaled(16))
                                    }
                                    Text(isLoadingMoreMessages ? "Loading..." : "Load older messages")
                                        .font(.systemScaled(14, weight: .medium))
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
                        
                        // System 32: Group Pulse Card (group conversations only)
                        if AMENFeatureFlags.shared.groupDiscussionPulseEnabled,
                           conversation.isGroup {
                            GroupPulseCard(conversationId: conversation.id, isGroup: true)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }

                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            messageRowView(message: message, index: index)
                        }

                        // Typing indicator — shown when the other person is typing
                        if isTyping {
                            if AMENFeatureFlags.shared.messagingTypingIndicatorEnabled {
                                AmenChatTypingIndicator(names: remoteTypingNames)
                                    .padding(.horizontal, 16)
                                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                            } else {
                                LiquidGlassTypingIndicator()
                                    .padding(.horizontal, 16)
                                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                            }
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
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(
                                            key: UnifiedChatBottomAnchorKey.self,
                                            value: geo.frame(in: .named("UnifiedChatScroll")).maxY
                                        )
                                }
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120) // Extra padding so messages don't hide under input bar
                }
                .coordinateSpace(name: "UnifiedChatScroll")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: UnifiedChatScrollViewHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(UnifiedChatScrollOffsetKey.self) { value in
                    let delta = value - lastContentOffsetY
                    isScrollingDown = delta < -0.5
                    lastContentOffsetY = value
                    contentOffsetY = value

                    // Composer collapse progress: collapses smoothly when user scrolls
                    // up through history (offset decreases below 0).
                    // Collapse starts at -60 pts from top and completes at -200 pts.
                    let scrolledFromTop: CGFloat = -value  // positive when scrolled down
                    let collapseStart: CGFloat = 60
                    let collapseEnd: CGFloat = 200
                    let rawProgress = (scrolledFromTop - collapseStart) / (collapseEnd - collapseStart)
                    let newProgress = min(max(rawProgress, 0), 1)
                    // Only apply when not focused (don't collapse while typing)
                    if !isInputFocused && !isRecording {
                        withAnimation(.interpolatingSpring(stiffness: 220, damping: 32)) {
                            composerCollapseProgress = newProgress
                        }
                    } else {
                        withAnimation(.interpolatingSpring(stiffness: 220, damping: 32)) {
                            composerCollapseProgress = 0
                        }
                    }
                }
                .onPreferenceChange(UnifiedChatScrollViewHeightKey.self) { value in
                    scrollViewHeight = value
                }
                .onPreferenceChange(UnifiedChatBottomAnchorKey.self) { value in
                    bottomAnchorY = value
                    let distance = bottomAnchorY - scrollViewHeight
                    let nearBottom = distance < 80
                    isNearBottom = nearBottom
                    showJumpToLatest = !nearBottom && !messages.isEmpty
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
                    // System 32: extractSmartContext not yet implemented on coordinator
                    // if AMENFeatureFlags.shared.messagesSmartContextEnabled, newCount >= 5 { ... }
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
                    // Store proxy so jumpToUnreadButton can reach it from outside the closure
                    chatScrollProxy = proxy

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
                // System 36: Jump-to-message from thread search.
                // The search sheet writes the target ID; we scroll and clear it.
                .onChange(of: threadSearchJumpTargetId) { _, target in
                    guard let target, !target.isEmpty else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        threadSearchJumpTargetId = nil
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if LiquidGlassEffectsFlags.jumpToLatestPill, showJumpToLatest {
                        JumpToLatestPill {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 130)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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
            .font(.systemScaled(12, weight: .medium))
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.3)) {
                chatScrollProxy?.scrollTo("unread-separator", anchor: .top)
                showJumpToUnread = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.systemScaled(14, weight: .semibold))
                
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
            attachTrayCell(icon: "photo.fill",       label: "Photos", iconColor: .blue,   bgColor: Color(red: 0.91, green: 0.96,  blue: 0.996), index: 0) { showingPhotoPicker = true }
            attachTrayCell(icon: "video.fill",       label: "Video",  iconColor: .purple, bgColor: Color(red: 0.94, green: 0.93,  blue: 0.973), index: 1) { showVideoPicker = true }
            attachTrayCell(icon: "doc.fill",         label: "Files",  iconColor: .green,  bgColor: Color(red: 0.94, green: 0.968, blue: 0.929), index: 2) { showDocumentPicker = true }
            attachTrayCell(icon: "link",             label: "Link",   iconColor: .orange, bgColor: Color(red: 1.0,  green: 0.957, blue: 0.925), index: 3) { showLinkSheet = true }
            attachTrayCell(icon: "chart.bar.fill",   label: "Poll",   iconColor: .indigo, bgColor: Color(red: 0.93, green: 0.92,  blue: 0.97),  index: 4) { showCreatePollSheet = true }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 8, y: -2)
        )
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6)).delay(0.05)) {
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
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
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

    private var attachmentMenuItems: [AmenMessagingAttachmentMenuItem] {
        AmenMessagingAttachmentActionRouter.menuItems(
            flags: AMENFeatureFlags.shared,
            selectedMessage: selectedMessage,
            hasDraftText: !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            scheduleReplyEnabled: prefsService.preferences.scheduleReplyEnabled,
            hasGroupShareTarget: false,
            cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
        )
    }

    private func dismissLiquidGlassAttachmentMenu() {
        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.82))) {
            showLiquidGlassAttachmentMenu = false
        }
    }

    private func handleAttachmentMenuAction(_ action: AmenMessagingAttachmentAction) {
        guard attachmentMenuItems.first(where: { $0.action == action })?.availability.isEnabled == true else {
            let reason = attachmentMenuItems.first(where: { $0.action == action })?.availability.reason ?? "This action is unavailable."
            AmenMessagingAnalytics.track(.attachmentMenuUnavailable, parameters: ["action": action.rawValue])
            toastManager.showInfo(reason)
            return
        }

        AmenMessagingAnalytics.track(.attachmentMenuActionTapped, parameters: ["action": action.rawValue])
        dismissLiquidGlassAttachmentMenu()

        switch action {
        case .camera:
            openCameraFromAttachmentMenu()
        case .photos:
            showingPhotoPicker = true
        case .voice:
            guard !isRecording else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                isRecording = true
            }
            voiceViewModel.startRecording()
        case .files:
            showDocumentPicker = true
        case .poll:
            showCreatePollSheet = true
        case .sendLater:
            guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                toastManager.showInfo("Write a message before scheduling.")
                return
            }
            scheduledDate = Date().addingTimeInterval(60 * 30)
            showSchedulePicker = true
        case .saveToSelah:
            presentSaveSheet(actions: [.saveToSelah])
        case .addToChurchNotes:
            presentSaveSheet(actions: [.addToChurchNotes])
        case .saveToNotes:
            presentSaveSheet(actions: [.saveToNotes])
        case .startReflection:
            presentSaveSheet(actions: [.saveToSelah])
        case .createReminder:
            presentSaveSheet(actions: [.remindMe])
        case .askBerean:
            if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messageText = "@Berean "
            } else if !messageText.localizedCaseInsensitiveContains("@Berean") {
                messageText = "@Berean \(messageText)"
            }
            isInputFocused = true
        case .stickers, .prayerRequest, .shareWithGroup, .shareSafely:
            let reason = attachmentMenuItems.first(where: { $0.action == action })?.availability.reason ?? "This action is unavailable."
            toastManager.showInfo(reason)
        }
    }

    private func openCameraFromAttachmentMenu() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            toastManager.showInfo("Camera is not available on this device.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCameraPicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        showingCameraPicker = true
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }

    private func handleSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items.prefix(5) {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            } catch {
                dlog("⚠️ Failed to load selected photo: \(error)")
            }
        }

        await MainActor.run {
            selectedImages = []
        }

        await sendPhotoAttachments(images)
    }

    private func sendPhotoAttachments(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            await MainActor.run {
                toastManager.showInfo("No photo was selected.")
            }
            return
        }

        let caption = await MainActor.run {
            messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        await MainActor.run {
            isSendingMessage = true
        }

        do {
            try await messagingService.sendMessageWithPhotos(
                conversationId: conversation.id,
                text: caption,
                images: images
            )
            await MainActor.run {
                messageText = ""
                chatLinkController.reset()
                isInputFocused = false
                isSendingMessage = false
                successChips.show(images.count == 1 ? "Photo sent" : "Photos sent")
            }
        } catch {
            await MainActor.run {
                isSendingMessage = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func handleUnavailableAttachmentMenuItem(_ item: AmenMessagingAttachmentMenuItem) {
        AmenMessagingAnalytics.track(.attachmentMenuUnavailable, parameters: ["action": item.action.rawValue])
        toastManager.showInfo(item.availability.reason ?? "This action is unavailable.")
    }

    private func presentSaveSheet(actions: [AmenSaveActionType]) {
        guard let message = selectedMessage else {
            toastManager.showInfo("Select a message first.")
            return
        }
        pendingSaveMessage = AmenMessageSaveContext(
            message: message,
            conversationName: conversation.name,
            presentedActions: actions
        )
    }
    
    // MARK: - Edit Mode Banner
    // Shown above compactInputBar when user is editing an existing message.

    @ViewBuilder
    private var editModeBanner: some View {
        if editingMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Editing message")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    cancelEditMode()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
        }
    }

    // MARK: - Scheduled Messages Banner
    // Shown above input bar: lists pending scheduled messages for this conversation.

    @ViewBuilder
    private var scheduledMessagesBanner: some View {
        let pending = scheduledMessagesService.scheduledMessages(for: conversation.id)
        if !pending.isEmpty {
            VStack(spacing: 0) {
                ForEach(pending) { scheduled in
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(scheduled.scheduledAtFormatted)
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text(scheduled.text)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        // Cancel
                        Button {
                            Task { try? await scheduledMessagesService.cancelScheduledMessage(scheduled) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(4)
                                .background(Circle().fill(Color(.systemGray5)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    if scheduled.id != pending.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .background(.ultraThinMaterial)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
        }
    }

    // MARK: - Compact Input Bar

    private var compactInputBar: some View {
        HStack(spacing: 12) {
            // Plus button — rotates 45° when tray is open
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()

                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6))) {
                    if AmenMessagingAttachmentMenuPresentationMode.resolve(
                        liquidGlassMenuEnabled: AMENFeatureFlags.shared.messagingLiquidGlassAttachmentMenuEnabled
                    ) == .liquidGlassMenu {
                        showLiquidGlassAttachmentMenu.toggle()
                        isMediaSectionExpanded = false
                        isAttachTrayOpen = false
                        isInputFocused = false
                        if showLiquidGlassAttachmentMenu {
                            AmenMessagingAnalytics.track(.attachmentMenuOpened)
                        }
                    } else {
                        showLiquidGlassAttachmentMenu = false
                        isMediaSectionExpanded.toggle()
                        if isMediaSectionExpanded {
                            isInputFocused = false
                            isAttachTrayOpen = true
                        } else {
                            isAttachTrayOpen = false
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 1)
                                .opacity(0.25)
                        )

                    Image(systemName: "plus")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .rotationEffect(.degrees((isMediaSectionExpanded || showLiquidGlassAttachmentMenu) ? 45 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isMediaSectionExpanded)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showLiquidGlassAttachmentMenu)
                }
            }
            .buttonStyle(SpringButtonStyle())
            
            // Text input - frosted glass with visible text and subtle border
            // cornerRadius morphs when focused (iMessage-style)
            let inputCornerRadius: CGFloat = isInputFocused ? 16 : 20
            let inputBackground = RoundedRectangle(cornerRadius: inputCornerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(0.6)
                    .clipShape(RoundedRectangle(cornerRadius: inputCornerRadius))
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .rotationEffect(.degrees(10))
                    .offset(x: inputShimmerX)
                    .opacity(0.25)
                    .clipShape(RoundedRectangle(cornerRadius: inputCornerRadius))
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isInputFocused)
            let inputBorder = RoundedRectangle(cornerRadius: inputCornerRadius)
                .stroke(Color.white, lineWidth: 1)
                .opacity(0.2)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isInputFocused)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if messageText.isEmpty {
                        Text(placeholderText)
                            .font(.systemScaled(16, weight: .regular))
                            .foregroundColor(Color.primary.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $messageText, axis: .vertical)
                        .font(.systemScaled(16, weight: .regular))
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .tint(Color.primary)
                        .foregroundColor(Color.primary)
                }

                // Voice/Send/Stop button — morphs between states with spring animation
                // Long-press (when text present) shows "Send Later" schedule picker.
                Button {
                    if isRecording {
                        // Stop recording — upload to Storage and send
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            isRecording = false
                        }
                        voiceViewModel.stopAndSend()
                    } else if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if editingMessage != nil {
                            Task { await performEditWithSafetyCheck() }
                        } else {
                            Task { await performSendWithSafetyCheck() }
                        }
                    } else {
                        // Mic tap — start recording
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            isRecording = true
                        }
                        voiceViewModel.startRecording()
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
                                    reduceMotion ? nil : .easeOut(duration: 1.0).repeatForever(autoreverses: false),
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
                                    : AnyShapeStyle(recipientAccentColor ?? Color.amenGold)
                            )
                            .frame(width: 32, height: 32)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isMessageEmpty)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)

                        if isRecording {
                            Image(systemName: "stop.fill")
                                .font(.systemScaled(12, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if isMessageEmpty {
                            Image(systemName: "mic")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.systemScaled(14, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isMessageEmpty)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
                }
                .highlightSweep(trigger: sendSweepTrigger)
                .buttonStyle(SpringButtonStyle())
                .disabled(isSendingMessage || isBereanStreaming)
                .successSeal(
                    isActive: messageSeal.isVisible,
                    label: "Sent",
                    yOffset: -46
                )
                // Long-press → Send Later (schedule reply) when message text is non-empty
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            guard prefsService.preferences.scheduleReplyEnabled,
                                  editingMessage == nil,
                                  !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            scheduledDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                                showSchedulePicker = true
                            }
                        }
                )
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
        .padding(.vertical, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: messageText)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isInputBarFocused)
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                    inputShimmerX = 220
                }
            }
        }
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
                            .font(.systemScaled(13, weight: .medium))
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
            // System 32: Use backend CF when smartRepliesEnabled, fall back to on-device service
            if AMENFeatureFlags.shared.smartRepliesEnabled,
               let lastIncoming = messages.last(where: { !$0.isFromCurrentUser && !$0.text.isEmpty }) {
                do {
                    let fn = Functions.functions()
                    let contextLines = recentMessages.dropLast().map { msg -> String in
                        let speaker = msg.isFromCurrentUser ? "You" : otherName
                        return "\(speaker): \(String(msg.text.prefix(100)))"
                    }
                    let result = try await fn.httpsCallable("generateSmartReplies").call([
                        "conversationId": conversation.id,
                        "lastMessageText": String(lastIncoming.text.prefix(300)),
                        "context": contextLines,
                    ])
                    let data = result.data as? [String: Any]
                    let replies = data?["replies"] as? [String] ?? []
                    await MainActor.run {
                        smartReplySuggestions = replies.filter { !$0.isEmpty }
                        isLoadingSmartReplies = false
                    }
                    return
                } catch {
                    // Fall through to on-device service on CF failure
                }
            }
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
                    self.remoteTypingNames = typingNames
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

        // Cancel any in-progress voice recording so mic isn't left open
        if isRecording {
            isRecording = false
            voiceViewModel.cancelRecording()
        }

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
        
        // FIX: Use Task.detached so the typing-clear write is NOT tied to the
        // current task scope. A plain `Task { }` is a child task — when the view
        // is dismissed, its scope can be cancelled before the async write
        // completes, leaving the remote participant stuck seeing "Alice is typing…"
        // until the 5-second RTDB TTL fires.
        // Task.detached inherits no actor or cancellation from the caller, so it
        // runs to completion regardless of how quickly the view disappears.
        // `messagingService` is a singleton, so the weak-reference dance is not needed.
        let cid = conversation.id
        Task.detached {
            try? await FirebaseMessagingService.shared.updateTypingStatus(
                conversationId: cid,
                isTyping: false
            )
        }
    }

    private func handleCrisisSendAnyway() {
        showCrisisInterstitial = false
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
    }

    private func handleCrisisClose() {
        showCrisisInterstitial = false
        pendingCrisisMessageText = ""
        pendingCrisisMessageId = ""
        messages.removeAll { $0.id == pendingCrisisMessageId }
        pendingMessages.removeValue(forKey: pendingCrisisMessageId)
    }

    private func handleReplySwipeEnded(_ value: DragGesture.Value, for message: AppMessage) {
        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
        guard value.translation.width > 50 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
            replyingTo = message
            isInputFocused = true
        }
    }

    private var userProfileSheetView: some View {
        ChatUserProfileSheet(
            conversation: conversation,
            resolvedUserId: otherUserId ?? conversation.otherParticipantId
        )
    }

    private var groupInfoSheetView: some View {
        GroupInfoView(conversation: conversation)
    }

    private var documentPickerSheetView: some View {
        DocumentPicker { fileURL, fileName, fileSize in
            handleFileSelected(fileURL: fileURL, fileName: fileName, fileSize: fileSize)
        }
    }

    private var unavailableTranscriptPanel: some View {
        AmenVoiceTranscriptPanel(
            state: .unavailable,
            onClose: { pendingTranscriptMessage = nil },
            onCopy: nil,
            onTranslate: nil
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func handleVoiceRecordingCompletion(_ audioURL: URL, _ duration: TimeInterval) {
        Task { @MainActor in
            isRecording = false
            handleVoiceMessageRecorded(url: audioURL, duration: duration)
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            Task { await setupChatViewAsync() }
        } else if newPhase == .background {
            cleanupChatView()
        }
    }

    private func handleMessageTextChanged(_ newValue: String) {
        handleTypingIndicator(isTyping: !newValue.isEmpty)
        chatLinkController.handleTextChange(newValue)
        resolveMessageAttachmentIfNeeded(for: newValue)
        if !newValue.isEmpty {
            smartReplySuggestions = []
        }
        guard editingMessage == nil else { return }
        if newValue.isEmpty {
            UserDefaults.standard.removeObject(forKey: messageDraftKey)
        } else {
            UserDefaults.standard.set(newValue, forKey: messageDraftKey)
        }
    }

    private func resolveMessageAttachmentIfNeeded(for text: String) {
        messageAttachmentTask?.cancel()
        messageAttachmentTask = Task { @MainActor in
            let urls = smartAttachmentResolver.extractSupportedURLs(from: text)
            guard let url = urls.first else {
                messageSmartAttachment = nil
                messageMentionedLinks = []
                messageAttachmentState = .empty
                return
            }
            messageMentionedLinks = Array(urls.dropFirst())
            if messageSmartAttachment?.canonicalUrl == url.absoluteString { return }
            messageAttachmentState = .resolving
            do {
                let resolved = try await smartAttachmentResolver.resolve(url: url, source: "messagePaste")
                if resolved.safetyStatus == .blocked {
                    messageSmartAttachment = nil
                    messageAttachmentState = .blocked("blocked")
                    return
                }
                messageSmartAttachment = resolved
                messageAttachmentState = .resolved(resolved)
            } catch {
                messageAttachmentState = .failed(.resolveFailed)
            }
        }
    }

    private func openAttachmentURL(_ attachment: AmenSmartAttachment) {
        guard let url = URL(string: attachment.canonicalUrl) else { return }
        UIApplication.shared.open(url)
    }

    private func saveMessageAttachment(_ attachment: AmenSmartAttachment) {
        Task {
            do {
                try await AmenUniversalLinkIntelligenceService.shared.saveUniversalLink(linkId: attachment.id)
                successChips.show("Saved")
            } catch {
                successChips.show("Save failed")
            }
        }
    }

    private func showContextMenu(for message: AppMessage, isFromCurrentUser: Bool, frame: CGRect) {
        var menuActions: [AmenContextMenuAction] = []
        menuActions.append(AmenContextMenuAction(
            kind: .reply, label: "Reply",
            systemImage: "arrowshape.turn.up.left",
            handler: { replyingTo = message; isInputFocused = true }
        ))
        menuActions.append(AmenContextMenuAction(
            kind: .react, label: "React",
            systemImage: "face.smiling",
            handler: {
                selectedMessageForReaction = message
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showReactionPicker = true
                }
            }
        ))
        if message.messageType == .text || message.messageType == .image {
            menuActions.append(AmenContextMenuAction(
                kind: .copy, label: "Copy",
                systemImage: "doc.on.doc",
                handler: { UIPasteboard.general.string = message.text }
            ))
        }
        if isFromCurrentUser,
           message.messageType == .text,
           !message.isDeleted,
           message.timestamp.timeIntervalSinceNow > -900,
           prefsService.preferences.editMessageEnabled {
            menuActions.append(AmenContextMenuAction(
                kind: .edit, label: "Edit",
                systemImage: "pencil",
                handler: { beginEditMode(message: message) }
            ))
        }
        if isFromCurrentUser {
            menuActions.append(AmenContextMenuAction(
                kind: .delete, label: "Delete",
                systemImage: "trash",
                isDestructive: true,
                handler: { deleteMessage(message: message) }
            ))
        }
        if !isFromCurrentUser {
            menuActions.append(AmenContextMenuAction(
                kind: .report, label: "Report",
                systemImage: "exclamationmark.bubble.fill",
                isDestructive: true,
                handler: {
                    messageToReport = message
                    showReportConfirmation = true
                }
            ))
            menuActions.append(AmenContextMenuAction(
                kind: .block, label: "Block",
                systemImage: "person.slash.fill",
                isDestructive: true,
                handler: {
                    userIdToBlock = message.senderId
                    showBlockConfirmation = true
                }
            ))
            menuActions.append(AmenContextMenuAction(
                kind: .mute, label: "Mute",
                systemImage: "speaker.slash.fill",
                handler: { muteSender(userId: message.senderId) }
            ))
        }
        menuActions.append(AmenContextMenuAction(kind: .translate, label: "Translate", systemImage: "globe", isEnabled: false))
        menuActions.append(AmenContextMenuAction(
            kind: .saveToSelah, label: "Save to Selah",
            systemImage: "bookmark",
            handler: {
                pendingSaveMessage = AmenMessageSaveContext(
                    message: message,
                    conversationName: conversation.name,
                    presentedActions: [.saveToSelah]
                )
            }
        ))
        menuActions.append(AmenContextMenuAction(
            kind: .addToChurchNotes, label: "Add to Church Notes",
            systemImage: "note.text",
            handler: {
                pendingSaveMessage = AmenMessageSaveContext(
                    message: message,
                    conversationName: conversation.name,
                    presentedActions: [.addToChurchNotes]
                )
            }
        ))
        menuActions.append(AmenContextMenuAction(kind: .summarize, label: "Summarize", systemImage: "text.badge.checkmark", isEnabled: false))
        menuActions.append(AmenContextMenuAction(
            kind: .remindMe, label: "Remind Me",
            systemImage: "bell",
            handler: {
                pendingSaveMessage = AmenMessageSaveContext(
                    message: message,
                    conversationName: conversation.name,
                    presentedActions: [.remindMe]
                )
            }
        ))
        if let mediaAction = mediaActionsContextMenuAction(for: message) {
            menuActions.append(mediaAction)
        }
        presentMessageContextMenu(anchorFrame: frame, actions: menuActions)
    }

    private func mediaActionsContextMenuAction(for message: AppMessage) -> AmenContextMenuAction? {
        guard message.messageType == .image || message.messageType == .video else { return nil }
        return AmenContextMenuAction(
            kind: .saveToSelah,
            label: "Media Actions",
            systemImage: "photo.badge.ellipsis",
            handler: { activeMediaActionMessage = message }
        )
    }

    private func presentMessageContextMenu(anchorFrame: CGRect, actions: [AmenContextMenuAction]) {
        AmenMessageContextMenuPresenter.shared.present(anchorFrame: anchorFrame, actions: actions)
    }

    private func editAction(for message: AppMessage, isFromCurrentUser: Bool) -> (() -> Void)? {
        guard isFromCurrentUser, prefsService.preferences.editMessageEnabled else { return nil }
        return { beginEditMode(message: message) }
    }

    private func retryAction(for message: AppMessage) -> (() -> Void)? {
        guard message.isSendFailed else { return nil }
        return { retryFailedMessage(messageId: message.id, text: message.text) }
    }

    private func reportAction(for message: AppMessage, isFromCurrentUser: Bool) -> (() -> Void)? {
        guard !isFromCurrentUser else { return nil }
        return {
            messageToReport = message
            showReportConfirmation = true
        }
    }

    private func blockAction(for message: AppMessage, isFromCurrentUser: Bool) -> (() -> Void)? {
        guard !isFromCurrentUser else { return nil }
        return {
            userIdToBlock = message.senderId
            showBlockConfirmation = true
        }
    }

    private func muteAction(for message: AppMessage, isFromCurrentUser: Bool) -> (() -> Void)? {
        guard !isFromCurrentUser else { return nil }
        return { muteSender(userId: message.senderId) }
    }

    private func mediaAction(for message: AppMessage) -> (() -> Void)? {
        guard message.messageType == .image || message.messageType == .video else { return nil }
        return { activeMediaActionMessage = message }
    }

    private func replyAction(for message: AppMessage) -> () -> Void {
        {
            replyingTo = message
            isInputFocused = true
        }
    }

    private func deleteAction(for message: AppMessage) -> () -> Void {
        { deleteMessage(message: message) }
    }

    private func contextMenuRequestAction(for message: AppMessage, isFromCurrentUser: Bool) -> (CGRect) -> Void {
        { frame in
            showContextMenu(for: message, isFromCurrentUser: isFromCurrentUser, frame: frame)
        }
    }

    private func mediaActionOverlayView(for mediaMsg: AppMessage) -> some View {
        AmenMediaActionOverlay(
            message: mediaMsg,
            flags: AMENFeatureFlags.shared,
            onSave: { handleMediaOverlayShare(mediaMsg) },
            onShare: { handleMediaOverlayShare(mediaMsg) },
            onSaveToSelah: saveMediaToSelahAction(for: mediaMsg),
            onAddToNotes: addMediaToNotesAction(for: mediaMsg),
            onDismiss: { activeMediaActionMessage = nil }
        )
    }

    private func messageBubbleView(
        message: AppMessage,
        isFromCurrentUser: Bool,
        isLastInGroup: Bool,
        isLastOutgoing: Bool
    ) -> some View {
        LiquidGlassMessageBubble(
            message: message,
            isFromCurrentUser: isFromCurrentUser,
            isLastInGroup: isLastInGroup,
            showReadReceipt: isLastOutgoing,
            isRetrying: messagingService.retryingMessageIds.contains(message.id),
            onReply: replyAction(for: message),
            onReact: { emoji in
                addReaction(to: message, emoji: emoji)
            },
            onLongPress: longPressAction(for: message),
            onDelete: deleteAction(for: message),
            onEdit: editAction(for: message, isFromCurrentUser: isFromCurrentUser),
            onRetry: retryAction(for: message),
            onReport: reportAction(for: message, isFromCurrentUser: isFromCurrentUser),
            onBlock: blockAction(for: message, isFromCurrentUser: isFromCurrentUser),
            onMute: muteAction(for: message, isFromCurrentUser: isFromCurrentUser),
            contextMenuEnabled: AMENFeatureFlags.shared.messagingLiquidGlassContextMenuEnabled,
            onContextMenuRequest: contextMenuRequestAction(for: message, isFromCurrentUser: isFromCurrentUser),
            onMediaAction: mediaAction(for: message)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    handleReplySwipeEnded(value, for: message)
                }
        )
    }

    private func handleMediaOverlayShare(_ mediaMsg: AppMessage) {
        if let url = mediaMsg.attachments.first?.url {
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.rootViewController?
                .present(av, animated: true)
        }
        activeMediaActionMessage = nil
    }

    private func saveMediaToSelahAction(for mediaMsg: AppMessage) -> (() -> Void)? {
        guard AMENFeatureFlags.shared.selahMediaOSEnabled else { return nil }
        return {
            pendingSaveMessage = AmenMessageSaveContext(
                message: mediaMsg,
                conversationName: conversation.name,
                presentedActions: [.saveToSelah]
            )
            activeMediaActionMessage = nil
        }
    }

    private func addMediaToNotesAction(for mediaMsg: AppMessage) -> (() -> Void) {
        {
            pendingSaveMessage = AmenMessageSaveContext(
                message: mediaMsg,
                conversationName: conversation.name,
                presentedActions: [.addToChurchNotes]
            )
            activeMediaActionMessage = nil
        }
    }

    @ViewBuilder
    private var messageActionClusterOverlay: some View {
        if showMessageActionCluster, let msg = actionClusterMessage {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showMessageActionCluster = false
                        actionClusterMessage = nil
                    }
                VStack {
                    Spacer()
                    MessageActionCluster(
                        message: msg,
                        onAction: { action in handleMessageClusterAction(action, message: msg) },
                        onDismiss: {
                            withAnimation(Motion.adaptive(.spring(response: 0.25))) {
                                showMessageActionCluster = false
                                actionClusterMessage = nil
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var mediaIntelligenceDockOverlay: some View {
        if showMediaIntelligenceDock, let mediaMsg = mediaDockMessage {
            let attachType: AmenMediaAttachmentType = {
                switch mediaMsg.messageType {
                case .video: return .video
                case .link:  return .link
                case .file:  return .file
                default:     return .photo
                }
            }()
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(Motion.adaptive(.spring(response: 0.25))) {
                            showMediaIntelligenceDock = false
                        }
                    }
                VStack {
                    Spacer()
                    MediaIntelligenceDock(
                        messageId: mediaMsg.id,
                        mediaUrl: mediaMsg.mediaURL ?? "",
                        mediaType: attachType,
                        onAction: { _ in },
                        onDismiss: {
                            withAnimation(Motion.adaptive(.spring(response: 0.25))) {
                                showMediaIntelligenceDock = false
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .transition(.opacity)
        }
    }

    private func longPressAction(for message: AppMessage) -> () -> Void {
        {
            if AMENFeatureFlags.shared.messagesSmartContextEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                actionClusterMessage = message
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showMessageActionCluster = true
                }
            } else {
                selectedMessageForReaction = message
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showReactionPicker = true
                }
            }
        }
    }

    private struct MessageRowContext {
        let currentUID: String?
        let isFromCurrentUser: Bool
        let isLastInGroup: Bool
        let isLastOutgoing: Bool
        let showDateHeader: Bool
    }

    private func messageRowContext(for message: AppMessage, at index: Int) -> MessageRowContext {
        let currentUID = Auth.auth().currentUser?.uid
        let isFromCurrentUser = message.senderId == currentUID
        let nextMessage: AppMessage? = index + 1 < messages.count ? messages[index + 1] : nil
        let isLastInGroup = nextMessage?.senderId != message.senderId
        let isLastOutgoing = isFromCurrentUser && (nextMessage == nil || nextMessage?.senderId != currentUID)
        let prevMessage: AppMessage? = index > 0 ? messages[index - 1] : nil
        let showDateHeader = prevMessage.map { !Calendar.current.isDate($0.timestamp, inSameDayAs: message.timestamp) } ?? true
        return MessageRowContext(
            currentUID: currentUID,
            isFromCurrentUser: isFromCurrentUser,
            isLastInGroup: isLastInGroup,
            isLastOutgoing: isLastOutgoing,
            showDateHeader: showDateHeader
        )
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

                // Remove any optimistic (pending) message whose ID now appears in the
                // Firestore snapshot — the server-confirmed version wins in the merge below.
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
    
    // MARK: - Edit Message

    private func beginEditMode(message: AppMessage) {
        draftBeforeEdit = messageText   // preserve any in-progress draft
        editingMessage = message
        editingOriginalText = message.text
        messageText = message.text
        isInputFocused = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cancelEditMode() {
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
            editingMessage = nil
            editingOriginalText = ""
            messageText = draftBeforeEdit   // restore draft that was interrupted by edit mode
            draftBeforeEdit = ""
            isInputFocused = false
        }
    }

    private func saveEdit() {
        guard let msg = editingMessage,
              !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              messageText != editingOriginalText else {
            cancelEditMode()
            return
        }
        let newText = messageText
        // Optimistic local update: update text immediately so the user
        // sees the new content before the Firestore snapshot arrives.
        if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
            messages[idx].text = newText
            messages[idx].editedAt = Date()
        }
        cancelEditMode()
        Task {
            do {
                try await messagingService.editMessage(
                    conversationId: conversation.id,
                    messageId: msg.id,
                    newText: newText
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                dlog("❌ Edit message failed: \(error)")
                toastManager.showError("Could not save edit")
                // Roll back optimistic update
                if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                    messages[idx].editedAt = nil
                }
            }
        }
    }

    // MARK: - Schedule Reply

    private func scheduleReply(at date: Date) {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let replyId = replyingTo?.id
        let replyText = replyingTo?.text
        let replyAuthor = replyingTo?.senderName
        messageText = ""
        replyingTo = nil
        Task {
            do {
                try await scheduledMessagesService.scheduleMessage(
                    conversationId: conversation.id,
                    text: text,
                    scheduledAt: date,
                    replyToMessageId: replyId,
                    replyToText: replyText,
                    replyToAuthorName: replyAuthor
                )
                await MainActor.run {
                    toastManager.showSuccess("Scheduled")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                dlog("❌ Schedule reply failed: \(error)")
                toastManager.showError("Could not schedule message")
            }
        }
    }

    // Phase 4B: Build pill context from current message state — extracted to avoid type-checker timeout.
    private func updateSmartPillContext(for newMessages: [AppMessage]) {
        guard AMENFeatureFlags.shared.messagingSmartPillsEnabled else { return }
        let sel = selectedMessage
        let unread = newMessages.filter { !$0.isRead && !$0.isFromCurrentUser }.count
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        let firstAttach = sel?.attachments.first
        let isVoice = firstAttach?.type == .audio
        let isMedia = firstAttach.map { $0.type == .photo || $0.type == .video } ?? false
        let isLong = (sel?.text.count ?? 0) > AmenSmartPillPriorityEngine.longMessageCharThreshold
        let context = AmenSmartPillEligibilityContext(
            conversationId: conversation.id,
            messageCount: newMessages.count,
            unreadCount: unread,
            lastMessage: newMessages.last,
            selectedMessage: sel,
            userLanguageCode: langCode,
            isGroupConversation: conversation.isGroup,
            detectedLanguage: nil, // AppMessage does not expose detectedLanguage
            hasVoiceMessage: isVoice,
            hasMediaMessage: isMedia,
            hasLongText: isLong,
            safetySignalPresent: false,
            transcriptAvailable: false,
            isNetworkAvailable: true
        )
        intelligenceCoordinator.update(context: context)
    }

    // Phase 7: Pre-send safety evaluation. Calls sendMessage() only after passing all layers.
    private func performSendWithSafetyCheck() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let senderUID = Auth.auth().currentUser?.uid ?? ""
        let recipientUID = otherUserId ?? ""

        let decision = await intelligenceCoordinator.evaluatePreSend(
            text: text,
            senderUID: senderUID,
            recipientUID: recipientUID,
            conversationId: conversation.id
        )

        switch decision {
        case .allow, .flagged:
            sendMessage()
        case .softWarn, .requireEdit:
            intelligenceCoordinator.presentSafetyNudge(decision: decision, messageText: text)
        case .block(let reason):
            dlog("[Safety] Message blocked: \(reason)")
            errorMessage = "This message can't be sent."
            showErrorAlert = true
        }
    }

    // NB-5: Safety check for message edits — mirrors performSendWithSafetyCheck.
    // When messagingSafetyNudgesEnabled is false, falls through to saveEdit() immediately.
    // The shared nudge UI is reused; safetyNudgeIsForEdit routes "Send Anyway"→saveEdit().
    private func performEditWithSafetyCheck() async {
        guard AMENFeatureFlags.shared.messagingSafetyNudgesEnabled else {
            saveEdit()
            return
        }
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != editingOriginalText else {
            cancelEditMode()
            return
        }
        let senderUID = Auth.auth().currentUser?.uid ?? ""
        let recipientUID = otherUserId ?? ""
        let decision = await intelligenceCoordinator.evaluatePreSend(
            text: text,
            senderUID: senderUID,
            recipientUID: recipientUID,
            conversationId: conversation.id
        )
        switch decision {
        case .allow, .flagged:
            saveEdit()
        case .softWarn, .requireEdit:
            safetyNudgeIsForEdit = true
            intelligenceCoordinator.presentSafetyNudge(decision: decision, messageText: text)
        case .block(let reason):
            dlog("[Safety] Edit blocked: \(reason)")
            errorMessage = "This edit can't be saved."
            showErrorAlert = true
        }
    }

    private func scrollToMessage(_ messageId: String) {
        guard messages.contains(where: { $0.id == messageId }) else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            chatScrollProxy?.scrollTo(messageId, anchor: .center)
        }
    }

    // System 32: Route smart context bar chip taps.
    private func handleSmartContextChip(_ chip: SmartContextChip) {
        switch chip {
        case .summary:
            showThreadSummaryPanel = true
        case .decisions:
            break // extractSmartContext not yet implemented on coordinator
        case .questions:
            break // extractSmartContext not yet implemented on coordinator
        case .actions:
            break // extractSmartContext not yet implemented on coordinator
        case .media:
            if let mediaMsg = messages.last(where: { $0.messageType == .image || $0.messageType == .video }) {
                mediaDockMessage = mediaMsg
                withAnimation(Motion.adaptive(.spring(response: 0.3))) {
                    showMediaIntelligenceDock = true
                }
            }
        case .catchUp:
            intelligenceCoordinator.requestCatchUp(conversationId: conversation.id, messages: messages)
        }
    }

    // System 32: Handle MessageActionCluster actions.
    private func handleMessageClusterAction(_ action: MessageClusterAction, message: AppMessage) {
        switch action {
        case .react:
            selectedMessageForReaction = message
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                showReactionPicker = true
            }
        case .reply:
            replyingTo = message
            isInputFocused = true
        case .copy:
            UIPasteboard.general.string = message.text
            toastManager.showSuccess("Copied")
        case .pin:
            Task { try? await FirebaseMessagingService.shared.pinMessage(conversationId: conversation.id, messageId: message.id) }
        case .save:
            pendingSaveMessage = AmenMessageSaveContext(
                message: message,
                conversationName: conversation.name,
                presentedActions: [.saveToSelah, .addToChurchNotes, .saveToNotes, .remindMe]
            )
        case .summarize:
            showThreadSummaryPanel = true
        case .createTask:
            break // extractSmartContext not yet implemented on coordinator
        case .markDecision:
            break // extractSmartContext not yet implemented on coordinator
        case .remindMe:
            pendingSaveMessage = AmenMessageSaveContext(
                message: message,
                conversationName: conversation.name,
                presentedActions: [.remindMe]
            )
        case .forward:
            Task {
                guard !message.text.isEmpty else { return }
                await MainActor.run {
                    let activity = UIActivityViewController(activityItems: [message.text], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(activity, animated: true)
                    }
                }
            }
        case .report:
            messageToReport = message
        }
    }

    // Phase 4A: Route smart pill taps to the appropriate action.
    private func handleSmartPillTap(_ type: AmenSmartPillType) {
        AmenMessagingAnalytics.track(.smartPillTapped, parameters: ["pill": type.rawValue])
        switch type {
        case .translate:
            if let msg = messages.last(where: { !$0.isFromCurrentUser }) {
                intelligenceCoordinator.requestTranslation(for: msg)
            }
        case .catchMeUp:
            intelligenceCoordinator.requestCatchUp(
                conversationId: conversation.id,
                messages: messages
            )
        case .saveToSelah, .addToChurchNotes, .saveToNotes, .remindMe:
            if let msg = selectedMessage ?? messages.last {
                pendingSaveMessage = AmenMessageSaveContext(
                    message: msg,
                    conversationName: conversation.name,
                    presentedActions: [.saveToSelah, .addToChurchNotes, .saveToNotes, .remindMe]
                )
            }
        case .voiceTranscript:
            // CF-2: open transcript panel in honest unavailable state; no silent no-op
            AmenMessagingAnalytics.track(.voiceTranscriptUnavailable)
            pendingTranscriptMessage = selectedMessage
                ?? messages.last(where: { !$0.isFromCurrentUser })
                ?? messages.last
        case .mediaActions:
            AmenMessagingAnalytics.track(.mediaActionsShown)
            activeMediaActionMessage = selectedMessage
                ?? messages.last(where: { $0.messageType == .image || $0.messageType == .video })
        case .extractActions:
            // CF-2: no action extraction backend exists yet — show honest info toast
            AmenMessagingAnalytics.track(.extractActionsTapped)
            toastManager.showInfo("Action extraction isn't available yet.")
        default:
            break
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
            // Show a one-time AI processing disclosure for privacy compliance.
            // Key is per-conversation so repeat users in the same chat are not re-prompted.
            let disclosureKey = "berean_dm_ai_disclosed_\(conversation.id)"
            if !UserDefaults.standard.bool(forKey: disclosureKey) {
                messageText = ""
                isInputFocused = false
                pendingBereanText = userText
                showBereanDMDisclosure = true
                return
            }
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

        // Feature 2: Capture reply context before clearing state
        let capturedReplyingTo = replyingTo
        let replyMessageId = capturedReplyingTo?.id
        let replyText = capturedReplyingTo?.text
        let replyAuthorName = capturedReplyingTo?.senderName

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
            isSendFailed: false,
            replyToMessageId: replyMessageId,
            replyToText: replyText,
            replyToAuthorName: replyAuthorName
        )
        pendingMessages[messageId] = optimisticMessage
        // Append only if not already present (belt-and-suspenders)
        if !messages.contains(where: { $0.id == messageId }) {
            messages.append(optimisticMessage)
        }

        // Clear input immediately for snappy UX
        messageText = ""
        chatLinkController.reset()
        // Feature 2: Clear reply state after composing
        replyingTo = nil
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

        // Haptic feedback + success seal (optimistic — matches the optimistic message append)
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        messageSeal.trigger()
        sendSweepTrigger.toggle()
        successChips.show("Sent")

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

                // Feature 2: Write reply metadata directly to the message document after base send
                try await messagingService.sendMessage(
                    conversationId: conversationId,
                    text: textToSend,
                    replyToMessageId: replyMessageId,
                    clientMessageId: messageId
                )

                // Feature 2: Increment replyCount on the parent message (fire-and-forget)
                if let parentId = replyMessageId {
                    Task.detached(priority: .background) {
                        try? await Firestore.firestore()
                            .collection("conversations").document(conversationId)
                            .collection("messages").document(parentId)
                            .updateData(["replyCount": FieldValue.increment(Int64(1))])
                    }
                }

                dlog("✅ Message sent successfully!")
                
                // Success haptic
                await MainActor.run {
                    let successHaptic = UINotificationFeedbackGenerator()
                    successHaptic.notificationOccurred(.success)

                    // Chat memory: extract from recent messages
                    let recentMessages = messages.suffix(5).map { msg in
                        ExtractableMessage(
                            id: msg.id,
                            text: msg.text,
                            senderId: msg.senderId,
                            timestamp: msg.timestamp
                        )
                    }
                    chatExtractionEngine.analyzeMessages(
                        Array(recentMessages),
                        chatId: conversation.id
                    )
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

                    let errorMsg = (error as? FirebaseMessagingError)?.localizedDescription ?? "Failed to send message"

                    // Only auto-retry for transient/network errors — not permission or auth failures
                    if FirebaseMessagingService.isNonRetryableError(error) {
                        // Non-retryable: show error immediately, no auto-retry
                        messagingService.failedMessages[messageId] = (
                            text: textToSend,
                            error: (error as? FirebaseMessagingError) ?? .networkError(error)
                        )
                        toastManager.showError(errorMsg)
                    } else if !networkMonitor.isConnected {
                        // Network down: schedule retry, show offline toast
                        messagingService.scheduleRetry(
                            for: messageId,
                            conversationId: conversation.id,
                            text: textToSend,
                            attempt: 0
                        )
                        toastManager.showWarning("No internet connection. Retrying when back online…")
                    } else {
                        // Transient error: schedule retry with manual fallback
                        messagingService.scheduleRetry(
                            for: messageId,
                            conversationId: conversation.id,
                            text: textToSend,
                            attempt: 0
                        )
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
            lazy var db = Firestore.firestore()
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

    // MARK: - Feature 1: AMEN Reaction Toggle

    private func toggleAmenReaction(messageId: String, reaction: String) {
        Task {
            do {
                try await messagingService.toggleAmenReaction(
                    conversationId: conversation.id,
                    messageId: messageId,
                    reaction: reaction
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                dlog("❌ Error toggling AMEN reaction: \(error)")
                await MainActor.run { toastManager.showError("Could not update reaction") }
            }
        }
    }

    // MARK: - Feature 3: Poll

    private func sendPoll(_ poll: PollMessage) {
        Task {
            do {
                try await messagingService.sendPollMessage(conversationId: conversation.id, poll: poll)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } catch {
                dlog("❌ Error sending poll: \(error)")
                await MainActor.run { toastManager.showError("Failed to send poll") }
            }
        }
    }

    private func togglePollVote(messageId: String, optionId: String, allowMultiple: Bool) {
        Task {
            do {
                try await messagingService.voteOnPoll(
                    conversationId: conversation.id,
                    messageId: messageId,
                    optionId: optionId,
                    allowMultiple: allowMultiple
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                dlog("❌ Error voting on poll: \(error)")
                await MainActor.run { toastManager.showError("Could not record vote") }
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
                lazy var db = Firestore.firestore()
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

    private func handleVoiceMessageRecorded(url: URL, duration: TimeInterval) {
        let msgId = UUID().uuidString
        let msg = AppMessage(
            id: msgId,
            text: "",
            isFromCurrentUser: true,
            timestamp: Date(),
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: messagingService.currentUserName,
            isSent: false,
            isDelivered: false,
            isSendFailed: false,
            messageType: .file,
            mediaURL: url.absoluteString,
            mediaDuration: duration,
            mediaFileName: "Voice Message",
            mediaFileExtension: ".m4a"
        )
        appendAttachmentMessage(msg)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    text: "[Voice Message] \(url.absoluteString)",
                    clientMessageId: msgId
                )
            } catch {
                dlog("❌ Voice message send failed: \(error)")
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                        messages[idx].isSendFailed = true
                    }
                    toastManager.showError("Voice message failed to send")
                }
            }
        }
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

private struct PrimaryChatSheetsModifier: ViewModifier {
    @Binding var showUserProfile: Bool
    @Binding var showGroupInfo: Bool
    @Binding var showCrisisInterstitial: Bool
    let userProfileSheetView: () -> AnyView
    let groupInfoSheetView: () -> AnyView
    let onCrisisSendAnyway: () -> Void
    let onCrisisClose: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showUserProfile) {
                userProfileSheetView()
            }
            .sheet(isPresented: $showGroupInfo) {
                groupInfoSheetView()
            }
            .sheet(isPresented: $showCrisisInterstitial) {
                SelfHarmCrisisInterstitial(
                    onSendAnyway: onCrisisSendAnyway,
                    onClose: onCrisisClose
                )
                .presentationDetents([.medium, .large])
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
                        .font(.systemScaled(15, weight: .medium))
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
                                    .font(.systemScaled(16, weight: .semibold))
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
                                    .font(.systemScaled(16, weight: .semibold))
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
                                    .font(.systemScaled(32, weight: .bold))
                                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                                
                                Text("@\(userProfile.username)")
                                    .font(.systemScaled(16, weight: .medium))
                                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            }
                            
                            // Bio (if available)
                            if !userProfile.bio.isEmpty {
                                Text(userProfile.bio)
                                    .font(.systemScaled(15, weight: .regular))
                                    .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .padding(.horizontal, 32)
                            }
                            
                            // Member since date
                            Text("Member since \(formattedJoinDate(userProfile.createdAt))")
                                .font(.systemScaled(14, weight: .regular))
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
                                    .font(.systemScaled(12, weight: .medium))
                                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                
                                Text("Avg. response: \(averageResponseTime)")
                                    .font(.systemScaled(13, weight: .medium))
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
                                            .font(.systemScaled(17, weight: .semibold))
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
                                        .font(.systemScaled(17, weight: .semibold))
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
                                            .font(.systemScaled(20, weight: .semibold))
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
                        .font(.systemScaled(48))
                        .foregroundColor(Color(red: 0.8, green: 0.3, blue: 0.3))
                    
                    Text("Unable to load profile")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.systemScaled(14, weight: .regular))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Button {
                        loadUserProfile()
                    } label: {
                        Text("Try Again")
                            .font(.systemScaled(15, weight: .semibold))
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
                .font(.systemScaled(40, weight: .bold))
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
            lazy var db = Firestore.firestore()
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
            .font(.systemScaled(14, weight: .medium))
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
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                
                Text(value)
                    .font(.systemScaled(20, weight: .bold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
            
            Text(label)
                .font(.systemScaled(13, weight: .medium))
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
    var onEdit: (() -> Void)? = nil          // Edit Message
    var onRetry: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onMute: (() -> Void)? = nil
    var contextMenuEnabled: Bool = false
    var onContextMenuRequest: ((CGRect) -> Void)? = nil
    var onMediaAction: (() -> Void)? = nil   // Phase 11: media overlay trigger

    // Inline double-tap reaction bar state
    @State private var showInlineReactions = false
    @State private var capturedBubbleFrame: CGRect = .zero

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

    // Spring entrance animation
    @State private var isVisible = false

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
                        .font(.systemScaled(24))
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
                    if !isFromCurrentUser, isLastInGroup {
                        Text(message.senderName ?? "Deleted User")
                            .font(.systemScaled(11, weight: .medium))
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
                                        .font(.systemScaled(11))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button { onRetry?() } label: {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.systemScaled(18))
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
                                VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                                    SmartMessageText(
                                        text: message.text,
                                        context: .local(messageId: message.id, surface: "unified_chat"),
                                        foregroundColor: isFromCurrentUser ? .white : Color(.label)
                                    )
                                    .font(.systemScaled(16))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(bubbleBackground)
                                    .frame(maxWidth: 280, alignment: isFromCurrentUser ? .trailing : .leading)
                                    // "Edited" indicator — subtle, below bubble
                                    if message.editedAt != nil {
                                        Text("Edited")
                                            .font(.systemScaled(10, weight: .regular))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                    }
                                }
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
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.65))) {
                                showInlineReactions.toggle()
                            }
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { capturedBubbleFrame = geo.frame(in: .global) }
                            }
                        )
                        .contextMenu {
                            if !contextMenuEnabled {
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
                                if (message.messageType == .image || message.messageType == .video),
                                   let onMediaAction {
                                    Button { onMediaAction() } label: {
                                        Label("Media Actions", systemImage: "photo.badge.ellipsis")
                                    }
                                }
                                // Edit Message — outgoing text only, within 15-minute window
                                if isFromCurrentUser,
                                   message.messageType == .text,
                                   !message.isDeleted,
                                   let onEdit,
                                   message.timestamp.timeIntervalSinceNow > -900 {
                                    Button { onEdit() } label: {
                                        Label("Edit", systemImage: "pencil")
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
                        .onLongPressGesture(minimumDuration: 0.4) {
                            guard contextMenuEnabled else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onContextMenuRequest?(capturedBubbleFrame)
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
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                            swipeOffset = 0
                        }
                        didTriggerReplyHaptic = false
                    }
            )
            } // ZStack
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.88, anchor: .bottom)
        .offset(y: isVisible ? 0 : 4)
        .onAppear {
            let delay: Double = isFromCurrentUser ? 0 : 0.05
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 16).delay(delay)) {
                isVisible = true
            }
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
                        .font(.systemScaled(26))
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
            switch message.deliveryStatus {
            case .failed:
                EmptyView()
            case .sending:
                Image(systemName: "clock")
                    .font(.systemScaled(10))
                    .foregroundStyle(.secondary)
            case .read:
                HStack(spacing: 1) {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(9, weight: .semibold))
                    Image(systemName: "checkmark")
                        .font(.systemScaled(9, weight: .semibold))
                }
                .foregroundStyle(sentColor)
            case .delivered:
                HStack(spacing: 1) {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(9, weight: .semibold))
                    Image(systemName: "checkmark")
                        .font(.systemScaled(9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            case .sent:
                Image(systemName: "checkmark")
                    .font(.systemScaled(9, weight: .semibold))
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
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(isFromCurrentUser ? .white.opacity(0.85) : Color.accentColor)
                        .lineLimit(1)
                }
                Text(replyMessage.text)
                    .font(.systemScaled(12))
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
                Text(String((message.senderName ?? "Deleted User").prefix(1)).uppercased())
                    .font(.systemScaled(12, weight: .semibold))
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
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(comingSoon ? Color.gray.opacity(0.5) : color)
                        .frame(width: 52, height: 52)
                    
                    if comingSoon {
                        Text("Soon")
                            .font(.systemScaled(8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.6))
                            .clipShape(Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
                
                Text(title)
                    .font(.systemScaled(12, weight: .medium))
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
                    .font(.systemScaled(19, weight: .semibold))
                    .foregroundStyle(item.iconColor)
            }
            Text(item.label)
                .font(.systemScaled(11, weight: .medium))
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
                withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.7))) {
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
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isExpanded)
                    }

                    Text("Quick replies")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.systemScaled(12, weight: .medium))
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
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) {
                slidingOutId = reply.id
            }

            onChipTapped(reply.text)

            // Restore after 1.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                    slidingOutId = nil
                    dismissedChipIds.insert(reply.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(reply.emoji)
                    .font(.systemScaled(16))
                Text(reply.text)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.systemScaled(12, weight: .medium))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .font(.systemScaled(10, weight: .bold))
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
                                reduceMotion ? nil : .easeInOut(duration: 0.55)
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
                    .font(.systemScaled(10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.75, green: 0.60, blue: 0.20))

                Text(text)
                    .font(.systemScaled(15, weight: .regular))
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
            .frame(maxWidth: 320, alignment: .leading)

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
            let streamingRequest = BereanChatProxyRequest(
                message: prompt,
                systemPromptSuffix: systemPrompt,
                maxTokens: 600
            )
            let result = try await functions.httpsCallable("bereanChatProxy").call(streamingRequest)

            guard let data = result.data as? [String: Any],
                  let text = (data["response"] as? String) ?? (data["text"] as? String) else {
                dlog("❌ BereanStreamingService: unexpected proxy response")
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
            dlog("ℹ️ BereanStreamingService: task cancelled")
            return "__error__: cancelled"
        } catch {
            dlog("❌ BereanStreamingService: \(error)")
            return "__error__: \(error.localizedDescription)"
        }
    }
}

// MARK: - Feature 1: AMEN Reaction Tray

private struct AmenReactionTray: View {
    let reactions = ["🙏 Pray", "🙌 Amen", "💙 Encouraged", "👁 Seen", "🤔 Thinking"]
    let onSelect: (String) -> Void
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(reactions.enumerated()), id: \.element) { index, reaction in
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onSelect(reaction)
                } label: {
                    Text(reaction)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .background(Color.white.opacity(0.7))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.07), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.7)
                .offset(y: isVisible ? 0 : 6)
                .animation(.interpolatingSpring(stiffness: 220, damping: 18).delay(Double(index) * 0.04), value: isVisible)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
        .onAppear { isVisible = true }
    }
}

// MARK: - Feature 1: Reaction Capsules Row

private struct ReactionCapsulesRow: View {
    let reactions: [String: [String]]
    let currentUserId: String
    let onToggle: (String) -> Void

    var body: some View {
        if reactions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 5) {
                ForEach(reactions.sorted(by: { $0.value.count > $1.value.count }), id: \.key) { key, uids in
                    let isSelected = uids.contains(currentUserId)
                    Button { onToggle(key) } label: {
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.systemScaled(11, weight: .medium))
                            if uids.count > 1 {
                                Text("\(uids.count)")
                                    .font(.systemScaled(11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.75))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.black.opacity(0.75) : Color.white.opacity(0.65))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Feature 2: Reply Preview Strip (shown in composer when replying)

struct ReplyPreviewStrip: View {
    let replyToText: String
    let replyToAuthor: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.25))
                .frame(width: 3)
                .frame(maxHeight: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(replyToAuthor)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.65))
                Text(replyToText)
                    .font(.systemScaled(12))
                    .foregroundStyle(.black.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 0.5))
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

// MARK: - Feature 2: Inline Reply Quote (shown inside bubble area above the bubble)

struct InlineReplyQuote: View {
    let text: String
    let authorName: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.3))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(authorName)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.55))
                Text(text)
                    .font(.systemScaled(12))
                    .foregroundStyle(.black.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Feature 3: Glass Poll Card

struct GlassPollCard: View {
    let poll: PollMessage
    let currentUserId: String
    let onVote: (String) -> Void

    private var totalVotes: Int {
        poll.options.reduce(0) { $0 + $1.votes.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                Text(poll.question)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.88))
            }

            VStack(spacing: 8) {
                ForEach(poll.options) { option in
                    PollOptionRow(
                        option: option,
                        totalVotes: totalVotes,
                        isSelected: option.votes.contains(currentUserId),
                        onTap: { onVote(option.id) }
                    )
                }
            }

            if totalVotes > 0 {
                Text("\(totalVotes) vote\(totalVotes == 1 ? "" : "s")")
                    .font(.systemScaled(11))
                    .foregroundStyle(.black.opacity(0.35))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black.opacity(0.07), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct PollOptionRow: View {
    let option: PollMessage.PollOption
    let totalVotes: Int
    let isSelected: Bool
    let onTap: () -> Void
    @State private var animatedProgress: CGFloat = 0

    private var voteRatio: CGFloat {
        guard totalVotes > 0 else { return 0 }
        return CGFloat(option.votes.count) / CGFloat(totalVotes)
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .frame(height: 44)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.black.opacity(0.08) : Color.black.opacity(0.04))
                        .frame(width: geo.size.width * animatedProgress, height: 44)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: animatedProgress)
                }
                .frame(height: 44)

                HStack {
                    HStack(spacing: 6) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                        Text(option.text)
                            .font(.systemScaled(14, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .padding(.leading, 12)

                    Spacer()

                    if totalVotes > 0 {
                        Text("\(Int(voteRatio * 100))%")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.black.opacity(0.4))
                            .padding(.trailing, 12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                isSelected ? Color.black.opacity(0.12) : Color.black.opacity(0.05),
                lineWidth: isSelected ? 1 : 0.5
            ))
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.75)).delay(0.1)) {
                animatedProgress = voteRatio
            }
        }
        .onChange(of: option.votes.count) { _, _ in
            withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.75))) {
                animatedProgress = voteRatio
            }
        }
    }
}

// MARK: - Feature 3: Create Poll Sheet

struct CreatePollSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (PollMessage) -> Void

    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @State private var allowMultiple = false

    private var canCreate: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 2
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.97).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        questionSection
                        optionsSection
                        allowMultipleSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Create Poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(.black.opacity(0.6))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let uid = FirebaseMessagingService.shared.currentUserId
                        let pollOptions = options
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .map { PollMessage.PollOption(text: $0) }
                        let poll = PollMessage(
                            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                            options: pollOptions,
                            allowMultiple: allowMultiple,
                            createdBy: uid
                        )
                        onCreate(poll)
                        isPresented = false
                    }
                    .disabled(!canCreate)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(canCreate ? .black : .black.opacity(0.25))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.5))
                .padding(.horizontal, 4)
            TextField("Ask something...", text: $question, axis: .vertical)
                .font(.systemScaled(16))
                .lineLimit(1...3)
                .padding(14)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 0.5))
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.5))
                .padding(.horizontal, 4)

            ForEach(Array(options.indices), id: \.self) { idx in
                HStack(spacing: 10) {
                    TextField("Option \(idx + 1)", text: $options[idx])
                        .font(.systemScaled(15))
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .background(Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 0.5))

                    if options.count > 2 {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                let removeIndex: Int = idx
                                options.remove(at: removeIndex)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.systemScaled(20))
                                .foregroundStyle(.black.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if options.count < 6 {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                        options.append("")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.systemScaled(15, weight: .medium))
                        Text("Add option")
                            .font(.systemScaled(14, weight: .medium))
                    }
                    .foregroundStyle(.black.opacity(0.45))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allowMultipleSection: some View {
        Toggle(isOn: $allowMultiple) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow multiple choices")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.75))
                Text("People can vote on more than one option")
                    .font(.systemScaled(12))
                    .foregroundStyle(.black.opacity(0.4))
            }
        }
        .tint(.black)
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

// MARK: - Schedule Reply Picker Sheet

struct ScheduleReplyPickerSheet: View {
    let text: String
    @Binding var selectedDate: Date
    let onConfirm: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    // Quick-select presets
    private var presets: [(label: String, date: Date)] {
        let now = Date()
        let cal = Calendar.current
        return [
            ("In 1 hour",    cal.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)),
            ("In 3 hours",   cal.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(10800)),
            ("Tomorrow 9 AM", {
                var c = cal.dateComponents([.year, .month, .day], from: now)
                c.day = (c.day ?? 1) + 1
                c.hour = 9; c.minute = 0
                return cal.date(from: c) ?? now.addingTimeInterval(86400)
            }()),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Message preview
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Message")
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(text)
                                .font(.systemScaled(15))
                                .foregroundStyle(.primary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.ultraThinMaterial)
                                )
                        }
                        .padding(.horizontal, 20)

                        // Quick presets
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Schedule")
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 20)
                            VStack(spacing: 0) {
                                ForEach(presets, id: \.label) { preset in
                                    Button {
                                        selectedDate = preset.date
                                    } label: {
                                        HStack {
                                            Text(preset.label)
                                                .font(.systemScaled(15))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            if Calendar.current.isDate(selectedDate, equalTo: preset.date, toGranularity: .minute) {
                                                Image(systemName: "checkmark")
                                                    .font(.systemScaled(12, weight: .semibold))
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if preset.label != presets.last?.label {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal, 20)
                        }

                        // Custom date picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Custom Time")
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 20)
                            DatePicker(
                                "",
                                selection: $selectedDate,
                                in: Date().addingTimeInterval(60)...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal, 20)
                        }

                        // Confirm button
                        Button {
                            dismiss()
                            onConfirm(selectedDate)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .font(.systemScaled(14, weight: .semibold))
                                Text("Schedule for \(selectedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.systemScaled(15, weight: .semibold))
                            }
                            .foregroundStyle(AmenTheme.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(AmenTheme.Colors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Send Later")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
