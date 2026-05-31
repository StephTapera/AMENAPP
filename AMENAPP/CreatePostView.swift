//
//  CreatePostView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

/// A comprehensive view for creating and publishing posts to the AMEN community
/// 
/// Features:
/// - Multi-category post creation (#OPENTABLE, Testimonies, Prayer)
/// - Rich text editing with hashtag suggestions
/// - Image attachment (up to 4 images)
/// - Link preview support
/// - Post scheduling
/// - Draft management
/// - Real-time character count validation
/// - Accessibility support
///
/// - Note: This view handles all aspects of post creation including validation,
///   media uploads, and scheduling. Posts can be published immediately or scheduled
///   for future publication.
struct CreatePostView: View {
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var postsManager: PostsManager = .shared
    @ObservedObject private var draftsManager: DraftsManager = .shared
    @ObservedObject private var userService: UserService = .shared
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @AppStorage("currentUserProfileImageURL") private var cachedProfileImageURL: String = ""
    @State private var postText = ""
    @State private var selectedCategory: PostCategory = .openTable
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []
    @State private var showingImagePicker = false
    @State private var showingLinkSheet = false
    @State private var linkURL = ""
    @State private var allowComments = true
    @State private var commentPermission: CommentPermissionLevel = .everyone  // ✅ Comment permission level
    @State private var showCommentControls = false  // ✅ Show comment controls sheet
    @State private var showingSuggestions = false
    @State private var hashtagSuggestions: [String] = []
    @State private var showingDraftSavedNotice = false
    @State private var selectedTopicTag = ""
    @State private var showingTopicTagSheet = false
    @State private var showingScheduleSheet = false
    @State private var isPublishing = false
    @State private var postBtnState: PostButtonMorphState = .idle
    @State private var uploadState: UploadVisualState = .idle
    @State private var showDraftsSheet = false
    @State private var showGuidelinesGate = false
    @State private var scheduledDate: Date?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var errorTitle = "Error"
    @State private var showingSuccessNotice = false
    /// P1-7: Persistent inline failure banner — stays visible after the toast dismisses
    /// so the user knows their last publish attempt failed before they try again.
    @State private var publishFailureBannerMessage: String?
    @State private var showCancelConfirmation = false
    @State private var shouldPersistDraftOnExit = true

    // P1-6 FIX: Better error recovery
    @State private var isRetryableError = false
    @State private var retryAction: (() -> Void)?
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var categoryNamespace
    
    // MARK: - New Features State
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var mentionSearchTask: Task<Void, Never>?
    @StateObject private var linkController = ComposerLinkPreviewController()
    @ObservedObject private var smartAttachmentResolver = AmenSmartAttachmentResolverService.shared // PERF: singleton → @ObservedObject
    @State private var smartAttachmentState: AmenAttachmentComposerState = .empty
    @State private var smartAttachment: AmenSmartAttachment?
    @State private var mentionedLinkURLs: [URL] = []
    @State private var smartAttachmentResolutionTask: Task<Void, Never>?
    @State private var useSmartAttachmentAsSoundtrack = false
    @State private var showingMediaAttachmentPicker = false
    @State private var selectedMusicAttachment: AmenMediaAttachment?
    @State private var showMusicAttachmentPicker = false
    @ObservedObject private var insightEngine = ComposerInsightEngine.shared // PERF: singleton → @ObservedObject
    @State private var showMentionSuggestions = false
    @State private var mentionSuggestions: [AlgoliaUser] = []
    @State private var currentMentionQuery = ""
    @State private var showDraftRecovery = false
    @State private var recoveredDraft: Draft?
    @State private var uploadProgress: Double = 0.0
    @State private var isUploadingImages = false
    @State private var activePublishTask: Task<Void, Never>?
    @State private var pendingUploadCleanupPaths: Set<String> = []
    @State private var uploadCapsuleState: UploadCapsuleState?
    @State private var uploadCapsuleProgress: Double = 0.0
    @State private var isUploadCapsuleExpanded = false
    @State private var uploadCapsuleMediaStatuses: [String: UploadCapsuleMediaStatus] = [:]
    @State private var uploadCapsuleClientRequestId: String?
    @State private var uploadCapsuleIdempotencyKey: String?
    @State private var pendingPublishPostID: String?
    /// Idempotency key scoped to the current publish attempt; cleared on success/failure.
    /// Prevents duplicate Firestore documents if the user double-taps submit or if the
    /// app retries after a transient network failure.
    @State private var postIdempotencyKey: String? = nil
    @StateObject private var cameraCoordinator = CreatePostCameraCoordinator()
    @State private var mediaMetadataDraft = CreatePostMediaMetadataDraft()
    @State private var showMediaMetadataAuthoring = false
    @State private var showAmenAudioComposer = false
    @State private var selectedMediaIndex: Int = 0
    @State private var showPerMediaCaptionEducation = false
    @State private var hasCheckedPerMediaCaptionEducation = false
    @State private var activePerMediaCaptionEditor: PerMediaCaptionEditorRoute?
    @State private var perMediaCaptionModerationTask: Task<Void, Never>?
    @State private var perMediaCaptionModeratingIndex: Int?
    @State private var perMediaCaptionGeneratingAltIndex: Int?
    @State private var perMediaCaptionStatusMessages: [Int: String] = [:]
    @State private var perMediaCaptionErrorMessages: [Int: String] = [:]
    private var isUITestAttachMockMedia: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-attach-mock-media")
    }

    // MARK: - Camera

    // MARK: - Poll composer
    @State private var showingPoll = false
    @State private var pollQuestion = ""
    @State private var pollOptions: [String] = ["", ""]  // start with 2 blank options
    @State private var pollDuration: PollDuration = .oneDay

    // MARK: - SocialLayer
    @State private var richSpans: [ComposerRichSpan] = []
    @State private var showingGIFPicker = false
    @State private var showingStickerPicker = false
    @State private var composerScriptureRefs: [ComposerScriptureRef] = []
    @StateObject private var scriptureDetectService = ScriptureAutoDetectService()

    /// Unified publish pipeline state. Read this in UI code instead of checking
    /// `isPublishing`/`isUploadingImages` separately.
    enum PublishState: Equatable {
        case idle
        case uploadingMedia  // media upload in progress (implies isPublishing too)
        case publishing      // network post write in progress
    }

    /// Derived from the two existing boolean flags — zero mutation risk.
    var publishState: PublishState {
        if isUploadingImages { return .uploadingMedia }
        if isPublishing { return .publishing }
        return .idle
    }

    enum PostButtonMorphState { case idle, sending, sent }

    enum PollDuration: String, CaseIterable, Identifiable {
        case oneDay   = "1 day"
        case threeDays = "3 days"
        case oneWeek  = "1 week"
        case noExpiry = "No expiry"
        var id: String { rawValue }
        var expiryDate: Date? {
            switch self {
            case .oneDay:    return Calendar.current.date(byAdding: .day, value: 1, to: Date())
            case .threeDays: return Calendar.current.date(byAdding: .day, value: 3, to: Date())
            case .oneWeek:   return Calendar.current.date(byAdding: .day, value: 7, to: Date())
            case .noExpiry:  return nil
            }
        }
    }

    // Tag people
    @State private var taggedUsers: [MentionedUser] = []
    @State private var showingTagPeopleSheet = false

    // MARK: - System 28: Feed Intelligence OS
    @State private var feedDirectionDetection: FeedDirectionDetectionResult = .empty
    @State private var feedDirectionDraft = FeedDirectionDraft(
        rawText: "", interpretedSummary: nil, intentType: .unknown,
        duration: .today, intensity: .medium, visibility: .privateOnly, affectedSurfaces: [])
    @State private var showGuideMyFeedSheet = false
    @State private var feedDirectionResponse: SubmitFeedDirectionResponse? = nil
    @State private var showFeedDirectionToast = false

    // Audience / visibility
    @State private var postVisibility: Post.PostVisibility = .everyone
    @State private var showingAudienceSheet = false

    // HeyFeed intent — what this post is for (optional, aids distribution + feed learning)
    @State private var selectedPostIntent: PostIntent?
    // HeyFeed audience hint - who this post is for (optional, aids feed routing)
    @State private var selectedAudienceHint: AudienceHint?

    // Scripture verse - two-stage Liquid Glass drawer
    @State private var attachedVerseReference: String = ""
    @State private var attachedVerseText: String = ""
    @State private var showingVersePickerSheet = false
    
    // Scripture attachment ViewModel (new structured system)
    @StateObject private var verseAttachmentVM = VerseAttachmentViewModel()

    // Church tag
    @State private var taggedChurchId: String = ""
    @State private var taggedChurchName: String = ""
    @State private var showingChurchTagSheet = false
    
    // P0-1 FIX: Prevent duplicate post creation using a UUID idempotency token.
    // Using UUID instead of hashValue (hashValue is unstable across launches and collision-prone).
    @State private var inFlightPostId: String? = nil
    @State private var draftVM = CreatePostDraftViewModel()
    /// Pre-seeded Firestore document IDs for thread segments, preserved across retries
    /// so a partial-failure retry writes to the same docs instead of creating duplicates.
    @State private var pendingThreadSegmentIds: [String] = []
    
    // P0-2 FIX: Store delayed tasks for cancellation
    @State private var delayedTasks: [Task<Void, Never>] = []
    
    // TRUST & SAFETY: Content moderation tracking
    @StateObject private var integrityTracker = ComposerIntegrityTracker()
    @ObservedObject private var rateLimiter = ComposerRateLimiter.shared
    @State private var showModerationNudge = false
    @State private var moderationNudgeMessage = ""
    @State private var showModerationBlockingModal = false
    @State private var blockingModerationDecision: ModerationDecision?
    @State private var shakePublishButton = false
    @State private var shakeTopicTag = false  // P1 FIX: Shake topic tag when validation fails
    
    // GUARDIAN PRE-GATE: true while the post has been submitted but is still
    // in "under_review" state awaiting the serverSidePostModeration CF decision.
    // Used to show "being reviewed" copy instead of the standard "Posted!" pill.
    @State private var postPendingReview: Bool = false

    // AI CONTENT DETECTION
    @State private var showAIContentAlert = false
    @State private var aiContentConfidence: Double = 0.0
    @State private var aiContentReason: String = ""
    
    // ✅ AUTHENTICITY PROMPT (gentle nudge for suspicious content)
    @State private var showAuthenticityPrompt = false
    @State private var authenticityPromptMessage = ""
    @State private var personalContextText = ""  // User's added personal context

    // ✅ SOURCE LABEL — when AI-flagged content is allowed through with disclosure
    @State private var showSourcePrompt = false
    @State private var pendingSourceContent = ""  // content waiting for source decision
    @State private var postContentSource: String? = nil  // "ChatGPT" | "External" | nil
    
    // ✅ HEY FEED: Think First guardrails
    @State private var showThinkFirstPrompt = false
    @State private var thinkFirstCheckResult: ThinkFirstGuardrailsService.ContentCheckResult?
    @State private var pendingPostContent = ""  // Store content during guardrail check

    // Phase P1-4: server-authoritative ThinkFirst gate. When the server
    // validator overrides the client verdict (block/requireEdit) or fails
    // (serverError/inputRejected), the publish path fails-closed and the
    // user sees this alert instead of the existing client-driven sheet.
    @State private var showServerThinkFirstAlert = false
    @State private var serverThinkFirstAlertMessage: String = ""
    
    // Berean AI tone assist
    @State private var bereanToneSuggestion: String?
    @State private var isLoadingBereanTone = false
    @State private var showBereanToneSheet = false
    @State private var showPostAICard = false
    @StateObject private var alignmentViewModel = BiblicalAlignmentViewModel()
    @State private var showCorrectAIForPost = false
    @State private var showPostDiscernmentPrompt = false
    @State private var spiritualComposeAnalysis = AmenComposeAnalysis(intent: .unknown, suggestions: [], shouldShowDiscernmentGate: false, discernmentTitle: nil, discernmentMessage: nil)
    @State private var showSpiritualDiscernmentGate = false
    @State private var bypassSpiritualDiscernmentGate = false
    // AI Usage Label tracking — set when the user accepts a tone rewrite via Safety OS
    @State private var pendingAIUsage: PostAIUsage? = nil
    @State private var safetyOSDraftTriggers: [AmenTriggerResult] = []
    @State private var activeSafetyOSTrigger: AmenTriggerResult?
    @State private var safetyOSCanonicalTask: Task<Void, Never>?
    @State private var pendingWellnessContext: WellnessInterventionContext? = nil
    @State private var wellnessClearedForPublish = false
    @State private var showBotChallenge = false
    @State private var botChallengeCleared = false
    @StateObject private var contextualComposerObserver = AmenMagicWordComposerObserver()
    @ObservedObject private var supportDetectionService = SupportDetectionService.shared
    @ObservedObject private var supportActionExecutor = SupportActionExecutor.shared
    @State private var supportDraftPayload: SupportInterventionPayload?
    @State private var supportDraftTask: Task<Void, Never>?
    @State private var showSupportDraftSheet = false
    @State private var bypassSupportDraftGate = false
    
    // MARK: - New Features (Phase 1-3)
    
    // Phase 1: Alt text for images
    @State private var imageAltTexts: [String] = []  // Alt text for each image (accessibility)
    @State private var editingAltTextIndex: Int? = nil
    @State private var showAltTextSheet = false
    
    // Phase 1: Hide engagement counts
    @State private var hideEngagementCounts = false  // Privacy: hide likes/interactions from others
    
    // Phase 1: Content warning
    @State private var hasSensitiveContent = false  // Mark post as sensitive
    @State private var sensitiveContentReason: String = ""  // Optional reason (grief, trauma, etc.)
    
    // Phase 2: Voice-to-text
    @State private var isRecording = false
    @State private var showVoicePermissionAlert = false
    
    // Phase 2: AI verse suggestions
    @State private var showVerseSuggestions = false
    @State private var suggestedVerses: [ScripturePassage] = []
    @State private var isLoadingVerseSuggestions = false
    
    // Phase 2: Post preview
    @State private var showPreview = false
    
    // Phase 3: Save as template
    @State private var showSaveTemplateSheet = false
    @State private var templateName = ""
    
    // Phase 3: Thread creation
    @State private var isThreadMode = false
    @State private var threadPosts: [String] = [""]  // Array of thread post texts
    @State private var currentThreadIndex = 0
    
    // MARK: - Initializer
    
    init(initialCategory: PostCategory? = nil) {
        if let category = initialCategory {
            _selectedCategory = State(initialValue: category)
            // P1-3: Prayer posts default to followers-only comments + followers visibility for privacy
            if category == .prayer {
                _commentPermission = State(initialValue: .followersOnly)
                _postVisibility = State(initialValue: .followers)
            }
        }
    }
    
    enum PostCategory: String, CaseIterable {
        case openTable = "openTable"      // ✅ Firebase-safe (no special chars)
        case testimonies = "testimonies"  // ✅ Firebase-safe (lowercase)
        case prayer = "prayer"            // ✅ Firebase-safe (lowercase)
        case tip = "tip"                  // ✅ NEW: Tips category
        case funFact = "funFact"          // ✅ NEW: Fun Facts category
        
        /// Display name for UI (with special formatting)
        var displayName: String {
            switch self {
            case .openTable: return "#OPENTABLE"
            case .testimonies: return "Testimonies"
            case .prayer: return "Prayer"
            case .tip: return "Tip"
            case .funFact: return "Fun Fact"
            }
        }
        
        var icon: String {
            switch self {
            case .openTable: return "lightbulb.fill"
            case .testimonies: return "star.fill"
            case .prayer: return "hands.sparkles.fill"
            case .tip: return "info.circle.fill"
            case .funFact: return "sparkles"
            }
        }
        
        var primaryColor: Color {
            switch self {
            case .openTable: return .orange
            case .testimonies: return .yellow
            case .prayer: return .blue
            case .tip: return .green
            case .funFact: return .purple
            }
        }
        
        var secondaryColor: Color {
            switch self {
            case .openTable: return .yellow
            case .testimonies: return .orange
            case .prayer: return .cyan
            case .tip: return .mint
            case .funFact: return .pink
            }
        }
        
        var description: String {
            switch self {
            case .openTable: return "Discussions about AI, tech & faith"
            case .testimonies: return "Share your faith journey"
            case .prayer: return "Prayer requests & praise reports"
            case .tip: return "Share helpful tips & advice"
            case .funFact: return "Share interesting facts"
            }
        }
        
        /// Convert to Post.PostCategory for backend
        var toPostCategory: Post.PostCategory {
            switch self {
            case .openTable: return .openTable
            case .testimonies: return .testimonies
            case .prayer: return .prayer
            case .tip: return .tip
            case .funFact: return .funFact
            }
        }
    }
    
    // P0-2 FIX: Helper to schedule cancellable delayed actions
    private func scheduleDelayedAction(seconds: Double, action: @escaping @MainActor () -> Void) {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        delayedTasks.append(task)
    }
    
    var body: some View {
        mainView
            .sheet(isPresented: $showCorrectAIForPost) {
                CorrectTheAIView(
                    originalText: postText,
                    onSave: { lens, correction, remember in
                        Task {
                            _ = await alignmentViewModel.saveCorrection(
                                originalText: postText,
                                correctionText: correction,
                                targetType: "post",
                                lens: lens,
                                correctionIntent: "tone",
                                savedToProfile: remember
                            )
                            showCorrectAIForPost = false
                        }
                    },
                    onApplyRewrite: { lens in
                        Task {
                            await alignmentViewModel.requestRewrite(for: postText, lens: lens, targetType: "post")
                            if let rewritten = alignmentViewModel.rewrittenText {
                                postText = rewritten
                            }
                            showCorrectAIForPost = false
                        }
                    },
                    onCancel: {
                        showCorrectAIForPost = false
                    }
                )
            }
            .sheet(isPresented: $showPostDiscernmentPrompt) {
                if let prompt = alignmentViewModel.discernmentPrompt {
                    SpiritualDiscernmentPromptView(
                        prompt: prompt,
                        onSelect: { _ in
                            showPostDiscernmentPrompt = false
                            proceedWithPublish()
                        },
                        onDismiss: {
                            showPostDiscernmentPrompt = false
                            proceedWithPublish()
                        }
                    )
                }
            }
            .sheet(isPresented: $showSpiritualDiscernmentGate) {
                DiscernmentGateSheet(
                    title: spiritualComposeAnalysis.discernmentTitle ?? "Discernment Moment",
                    message: spiritualComposeAnalysis.discernmentMessage ?? "This may land differently than intended.",
                    rewrite: spiritualComposeAnalysis.suggestions.first(where: { $0.id == "soften" || $0.id == "clarify" })?.replacementText,
                    onEdit: {
                        bypassSpiritualDiscernmentGate = false
                        showSpiritualDiscernmentGate = false
                        isTextFieldFocused = true
                    },
                    onRewrite: {
                        if let replacement = spiritualComposeAnalysis.suggestions.first(where: { $0.id == "soften" || $0.id == "clarify" })?.replacementText {
                            postText = replacement
                            spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: replacement)
                        }
                        bypassSpiritualDiscernmentGate = false
                        showSpiritualDiscernmentGate = false
                        isTextFieldFocused = true
                    },
                    onPause: {
                        postText = "I want to pause and pray before I say more."
                        spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: postText)
                        bypassSpiritualDiscernmentGate = false
                        showSpiritualDiscernmentGate = false
                        isTextFieldFocused = true
                    },
                    onSendAnyway: {
                        bypassSpiritualDiscernmentGate = true
                        showSpiritualDiscernmentGate = false
                        publishPost()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $activeSafetyOSTrigger) { trigger in
                AmenDiscernmentSheet(
                    trigger: trigger,
                    originalText: postText,
                    suggestedRewrite: AmenLocalTriggerEngine.shared.suggestedRewrite(for: trigger, originalText: postText)
                ) { action in
                    handleSafetyOSDraftAction(action, trigger: trigger)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $pendingWellnessContext) { ctx in
                WellnessPauseSheet(
                    context: ctx,
                    onContinue: {
                        wellnessClearedForPublish = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            publishPost()
                        }
                    },
                    onPause: {}
                )
            }
            .sheet(isPresented: $showBotChallenge) {
                BotSuspicionFrictionView(
                    onChallengePassed: {
                        AmenBotDefenseService.shared.markChallengeCompleted()
                        botChallengeCleared = true
                        showBotChallenge = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            publishPost()
                        }
                    },
                    onCancel: {
                        showBotChallenge = false
                    }
                )
                .presentationDetents([.medium])
            }
    }

    private var topicTagButtonText: String {
        if selectedTopicTag.isEmpty {
            return selectedCategory == .testimonies ? "Add category" : "Add topic tag"
        }
        return selectedTopicTag
    }
    
    @ViewBuilder
    private var composeContentArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = alignmentViewModel.result,
               result.status != .aligned {
                LiquidGlassAlignmentBanner(
                    result: result,
                    onViewContext: {
                        if result.status == .contextNeeded {
                            showPostDiscernmentPrompt = true
                        }
                    },
                    onCorrectAI: {
                        showCorrectAIForPost = true
                    },
                    onRewrite: {
                        Task {
                            await alignmentViewModel.requestRewrite(for: postText, lens: .balancedBiblical, targetType: "post")
                            if let rewritten = alignmentViewModel.rewrittenText {
                                postText = rewritten
                            }
                        }
                    },
                    onContinue: result.status == .contextNeeded ? {
                        proceedWithPublish()
                    } : nil,
                    onHold: result.status == .humanReview ? {} : nil
                )
            }

            // TRUST & SAFETY: Show personalize nudge banner
            if showModerationNudge {
                PersonalizeNudgeBanner(
                    message: moderationNudgeMessage,
                    isVisible: $showModerationNudge
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            textEditorView
            AmenComposerDiscernmentOverlay(triggers: safetyOSDraftTriggers)
            AmenContextualReactionLayer(results: contextualComposerObserver.results, maxVisible: 3)
            supportDraftPresentation
            IntentComposeAssistantBar(
                analysis: spiritualComposeAnalysis,
                onApplySuggestion: { suggestion in
                    if let replacement = suggestion.replacementText {
                        postText = replacement
                    } else if suggestion.id == "scripture_context" {
                        showingVersePickerSheet = true
                    }
                    spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: postText)
                },
                onDismissSuggestion: { suggestion in
                    spiritualComposeAnalysis = AmenComposeAnalysis(
                        intent: spiritualComposeAnalysis.intent,
                        suggestions: spiritualComposeAnalysis.suggestions.filter { $0.id != suggestion.id },
                        shouldShowDiscernmentGate: spiritualComposeAnalysis.shouldShowDiscernmentGate,
                        discernmentTitle: spiritualComposeAnalysis.discernmentTitle,
                        discernmentMessage: spiritualComposeAnalysis.discernmentMessage
                    )
                },
                onWhy: { suggestion in
                    showError(title: suggestion.title, message: suggestion.reason)
                }
            )
            
            versePreviewBadge
            
            // Inline scripture suggestion (appears while typing)
            if verseAttachmentVM.showInlineSuggestion, let verse = verseAttachmentVM.inlineSuggestedVerse, verseAttachmentVM.attachedScripture == nil {
                InlineScriptureSuggestionBar(
                    verse: verse,
                    label: verseAttachmentVM.inlineSuggestionLabel,
                    onAttach: {
                        verseAttachmentVM.attachVerse(verse, source: .inlineSuggestion)
                        attachedVerseReference = verse.reference.displayString
                        attachedVerseText = verse.text
                    },
                    onDismiss: {
                        verseAttachmentVM.dismissInlineSuggestion()
                    },
                    onSeeRelated: {
                        verseAttachmentVM.openMiniAttach(draftText: postText)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .padding(.horizontal, -4)
            }
            
            taggedUsersChips

            // MARK: - Quick Category Chips (Testimony / Prayer / Scripture shortcuts)
            if !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ComposerSuggestionChips(
                    onMarkAsTestimony: { selectedCategory = .testimonies },
                    onMarkAsPrayer: { selectedCategory = .prayer },
                    onAddScripture: { verseAttachmentVM.openMiniAttach(draftText: postText) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // MARK: - Guide My Feed chip (Feed Intelligence OS)
            if feedDirectionDetection.isDetected && featureFlags.guideMyFeedEnabled {
                GuideMyFeedComposerChip(detection: feedDirectionDetection) {
                    feedDirectionDraft = AmenFeedDirectionDetector.shared.buildDraft(
                        from: feedDirectionDetection, rawText: postText)
                    showGuideMyFeedSheet = true
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // MARK: - Smart Composition Cues
            composerSuggestionRow

            // MARK: - Post Intent (optional HeyFeed signal)
            if postText.count > 20 {
                CreatePostIntentRow(selectedIntent: $selectedPostIntent)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // MARK: - Audience Hint (optional HeyFeed routing signal)
            if postText.count > 20 {
                CreatePostAudienceHintRow(selectedHint: $selectedAudienceHint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Topic tags are optional routing signals.
            if selectedCategory == .openTable || selectedCategory == .prayer || selectedCategory == .testimonies {
                Button {
                    showingTopicTagSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.systemScaled(12, weight: .medium))
                        Text(topicTagButtonText)
                            .font(.systemScaled(13, weight: .medium))
                        if selectedTopicTag.isEmpty {
                            Text("Optional")
                                .font(.systemScaled(10, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                    .foregroundStyle(selectedTopicTag.isEmpty ? Color.secondary : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        let fillColor: Color = selectedTopicTag.isEmpty ? Color(.systemGray6) : Color.primary.opacity(0.08)
                        Capsule().fill(fillColor)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedTopicTag.isEmpty ? "Select topic tag" : "Topic: \(selectedTopicTag)")
                .accessibilityHint("Choose a topic tag for your post")
                .modifier(ShakeEffect(shakes: shakeTopicTag ? 3 : 0))
            }

            // Witness camera preview
            if let attachment = cameraCoordinator.attachedWitnessMedia {
                WitnessDraftAttachmentPreview(attachment: attachment) {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                        cameraCoordinator.removeAttachedMedia()
                    }
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            // Library photo grid
            if !selectedImageData.isEmpty {
                ImagePreviewGrid(images: $selectedImageData, onAddMore: { showingImagePicker = true })
            }

            if !selectedImageData.isEmpty || cameraCoordinator.attachedWitnessMedia != nil {
                Button {
                    showMediaMetadataAuthoring = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "captions.bubble")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.primary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Prepare media details")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(mediaMetadataSummaryText)
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Add captions, alt text, and other media details")
            }

            if featureFlags.composerApprovedAudioEnabled, (!selectedImageData.isEmpty || cameraCoordinator.attachedWitnessMedia != nil) {
                Button {
                    showAmenAudioComposer = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.primary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(mediaMetadataDraft.audioAttachment == nil ? "Add Music" : "Music added")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text({
                                guard let title = mediaMetadataDraft.audioAttachment?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                      !title.isEmpty else {
                                    return "Worship, instrumental, prayer, testimony, and approved original audio"
                                }
                                return title
                            }())
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mediaMetadataDraft.audioAttachment == nil ? "Add music to post" : "Music added — tap to change")
                .accessibilityHint("Attach worship music or approved audio to your post")
                .accessibilityIdentifier("composer_add_music_button")
            }

            // Poll composer
            if showingPoll {
                PollComposerCard(
                    options: $pollOptions,
                    duration: $pollDuration,
                    onRemove: {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            showingPoll = false
                            pollOptions = ["", ""]
                            pollDuration = .oneDay
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ComposerLinkPreview(controller: linkController)
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8), value: linkController.activeURL)
            smartAttachmentComposerPreview

            // Music attachment card (Threads-style)
            if let music = selectedMusicAttachment {
                AmenMusicCardContainer(attachment: music)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                selectedMusicAttachment = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.secondary)
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .accessibilityLabel("Remove music attachment")
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .padding(.top, 8)
            }

            // Inline toolbar — simple gray icons
            threadsAttachmentBar
                .padding(.top, 8)
        }
    }
    
    // MARK: - Compose Input Row (extracted to reduce type-checker complexity)
    private var composeInputRow: some View {
        HStack(alignment: .top, spacing: 8) {
            // Thread connector line
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1)
            }
            .frame(width: 36) // tighter alignment under avatar
            .padding(.top, 4)

            // Text input — clean, no borders
            composeContentArea
        }
        .padding(.horizontal, 16)
    }

    private var mainView: some View {
        navigationStackView
    }
    
    // MARK: - Main Content ZStack
    private var mainContentZStack: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Threads-style compose layout ────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // User row with avatar + category selector
                        threadsUserRow
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        // Compose area with thread connector
                        composeInputRow

                        // ── Add to thread row (Threads-style) ───────────────
                        if !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThreadMode {
                            HStack(spacing: 12) {
                                // Small avatar echo
                                Circle()
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(width: 24, height: 24)
                                    .padding(.leading, 16)

                                Button {
                                    beginThreadMode()
                                } label: {
                                    Text("Add to thread…")
                                        .font(.systemScaled(15))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Post as a thread with multiple connected posts")

                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                        // ── Thread posts (when in thread mode) ───────────────
                        if isThreadMode && threadPosts.count > 1 {
                            ForEach(1..<threadPosts.count, id: \.self) { index in
                                HStack(alignment: .top, spacing: 12) {
                                    // Thread connector line
                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.1))
                                            .frame(width: 1)
                                    }
                                    .frame(width: 44)
                                    .padding(.top, 4)
                                    
                                    // Thread post text field
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField("Continue thread…", text: Binding(
                                            get: { threadPosts[index] },
                                            set: { threadPosts[index] = $0 }
                                        ), axis: .vertical)
                                        .font(.systemScaled(16))
                                        .lineLimit(10...20)
                                        .textFieldStyle(.plain)
                                        .accessibilityLabel("Thread post \(index + 1)")
                                        
                                        // Remove thread post button
                                        if threadPosts.count > 2 || !threadPosts[index].isEmpty {
                                            Button {
                                                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                                    threadPosts.remove(at: index)
                                                    if threadPosts.count == 1 {
                                                        isThreadMode = false
                                                        postText = threadPosts[0]
                                                        threadPosts = [""]
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.systemScaled(14))
                                                    Text("Remove")
                                                        .font(.systemScaled(13))
                                                }
                                                .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Remove thread post \(index + 1)")
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            
                            // Add another thread post button
                            if threadPosts.count < 10 {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(.tertiarySystemFill))
                                        .frame(width: 24, height: 24)
                                        .padding(.leading, 16)
                                    
                                    Button {
                                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                            threadPosts.append("")
                                        }
                                    } label: {
                                        Text("Add another post…")
                                            .font(.systemScaled(15))
                                            .foregroundStyle(Color(.tertiaryLabel))
                                    }
                                    .accessibilityHint("Add a new post to this thread")
                                    .buttonStyle(.plain)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }

                        Spacer(minLength: 40)
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()
                    .opacity(0.35)
                ScriptureAutoDetectRail(service: scriptureDetectService) { ref in
                    composerScriptureRefs.append(ref)
                }
                .padding(.horizontal, 16)
                // ── Bottom toolbar with schedule, tone check, etc. ────────────
                threadsBottomBar
                    .padding(.bottom, 8)

                // P1-7: Persistent publish-failure banner — visible until user dismisses or retries
                if let failMsg = publishFailureBannerMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.white)
                        Text(failMsg)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            guard publishState == .idle else { return }
                            publishPost()
                            publishFailureBannerMessage = nil
                        } label: {
                            Text("Retry")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.25), in: Capsule())
                        }
                        .disabled(publishState != .idle)
                        Button {
                            publishFailureBannerMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: publishFailureBannerMessage != nil)
                }

                // Upload progress overlay
                if let uploadCapsuleState {
                    VStack {
                        Spacer()
                        LiquidGlassUploadCapsule(
                            state: uploadCapsuleState,
                            progress: uploadCapsuleProgress,
                            uploadedCount: uploadCapsuleUploadedCount,
                            totalCount: uploadCapsuleMediaItems.count,
                            mediaItems: uploadCapsuleMediaItems,
                            isExpanded: isUploadCapsuleExpanded,
                            onToggleExpanded: {
                                withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.82))) {
                                    isUploadCapsuleExpanded.toggle()
                                }
                            },
                            onRetry: retryUploadCapsuleAction,
                            onCancel: nil
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 102)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: uploadCapsuleState)
                }

                // Success notification
                // When postPendingReview is true the post is still "under_review" in Firestore
                // (GUARDIAN pre-gate). Show "Under Review" so the author knows moderation is
                // running. The post will appear in feeds once the CF promotes visibility.
                if showingSuccessNotice && uploadCapsuleState == nil {
                    VStack {
                        Spacer()
                        PostedPill(finalLabel: postPendingReview ? "Under Review" : "Posted")
                            .padding(.bottom, 56) // Anchored just above bottom bar
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.72), value: showingSuccessNotice)
                }
            }
        }
        .accessibilityIdentifier("create_post_view")
        .accessibilityIdentifier("screen.composer.post")
        .overlay(alignment: .top) {
            if showingDraftSavedNotice {
                Text("Draft saved")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8)), value: showingDraftSavedNotice)
    }

    // MARK: - Navigation Stack Content with Toolbar
    @ViewBuilder
    private var navigationStackContent: some View {
        mainContentZStack
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbar {
                toolbarContent
            }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                isTextFieldFocused = false
                let hasContent = !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !selectedImageData.isEmpty
                    || cameraCoordinator.attachedWitnessMedia != nil
                    || showingPoll
                    || isThreadMode
                if hasContent {
                    showCancelConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(17, weight: .semibold))
                    Text("Back")
                        .font(.systemScaled(17, weight: .regular))
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Close")
            .accessibilityHint("Go back and discard or save as draft")
            .amenAlert(isPresented: $showCancelConfirmation, config: LiquidGlassAlertConfig(
                title: "Save your post?",
                message: nil,
                icon: "doc.badge.gearshape",
                primaryButton: LiquidGlassAlertButton("Save Draft", tone: .primary) {
                    shouldPersistDraftOnExit = false
                    autoSaveDraft()
                    saveDraft()
                    dismiss()
                },
                secondaryButton: LiquidGlassAlertButton("Discard Post", tone: .destructive) {
                    shouldPersistDraftOnExit = false
                    draftVM.clearDraft()
                    recoveredDraft = nil
                    cameraCoordinator.removeAttachedMedia()
                    cleanupPendingUploadArtifacts()
                    dismiss()
                }
            ))
        }

        ToolbarItem(placement: .principal) {
            Text("New post")
                .font(.systemScaled(16, weight: .semibold))
        }

        // Draft button
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showDraftsSheet = true
            } label: {
                Image(systemName: "doc.text")
                    .font(.systemScaled(16, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Saved drafts")
            .accessibilityHint("View and restore previously saved post drafts")
        }

        // Liquid Glass Post Button
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                if canPost {
                    triggerLiquidPost()
                }
            } label: {
                HStack(spacing: 6) {
                    // P1-13: Show spinner during any publish/upload phase to block double-taps.
                    if publishState != .idle {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.75)
                            .frame(width: 20, height: 20)
                    } else {
                        ZStack {
                            Circle()
                                .fill(canPost ? Color.black.opacity(0.08) : Color.black.opacity(0.35))
                                .frame(width: 20, height: 20)

                            Image(systemName: scheduledDate != nil ? "calendar" : "arrow.up")
                                .font(.systemScaled(11, weight: .bold))
                        }
                    }

                    Text(postPendingReview ? "Pending Review" : scheduledDate != nil ? "Schedule" : "Post")
                }
            }
            .buttonStyle(.amenGlass(
                role: .primary,
                size: .compact,
                shape: .capsule,
                background: .balanced,
                placement: .overlay
            ))
            .disabled(!canPost || publishState != .idle)
            .accessibilityHint(canPost ? "" : "Add text or media to enable posting")
        }
    }

    // MARK: - Photo Picker Modifiers
    private func applyPhotoPickerModifiers<Content: View>(_ content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingImagePicker,
                selection: $selectedImages,
                maxSelectionCount: 4,
                matching: .images
            )
            .onChange(of: selectedImages) { _, newItems in
                Task {
                    selectedImageData = []
                    var oversizedImages = 0

                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let maxSize = 10 * 1024 * 1024 // 10 MB
                            if data.count > maxSize {
                                oversizedImages += 1
                                dlog("⚠️ Image exceeds 10MB limit, skipping")
                                continue
                            }
                            selectedImageData.append(data)
                        }
                    }

                    mediaMetadataDraft.syncForImages(count: selectedImageData.count)
                    selectedMediaIndex = 0

                    // Trigger education modal on first multi-image selection (contract: >=2 items)
                    if AMENFeatureFlags.shared.perMediaCaptionsEnabled,
                       AMENFeatureFlags.shared.perMediaCaptionEducationEnabled,
                       selectedImageData.count >= 2,
                       !hasCheckedPerMediaCaptionEducation,
                       let uid = Auth.auth().currentUser?.uid {
                        hasCheckedPerMediaCaptionEducation = true
                        let seen = await MediaCaptionEducationService.shared.hasSeenEducation(uid: uid)
                        if !seen {
                            await MainActor.run { showPerMediaCaptionEducation = true }
                        }
                    }

                    if oversizedImages > 0 {
                        await MainActor.run {
                            showError(
                                title: "Some Images Too Large",
                                message: "\(oversizedImages) image(s) exceeded the 10MB size limit and were skipped. Try using smaller images."
                            )
                        }
                    }
                }
            }
    }
    
    // MARK: - Sheet Modifiers Group 1
    private func applySheetModifiers1<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingLinkSheet) {
                LinkInputSheet(url: $linkURL, isPresented: $showingLinkSheet) { url in
                    // Delegate to controller so manual URL also gets rich preview
                    linkController.handleTextChange(url)
                }
            }
            .sheet(isPresented: $showingTopicTagSheet) {
                TopicTagSheet(selectedTag: $selectedTopicTag, isPresented: $showingTopicTagSheet, selectedCategory: $selectedCategory)
            }
            .sheet(isPresented: $showingScheduleSheet) {
                SmartScheduleSheet(
                    isPresented: $showingScheduleSheet,
                    scheduledDate: $scheduledDate,
                    postText: postText,
                    hasImages: !selectedImageData.isEmpty,
                    hasVideo: cameraCoordinator.attachedWitnessMedia?.isVideo == true
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingGIFPicker) {
                ComposerGIFPickerSheet { _ in
                    showingGIFPicker = false
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingStickerPicker) {
                ComposerStickerPickerSheet { _ in
                    showingStickerPicker = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDraftsSheet) {
                DraftsView()
            }
            .sheet(isPresented: $showMediaMetadataAuthoring) {
                MediaMetadataAuthoringSheet(
                    draft: $mediaMetadataDraft,
                    photoPreviewImages: selectedImageData.compactMap(UIImage.init(data:)),
                    witnessAttachment: cameraCoordinator.attachedWitnessMedia
                ) {
                    showMediaMetadataAuthoring = false
                }
            }
            .sheet(isPresented: $showAmenAudioComposer) {
                AmenAudioComposerSheet(
                    draft: mediaMetadataDraft.audioAttachment.map { a in
                        AmenAudioAttachmentDraft(
                            title: a.title,
                            artist: a.artist ?? "",
                            source: a.source,
                            category: .originalAudio,
                            trimStartMs: Int(a.startOffset * 1000),
                            trimDurationMs: Int((a.trimDuration ?? 30) * 1000),
                            musicVolume: a.volume,
                            originalAudioVolume: 1.0,
                            isApproved: true
                        )
                    },
                    onCancel: { showAmenAudioComposer = false },
                    onApply: { updated in
                        if let bed = updated.asMediaAudioBed {
                            mediaMetadataDraft.audioAttachment = MediaAudioAttachment(
                                source: bed.source,
                                title: bed.title,
                                artist: bed.artist,
                                startOffset: bed.startOffset,
                                trimDuration: bed.trimDuration,
                                volume: bed.volume
                            )
                        } else {
                            mediaMetadataDraft.audioAttachment = nil
                        }
                        showAmenAudioComposer = false
                    }
                )
            }
            .sheet(isPresented: $showMusicAttachmentPicker) {
                AmenMusicPickerSheet(selectedMusic: $selectedMusicAttachment)
            }
            .sheet(item: $activePerMediaCaptionEditor) { route in
                if route.index < mediaMetadataDraft.frameCaptions.count {
                    PerMediaCaptionMetadataSheet(
                        route: route,
                        draft: $mediaMetadataDraft.frameCaptions[route.index],
                        onGenerateAltText: {
                            Task { await generateAltTextForMediaCaption(index: route.index) }
                        },
                        isGeneratingAltText: perMediaCaptionGeneratingAltIndex == route.index,
                        onSave: {
                            activePerMediaCaptionEditor = nil
                            Task { await moderateMediaCaptionIfNeeded(index: route.index, force: true) }
                        },
                        onCancel: {
                            activePerMediaCaptionEditor = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showingMediaAttachmentPicker) {
                AmenMediaAttachmentPickerView(
                    currentState: smartAttachmentState,
                    onAttach: { attachment in
                        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                            smartAttachment = attachment
                            smartAttachmentState = .resolved(attachment)
                        }
                        showingMediaAttachmentPicker = false
                    },
                    onDismiss: { showingMediaAttachmentPicker = false }
                )
            }
            .sheet(isPresented: $showCommentControls) {
                PostCommentControlsSheet(selectedPermission: $commentPermission)
                    .onChange(of: commentPermission) { oldValue, newValue in
                        // Update allowComments based on permission
                        allowComments = (newValue != .nobody)
                    }
            }
            .sheet(isPresented: $showingTagPeopleSheet) {
                TagPeopleSheet(taggedUsers: $taggedUsers)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAudienceSheet) {
                PostAudienceSheet(selectedVisibility: $postVisibility)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showGuideMyFeedSheet) {
                GuideMyFeedSheet(
                    draft: $feedDirectionDraft,
                    onApply: { draft in
                        Task {
                            let context = ComposerFeedDirectionContext(
                                source: "composer",
                                timezone: TimeZone.current.identifier,
                                localHour: Calendar.current.component(.hour, from: Date()),
                                isSunday: Calendar.current.component(.weekday, from: Date()) == 1,
                                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled,
                                reduceTransparencyEnabled: UIAccessibility.isReduceTransparencyEnabled
                            )
                            let request = SubmitFeedDirectionRequest(
                                rawText: draft.rawText,
                                composerContext: context,
                                duration: draft.duration,
                                intensity: draft.intensity,
                                visibility: draft.visibility,
                                affectedSurfaces: draft.affectedSurfaces,
                                clientDetectionConfidence: feedDirectionDetection.confidence
                            )
                            FeedDirectionAnalytics.submitted(
                                intentType: draft.intentType.rawValue,
                                duration: draft.duration.rawValue,
                                intensity: draft.intensity.rawValue,
                                surfaces: draft.affectedSurfaces.map(\.rawValue)
                            )
                            do {
                                let response = try await AmenFeedDirectionService.shared.submitFeedDirection(request)
                                feedDirectionResponse = response
                                showFeedDirectionToast = true
                                feedDirectionDetection = .empty
                                FeedDirectionAnalytics.applySuccess(signalId: response.signalId, intentType: response.intentType.rawValue)
                            } catch {
                                FeedDirectionAnalytics.applyFailed(reason: error.localizedDescription)
                            }
                        }
                    },
                    onCancel: { feedDirectionDetection = .empty }
                )
            }

            .sheet(isPresented: $showingChurchTagSheet) {
                PostChurchTagSheet(
                    taggedChurchId: $taggedChurchId,
                    taggedChurchName: $taggedChurchName,
                    isPresented: $showingChurchTagSheet
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showModerationBlockingModal) {
                if let decision = blockingModerationDecision {
                    ModerationDecisionView(
                        decision: decision,
                        onRevise: {
                            showModerationBlockingModal = false
                            blockingModerationDecision = nil
                            // User can edit and try again
                        },
                        onCancel: {
                            showModerationBlockingModal = false
                            blockingModerationDecision = nil
                            dismiss()
                        }
                    )
                }
            }
            .sheet(isPresented: $showAuthenticityPrompt) {
                AuthenticityPromptSheet(
                    message: authenticityPromptMessage,
                    personalContext: $personalContextText,
                    onContinue: {
                        // User added personal context, allow post to continue
                        showAuthenticityPrompt = false
                        // Append personal context to the post
                        if !personalContextText.isEmpty {
                            postText += "\n\n" + personalContextText
                            personalContextText = "" // Reset for next time
                        }
                        // Retry publishing with the updated content
                        publishPost()
                    },
                    onCancel: {
                        showAuthenticityPrompt = false
                        personalContextText = ""
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSourcePrompt) {
                SourceLabelPrompt(
                    onPostWithSource: { source in
                        showSourcePrompt = false
                        postContentSource = source
                        publishPost()
                    },
                    onEdit: {
                        showSourcePrompt = false
                        postContentSource = nil
                    }
                )
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(.clear)
            }
    }
    
    // MARK: - Sheet Modifiers Group 2
    private func applySheetModifiers2<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showThinkFirstPrompt) {
                thinkFirstPromptSheetContent
            }
            .sheet(isPresented: $showBereanToneSheet) {
                bereanToneSheetContent
            }
            .sheet(isPresented: $showAltTextSheet) {
                altTextSheetContent
            }
            // Phase P1-4: server-authoritative ThinkFirst override. Has no
            // "proceed anyway" affordance — the user must revise or retry.
            .amenAlert(isPresented: $showServerThinkFirstAlert, config: LiquidGlassAlertConfig(
                title: "Safety Check",
                message: serverThinkFirstAlertMessage,
                icon: "shield.lefthalf.fill",
                primaryButton: LiquidGlassAlertButton("OK", tone: .primary) { }
            ))
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("aiContentDetected"))) { notification in
                if let userInfo = notification.userInfo,
                   let confidence = userInfo["confidence"] as? Double,
                   let reason = userInfo["reason"] as? String {
                    aiContentConfidence = confidence
                    aiContentReason = reason
                    showAIContentAlert = true
                }
            }
    }
    
    // MARK: - Final Modifiers (Camera, Alerts, Lifecycle)
    private func applyFinalModifiers<Content: View>(_ content: Content) -> some View {
        content
        .interactiveDismissDisabled(!postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImageData.isEmpty || !linkURL.isEmpty || cameraCoordinator.attachedWitnessMedia != nil || showingPoll || isThreadMode)
        .perMediaCaptionEducation(isPresented: $showPerMediaCaptionEducation) {}
        // Verse drawer — top-level so it doesn't conflict with other sheets
        .verseDrawer(isPresented: $showingVersePickerSheet) { verse in
            attachedVerseReference = verse.reference.displayString
            attachedVerseText = verse.text
            verseAttachmentVM.attachVerse(verse, source: .manualSearch)
        }
        // Scripture detail route (from pill tap)
        .fullScreenCover(isPresented: $verseAttachmentVM.showScriptureDetail) {
            if let ctx = verseAttachmentVM.scriptureDetailContext {
                ScriptureDetailRoute(context: ctx) {
                    verseAttachmentVM.dismissScriptureDetail()
                }
            }
        }
        // Quick replace drawer
        .sheet(isPresented: $verseAttachmentVM.showQuickReplace) {
            if let attachment = verseAttachmentVM.attachedScripture {
                QuickReplaceVerseDrawer(
                    currentAttachment: attachment,
                    replaceResults: verseAttachmentVM.quickReplaceResults,
                    onReplace: { newVerse in
                        verseAttachmentVM.attachVerse(newVerse, source: .replace)
                        attachedVerseReference = newVerse.reference.displayString
                        attachedVerseText = newVerse.text
                    },
                    onOpenFullSearch: {
                        verseAttachmentVM.dismissQuickReplace()
                        showingVersePickerSheet = true
                    },
                    onDismiss: {
                        verseAttachmentVM.dismissQuickReplace()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
        .fullScreenCover(isPresented: $cameraCoordinator.isPresentingCamera) {
            WitnessCameraView(coordinator: cameraCoordinator)
                .ignoresSafeArea()
        }
        .onChange(of: cameraCoordinator.shouldRestoreFocusAfterDismiss) { _, shouldRestore in
            guard shouldRestore else { return }
            isTextFieldFocused = true
            cameraCoordinator.clearRestoreRequest()
        }
        .onChange(of: selectedImageData.count) { _, _ in
            syncMediaMetadataDraftFromCurrentAttachments()
        }
        .onChange(of: cameraCoordinator.attachedWitnessMedia?.id) { _, _ in
            syncMediaMetadataDraftFromCurrentAttachments()
        }
        .sheet(isPresented: $showSupportDraftSheet) {
            if let payload = supportDraftPayload,
               case .sheet(let model) = payload.presentationMode {
                SupportInterventionSheetView(
                    model: model,
                    actions: payload.actions,
                    onAction: handleSupportDraftAction(_:),
                    onDismiss: dismissSupportDraftPrompt,
                    onContinue: continuePostAfterSupportPrompt
                )
            }
        }
        .amenAlert(isPresented: $showingErrorAlert, config: errorAlertConfig)
        .amenAlert(
            isPresented: $showAIContentAlert,
            config: LiquidGlassAlertConfig(
                title: "Share Your Own Voice",
                message: "AMEN is a community for authentic, personal sharing. We noticed this content may not be written in your own words.\n\nPlease share your personal thoughts, experiences, and reflections.",
                icon: "person.crop.circle.badge.exclamationmark",
                primaryButton: LiquidGlassAlertButton("Edit Post", tone: .primary) {
                    activePublishTask?.cancel()
                    activePublishTask = nil
                    stopPublishAttempt()
                }
            )
        )
        .overlay {
            if showGuidelinesGate {
                CommunityGuidelinesGateView(
                    onAccept: {
                        showGuidelinesGate = false
                        // Re-call publishPost after user acknowledges
                        publishPost()
                    },
                    onCancel: {
                        showGuidelinesGate = false
                        activePublishTask?.cancel()
                        activePublishTask = nil
                        stopPublishAttempt()
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if showFeedDirectionToast, let response = feedDirectionResponse {
                GuideMyFeedConfirmationToast(
                    response: response,
                    onUndo: {
                        showFeedDirectionToast = false
                        if let response = feedDirectionResponse {
                            FeedDirectionAnalytics.undoTapped(signalId: response.signalId)
                        }
                        Task { try? await AmenFeedDirectionService.shared.resetFeedPreference(scope: .temporary) }
                    },
                    onDismiss: { showFeedDirectionToast = false }
                )
                .padding(.top, 60)
            }
        }
        .task {
            // Load current user if not yet available so the composer header shows
            // the real username and avatar instead of the "@you" fallback.
            if userService.currentUser == nil {
                await userService.fetchCurrentUser()
            }
        }
        .onAppear {
            // Delay focus slightly so the sheet finishes its presentation
            // animation before requesting keyboard; without the delay the
            // keyboard sometimes fails to appear on first open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTextFieldFocused = true
            }
            updateHashtagSuggestions()
            if isUITestAttachMockMedia, selectedImageData.isEmpty {
                injectUITestMockMedia()
            }

            // Check for auto-saved draft recovery
            checkForDraftRecovery()

            // Start auto-save timer (every 30 seconds)
            startAutoSaveTimer()

            // Track composer open
            AMENAnalyticsService.shared.track(.createHubOpened)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // App is backgrounding — flush draft immediately so data survives a crash/kill.
                autoSaveDraft()
            }
        }
        .onDisappear {
            persistDraftIfNeeded()

            // Stop auto-save task when view disappears
            autoSaveTask?.cancel()
            autoSaveTask = nil
            
            // Cancel in-flight mention search so its callback cannot write to @State
            // after the TextEditor's UITextView is torn down (prevents RTIInputSystemClient SIGABRT)
            mentionSearchTask?.cancel()
            mentionSearchTask = nil
            supportDraftTask?.cancel()
            supportDraftTask = nil
            
            // Cancel pending link preview
            linkController.reset()
            
            // Cancel in-flight image upload if the user dismisses mid-upload.
            // Task.isCancelled is already checked in the upload loop, so the
            // Storage write stops cleanly. The 48h orphanedMediaCleanup CF
            // handles any partial uploads that slipped through.
            if isUploadingImages {
                activePublishTask?.cancel()
                activePublishTask = nil
                stopPublishAttempt(markDraftFailed: true)
            }

            if !pendingUploadCleanupPaths.isEmpty {
                cleanupPendingUploadArtifacts()
            }
            
            // P0-2 FIX: Cancel all delayed tasks to prevent crash on rapid navigation
            delayedTasks.forEach { $0.cancel() }
            delayedTasks.removeAll()
        }
        .supportDestinationSheet()
        .amenAlert(
            isPresented: $showDraftRecovery,
            config: LiquidGlassAlertConfig(
                title: "Recover Draft?",
                message: "You have an unsaved draft from earlier. Would you like to continue editing it?",
                icon: "doc.text",
                primaryButton: LiquidGlassAlertButton("Recover", tone: .primary) {
                    if let draft = recoveredDraft { loadDraft(draft) }
                },
                secondaryButton: LiquidGlassAlertButton("Discard", tone: .destructive) {
                    clearRecoveredDraft()
                }
            )
        )
    }

    private func injectUITestMockMedia() {
        // 1x1 transparent PNG for deterministic UI-test media attachment.
        let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8AAgMBgN6byd4AAAAASUVORK5CYII="
        guard let data = Data(base64Encoded: tinyPNGBase64) else { return }
        selectedImageData = [data]
        mediaMetadataDraft.syncForImages(count: selectedImageData.count)
    }
    
    // MARK: - Navigation Stack View
    private var navigationStackView: some View {
        let baseStack = NavigationStack {
            applySheetModifiers2(applySheetModifiers1(applyPhotoPickerModifiers(navigationStackContent)))
        }
        .background(Color(.systemBackground))

        return applyFinalModifiers(baseStack)
    }
    
    // MARK: - Computed Properties
    private var hasDraftableContent: Bool {
        let trimmedText = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty
            || !selectedImageData.isEmpty
            || cameraCoordinator.attachedWitnessMedia != nil
            || showingPoll
            || isThreadMode
            || !linkURL.isEmpty
            || !attachedVerseReference.isEmpty
    }

    private var canPost: Bool {
        let hasText = !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isWithinLimit = postText.count <= 500
        guard isWithinLimit else { return false }

        let hasWitnessMedia = cameraCoordinator.attachedWitnessMedia != nil
        let hasValidPoll = showingPoll && pollHasValidOptions
        // P1-12: link-only and verse-only posts carry standalone content.
        let hasLink = !linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasVerse = !attachedVerseReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let hasContent = hasText || hasWitnessMedia || hasValidPoll
            || !selectedImageData.isEmpty || hasLink || hasVerse

        return hasContent
    }

    private var pollHasValidOptions: Bool {
        let filled = pollOptions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return filled.count >= 2
    }
    
    // P2 FIX: Verse attachment preview badge (Liquid Glass)
    @ViewBuilder
    private var versePreviewBadge: some View {
        if let attachment = verseAttachmentVM.attachedScripture {
            AttachedScripturePill(
                attachment: attachment,
                onTap: {
                    verseAttachmentVM.openScriptureDetail(from: .composer)
                },
                onReplace: {
                    verseAttachmentVM.openQuickReplace()
                },
                onRemove: {
                    verseAttachmentVM.removeAttachment()
                    attachedVerseReference = ""
                    attachedVerseText = ""
                },
                onViewChapter: {
                    verseAttachmentVM.openScriptureDetail(from: .composer)
                },
                onCopyReference: {
                    UIPasteboard.general.string = attachment.canonicalReference
                }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if !attachedVerseReference.isEmpty {
            // Legacy fallback for existing data
            LiquidGlassAttachedVerseBadge(
                reference: attachedVerseReference,
                text: attachedVerseText,
                onRemove: {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                        attachedVerseReference = ""
                        attachedVerseText = ""
                    }
                },
                onEdit: {
                    showingVersePickerSheet = true
                }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    // P2 FIX: Tagged users chips
    @ViewBuilder
    private var taggedUsersChips: some View {
        if !taggedUsers.isEmpty {
            TaggedUsersView(
                users: $taggedUsers
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Smart Composition Cues

    @ViewBuilder
    private var composerSuggestionRow: some View {
        let result = insightEngine.result
        let suggestions = [result.primarySuggestion].compactMap { $0 } + result.secondarySuggestions
        if !suggestions.isEmpty && result.confidence >= 0.3 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.rawValue) { action in
                        ComposerCuePill(action: action) {
                            handleCueTap(action)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 4)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.78)), value: suggestions.map(\.rawValue))
        }
    }

    private func handleCueTap(_ action: ComposerSuggestedAction) {
        HapticManager.impact(style: .light)
        switch action {
        case .attachVerse:
            showingVersePickerSheet = true
        case .addTopicTag:
            showingTopicTagSheet = true
        case .addCalendarDate:
            showingScheduleSheet = true
        case .switchToThread:
            beginThreadMode()
        case .tagPeople:
            showingTagPeopleSheet = true
        case .adjustAudience:
            showingAudienceSheet = true
        case .addImage:
            showingImagePicker = true
        case .addPoll:
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                showingPoll = true
            }
        case .markAsTestimony:
            selectedCategory = .testimonies
        case .markAsPrayer:
            selectedCategory = .prayer
        case .markAsChurchNote:
            selectedPostIntent = .teaching
        }
    }

    private func beginThreadMode() {
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
            if isThreadMode {
                if threadPosts.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                   threadPosts.count < 10 {
                    threadPosts.append("")
                    currentThreadIndex = threadPosts.count - 1
                }
            } else {
                isThreadMode = true
                threadPosts = [postText, ""]
                currentThreadIndex = 1
            }
        }
    }

    private var characterCountText: String {
        "\(postText.count) / 500"
    }
    
    private var characterCountColor: Color {
        if postText.count > 500 {
            return .red
        } else if postText.count > 480 {
            return .orange
        } else {
            return .secondary.opacity(0.6)
        }
    }
    
    private var characterCountIcon: String {
        if postText.count > 500 {
            return "exclamationmark.triangle.fill"
        } else if postText.count > 450 {
            return "exclamationmark.circle.fill"
        } else {
            return "text.alignleft"
        }
    }
    
    // MARK: - Contextual verse suggestion

    private var shouldShowVerseSuggestion: Bool {
        let lower = postText.lowercased()
        let keywords = ["pray", "scripture", "verse", "bible", "psalm", "jesus", "god ", "faith", "grace", "forgiv", "worship", "holy", "spirit", "lord", "amen"]
        let hasKeyword = keywords.contains { lower.contains($0) }
        return hasKeyword && postText.count > 20 && attachedVerseReference.isEmpty
    }

    // MARK: - Sensitive content expansion (liquid glass)

    private var sensitiveContentExpansion: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reason field
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.primary.opacity(0.4))
                TextField("Reason (optional — grief, trauma, etc.)", text: $sensitiveContentReason)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color.primary)
                    .accessibilityLabel("Sensitive content reason")
                    .accessibilityHint("Optionally describe why this content is sensitive")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))

            // Hide engagement counts toggle
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    hideEngagementCounts.toggle()
                }
                HapticManager.impact(style: .light)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: hideEngagementCounts ? "eye.slash.fill" : "eye")
                        .font(.systemScaled(12))
                        .foregroundStyle(hideEngagementCounts ? Color(hex: "6B48FF") : Color.primary.opacity(0.4))
                    Text("Hide likes & comments count")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(Color.primary.opacity(0.75))
                    Spacer()
                    Image(systemName: hideEngagementCounts ? "checkmark.circle.fill" : "circle")
                        .font(.systemScaled(16))
                        .foregroundStyle(hideEngagementCounts ? Color(hex: "6B48FF") : Color.primary.opacity(0.25))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Alt text sheet

    @ViewBuilder
    private var altTextSheetContent: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Array(selectedImageData.enumerated()), id: \.offset) { index, data in
                            VStack(alignment: .leading, spacing: 8) {
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                Text("Image \(index + 1) description")
                                    .font(AMENFont.semiBold(12))
                                    .foregroundStyle(.secondary)
                                TextField("Describe this image for screen readers…", text: Binding(
                                    get: { index < imageAltTexts.count ? imageAltTexts[index] : "" },
                                    set: { val in
                                        while imageAltTexts.count <= index { imageAltTexts.append("") }
                                        imageAltTexts[index] = val
                                    }
                                ), axis: .vertical)
                                .font(AMENFont.regular(14))
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .lineLimit(3...6)
                                .accessibilityLabel("Image \(index + 1) description")
                                .accessibilityHint("Describe this image for people using screen readers")
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Alt Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showAltTextSheet = false }
                        .font(AMENFont.semiBold(15))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Berean AI tone assist — fun interactive popup
    @ViewBuilder
    private var bereanToneSheetContent: some View {
        BereanTonePopup(
            suggestion: bereanToneSuggestion,
            onUse: { suggestion in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                postText = suggestion
                bereanToneSuggestion = nil
                showBereanToneSheet = false
            },
            onDismiss: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showBereanToneSheet = false
            }
        )
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground(.clear)
    }
    
    // ✅ HEY FEED: Think First prompt sheet content
    @ViewBuilder
    private var thinkFirstPromptSheetContent: some View {
        if let checkResult = thinkFirstCheckResult {
            ThinkFirstPromptSheet(
                checkResult: checkResult,
                originalText: pendingPostContent.isEmpty ? postText : pendingPostContent,
                onRevise: { revisedText in
                    showThinkFirstPrompt = false
                    thinkFirstCheckResult = nil
                    // Update post text with revised content
                    postText = revisedText
                    pendingPostContent = ""
                },
                onProceed: {
                    showThinkFirstPrompt = false
                    thinkFirstCheckResult = nil
                    let content = pendingPostContent.isEmpty ? sanitizeContent(postText) : pendingPostContent
                    let hasMedia = !selectedImageData.isEmpty || cameraCoordinator.attachedWitnessMedia != nil
                    Task { await runAlignmentGuardThenProceed(content: content, hasMedia: hasMedia) }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    private var placeholderText: String {
        switch selectedCategory {
        case .openTable:
            return "What's on your heart..."
        case .testimonies:
            return "Share your testimony..."
        case .prayer:
            return "How can we pray for you..."
        case .tip:
            return "Share a tip..."
        case .funFact:
            return "Share a fun fact..."
        }
    }
    
    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // TRUST & SAFETY: Show personalize nudge banner
                if showModerationNudge {
                    PersonalizeNudgeBanner(
                        message: moderationNudgeMessage,
                        isVisible: $showModerationNudge
                    )
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if selectedCategory == .openTable || selectedCategory == .prayer || selectedCategory == .testimonies {
                    topicTagSelectorView
                }
                if selectedCategory == .prayer || selectedCategory == .testimonies {
                    verseSelectorView
                }
                textEditorView

                // Witness camera preview
                if let attachment = cameraCoordinator.attachedWitnessMedia {
                    WitnessDraftAttachmentPreview(attachment: attachment) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            cameraCoordinator.removeAttachedMedia()
                        }
                    }
                    .padding(.horizontal, 20)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cameraCoordinator.attachedWitnessMedia != nil)
                }

                // Library photo grid
                if !selectedImageData.isEmpty {
                    ImagePreviewGrid(
                        images: $selectedImageData,
                        onAddMore: { showingImagePicker = true },
                        selectedIndex: AMENFeatureFlags.shared.perMediaCaptionsEnabled
                            ? $selectedMediaIndex
                            : nil
                    )
                    .padding(.horizontal, 20)
                }

                // Per-media caption composer — one caption per swipe
                if AMENFeatureFlags.shared.perMediaCaptionsEnabled,
                   !selectedImageData.isEmpty,
                   selectedMediaIndex < mediaMetadataDraft.frameCaptions.count {
                    PerMediaCaptionComposer(
                        draft: $mediaMetadataDraft.frameCaptions[selectedMediaIndex],
                        index: selectedMediaIndex,
                        totalCount: selectedImageData.count,
                        mediaType: .image,
                        altTextEnabled: AMENFeatureFlags.shared.perMediaCaptionAltTextEnabled,
                        scriptureEnabled: AMENFeatureFlags.shared.perMediaCaptionScriptureRefsEnabled,
                        isModerating: perMediaCaptionModeratingIndex == selectedMediaIndex,
                        isGeneratingAltText: perMediaCaptionGeneratingAltIndex == selectedMediaIndex,
                        statusMessage: perMediaCaptionStatusMessages[selectedMediaIndex],
                        errorMessage: perMediaCaptionErrorMessages[selectedMediaIndex],
                        onCaptionFocusChanged: { focused in
                            guard !focused else { return }
                            Task { await moderateMediaCaptionIfNeeded(index: selectedMediaIndex) }
                        },
                        onClearCaption: {
                            perMediaCaptionStatusMessages[selectedMediaIndex] = nil
                            perMediaCaptionErrorMessages[selectedMediaIndex] = nil
                            AMENAnalyticsService.shared.track(.mediaCaptionRemoved(mediaIndex: selectedMediaIndex, mediaType: "image"))
                        },
                        onScriptureTapped: {
                            activePerMediaCaptionEditor = PerMediaCaptionEditorRoute(index: selectedMediaIndex, kind: .scripture)
                        },
                        onReflectionTapped: {
                            activePerMediaCaptionEditor = PerMediaCaptionEditorRoute(index: selectedMediaIndex, kind: .reflection)
                        },
                        onAltTextTapped: {
                            activePerMediaCaptionEditor = PerMediaCaptionEditorRoute(index: selectedMediaIndex, kind: .altText)
                        },
                        onGenerateAltText: {
                            Task { await generateAltTextForMediaCaption(index: selectedMediaIndex) }
                        }
                    )
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id("caption-\(selectedMediaIndex)")
                    .onAppear {
                        AMENAnalyticsService.shared.track(.mediaCaptionComposerShown(mediaCount: selectedImageData.count))
                    }
                }

                // Poll composer card
                if showingPoll {
                    PollComposerCard(
                        options: $pollOptions,
                        duration: $pollDuration,
                        onRemove: {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                showingPoll = false
                                pollOptions = ["", ""]
                                pollDuration = .oneDay
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: showingPoll)
                }

                ComposerLinkPreview(controller: linkController)
                    .padding(.horizontal, 20)
                    .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8), value: linkController.activeURL)
                smartAttachmentComposerPreview
                    .padding(.horizontal, 20)

                // Rich link card — shown when user manually adds a link URL via the sheet
                if !linkURL.isEmpty && linkController.activeURL == nil {
                    LinkCardView(urlString: linkURL, onRemove: { linkURL = "" })
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8), value: linkURL)
                }

                if let scheduledDate = scheduledDate {
                    scheduleIndicatorView(scheduledDate: scheduledDate)
                }
                characterCountView
            }
        }
        .scrollDismissesKeyboard(.interactively) // ✅ Dismiss keyboard on scroll (swipe down)
        .contentShape(Rectangle()) // Make entire scroll view tappable
        .simultaneousGesture(TapGesture().onEnded {
            // ✅ Dismiss keyboard when tapping empty space (like Threads)
            // simultaneousGesture instead of onTapGesture so TextEditor's
            // long-press text selection (copy/paste) is not consumed.
            isTextFieldFocused = false
        })
    }
    
    // MARK: - Threads-Style Compose Components

    @ViewBuilder
    private var smartAttachmentComposerPreview: some View {
        if featureFlags.smartAttachmentsEnabled {
            switch smartAttachmentState {
            case .detecting, .resolving:
                AmenSmartAttachmentSkeletonCard()
            case .resolved(let attachment):
                VStack(alignment: .leading, spacing: 10) {
                    AmenUniversalLinkCard(
                        attachment: attachment,
                        mode: .composerPreview,
                        onTap: nil
                    )
                    if attachment.type == .song {
                        Toggle("Use this song as post soundtrack", isOn: $useSmartAttachmentAsSoundtrack)
                            .font(.systemScaled(13, weight: .medium))
                    }
                    if !mentionedLinkURLs.isEmpty {
                        Text("Mentioned Links (\(mentionedLinkURLs.count))")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Button("Remove attached media", role: .destructive) {
                        smartAttachment = nil
                        mentionedLinkURLs = []
                        smartAttachmentState = .empty
                        useSmartAttachmentAsSoundtrack = false
                        AMENAnalyticsService.shared.track(.musicAttachmentRemoved(provider: attachment.provider.rawValue))
                    }
                    .font(.systemScaled(12, weight: .semibold))
                }
            default:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func resolveSmartAttachmentIfNeeded(for text: String) {
        guard featureFlags.smartAttachmentComposerPasteEnabled else { return }
        smartAttachmentResolutionTask?.cancel()
        smartAttachmentResolutionTask = Task { @MainActor in
            let urls = smartAttachmentResolver.extractSupportedURLs(from: text)
            guard let url = urls.first else {
                if case .resolved = smartAttachmentState { return }
                smartAttachment = nil
                mentionedLinkURLs = []
                smartAttachmentState = .empty
                return
            }
            if smartAttachment?.canonicalUrl == url.absoluteString { return }
            mentionedLinkURLs = Array(urls.dropFirst())
            smartAttachmentState = .resolving
            do {
                let resolved = try await smartAttachmentResolver.resolve(url: url, source: "composerPaste")
                if resolved.safetyStatus == .blocked {
                    smartAttachment = nil
                    smartAttachmentState = .blocked("blocked")
                    return
                }
                smartAttachment = resolved
                smartAttachmentState = .resolved(resolved)
                AMENAnalyticsService.shared.track(.musicAttachmentResolved(provider: resolved.provider.rawValue, entityType: resolved.type.rawValue))
            } catch {
                smartAttachmentState = .failed(.resolveFailed)
            }
        }
    }

    private var canPublish: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !selectedImageData.isEmpty
        || cameraCoordinator.attachedWitnessMedia != nil
    }

    /// User row: avatar + name + category picker (Threads-style)
    private var threadsUserRow: some View {
        // Resolve photo URL: live profile takes priority, cached AppStorage as fallback
        let photoURLString = userService.currentUser?.profileImageURL?.nilIfEmpty
            ?? cachedProfileImageURL.nilIfEmpty
        // Resolve display name: prefer @username, fall back to display name
        let nameToShow = userService.currentUser?.username.nilIfEmpty
            ?? userService.currentUser?.displayName.nilIfEmpty
            ?? "you"
        let initial = String(nameToShow.prefix(1)).uppercased()

        return HStack(spacing: 12) {
            // Profile photo
            if let urlString = photoURLString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(initial)
                                .font(.systemScaled(18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            } else {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(initial)
                            .font(.systemScaled(18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("@\(nameToShow)")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let uid = Auth.auth().currentUser?.uid,
                       VerifiedBadgeHelper.shared.isVerified(userId: uid) {
                        VerifiedBadge(
                            type: VerifiedBadgeHelper.shared.getVerificationType(userId: uid),
                            size: 14
                        )
                    }
                }

                // Category selector as inline menu
                Menu {
                    ForEach(PostCategory.allCases.filter { $0 != .tip && $0 != .funFact }, id: \.self) { category in
                        Button {
                            handleCategorySelection(category)
                        } label: {
                            Label(category.displayName, systemImage: category.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedCategory.displayName)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(selectedCategory.primaryColor.opacity(0.85))
                        Image(systemName: "chevron.down")
                            .font(.systemScaled(9, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                }
            }
            .accessibilityLabel("Post category: \(selectedCategory.displayName)")
            .accessibilityHint("Choose a category for your post")

            Spacer()
        }
    }

    /// Inline attachment icons (Threads-style: simple gray icons in a row)
    /// The SF Symbol name the engine recommends highlighting, if any.
    private var recommendedAttachmentIcon: String? {
        insightEngine.result.primarySuggestion?.attachmentBarIcon
    }

    @ViewBuilder
    private var threadsAttachmentBar: some View {
        let recommended = recommendedAttachmentIcon
        let canAddPhotos = !showingPoll
        let canOpenCamera = !showingPoll
        let canCreatePoll = cameraCoordinator.attachedWitnessMedia == nil && selectedImageData.isEmpty
        HStack(spacing: 20) {
            attachmentBarIcon(
                "photo",
                recommended: recommended,
                accessibilityLabel: "Add photos",
                isEnabled: canAddPhotos,
                disabledHint: "Remove the poll before adding photos."
            ) {
                guard canAddPhotos else { return }
                showingImagePicker = true
            }
            attachmentBarIcon(
                "camera",
                recommended: recommended,
                accessibilityLabel: "Take photo",
                isEnabled: canOpenCamera,
                disabledHint: "Remove the poll before taking a photo."
            ) {
                guard canOpenCamera else { return }
                cameraCoordinator.openCamera(restoreComposerFocus: isTextFieldFocused)
            }
            attachmentBarIcon(
                "chart.bar.xaxis",
                recommended: recommended,
                accessibilityLabel: showingPoll ? "Remove poll" : "Create poll",
                isEnabled: canCreatePoll,
                disabledHint: "Remove photos before creating a poll."
            ) {
                guard canCreatePoll else { return }
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                    showingPoll.toggle()
                    if !showingPoll {
                        pollOptions = ["", ""]
                        pollDuration = .oneDay
                    }
                }
            }
            attachmentBarIcon("text.book.closed", recommended: recommended, accessibilityLabel: "Attach scripture") {
                showingVersePickerSheet = true
            }
            attachmentBarIcon(
                "music.note",
                recommended: recommended,
                accessibilityLabel: selectedMusicAttachment == nil ? "Attach music" : "Change attached music"
            ) {
                showMusicAttachmentPicker = true
            }
            attachmentBarIcon("link", recommended: recommended, accessibilityLabel: "Add link") {
                showingLinkSheet = true
            }
            attachmentBarIcon("calendar", recommended: recommended, accessibilityLabel: "Schedule post") {
                showingScheduleSheet = true
            }
            attachmentBarIcon("photo.on.rectangle.angled", recommended: recommended, accessibilityLabel: "Add GIF") {
                showingGIFPicker = true
            }
            attachmentBarIcon("face.smiling", recommended: recommended, accessibilityLabel: "Add sticker") {
                showingStickerPicker = true
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func attachmentBarIcon(
        _ icon: String,
        recommended: String?,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        disabledHint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isHighlighted = (icon == recommended)
        Button(action: action) {
            Image(systemName: icon)
                .font(.systemScaled(19, weight: .regular))
                .foregroundStyle(isHighlighted && isEnabled ? Color.primary.opacity(0.9) : Color.primary.opacity(isEnabled ? 0.45 : 0.20))
                .scaleEffect(isHighlighted ? 1.08 : 1.0)
                .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)), value: isHighlighted)
        }
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(disabledHint ?? "")
    }

    /// Bottom bar: reply options + action icons + character count + context panels
    private var threadsBottomBar: some View {
        VStack(spacing: 6) {

            // ── Verse suggestion pill (contextual, no button needed) ──────
            if shouldShowVerseSuggestion {
                Button { showingVersePickerSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.systemScaled(11))
                        Text("Attach a verse?")
                            .font(AMENFont.semiBold(12))
                        Image(systemName: "plus")
                            .font(.systemScaled(11, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "6B48FF"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color(hex: "6B48FF").opacity(0.3), lineWidth: 0.5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach a Bible verse")
                .accessibilityHint("Search and attach a scripture reference to your post")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Alt text prompt when images attached ─────────────────────
            if !selectedImageData.isEmpty {
                let allAlt = imageAltTexts.count == selectedImageData.count && imageAltTexts.allSatisfy { !$0.isEmpty }
                Button {
                    if imageAltTexts.count != selectedImageData.count {
                        imageAltTexts = Array(repeating: "", count: selectedImageData.count)
                    }
                    editingAltTextIndex = 0
                    showAltTextSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: allAlt ? "checkmark.circle.fill" : "text.bubble")
                            .font(.systemScaled(11))
                            .foregroundColor(allAlt ? .green : Color.primary.opacity(0.45))
                        Text(allAlt ? "Alt text added" : "Add alt text for accessibility")
                            .font(AMENFont.regular(12))
                            .foregroundColor(Color.primary.opacity(0.55))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(allAlt ? "Alt text added for all images" : "Add alt text for images")
                .accessibilityHint("Add descriptions for your images so screen reader users can understand them")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .transition(.opacity)
            }

            // ── Readiness hint ──────────────────────────────────────────────
            if insightEngine.result.readinessState == .tooShort {
                HStack(spacing: 5) {
                    Image(systemName: "text.badge.plus")
                        .font(.systemScaled(10, weight: .medium))
                    Text("Want to add more context?")
                        .font(AMENFont.regular(11))
                }
                .foregroundStyle(Color.primary.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Main icon row ─────────────────────────────────────────────
            HStack(spacing: 10) {
                // AI quick-actions button
                Button {
                    withAnimation(reduceMotion ? nil : .amenSpring) { showPostAICard.toggle() }
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(showPostAICard ? AmenTheme.Colors.amenBlue : Color.primary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI writing tools")
                .accessibilityHint("Opens AI options for improving your post")

                // Reply options — Liquid Glass capsule
                Button {
                    showCommentControls = true
                } label: {
                    Text(commentPermission == .everyone ? "Anyone can reply" : commentPermission.rawValue)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.80))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reply permission: \(commentPermission == .everyone ? "anyone" : commentPermission.rawValue)")
                .accessibilityHint("Change who can reply to this post")

                // Audience/Visibility selector — Liquid Glass capsule
                Button {
                    showingAudienceSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: postVisibility.icon)
                            .font(.systemScaled(11, weight: .medium))
                        Text(postVisibility.displayName)
                            .font(.systemScaled(12, weight: .medium))
                    }
                    .foregroundStyle(Color.primary.opacity(0.80))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Post visibility: \(postVisibility.displayName)")
                .accessibilityHint("Change who can see this post")

                Spacer()

                // Sensitive content toggle
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        hasSensitiveContent.toggle()
                        if !hasSensitiveContent {
                            sensitiveContentReason = ""
                            hideEngagementCounts = false
                        }
                    }
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: hasSensitiveContent ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(hasSensitiveContent ? .orange : Color.primary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasSensitiveContent ? "Remove content warning" : "Mark as sensitive")

                // Berean AI tone checker — only when text exists
                if !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    BereanToneButton(isLoading: isLoadingBereanTone) {
                        requestBereanToneAssist()
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Compose language detection chip
                if AMENFeatureFlags.shared.creationLanguageEnabled {
                    ComposeLanguageChip(text: postText)
                }

                // Character count — always visible, calms down at low counts
                if postText.count > 0 {
                    Text("\(postText.count)/500")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(
                            postText.count > 500 ? .red :
                            postText.count > 480 ? .orange :
                            .secondary.opacity(0.6)
                        )
                        .transition(.opacity.animation(.easeIn(duration: 0.3)))
                }
            }

            // ── Sensitive content expansion panel ─────────────────────────
            if hasSensitiveContent {
                sensitiveContentExpansion
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .opacity(insightEngine.result.readinessState == .empty ? 0.85 : 1.0)
        .overlay(alignment: .bottomLeading) {
            if showPostAICard {
                PostAIGlassCard(
                    onImproveWriting: {
                        withAnimation(reduceMotion ? nil : .amenSpring) { showPostAICard = false }
                        requestBereanToneAssist()
                    },
                    onFindScripture: {
                        withAnimation(reduceMotion ? nil : .amenSpring) { showPostAICard = false }
                        showingVersePickerSheet = true
                    },
                    onAddHashtags: {
                        withAnimation(reduceMotion ? nil : .amenSpring) { showPostAICard = false }
                        showingSuggestions = true
                    }
                )
                .offset(y: -8)
                .transition(.scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .amenSpring, value: showPostAICard)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8)), value: hasSensitiveContent)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8)), value: shouldShowVerseSuggestion)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: selectedImageData.count)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: insightEngine.result.readinessState)
    }

    // MARK: - View Components
    
    private var categorySelectorView: some View {
        GlassCategoryBar(
            categories: PostCategory.allCases.filter { $0 != .tip && $0 != .funFact },
            selected: $selectedCategory,
            namespace: categoryNamespace
        ) { category in
            handleCategorySelection(category)
        }
    }
    
    private var topicTagSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            topicTagHeaderView
            
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showingTopicTagSheet = true
                }
            } label: {
                topicTagButtonContent
            }
            .accessibilityLabel(selectedTopicTag.isEmpty ? "Add topic tag" : "Topic tag: \(selectedTopicTag)")
            .accessibilityHint("Choose a topic tag for your post")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var topicTagHeaderView: some View {
        HStack {
            Image(systemName: "tag.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.red)
            
            Text(selectedCategory == .testimonies ? "Testimony Category" : selectedCategory == .openTable ? "Topic Tag" : "Prayer Type")
                .font(AMENFont.bold(15))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if selectedTopicTag.isEmpty {
                Text("Optional")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                    )
            }
        }
    }
    
    private var topicTagButtonContent: some View {
        HStack {
            if selectedTopicTag.isEmpty {
                HStack(spacing: 6) {
                    Text(selectedCategory == .testimonies ? "Select a category (optional)" : selectedCategory == .openTable ? "Select a topic tag" : "Select prayer type")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.secondary)
                    Text("Optional")
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            } else {
                // Show icon for prayer types
                if selectedCategory == .prayer {
                    Image(systemName: prayerTypeIcon(for: selectedTopicTag))
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(prayerTypeColor(for: selectedTopicTag))
                }
                
                Text(selectedTopicTag)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Audience Selector

    private var audienceSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Audience")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                Spacer()
            }

            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showingAudienceSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: postVisibility.icon)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(postVisibility.tintColor)
                    Text(postVisibility.displayName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Audience: \(postVisibility.displayName)")
            .accessibilityHint("Double tap to change who can see this post")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Verse Picker

    private var verseSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Scripture")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Optional")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
            }

            if let attachment = verseAttachmentVM.attachedScripture {
                // New Liquid Glass pill design
                AttachedScripturePill(
                    attachment: attachment,
                    onTap: {
                        verseAttachmentVM.openScriptureDetail(from: .composer)
                    },
                    onReplace: {
                        verseAttachmentVM.openQuickReplace()
                    },
                    onRemove: {
                        verseAttachmentVM.removeAttachment()
                        attachedVerseReference = ""
                        attachedVerseText = ""
                    },
                    onViewChapter: {
                        verseAttachmentVM.openScriptureDetail(from: .composer)
                    },
                    onCopyReference: {
                        UIPasteboard.general.string = attachment.canonicalReference
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !attachedVerseReference.isEmpty {
                // Legacy fallback
                LiquidGlassAttachedVerseBadge(
                    reference: attachedVerseReference,
                    text: attachedVerseText,
                    onRemove: {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            attachedVerseReference = ""
                            attachedVerseText = ""
                        }
                    },
                    onEdit: { showingVersePickerSheet = true }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Empty state — attach CTA
                Button {
                    showingVersePickerSheet = true
                } label: {
                    HStack {
                        Text("Attach a Bible verse")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.78)), value: verseAttachmentVM.attachedScripture != nil)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.78)), value: attachedVerseReference.isEmpty)
    }

    // MARK: - Church Tag

    private var churchTagView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "building.columns.fill")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("Tag a Church")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Optional")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
            }

            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showingChurchTagSheet = true
                }
            } label: {
                HStack {
                    if taggedChurchName.isEmpty {
                        Text("Tag your church")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(taggedChurchName)
                            .font(AMENFont.bold(15))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if !taggedChurchName.isEmpty {
                        Button {
                            withAnimation(reduceMotion ? nil : .default) {
                                taggedChurchId = ""
                                taggedChurchName = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var textEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ComposerRichTextEditor(
                        text: $postText,
                        richSpans: $richSpans,
                        maxLength: 500
                    )
                    .focused($isTextFieldFocused)
                    .frame(minHeight: 140)
                    .accessibilityLabel("Post content")
                    .onChange(of: postText) { oldValue, newValue in
                            // Defer side effects so they don't trigger a re-render mid-paste,
                            // which would interrupt the paste operation on SwiftUI TextEditor.
                            let addedLength = newValue.count - oldValue.count
                            let snapshot = newValue
                            Task { @MainActor in
                                // Track typing vs pasting for authenticity signals
                                if addedLength > 50 {
                                    let pastedText = String(snapshot.suffix(addedLength))
                                    integrityTracker.trackPaste(text: pastedText)
                                } else if addedLength > 0 {
                                    integrityTracker.trackTyping(addedCharacters: addedLength)
                                }
                                detectHashtags(in: snapshot)
                            }
                            linkController.handleTextChange(newValue)
                            resolveSmartAttachmentIfNeeded(for: newValue)
                            // Smart composition insight analysis
                            insightEngine.analyzeText(
                                newValue,
                                category: selectedCategory.rawValue,
                                hasVerse: !attachedVerseReference.isEmpty,
                                hasTopicTag: !selectedTopicTag.isEmpty,
                                hasPoll: showingPoll,
                                hasImages: !selectedImageData.isEmpty
                            )
                            // P1-4: Debounced autosave — saves 3s after user stops typing
                            scheduleAutosave()
                            // Scripture intent detection for inline suggestions
                            verseAttachmentVM.analyzeDraftText(newValue)
                            scheduleSupportDraftAnalysis(for: newValue)
                            spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: newValue)
                            safetyOSDraftTriggers = AmenLocalTriggerEngine.shared.analyze(text: newValue, surface: .post)
                            safetyOSCanonicalTask?.cancel()
                            safetyOSCanonicalTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                guard !Task.isCancelled, postText == newValue else { return }
                                safetyOSDraftTriggers = AmenLocalTriggerEngine.shared.analyze(
                                    text: newValue,
                                    surface: .post
                                )
                            }
                            contextualComposerObserver.update(text: newValue)
                            if featureFlags.guideMyFeedEnabled {
                                feedDirectionDetection = AmenFeedDirectionDetector.shared.detect(text: newValue)
                            } else {
                                feedDirectionDetection = .empty
                            }
                            Task { await scriptureDetectService.detect(in: snapshot) }
                        }

                    // Placeholder overlay
                    if postText.isEmpty {
                        EditorPlaceholderView(
                            isEmpty: postText.isEmpty,
                            placeholder: placeholderText,
                            description: selectedCategory.description
                        )
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(minHeight: 200)
            
            // Smart hashtag suggestions
            if showingSuggestions && !hashtagSuggestions.isEmpty {
                hashtagSuggestionsView
            }
            
            // MARK: - ✅ Mention Suggestions
            if showMentionSuggestions && !mentionSuggestions.isEmpty {
                mentionSuggestionsView
            }
            
            // MARK: - Tagged People Chips
            if !taggedUsers.isEmpty {
                taggedUsersChipsView
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var supportDraftPresentation: some View {
        if let payload = supportDraftPayload {
            switch payload.presentationMode {
            case .none, .sheet:
                EmptyView()
            case .chips(let chips):
                SupportChipsRowView(
                    chips: chips,
                    onTap: handleSupportDraftAction(_:),
                    onDismiss: dismissSupportDraftPrompt
                )
                .padding(.horizontal, 4)
            case .inlineCard(let model):
                SupportInlineCardView(
                    model: model,
                    actions: payload.actions,
                    onTap: handleSupportDraftAction(_:),
                    onDismiss: dismissSupportDraftPrompt
                )
                .padding(.horizontal, 4)
            }
        }
    }
    
    private var taggedUsersChipsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "person.badge.plus")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(Color.purple)
                Text("Tagged")
                    .font(AMENFont.bold(12))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(taggedUsers, id: \.userId) { user in
                        HStack(spacing: 5) {
                            Text("@\(user.username)")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(.purple)
                            Button {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                    taggedUsers.removeAll { $0.userId == user.userId }
                                }
                                HapticManager.impact(style: .light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.systemScaled(9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.08))
                                .overlay(Capsule().strokeBorder(Color.purple.opacity(0.2), lineWidth: 1))
                        )
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Mention Suggestions View

    private var mentionSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section label
            HStack(spacing: 5) {
                Image(systemName: "at")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Mention User")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 14)

            VStack(spacing: 0) {
                ForEach(mentionSuggestions, id: \.objectID) { user in
                    AlgoliaMentionSuggestionRow(user: user) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        insertMention(user)
                    }

                    if user.objectID != mentionSuggestions.last?.objectID {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.78), value: mentionSuggestions.count)
    }
    
    private var hashtagSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                
                Text("Suggested Hashtags")
                    .font(AMENFont.bold(13))
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hashtagSuggestions, id: \.self) { tag in
                        Button {
                            insertHashtag(tag)
                        } label: {
                            Text(tag)
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.1))
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func scheduleIndicatorView(scheduledDate: Date) -> some View {
        // Premium widget-style schedule indicator — matches SchedulePostSheet design language
        let accent     = Color(red: 0.98, green: 0.82, blue: 0.18)
        let accentDark = Color(red: 0.14, green: 0.10, blue: 0.02)
        let ink        = Color(red: 0.10, green: 0.10, blue: 0.10)

        return HStack(spacing: 0) {
            // Left accent block — day number
            VStack(spacing: 1) {
                Text(scheduledDate, format: .dateTime.weekday(.abbreviated))
                    .font(AMENFont.bold(9))
                    .foregroundStyle(accentDark.opacity(0.75))
                    .tracking(0.8)
                    .textCase(.uppercase)
                Text(scheduledDate, format: .dateTime.day())
                    .font(.systemScaled(22, weight: .black))
                    .foregroundStyle(accentDark)
            }
            .frame(width: 48)
            .padding(.vertical, 10)
            .background(accent)

            // Right info section
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduled for")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(ink.opacity(0.50))
                    ScheduledWhenLine(date: scheduledDate)
                }
                Spacer()
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        self.scheduledDate = nil
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(ink.opacity(0.07))
                            .frame(width: 28, height: 28)
                        Image(systemName: "xmark")
                            .font(.systemScaled(10, weight: .bold))
                            .foregroundStyle(ink.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.97, green: 0.97, blue: 0.95))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.07), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .transition(.scale.combined(with: .opacity))
    }

    private var characterCountView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: characterCountIcon)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(characterCountColor)
                    
                    Text(characterCountText)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(characterCountColor)
                }
                
                // Enhanced validation messages
                if postText.count > 500 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.systemScaled(10))
                        Text("Character limit exceeded - cannot post")
                            .font(AMENFont.bold(11))
                    }
                    .foregroundStyle(.red)
                } else if postText.count > 450 {
                    Text("Consider shortening your post")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private func handleCategorySelection(_ category: PostCategory) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selectedCategory = category
            updateHashtagSuggestions()
        }
        // P1-3: Prayer posts default to followers-only comments for privacy
        if category == .prayer {
            commentPermission = .followersOnly
            allowComments = true
        }
    }
    
    // MARK: - Prayer Type Helpers
    private func prayerTypeIcon(for type: String) -> String {
        switch type {
        case "Prayer Request":
            return "hands.sparkles.fill"
        case "Praise Report":
            return "hands.clap.fill"
        case "Answered Prayer":
            return "checkmark.seal.fill"
        default:
            return "hands.sparkles.fill"
        }
    }
    
    private func prayerTypeColor(for type: String) -> Color {
        switch type {
        case "Prayer Request":
            return Color(red: 0.4, green: 0.7, blue: 1.0)
        case "Praise Report":
            return Color(red: 1.0, green: 0.7, blue: 0.4)
        case "Answered Prayer":
            return Color(red: 0.4, green: 0.85, blue: 0.7)
        default:
            return Color(red: 0.4, green: 0.7, blue: 1.0)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Map CommentPermissionLevel to Post.CommentPermissions
    private func mapToPostCommentPermissions(_ level: CommentPermissionLevel) -> Post.CommentPermissions {
        switch level {
        case .everyone:
            return .everyone
        case .followersOnly:
            return .following
        case .mutualsOnly:
            return .mentioned  // Stored as "mentioned" in Firestore; CommentService maps it back to .mutualsOnly → enforces mutual-follow check correctly
        case .nobody:
            return .off
        }
    }
    
    /// Display user-friendly error message
    // P1-6 FIX: Enhanced error handling with retry support
    private func showError(title: String = "Oops!", message: String, isRetryable: Bool = false, retry: (() -> Void)? = nil) {
        errorTitle = title
        errorMessage = message
        isRetryableError = isRetryable
        retryAction = retry
        showingErrorAlert = true
    }

    private var errorAlertConfig: LiquidGlassAlertConfig {
        LiquidGlassAlertConfig(
            title: errorTitle,
            message: errorMessage,
            icon: "exclamationmark.triangle",
            primaryButton: isRetryableError
                ? LiquidGlassAlertButton("Retry", tone: .primary) {
                    retryAction?()
                }
                : LiquidGlassAlertButton("OK", tone: .dismiss) {
                    stopPublishAttempt()
                },
            secondaryButton: isRetryableError
                ? LiquidGlassAlertButton.cancel {
                    activePublishTask?.cancel()
                    activePublishTask = nil
                    stopPublishAttempt()
                    isRetryableError = false
                    retryAction = nil
                }
                : nil
        )
    }

    /// Show crisis resources alert when crisis is detected in prayer request
    private func showCrisisResourcesAlert(crisisResult: CrisisDetectionResult) {
        let resourcesText = crisisResult.recommendedResources.map { resource in
            "\(resource.displayName): \(resource.phoneNumber)"
        }.joined(separator: "\n")
        
        let alert = UIAlertController(
            title: "🙏 We're Here for You",
            message: """
            We noticed your prayer request may indicate you're going through a difficult time.
            
            Please consider reaching out to these resources for immediate support:
            
            \(resourcesText)
            
            You are not alone. Help is available 24/7.
            """,
            preferredStyle: .alert
        )
        
        // Add "Call Now" buttons for critical resources
        if crisisResult.urgencyLevel == .critical {
            for resource in crisisResult.recommendedResources.prefix(2) {
                alert.addAction(UIAlertAction(title: "Call \(resource.displayName)", style: .default) { _ in
                    if let url = URL(string: "tel://\(resource.phoneNumber.replacingOccurrences(of: "-", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                })
            }
        }
        
        // View Resources button
        alert.addAction(UIAlertAction(title: "View All Resources", style: .default) { _ in
            // Navigate to Resources view
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               windowScene.windows.first?.rootViewController != nil {
                // Present resources view
            }
        })
        
        // Continue Posting button
        alert.addAction(UIAlertAction(title: "Continue Posting", style: .cancel))
        
        // Present alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
    
    /// Convert technical errors to user-friendly messages
    private func getUserFriendlyError(from error: Error) -> (title: String, message: String) {
        let nsError = error as NSError
        
        // Network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return ("No Internet Connection", "Please check your internet connection and try again.")
            case NSURLErrorTimedOut:
                return ("Connection Timeout", "The request took too long. Please try again.")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return ("Connection Failed", "Unable to connect to the server. Please try again later.")
            default:
                return ("Network Error", "A network error occurred. Please check your connection and try again.")
            }
        }
        
        // Firebase Auth errors
        if nsError.domain == "FIRAuthErrorDomain" {
            return ("Authentication Error", "Your session may have expired. Please sign in again.")
        }
        
        // Storage errors
        if error.localizedDescription.contains("storage") || error.localizedDescription.contains("upload") {
            return ("Upload Failed", "We couldn't upload your images. Please check your connection and try again.")
        }
        
        // Firestore errors
        if nsError.domain == "FIRFirestoreErrorDomain" {
            switch nsError.code {
            case 7: // Permission denied
                return ("Permission Denied", "You don't have permission to perform this action.")
            case 14: // Unavailable
                return ("Service Unavailable", "The service is temporarily unavailable. Please try again in a moment.")
            default:
                return ("Database Error", "We couldn't save your post. Please try again.")
            }
        }
        
        // Image compression errors
        if error.localizedDescription.contains("compress") || error.localizedDescription.contains("ImageCompression") {
            return ("Image Processing Failed", "We couldn't process your images. Try using smaller images or fewer photos.")
        }
        
        // Default error
        return ("Something Went Wrong", "An unexpected error occurred. Please try again.")
    }
    
    /// Sanitizes user input to prevent malicious content
    private func sanitizeContent(_ content: String) -> String {
        // Trim whitespace and newlines
        var sanitized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit consecutive newlines to max 2
        while sanitized.contains("\n\n\n") {
            sanitized = sanitized.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return sanitized
    }
    
    /// Validates URL format
    private func isValidURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            return false
        }
        return true
    }
    
    private func updateHashtagSuggestions() {
        // Optimistic fallback per category while Firestore loads
        let fallback: [String]
        switch selectedCategory {
        case .openTable:
            fallback = ["#AIandFaith", "#TechEthics", "#Innovation", "#DigitalMinistry", "#TechForGood"]
        case .testimonies:
            fallback = ["#Testimony", "#FaithJourney", "#Blessed", "#Miracle", "#GodIsGood"]
        case .prayer:
            fallback = ["#PrayerRequest", "#PraiseReport", "#Intercession", "#DailyPrayer", "#PrayerWarrior"]
        case .tip:
            fallback = ["#TipOfTheDay", "#HelpfulTips", "#ProTip", "#LifeHack", "#Advice"]
        case .funFact:
            fallback = ["#FunFact", "#DidYouKnow", "#Interesting", "#TodayILearned", "#Facts"]
        }
        hashtagSuggestions = fallback

        // Fetch live trending tags from Firestore in background
        let categoryKey = selectedCategory.rawValue
        Task {
            do {
                let snapshot = try await FirebaseManager.shared.firestore
                    .collection("trendingHashtags")
                    .whereField("category", isEqualTo: categoryKey)
                    .order(by: "useCount", descending: true)
                    .limit(to: 8)
                    .getDocuments()

                let liveTags = snapshot.documents.compactMap { doc -> String? in
                    guard let tag = doc.data()["tag"] as? String else { return nil }
                    return tag.hasPrefix("#") ? tag : "#\(tag)"
                }

                if !liveTags.isEmpty {
                    await MainActor.run {
                        hashtagSuggestions = liveTags
                    }
                }
            } catch {
                // Network failure — fallback already shown, silently skip
                dlog("⚠️ [Hashtags] Firestore fetch failed, using fallback: \(error.localizedDescription)")
            }
        }
    }
    
    private func detectHashtags(in text: String) {
        // Detect if user is typing a hashtag
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        if let lastWord = words.last, lastWord.hasPrefix("#") && lastWord.count > 1 {
            withAnimation(reduceMotion ? nil : .default) {
                showingSuggestions = true
            }
        }

        // MARK: - Mention Detection
        // Detect if user is typing a mention (@username)
        if let lastWord = words.last, lastWord.hasPrefix("@") && lastWord.count > 1 {
            currentMentionQuery = String(lastWord.dropFirst()) // Remove @
            searchForMentions(query: currentMentionQuery)
        } else {
            withAnimation(reduceMotion ? nil : .default) {
                showMentionSuggestions = false
                mentionSuggestions = []
            }
        }
    }

    private func insertHashtag(_ tag: String) {
        if postText.isEmpty || postText.last == " " {
            postText += tag + " "
        } else {
            postText += " " + tag + " "
        }

        withAnimation(reduceMotion ? nil : .default) {
            showingSuggestions = false
        }
    }
    
    // MARK: - Berean AI Tone Assist
    
    private func requestBereanToneAssist() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isLoadingBereanTone else { return }
        isLoadingBereanTone = true
        let draft = postText
        let userId = FirebaseManager.shared.currentUser?.uid ?? ""
        Task {
            do {
                let rawResponse = try await BereanOrchestrator.shared.getPostToneSuggestions(
                    draft: draft,
                    userId: userId
                )
                // Parse the JSON response — we only want the suggestedRewrite string
                let rewrite = Self.extractSuggestedRewrite(from: rawResponse)
                await MainActor.run {
                    if let rewrite {
                        bereanToneSuggestion = rewrite
                        isLoadingBereanTone = false
                        showBereanToneSheet = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } else {
                        // No rewrite needed — tone is already good
                        isLoadingBereanTone = false
                        // Show brief confirmation that tone is great
                        bereanToneSuggestion = nil
                        showBereanToneSheet = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            } catch {
                dlog("⚠️ [Berean] Post tone assist unavailable: \(error)")
                await MainActor.run {
                    isLoadingBereanTone = false
                }
            }
        }
    }

    /// Extracts the `suggestedRewrite` field from the Berean JSON response.
    /// Returns nil if the rewrite is null/absent (meaning tone is already good).
    private static func extractSuggestedRewrite(from jsonString: String) -> String? {
        // Strip markdown code fences if present
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n")
                .dropFirst()              // remove ```json line
                .dropLast()              // remove closing ```
                .joined(separator: "\n")
        }
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not valid JSON — return the raw string trimmed as a fallback
            let fallback = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? nil : fallback
        }
        // suggestedRewrite can be a String or NSNull
        if let rewrite = json["suggestedRewrite"] as? String,
           !rewrite.isEmpty,
           rewrite.lowercased() != "null" {
            return rewrite
        }
        return nil
    }
    
    private func saveDraft(showNotice: Bool = true) {
        guard hasDraftableContent else { return }

        // Save post using DraftsManager
        draftsManager.saveDraft(
            content: postText,
            category: selectedCategory.rawValue,
            topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
            linkURL: linkURL.isEmpty ? nil : linkURL,
            visibility: postVisibility.rawValue,
            scriptureAttachment: verseAttachmentVM.attachedScripture,
            witnessAttachment: cameraCoordinator.attachedWitnessMedia,
            showingPoll: showingPoll,
            pollQuestion: pollQuestion,
            pollOptions: pollOptions,
            pollDurationRawValue: pollDuration.rawValue,
            isThreadMode: isThreadMode,
            threadPosts: threadPosts,
            currentThreadIndex: currentThreadIndex
        )

        guard showNotice else { return }

        withAnimation(reduceMotion ? nil : .default) {
            showingDraftSavedNotice = true
        }

        // P0-2 FIX: Use cancellable task instead of DispatchQueue
        scheduleDelayedAction(seconds: 2) {
            withAnimation(reduceMotion ? nil : .default) {
                showingDraftSavedNotice = false
            }
        }
    }

    private func persistDraftIfNeeded() {
        guard shouldPersistDraftOnExit, !isPublishing else { return }
        autoSaveDraft()
        saveDraft(showNotice: false)
    }

    @MainActor
    private func trackPendingUploadCleanupPath(_ path: String) {
        pendingUploadCleanupPaths.insert(path)
    }

    @MainActor
    private func clearPendingUploadCleanupPaths() {
        pendingUploadCleanupPaths.removeAll()
    }

    @MainActor
    private func cleanupPendingUploadArtifacts() {
        let paths = pendingUploadCleanupPaths
        pendingUploadCleanupPaths.removeAll()
        for path in paths {
            deleteStorageFolder(path: path)
        }
    }

    /// Triggers a short shake animation on the publish button to signal rejection.
    private func triggerPublishShake() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.error)
        withAnimation(reduceMotion ? nil : .default) {
            shakePublishButton = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            shakePublishButton = false
        }
    }

    private func scheduleSupportDraftAnalysis(for text: String) {
        supportDraftTask?.cancel()
        bypassSupportDraftGate = false

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            supportDraftPayload = nil
            return
        }

        supportDraftTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }

            let payload = await supportDetectionService.analyzeSupport(
                surface: .postDraft,
                text: trimmed,
                metadata: [
                    "category": selectedCategory.rawValue,
                    "hasImages": selectedImageData.isEmpty ? "false" : "true",
                    "hasWitnessMedia": cameraCoordinator.attachedWitnessMedia == nil ? "false" : "true",
                    "hasVerse": attachedVerseReference.isEmpty ? "false" : "true"
                ]
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                supportDraftPayload = payload
                if let payload {
                    supportDetectionService.record(payload: payload, outcome: .shown)
                }
            }
        }
    }

    private func handleSupportDraftAction(_ action: SupportAction) {
        guard let payload = supportDraftPayload else { return }
        supportActionExecutor.execute(action, from: .postDraft)
        supportDetectionService.record(payload: payload, outcome: .engaged)
        showSupportDraftSheet = false
    }

    private func dismissSupportDraftPrompt() {
        if let payload = supportDraftPayload {
            supportDetectionService.record(payload: payload, outcome: .dismissed)
        }
        supportDraftPayload = nil
        showSupportDraftSheet = false
    }

    @MainActor
    private func continuePostAfterSupportPrompt() {
        bypassSupportDraftGate = true
        showSupportDraftSheet = false
        publishPost()
    }

    private func shouldPresentSupportDraftGate(for text: String) -> Bool {
        guard !bypassSupportDraftGate,
              let payload = supportDraftPayload,
              payload.analyzedText == text,
              case .sheet = payload.presentationMode else {
            return false
        }

        return true
    }

    @MainActor
    private func publishPost() {
        guard !isPublishing else {
            dlog("⚠️ Already publishing, skipping")
            return
        }

        guard inFlightPostId == nil else {
            dlog("⚠️ [P0-1] Duplicate post blocked (in-flight id: \(inFlightPostId ?? "unknown"))")
            return
        }

        // CF-01 Part A: Generate or reuse an idempotency key for this publish attempt.
        // Reusing the same key on retry ensures the backend (and the duplicate-check
        // below) can detect and skip a write that already succeeded.
        let idempotencyKey = postIdempotencyKey ?? UUID().uuidString
        postIdempotencyKey = idempotencyKey
        dlog("🔑 [CF-01] postIdempotencyKey: \(idempotencyKey)")

        dlog("🔵 publishPost() called")
        dlog("   isPublishing: \(isPublishing)")
        dlog("   canPost: \(canPost)")

        // Smart community guidelines gate — checks first post, session, 30-day inactivity
        if CommunityGuidelinesEligibilityService.shared.shouldShowGuidelines {
            showGuidelinesGate = true
            return  // publishPost() will be called again after user acknowledges
        }

        // Cancel auto-save immediately — no point saving a post that's about to be published
        autoSaveTask?.cancel()
        autoSaveTask = nil
        
        // Cancel in-flight mention search (keyboard is about to be dismissed)
        mentionSearchTask?.cancel()
        mentionSearchTask = nil
        showMentionSuggestions = false
        mentionSuggestions = []
        
        // P0-4 FIX: Check rate limiting before posting
        if rateLimiter.isRateLimited(for: .post) {
            let unlockMessage: String
            if let unlockDate = rateLimiter.getUnlockTime(for: .post) {
                let seconds = Int(unlockDate.timeIntervalSinceNow)
                let mins = max(1, (seconds + 59) / 60)
                unlockMessage = "You can post again at \(CreatePostView.shortTimeFormatter.string(from: unlockDate)) (\(mins) min\(mins == 1 ? "" : "s") from now)."
            } else {
                unlockMessage = "Please wait a few minutes before sharing more."
            }
            showError(
                title: "Slow Down",
                message: "You're posting quite frequently. \(unlockMessage)"
            )
            inFlightPostId = nil
            return
        }
        
        // OFFLINE FIX: Block post submission when device has no network.
        // Firestore offline persistence does NOT queue creates reliably — the
        // write may silently succeed locally but never reach the server if the
        // connection drops before the document propagates. Surface an explicit
        // error so the user knows to retry after reconnecting.
        if !AMENNetworkMonitor.shared.isConnected {
            showError(
                title: "You're Offline",
                message: "Your post couldn't be sent — please check your connection and try again.",
                isRetryable: true,
                retry: { self.publishPost() }
            )
            return
        }

        // Auth check must pass before any upload or session work begins.
        guard Auth.auth().currentUser?.uid != nil else {
            showError(title: "Not Signed In", message: "Please sign in again to post.")
            return
        }

        // Seed the durable publish session immediately. This ID is reused as the
        // Firestore document ID, upload group, and idempotency key across retries.
        let publishToken = ensurePendingPublishSession()
        inFlightPostId = publishToken
        draftVM.markPublishing(token: publishToken)
        
        // Dismiss keyboard
        isTextFieldFocused = false
        
        // Validate content
        let sanitizedContent = sanitizeContent(postText)
        dlog("📝 Post content: '\(sanitizedContent)'")
        dlog("   Content length: \(sanitizedContent.count)")

        // Media-only posts (photos, videos, witness captures) are valid without caption text.
        let hasAttachedMedia = !selectedImageData.isEmpty || cameraCoordinator.attachedWitnessMedia != nil
        guard !sanitizedContent.isEmpty || hasAttachedMedia else {
            dlog("❌ Empty post detected (no text, no media)")
            stopPublishAttempt()
            showError(
                title: "Empty Post",
                message: "Please write something before posting."
            )
            return
        }
        
        guard sanitizedContent.count <= 500 else {
            dlog("❌ Post too long: \(sanitizedContent.count) characters")
            stopPublishAttempt()
            showError(
                title: "Post Too Long",
                message: "Your post is \(sanitizedContent.count - 500) characters over the limit. Please shorten it to 500 characters or less."
            )
            return
        }

        if let trigger = safetyOSDraftTriggers.first(where: \.shouldShowDiscernmentSheet), !bypassSpiritualDiscernmentGate {
            stopPublishAttempt()
            activeSafetyOSTrigger = trigger
            return
        }

        if spiritualComposeAnalysis.shouldShowDiscernmentGate && !bypassSpiritualDiscernmentGate {
            stopPublishAttempt()
            showSpiritualDiscernmentGate = true
            return
        }
        bypassSpiritualDiscernmentGate = false
        
        // Validate link URL if provided
        if !linkURL.isEmpty && !isValidURL(linkURL) {
            dlog("❌ Invalid link URL: \(linkURL)")
            stopPublishAttempt()
            showError(
                title: "Invalid Link",
                message: "The link you provided is not valid. Please enter a complete URL starting with http:// or https://"
            )
            return
        }
        
        // Validate image count
        if selectedImageData.count > 4 {
            dlog("❌ Too many images: \(selectedImageData.count)")
            stopPublishAttempt()
            showError(
                title: "Too Many Images",
                message: "You can only attach up to 4 images per post. Please remove \(selectedImageData.count - 4) image(s)."
            )
            return
        }

        if let perMediaCaptionMessage = perMediaCaptionValidationMessageForPublish() {
            stopPublishAttempt()
            showError(
                title: "Check Media Captions",
                message: perMediaCaptionMessage
            )
            return
        }

        if let scriptureMessage = scriptureValidationMessageForPublish() {
            stopPublishAttempt()
            showError(
                title: "Check Scripture",
                message: scriptureMessage
            )
            return
        }

        // Wellness pause: reflect before posting borderline or session-escalated content
        if !wellnessClearedForPublish,
           let wellnessCtx = AmenWellnessInterventionService.shared.checkBeforePost(text: sanitizedContent) {
            stopPublishAttempt()
            pendingWellnessContext = wellnessCtx
            return
        }
        wellnessClearedForPublish = false

        dlog("✅ All validations passed!")

        // ============================================================================
        // ✅ HEY FEED: Think First Guardrails + MODERATION CONSTITUTION Stage 1
        // ============================================================================
        if hasAttachedMedia {
            beginUploadCapsuleSession()
        }

        // P1-5: Show loading state immediately so the user gets feedback during safety evaluation
        isPublishing = true
        let _publishPerfToken = PerfBegin("post_safety_gauntlet")
        Task {
            defer { PerfEnd(_publishPerfToken, threshold: 500) }
            // ── Support gate: check before any network/moderation work ──
            if shouldPresentSupportDraftGate(for: sanitizedContent) {
                stopPublishAttempt()
                showSupportDraftSheet = true
                return
            }
            // ── Stage 1: ModerationIngestService (local guard + doxxing + grooming) ──
            guard let authorId = Auth.auth().currentUser?.uid else {
                await MainActor.run {
                    stopPublishAttempt()
                    showError(title: "Not Signed In", message: "Please sign in again to post.")
                }
                return
            }
            let ingestContentType: ModerationContentType = {
                switch selectedCategory {
                case .prayer: return .prayer
                case .testimonies: return .testimony
                default: return .post
                }
            }()

            let preSubmitResult = await ModerationIngestService.shared.check(
                text: sanitizedContent,
                contentType: ingestContentType,
                authorId: authorId
            )

            switch preSubmitResult {
            case .block(let reason, _):
                await MainActor.run {
                    presentBlockedUploadCapsule(reason: reason)
                    stopPublishAttempt()
                    draftVM.markModerationBlocked()
                    showError(title: "Can't Post This", message: reason)
                }
                return
            case .requireEdit(let message, let redacted):
                await MainActor.run {
                    presentFailedUploadCapsule(message: message)
                    stopPublishAttempt()
                    draftVM.markModerationEditRequired()
                    if let redacted { postText = redacted }
                    showError(title: "Edit Required", message: message)
                }
                return
            case .softPrompt(let message, let canOverride):
                if !canOverride {
                    await MainActor.run {
                        presentFailedUploadCapsule(message: message)
                        stopPublishAttempt()
                        showError(title: "Content Notice", message: message)
                    }
                    return
                }
                dlog("⚠️ [ModerationIngest] Soft prompt (continuing): \(message)")
            case .allow:
                break
            }

            // ── Trust + Safety backend preflight (authoritative) ──────────────
            if AmenSafetyFeatureFlags.shared.contentPreflightEnabled,
               !AmenSafetyFeatureFlags.shared.trustSafetyKillSwitch {
                if !botChallengeCleared {
                    let botOutcome = await AmenBotDefenseService.shared.evaluateBeforeAction(type: .post)
                    if botOutcome != .proceed {
                        await MainActor.run {
                            stopPublishAttempt()
                            if botOutcome == .challengeRequired {
                                showBotChallenge = true
                            } else {
                                showError(
                                    title: "Slow Down",
                                    message: "Please slow down before posting again."
                                )
                            }
                        }
                        return
                    }
                }
                botChallengeCleared = false
                let tsCanPost = await AmenContentPreflightService.shared.runFinalPreflight(
                    text: sanitizedContent.isEmpty ? nil : sanitizedContent,
                    surface: .post,
                    contentId: publishToken
                )
                if !tsCanPost {
                    await MainActor.run {
                        let reason = AmenTrustSafetyService.shared.lastDecision?.userFacingReason
                            ?? "This post cannot be shared."
                        stopPublishAttempt()
                        showError(title: "Post Blocked", message: reason)
                    }
                    return
                }
            }
            // ─────────────────────────────────────────────────────────────────

            // ── Stage 2: ThinkFirst Guardrails ──────────────────────────────────
            let context: ContentContext = {
                switch selectedCategory {
                case .prayer:
                    return .normalPost
                case .testimonies:
                    return .normalPost
                case .openTable:
                    // Check if topic is political
                    return selectedTopicTag.lowercased().contains("politic") ? .politicalTopic : .normalPost
                default:
                    return .normalPost
                }
            }()

            // ── Phase P1-4: on-device + server checks fired concurrently ────────
            // checkContent is local/fast; validate is a CF call. Both consume only
            // sanitizedContent/context/surface and share no data dependency, so we
            // fire them in parallel and collect both results before acting on either.
            // Fail-closed: ANY block/requireEdit/serverError from either check halts
            // the publish. We honor the stricter of (client, server).
            async let checkResultTask  = ThinkFirstGuardrailsService.shared.checkContent(
                sanitizedContent,
                context: context
            )
            async let serverOutcomeTask = ThinkFirstServerValidator.shared.validate(
                sanitizedContent,
                surface: .createPost
            )
            let (checkResult, serverOutcome) = await (checkResultTask, serverOutcomeTask)

            // Treat server errors and input-rejection as a hard halt with a
            // user-readable message. No "proceed anyway" affordance.
            if case .serverError(let message) = serverOutcome {
                await MainActor.run {
                    stopPublishAttempt()
                    serverThinkFirstAlertMessage = message
                    showServerThinkFirstAlert = true
                }
                return
            }
            if case .inputRejected(let message) = serverOutcome {
                await MainActor.run {
                    stopPublishAttempt()
                    serverThinkFirstAlertMessage = message
                    showServerThinkFirstAlert = true
                }
                return
            }

            // Server returned a decision. If it escalates to block/requireEdit,
            // override the client verdict and refuse to publish — the user must
            // revise. We deliberately show this via the dedicated alert (not the
            // existing client sheet) because the client sheet has a "proceed
            // anyway" path that must not bypass the server gate.
            if case .decided(let serverResult) = serverOutcome,
               (serverResult.action == .block || serverResult.action == .requireEdit) {
                await MainActor.run {
                    stopPublishAttempt()
                    serverThinkFirstAlertMessage = serverResult.userMessage.isEmpty
                        ? "We can't publish this as written. Please revise and try again."
                        : serverResult.userMessage
                    showServerThinkFirstAlert = true
                }
                return
            }

            await MainActor.run {
                // Store result for sheet display
                thinkFirstCheckResult = checkResult
                pendingPostContent = sanitizedContent

                switch checkResult.action {
                case .allow:
                    // All clear - proceed with posting
                    #if DEBUG
                    dlog("✅ Think First: Content approved, proceeding")
                    #endif
                    Task {
                        await runAlignmentGuardThenProceed(content: sanitizedContent, hasMedia: hasAttachedMedia)
                    }

                case .softPrompt:
                    // Show gentle prompt but allow posting
                    #if DEBUG
                    dlog("⚠️ Think First: Soft prompt - showing user suggestions")
                    #endif
                    stopPublishAttempt()
                    showThinkFirstPrompt = true

                case .requireEdit:
                    // Strongly recommend editing (e.g., PII detected with auto-redaction)
                    #if DEBUG
                    dlog("⚠️ Think First: Edit required - showing redaction options")
                    #endif
                    stopPublishAttempt()
                    showThinkFirstPrompt = true

                case .block:
                    // Hard block for policy violations
                    #if DEBUG
                    dlog("🚫 Think First: Content blocked")
                    #endif
                    stopPublishAttempt()
                    showThinkFirstPrompt = true
                }
            }
        }
    }

    private func handleSafetyOSDraftAction(_ action: AmenDiscernmentAction, trigger: AmenTriggerResult) {
        AMENAnalyticsService.shared.track(
            .safetyOSDiscernmentAction(
                postId: pendingPublishPostID ?? "draft",
                surface: "post_composer",
                trigger: trigger.type.rawValue,
                action: action.rawValue
            )
        )

        switch action {
        case .editWithGrace, .cancel:
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
            isTextFieldFocused = true
        case .rewriteGently, .addContext:
            if let replacement = AmenLocalTriggerEngine.shared.suggestedRewrite(for: trigger, originalText: postText) {
                postText = replacement
                spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: replacement)
                safetyOSDraftTriggers = AmenLocalTriggerEngine.shared.analyze(text: replacement, surface: .post)
                // Mark AI-assisted tone rewrite for disclosure label on published post
                let aiType: AIUseType = (action == .rewriteGently) ? .toneRewriteMinor : .toneRewriteMajor
                pendingAIUsage = PostAIUsage(
                    usedAI: true,
                    aiUseTypes: [aiType],
                    primaryLabel: .aiAssistedTone,
                    secondaryDetail: "Tone adjusted before publishing",
                    userAcceptedSuggestion: true,
                    disclosureRequired: false,
                    rawPromptStored: false,
                    rawUserTextStored: false
                )
                AMENAnalyticsService.shared.track(.homeInlinePostStarted)
            }
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
            isTextFieldFocused = true
        case .pauseAndPray:
            postText = "I want to pause and pray before I say more."
            spiritualComposeAnalysis = AmenSpiritualSystemsService.shared.analyzeComposer(text: postText)
            safetyOSDraftTriggers = AmenLocalTriggerEngine.shared.analyze(text: postText, surface: .post)
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
            isTextFieldFocused = true
        case .saveDraft:
            saveDraft(showNotice: false)
            bypassSpiritualDiscernmentGate = false
            activeSafetyOSTrigger = nil
        case .openScripture, .joinPrayer, .keepAsText, .postAnyway:
            bypassSpiritualDiscernmentGate = true
            activeSafetyOSTrigger = nil
            publishPost()
        }
    }

    private var mediaMetadataSummaryText: String {
        if let videoDraft = mediaMetadataDraft.videoDraft,
           cameraCoordinator.attachedWitnessMedia?.isVideo == true {
            let cueCount = videoDraft.captionCues.count
            let momentCount = videoDraft.keyMoments.count
            return "\(cueCount) caption cue\(cueCount == 1 ? "" : "s") • \(momentCount) moment\(momentCount == 1 ? "" : "s")"
        }

        if !mediaMetadataDraft.frameCaptions.isEmpty {
            let featured = mediaMetadataDraft.featuredFrameIndex + 1
            return "\(mediaMetadataDraft.frameCaptions.count) frame caption\(mediaMetadataDraft.frameCaptions.count == 1 ? "" : "s") • featured \(featured)"
        }

        return "Add captions, key moments, frame text, and featured frames"
    }

    @MainActor
    private func perMediaCaptionValidationMessageForPublish() -> String? {
        guard AMENFeatureFlags.shared.perMediaCaptionsEnabled else { return nil }

        for (index, draft) in mediaMetadataDraft.frameCaptions.enumerated() {
            let caption = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let altText = draft.altText.trimmingCharacters(in: .whitespacesAndNewlines)
            let reflection = draft.reflectionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

            if caption.count > 2200 {
                return "Caption for photo \(index + 1) is too long."
            }
            if altText.count > 1000 {
                return "Alt text for photo \(index + 1) is too long."
            }
            if reflection.count > 500 {
                return "Reflection for photo \(index + 1) is too long."
            }
            if draft.scriptureRefs.count > 10 {
                return "Photo \(index + 1) has too many scripture references."
            }
            if draft.captionModerationState == .rejected {
                return "Caption for photo \(index + 1) needs edits before posting."
            }
            if draft.captionModerationState == .pending {
                return "Caption for photo \(index + 1) is still being checked. Please wait a moment and try again."
            }
        }

        return nil
    }

    @MainActor
    private func moderateMediaCaptionIfNeeded(index: Int, force: Bool = false) async {
        guard AMENFeatureFlags.shared.perMediaCaptionsEnabled,
              AMENFeatureFlags.shared.perMediaCaptionModerationEnabled,
              AMENFeatureFlags.shared.perMediaCaptionIncrementalModerationEnabled,
              index < mediaMetadataDraft.frameCaptions.count else {
            return
        }

        let draft = mediaMetadataDraft.frameCaptions[index]
        let caption = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let altText = draft.altText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reflection = draft.reflectionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasModeratableContent = !caption.isEmpty || !altText.isEmpty || !reflection.isEmpty

        guard force || hasModeratableContent else {
            mediaMetadataDraft.frameCaptions[index].captionModerationState = .notRequired
            perMediaCaptionStatusMessages[index] = nil
            perMediaCaptionErrorMessages[index] = nil
            return
        }

        perMediaCaptionModerationTask?.cancel()
        perMediaCaptionModerationTask = Task {
            try? await Task.sleep(for: .milliseconds(force ? 0 : 450))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                perMediaCaptionModeratingIndex = index
                perMediaCaptionErrorMessages[index] = nil
                mediaMetadataDraft.frameCaptions[index].captionModerationState = .pending
                perMediaCaptionStatusMessages[index] = "Checking caption safety"
            }

            do {
                let result = try await Functions.functions().httpsCallable("moderateMediaCaption").call([
                    "mediaIndex": index,
                    "mediaId": mediaMetadataDraft.frameCaptions[index].id,
                    "type": "image",
                    "url": "draft://local/\(index)",
                    "caption": caption,
                    "altText": altText,
                    "scriptureRefs": Array(draft.scriptureRefs.prefix(10)),
                    "reflectionPrompt": reflection
                ])
                let data = result.data as? [String: Any]
                let statusRaw = data?["status"] as? String ?? "pending"
                let status = MediaCaptionModerationState(rawValue: statusRaw) ?? .pending
                let reason = data?["reason"] as? String

                await MainActor.run {
                    guard index < mediaMetadataDraft.frameCaptions.count else { return }
                    mediaMetadataDraft.frameCaptions[index].captionModerationState = status
                    perMediaCaptionModeratingIndex = nil
                    switch status {
                    case .approved:
                        perMediaCaptionStatusMessages[index] = "Caption approved"
                        perMediaCaptionErrorMessages[index] = nil
                        AMENAnalyticsService.shared.track(.mediaCaptionEdited(mediaIndex: index, mediaType: "image"))
                    case .notRequired:
                        perMediaCaptionStatusMessages[index] = nil
                        perMediaCaptionErrorMessages[index] = nil
                    case .pending:
                        perMediaCaptionStatusMessages[index] = "Caption queued for review"
                        perMediaCaptionErrorMessages[index] = nil
                    case .rejected:
                        perMediaCaptionStatusMessages[index] = nil
                        perMediaCaptionErrorMessages[index] = reason ?? "This caption needs edits before posting."
                    case .removed:
                        perMediaCaptionStatusMessages[index] = nil
                        perMediaCaptionErrorMessages[index] = nil
                    }
                }
            } catch {
                await MainActor.run {
                    guard index < mediaMetadataDraft.frameCaptions.count else { return }
                    mediaMetadataDraft.frameCaptions[index].captionModerationState = .pending
                    perMediaCaptionModeratingIndex = nil
                    perMediaCaptionStatusMessages[index] = "Caption queued for review"
                    perMediaCaptionErrorMessages[index] = nil
                }
            }
        }
    }

    @MainActor
    private func generateAltTextForMediaCaption(index: Int) async {
        guard AMENFeatureFlags.shared.perMediaCaptionsEnabled,
              AMENFeatureFlags.shared.perMediaCaptionAltTextEnabled,
              index < mediaMetadataDraft.frameCaptions.count else {
            return
        }

        perMediaCaptionGeneratingAltIndex = index
        perMediaCaptionErrorMessages[index] = nil
        defer { perMediaCaptionGeneratingAltIndex = nil }

        do {
            let result = try await Functions.functions().httpsCallable("generateAltText").call([
                "mediaId": mediaMetadataDraft.frameCaptions[index].id,
                "mediaIndex": index,
                "type": "image",
                "url": "draft://local/\(index)"
            ])
            let data = result.data as? [String: Any]
            let suggestion = (data?["altText"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suggestion.isEmpty else {
                perMediaCaptionErrorMessages[index] = "Couldn't generate alt text right now."
                return
            }
            mediaMetadataDraft.frameCaptions[index].altText = String(suggestion.prefix(1000))
            perMediaCaptionStatusMessages[index] = "Alt text suggestion added"
            await moderateMediaCaptionIfNeeded(index: index, force: true)
        } catch {
            perMediaCaptionErrorMessages[index] = "Couldn't generate alt text right now."
        }
    }

    private func applyMetadataToImageItems(urls: [String]) -> [PostMediaItem] {
        urls.enumerated().map { index, url in
            let frameDraft = mediaMetadataDraft.frameCaption(for: index)
            return PostMediaItem(
                type: .image,
                url: url,
                thumbnailURL: url,
                order: index,
                frameCaption: frameDraft?.text.nilIfEmpty,
                frameCaptionMetadata: frameDraft?.asFrameCaption,
                audioBed: mediaMetadataDraft.audioAttachment?.asMediaAudioBed,
                isFeaturedFrame: mediaMetadataDraft.featuredFrameIndex == index,
                previewURL: url,
                originalURL: url,
                processingStatus: MediaGenerationStatus(
                    mediaProcessing: .ready,
                    captions: .notRequested,
                    keyMoments: .notRequested,
                    featuredFrame: .ready,
                    lastUpdatedAt: Date(),
                    errorMessage: nil
                ),
                userEditedMetadata: frameDraft != nil
            )
        }
    }

    private func applyMetadataToVideoItem(_ item: PostMediaItem) -> PostMediaItem {
        guard let videoDraft = mediaMetadataDraft.videoDraft else { return item }
        return PostMediaItem(
            id: item.id,
            type: item.type,
            url: item.url,
            thumbnailURL: item.thumbnailURL,
            aspectRatio: item.aspectRatio,
            order: item.order,
            duration: item.duration,
            fileSize: item.fileSize,
            width: item.width,
            height: item.height,
            captionTrack: videoDraft.captionTrack,
            keyMoments: videoDraft.persistedKeyMoments,
            frameCaption: item.frameCaption,
            frameCaptionMetadata: item.frameCaptionMetadata,
            audioBed: videoDraft.audioBed ?? mediaMetadataDraft.audioAttachment?.asMediaAudioBed,
            isFeaturedFrame: true,
            featuredFrameTime: videoDraft.featuredFrameTime,
            previewURL: item.thumbnailURL ?? item.url,
            originalURL: item.url,
            processingStatus: videoDraft.generationStatus,
            userEditedMetadata: videoDraft.userEdited
        )
    }

    private func syncMediaMetadataDraftFromCurrentAttachments() {
        mediaMetadataDraft.syncForImages(count: selectedImageData.count)
        if let witnessAttachment = cameraCoordinator.attachedWitnessMedia,
           witnessAttachment.isVideo {
            mediaMetadataDraft.syncForWitnessVideo(duration: witnessAttachment.durationSec)
        } else {
            mediaMetadataDraft.videoDraft = nil
        }
    }
    
    /// Fires the .postingFailed notification so ContentView hides the posting bar.
    /// Call this on every path that sets isPublishing = false due to an error.
    @MainActor private func notifyPostingFailed(message: String = "Post failed. Tap Retry to try again.") {
        NotificationCenter.default.post(name: .postingFailed, object: nil)
        publishFailureBannerMessage = message
    }

    @MainActor
    private func stopPublishAttempt(markDraftFailed: Bool = false) {
        isPublishing = false
        isUploadingImages = false
        uploadProgress = 0
        inFlightPostId = nil
        uploadState = .idle  // P1-1: reset button state on failure/cancel
        if markDraftFailed {
            draftVM.markFailed()
            // CF-01: Clear idempotency key on hard/non-retryable failure so the
            // next publish attempt gets a fresh key and cannot reuse a stale one.
            postIdempotencyKey = nil
        } else {
            draftVM.cancelPublishing()
            // CF-01: Preserve postIdempotencyKey on soft-cancel / transient error
            // so that a subsequent retry uses the same key (idempotent re-submit).
        }
    }

    @MainActor
    private func scriptureValidationMessageForPublish() -> String? {
        guard verseAttachmentVM.attachedScripture == nil else { return nil }
        let reference = attachedVerseReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return nil }

        let detectedReferences = ScriptureVerificationService.shared.detectScriptures(in: reference)
        guard let detected = detectedReferences.first else {
            return "The attached scripture reference could not be recognized. Please replace it with a standard reference like John 3:16."
        }

        let normalizedDetected = detected.fullReference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedDetected == reference.lowercased() else {
            return "Please attach one clear scripture reference before posting."
        }

        return nil
    }

    // ============================================================================
    // ✅ NEW: Proceed with publish after guardrails check
    // ============================================================================
    @MainActor
    private func proceedWithPublish() {
        let sanitizedContent = pendingPostContent.isEmpty ? sanitizeContent(postText) : pendingPostContent

        if inFlightPostId == nil {
            let publishToken = ensurePendingPublishSession()
            inFlightPostId = publishToken
            draftVM.markPublishing(token: publishToken)
        }

        dlog("   Setting isPublishing = true")
        isPublishing = true
        // Notify the feed so the Threads-style posting bar appears immediately
        let _startCategory = selectedCategory.toPostCategory.rawValue
        NotificationCenter.default.post(name: .postingStarted, object: nil,
                                        userInfo: ["category": _startCategory])
        
        // Convert CreatePostView.PostCategory to Post.PostCategory for backend
        let postCategory = selectedCategory.toPostCategory
        dlog("   Post category: \(postCategory.rawValue)")
        
        // Check if post is scheduled
        if let scheduledDate = scheduledDate {
            dlog("📅 Scheduling post for: \(scheduledDate)")
            // Handle scheduled post
            schedulePost(
                content: sanitizedContent,
                category: postCategory,
                topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
                allowComments: allowComments,
                linkURL: linkURL.isEmpty ? linkController.activeURL?.absoluteString : linkURL,
                scheduledFor: scheduledDate
            )
        } else if isThreadMode && threadPosts.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count > 1 {
            dlog("🧵 Publishing thread (\(threadPosts.count) posts)")
            publishThread(
                posts: threadPosts,
                category: postCategory,
                topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
                allowComments: allowComments
            )
        } else {
            dlog("📤 Publishing immediately")
            // If user chose an intent but no topic tag, use the intent's feed key as the tag.
            let resolvedTopicTag: String? = selectedTopicTag.isEmpty
                ? selectedPostIntent?.feedTopicKey
                : selectedTopicTag
            // Publish immediately
            publishImmediately(
                content: sanitizedContent,
                category: postCategory,
                topicTag: resolvedTopicTag,
                allowComments: allowComments,
                linkURL: linkURL.isEmpty ? linkController.activeURL?.absoluteString : linkURL
            )
        }
    }

    private func runAlignmentGuardThenProceed(content: String, hasMedia: Bool) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        alignmentViewModel.clear()

        if trimmed.isEmpty && hasMedia {
            await MainActor.run {
                proceedWithPublish()
            }
            return
        }

        guard !trimmed.isEmpty else {
            await MainActor.run {
                proceedWithPublish()
            }
            return
        }

        await alignmentViewModel.scan(
            text: trimmed,
            targetType: "post",
            sourceSurface: "create_post",
            hasMedia: hasMedia
        )

        guard let result = alignmentViewModel.result else {
            await MainActor.run {
                proceedWithPublish()
            }
            return
        }

        switch result.status {
        case .aligned:
            // Social Safety OS backend check runs after local alignment for every publish.
            let mediaURLs: [String] = []  // upload URLs not yet available at this stage
            let decision = await AmenContentSafetyService.shared.gate(
                draft: trimmed,
                mediaURLs: mediaURLs,
                contentType: "post"
            )
            if decision.actions.contains(.blockSend) {
                await MainActor.run {
                    stopPublishAttempt()
                    showError(
                        title: "Post Blocked",
                        message: decision.userFacingMessage ?? "This post can't be shared in this community."
                    )
                }
                return
            }
            if decision.actions.contains(.holdForReview) || decision.actions.contains(.escalateToHumanReview) {
                await MainActor.run {
                    stopPublishAttempt()
                    showError(
                        title: "Safety Review Needed",
                        message: decision.userFacingMessage ?? "This post needs human review before it can be shared."
                    )
                }
                return
            }
            if decision.actions.contains(.requireSource) {
                await MainActor.run {
                    stopPublishAttempt()
                    showError(
                        title: "Add Context First",
                        message: decision.userFacingMessage ?? "Please add a source, scripture reference, or clarify that this is your opinion before sharing."
                    )
                }
                return
            }
            if decision.actions.contains(.requireRewrite) || decision.actions.contains(.promptBeforePost) {
                await MainActor.run {
                    stopPublishAttempt()
                    showError(
                        title: "Think First",
                        message: decision.userFacingMessage ?? "Please revise this before sharing."
                    )
                }
                return
            }
            await MainActor.run {
                proceedWithPublish()
            }
        case .contextNeeded:
            await alignmentViewModel.loadDiscernmentPrompt(text: trimmed, surface: "create_post")
            await MainActor.run {
                stopPublishAttempt()
                showPostDiscernmentPrompt = true
            }
        case .needsDiscernment:
            await MainActor.run {
                stopPublishAttempt()
            }
        case .blocked:
            await MainActor.run {
                stopPublishAttempt()
                showError(title: "Needs a Rewrite", message: result.userVisibleSummary)
            }
        case .humanReview:
            await MainActor.run {
                stopPublishAttempt()
            }
        }
    }
    
    private func publishImmediately(
        content: String,
        category: Post.PostCategory,
        topicTag: String?,
        allowComments: Bool,
        linkURL: String?
    ) {
        activePublishTask?.cancel()
        activePublishTask = Task {
            // Safety net: if any unhandled throw escapes the do/catch below,
            // ensure isPublishing and inFlightPostId are always cleared.
            // Individual error paths each reset these explicitly; this defer
            // is the last-resort guard against logic errors or future regressions.
            defer {
                Task { @MainActor in
                    if isPublishing {
                        stopPublishAttempt()
                    }
                }
            }
            do {
                dlog("🚀 Starting post creation...")
                dlog("   Content length: \(content.count)")
                dlog("   Category: \(category.rawValue)")
                dlog("   Topic tag: \(topicTag ?? "none")")
                dlog("   Allow comments: \(allowComments)")
                dlog("   Link URL: \(linkURL ?? "none")")
                dlog("   Images: \(selectedImageData.count)")
                
                guard let currentUserId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "CreatePostView", code: 401, 
                                  userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
                }
                let hasAttachedMedia = !selectedImageData.isEmpty || cameraCoordinator.attachedWitnessMedia != nil
                
                // ============================================================================
                // ⚡ INSTAGRAM-FAST: Run moderation and post creation in parallel
                // ============================================================================
                
                // ── TIER 0: Instant client-side hard block ───────────────
                // Runs offline — no network, no latency.
                // Catches profanity, harassment, sexual content, hate speech, violence.
                let localGuard = LocalContentGuard.check(content)
                if localGuard.isBlocked {
                    dlog("🚫 [LocalGuard] Blocked (\(localGuard.category.rawValue)): content rejected before network")
                    await MainActor.run {
                        stopPublishAttempt()
                        notifyPostingFailed()
                        showError(
                            title: "Post Not Allowed",
                            message: localGuard.userMessage
                        )
                    }
                    return
                }
                // ─────────────────────────────────────────────────────────

                // P1-1 FIX: PARALLEL MODERATION - Run all safety checks in parallel
                let contentCategory: ContentCategory = .post
                dlog("🛡️ Starting parallel moderation checks...")
                
                // TRUST & SAFETY: Export real authenticity signals from tracking
                let signals = integrityTracker.exportAuthenticitySignals()
                dlog("📊 Authenticity: typed=\(signals.typedCharacters) pasted=\(signals.pastedCharacters) ratio=\(signals.typedVsPastedRatio)")
                
                let pasteRatio = signals.pastedCharacters > 0 ? 
                    Double(signals.pastedCharacters) / Double(signals.pastedCharacters + signals.typedCharacters) : 0.0
                
                // ⚡ FAST PATH: Only run AI detection on the critical path (client-side, instant).
                // ContentModerationService (Cloud Function, 500–1500ms) runs post-write.
                let aiResult = await AIContentDetectionService.shared.detectAIContent(content, pastedRatio: pasteRatio)
                
                // ✅ CHECK AI DETECTION RESULT WITH TIERED RESPONSE
                // Tier 1: High confidence (≥40%) - BLOCK
                if aiResult.isAIGenerated {
                    dlog("🚫 AI content detected - blocking post (confidence: \(Int(aiResult.confidence * 100))%)")
                    dlog("   Reason: \(aiResult.reason)")
                    await MainActor.run {
                        stopPublishAttempt()
                        notifyPostingFailed()
                        showError(
                            title: "Share Your Own Voice",
                            message: "AMEN is a community for authentic, personal sharing. We noticed this content may not be written in your own words.\n\nPlease share your personal thoughts, experiences, and reflections. We want to hear from you, not from AI tools."
                        )
                    }
                    return
                }
                // Tier 2: Medium confidence (25-39%) - SOURCE LABEL OPTION
                // User may post with a visible "via ChatGPT" label instead of being blocked
                else if aiResult.confidence >= 0.25 && aiResult.confidence < 0.4 {
                    dlog("⚠️ Pasted/AI content detected - showing source label prompt (confidence: \(Int(aiResult.confidence * 100))%)")
                    await MainActor.run {
                        stopPublishAttempt()
                        notifyPostingFailed()
                        showSourcePrompt = true
                    }
                    return
                }

                dlog("✅ Fast-path checks passed (AI detection)")
                
                // Start fetching user data in parallel
                guard let currentUser = Auth.auth().currentUser else {
                    throw NSError(domain: "CreatePostView", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
                }
                
                let postIDString = ensurePendingPublishSession()
                let postId = UUID(uuidString: postIDString) ?? UUID()
                let timestamp = Date()
                
                // ⚡ PARALLEL: Fetch profile picture while other tasks run
                dlog("🖼️ Fetching profile picture in parallel...")
                let userDataTask = Task {
                    try await FirebaseManager.shared.firestore
                        .collection("users")
                        .document(currentUser.uid)
                        .getDocument()
                }
                
                // P0-3 FIX: Make image upload BLOCKING if images attached
                var imageURLs: [String]? = nil
                var structuredMediaItems: [PostMediaItem] = []
                var witnessMediaMetadata: PostWitnessMediaMetadata? = nil
                var mediaStoragePaths: [String] = []
                if !selectedImageData.isEmpty {
                    dlog("📤 Uploading \(selectedImageData.count) images (blocking)...")
                    do {
                        await MainActor.run {
                            setUploadCapsuleState(.uploading, stageProgress: 0)
                        }
                        let uploadResult = try await uploadImages()
                        imageURLs = uploadResult.urls
                        structuredMediaItems = applyMetadataToImageItems(urls: uploadResult.urls)
                        mediaStoragePaths = uploadResult.storagePaths
                        await MainActor.run {
                            setUploadCapsuleState(.processing, stageProgress: 0.2)
                        }
                        dlog("✅ Images uploaded: \(imageURLs?.count ?? 0)")
                        
                        // Verify we got URLs back
                        if imageURLs?.isEmpty ?? true {
                            throw NSError(
                                domain: "ImageUpload",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "All images failed to upload. Please check your connection and try again."]
                            )
                        }
                    } catch {
                        // P0-3 FIX: Show error and STOP post creation if images fail
                        // P1-6 FIX: Offer retry for network/upload errors
                        await MainActor.run {
                            presentFailedUploadCapsule(message: getUserFriendlyError(from: error).message)
                            stopPublishAttempt(markDraftFailed: true)
                            notifyPostingFailed()
                            let friendlyError = getUserFriendlyError(from: error)
                            
                            // Check if error is network-related (retryable)
                            let nsError = error as NSError
                            let isNetworkError = nsError.domain == NSURLErrorDomain || 
                                                 nsError.code == NSURLErrorNotConnectedToInternet ||
                                                 nsError.code == NSURLErrorTimedOut ||
                                                 nsError.localizedDescription.lowercased().contains("network") ||
                                                 nsError.localizedDescription.lowercased().contains("connection")
                            
                            showError(
                                title: friendlyError.title, 
                                message: friendlyError.message,
                                isRetryable: isNetworkError,
                                retry: isNetworkError ? {
                                    publishPost()
                                } : nil
                            )
                        }
                        dlog("❌ [P0-3] Image upload failed - aborting post creation")
                        return
                    }
                }

                if let witnessAttachment = cameraCoordinator.attachedWitnessMedia {
                    do {
                        await MainActor.run {
                            let stage: UploadCapsuleState = witnessAttachment.isVideo ? .processing : .uploading
                            setUploadCapsuleState(stage, stageProgress: 0.45)
                            updateUploadCapsuleMediaStatus(for: uploadCapsuleWitnessId, to: .processing)
                        }
                        let uploadResult = try await uploadWitnessAttachment(witnessAttachment, startingOrder: structuredMediaItems.count)
                        structuredMediaItems.append(applyMetadataToVideoItem(uploadResult.mediaItem))
                        witnessMediaMetadata = uploadResult.metadata
                        if let storagePath = uploadResult.metadata.finalAsset.storagePath {
                            mediaStoragePaths.append(storagePath)
                        }
                        await MainActor.run {
                            updateUploadCapsuleMediaStatus(
                                for: uploadCapsuleWitnessId,
                                to: witnessAttachment.isVideo ? .moderating : .uploaded
                            )
                            setUploadCapsuleState(.moderating, stageProgress: 0.1)
                        }
                    } catch {
                        await MainActor.run {
                            presentFailedUploadCapsule(message: getUserFriendlyError(from: error).message)
                            stopPublishAttempt(markDraftFailed: true)
                            notifyPostingFailed()
                            showError(title: "Witness Capture Failed", message: getUserFriendlyError(from: error).message)
                        }
                        return
                    }
                }
                
                // ⚡ WAIT: Get results from parallel tasks
                let userDoc = try await userDataTask.value
                let userData = userDoc.data()
                let authorProfileImageURL = userData?["profileImageURL"] as? String
                let authorUsername = userData?["username"] as? String
                
                // P1-3 FIX: Parallelize mention resolution
                let mentionUsernames = Post.extractMentionUsernames(from: content)
                var mentions: [MentionedUser] = []
                
                if !mentionUsernames.isEmpty {
                    dlog("📧 [P1-3] Found \(mentionUsernames.count) mentions: \(mentionUsernames)")
                    let viewerId = currentUser.uid
                    mentions = await resolveMentions(mentionUsernames, viewerId: viewerId)
                    dlog("✅ [P1-3] Resolved \(mentions.count)/\(mentionUsernames.count) mentions in parallel")
                }
                
                // Create Post object with mentions
                let _authorName: String = currentUser.displayName ?? "User"
                let _authorInitials: String = String(_authorName.prefix(1))
                let _commentPerms: Post.CommentPermissions = allowComments ? mapToPostCommentPermissions(commentPermission) : .off
                let _resolvedLinkURL: String? = linkURL ?? linkController.activeURL?.absoluteString
                let _verseRef: String? = attachedVerseReference.isEmpty ? nil : attachedVerseReference
                let _verseText: String? = attachedVerseText.isEmpty ? nil : attachedVerseText
                let _mediaItems: [PostMediaItem]? = structuredMediaItems.isEmpty ? nil : structuredMediaItems
                var newPost = Post(
                    id: postId,
                    firebaseId: nil,
                    authorId: currentUser.uid,
                    authorName: _authorName,
                    authorUsername: authorUsername,
                    authorInitials: _authorInitials,
                    authorProfileImageURL: authorProfileImageURL,
                    timeAgo: "now",
                    content: content,
                    category: category,
                    topicTag: topicTag,
                    visibility: postVisibility,
                    allowComments: allowComments,
                    commentPermissions: _commentPerms,
                    imageURLs: imageURLs,
                    linkURL: _resolvedLinkURL,
                    linkPreviewTitle: linkController.metadata?.title,
                    linkPreviewDescription: linkController.metadata?.description,
                    linkPreviewImageURL: linkController.metadata?.imageURL?.absoluteString,
                    linkPreviewSiteName: linkController.metadata?.siteName,
                    verseReference: _verseRef,
                    verseText: _verseText,
                    createdAt: timestamp,
                    amenCount: 0,
                    lightbulbCount: 0,
                    commentCount: 0,
                    repostCount: 0,
                    mediaItems: _mediaItems,
                    witnessMedia: witnessMediaMetadata,
                    smartAttachment: smartAttachment,
                    hasSmartAttachment: smartAttachment != nil,
                    attachmentCount: smartAttachment == nil ? 0 : 1,
                    primaryAttachmentId: smartAttachment?.id
                )
                
                // Set mentions if any were found
                if !mentions.isEmpty {
                    newPost.mentions = mentions
                }
                
                // Set tagged users if any were selected
                if !taggedUsers.isEmpty {
                    newPost.taggedUserIds = taggedUsers.map(\.userId)
                    // Default all tags to "approved" — recipient can remove themselves later
                    newPost.tagStatusByUid = Dictionary(
                        uniqueKeysWithValues: taggedUsers.map { ($0.userId, "approved") }
                    )
                }

                // Set church tag if provided
                if !taggedChurchId.isEmpty {
                    newPost.taggedChurchId = taggedChurchId
                    newPost.taggedChurchName = taggedChurchName.isEmpty ? nil : taggedChurchName
                }
                newPost.mediaItems = structuredMediaItems.isEmpty ? nil : structuredMediaItems
                newPost.witnessMedia = witnessMediaMetadata
                // Attach AI usage label if tone check / rewrite was accepted
                if let usage = pendingAIUsage { newPost.aiUsage = usage }
                newPost.mediaAttachments = selectedMusicAttachment.map { [$0] }
                newPost.publicationVisibility = hasAttachedMedia ? "private_pending" : "public"

                dlog("   ✅ Post object created: \(postId)")
                
                // Save to Firestore immediately.
                // GUARDIAN PRE-GATE: Write visibility as "under_review" so the post is
                // invisible to all feed queries (which filter visibility == "everyone")
                // until the serverSidePostModeration Cloud Function finishes its check
                // and promotes visibility to requestedVisibility on pass, or keeps it
                // "flagged"/"removed" on fail.  requestedVisibility records the author's
                // intent so the CF knows what to promote to on approval.
                var postData: [String: Any] = [
                    "authorId": currentUser.uid,
                    "authorName": currentUser.displayName ?? "User",
                    "authorInitials": String((currentUser.displayName ?? "U").prefix(1)),
                    "content": content,
                    "category": category.rawValue,
                    "topicTag": topicTag as Any,
                    "visibility": "under_review",
                    "requestedVisibility": postVisibility.rawValue,
                    "publicationVisibility": hasAttachedMedia ? "private_pending" : "public",
                    "uploadGroupId": postIDString,
                    "allowComments": allowComments,
                    "imageURLs": imageURLs as Any,
                    "mediaStoragePaths": mediaStoragePaths,
                    "linkURL": (linkURL ?? linkController.activeURL?.absoluteString) as Any? as Any,
                    "createdAt": Timestamp(date: timestamp),
                    "updatedAt": Timestamp(date: timestamp),
                    "status": hasAttachedMedia ? "moderating" : "publishing",
                    "mediaCount": structuredMediaItems.count,
                    "amenCount": 0,
                    "commentCount": 0,
                    "repostCount": 0,
                    "lightbulbCount": 0,
                    "clientRequestId": uploadCapsuleClientRequestId ?? inFlightPostId ?? UUID().uuidString,
                    "idempotencyKey": uploadCapsuleIdempotencyKey ?? inFlightPostId ?? postId.uuidString
                ]

                if !structuredMediaItems.isEmpty,
                   let encodedMediaItems = try? Firestore.Encoder().encode(structuredMediaItems) {
                    postData["mediaItems"] = encodedMediaItems
                }
                if let smartAttachment,
                   let encodedAttachment = try? Firestore.Encoder().encode(smartAttachment) {
                    postData["smartAttachment"] = encodedAttachment
                    postData["hasSmartAttachment"] = true
                    postData["attachmentCount"] = 1
                    postData["primaryAttachmentId"] = smartAttachment.id
                    postData["soundtrackEnabled"] = useSmartAttachmentAsSoundtrack
                    postData["smartObjectIds"] = [smartAttachment.id]
                    postData["primarySmartObjectId"] = smartAttachment.id
                    postData["objectType"] = smartAttachment.type.rawValue
                    postData["sourceProvider"] = smartAttachment.provider.rawValue
                    postData["canonicalUrl"] = smartAttachment.canonicalUrl
                    postData["safetyState"] = smartAttachment.safetyStatus.rawValue
                    postData["explicitContentState"] = smartAttachment.safetyStatus == .blocked ? "blocked" : "unknown"
                }

                // Music / media attachments (v2 media system)
                if let music = selectedMusicAttachment,
                   let encodedMedia = try? Firestore.Encoder().encode([music] as [AmenMediaAttachment]) {
                    postData["mediaAttachments"] = encodedMedia
                }

                if let witnessMediaMetadata,
                   let encodedWitnessMedia = try? Firestore.Encoder().encode(witnessMediaMetadata) {
                    postData["witnessMedia"] = encodedWitnessMedia
                }
                
                // ✅ Add profile picture if available
                if let authorProfileImageURL = authorProfileImageURL {
                    postData["authorProfileImageURL"] = authorProfileImageURL
                }
                
                // ✅ Add username if available
                if let authorUsername = authorUsername {
                    postData["authorUsername"] = authorUsername
                }
                
                // ✅ Add mentions if available
                if !mentions.isEmpty {
                    postData["mentions"] = mentions.map { mention in
                        [
                            "userId": mention.userId,
                            "username": mention.username,
                            "displayName": mention.displayName
                        ]
                    }
                }
                
                // ✅ Add tagged users if any were selected
                if !taggedUsers.isEmpty {
                    postData["taggedUserIds"] = taggedUsers.map(\.userId)
                    postData["tagStatusByUid"] = Dictionary(
                        uniqueKeysWithValues: taggedUsers.map { ($0.userId, "approved") }
                    ) as [String: Any]
                }
                
                // ✅ Add link preview metadata if available
                if let lm = linkController.metadata {
                    postData["linkPreviewTitle"] = lm.title as Any
                    postData["linkPreviewDescription"] = lm.description as Any
                    postData["linkPreviewImageURL"] = lm.imageURL?.absoluteString as Any
                    postData["linkPreviewSiteName"] = lm.siteName as Any
                    postData["linkPreviewType"] = lm.previewType.rawValue
                    if let ref = lm.verseReference { postData["verseReference"] = ref }
                    if let vt = lm.verseText { postData["verseText"] = vt }
                    dlog("   🔗 Link preview metadata added (type=\(lm.previewType.rawValue))")
                }

                // ✅ Add content source label if user acknowledged non-original content
                if let source = postContentSource {
                    postData["contentSource"] = source
                    dlog("   🏷️ Content source label: \(source)")
                }

                // ✅ Attached scripture verse (from verse picker)
                if let attachment = verseAttachmentVM.attachedScripture {
                    // New structured format
                    postData["verseReference"] = attachment.canonicalReference
                    postData["verseText"] = attachment.previewText
                    postData["scriptureAttachment"] = attachment.firestoreData
                    dlog("   📖 Verse attached (structured): \(attachment.canonicalReference)")
                } else if !attachedVerseReference.isEmpty {
                    // Legacy fallback
                    postData["verseReference"] = attachedVerseReference
                    if !attachedVerseText.isEmpty {
                        postData["verseText"] = attachedVerseText
                    }
                    dlog("   📖 Verse attached: \(attachedVerseReference)")
                }

                // ✅ Church tag
                if !taggedChurchId.isEmpty {
                    postData["taggedChurchId"] = taggedChurchId
                    postData["taggedChurchName"] = taggedChurchName
                    dlog("   ⛪ Church tagged: \(taggedChurchName)")
                }

                // ✅ Poll attachment
                // P1-10: Check poll option text through content guard
                if showingPoll && pollHasValidOptions {
                    let allPollText = ([pollQuestion] + pollOptions).joined(separator: " ")
                    let pollCheckResult = await ModerationIngestService.shared.check(
                        text: allPollText,
                        contentType: .post,
                        authorId: Auth.auth().currentUser?.uid ?? ""
                    )
                    if case .block(let reason, _) = pollCheckResult {
                        await MainActor.run {
                            stopPublishAttempt()
                            showError(title: "Poll Content Issue", message: reason)
                        }
                        return
                    }
                }
                if showingPoll && pollHasValidOptions {
                    let filledOptions = pollOptions
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .map { PostPoll.PollOption(id: UUID().uuidString, text: $0, voteCount: 0) }
                    let poll = PostPoll(
                        question: pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines),
                        options: filledOptions,
                        expiresAt: pollDuration.expiryDate,
                        totalVotes: 0
                    )
                    postData["poll"] = poll.firestoreData
                    dlog("   📊 Poll attached: \(filledOptions.count) options, expires: \(String(describing: pollDuration.expiryDate))")
                }

                // ✅ Sensitive content flag — surfaced in feed behind a tap-to-reveal blur
                if hasSensitiveContent {
                    postData["hasSensitiveContent"] = true
                    if !sensitiveContentReason.isEmpty {
                        postData["sensitiveContentReason"] = sensitiveContentReason
                    }
                }

                // ✅ Privacy: hide engagement counts (likes/comments) from public view
                if hideEngagementCounts {
                    postData["hideEngagementCounts"] = true
                }

                // ✅ Alt text for image accessibility
                let filteredAlt = imageAltTexts.filter { !$0.isEmpty }
                if !filteredAlt.isEmpty {
                    postData["imageAltTexts"] = filteredAlt
                }

                // SECURITY: Stamp every post with moderationStatus="pending" so the
                // server-side Cloud Function trigger (posts/{postId} onCreate) always
                // runs a second-pass moderation check. A modified client that bypasses
                // the pre-write checks above will still have this field present, and the
                // Cloud Function will evaluate and delete the post if it violates policy.
                postData["moderationStatus"] = hasAttachedMedia ? "pending" : "not_required"
                postData["clientSafetyVersion"] = 1
                if hasAttachedMedia {
                    postData["moderationSummary"] = [
                        "safe": false,
                        "decision": "pending"
                    ]
                }

                // P0-1: Run crisis detection BEFORE writing to Firestore for prayer posts
                if category == .prayer, !content.isEmpty {
                    do {
                        let crisisCheck = try await CrisisDetectionService.shared.detectCrisis(
                            in: content,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )
                        if crisisCheck.isCrisis {
                            await MainActor.run {
                                stopPublishAttempt()
                                showCrisisResourcesAlert(crisisResult: crisisCheck)
                            }
                            return
                        }
                    } catch {
                        // Crisis detection failure is non-blocking — proceed with publish
                        dlog("⚠️ Pre-publish crisis check failed (non-blocking): \(error)")
                    }
                }

                dlog("   📤 Saving to Firestore immediately...")
                await MainActor.run {
                    if hasAttachedMedia {
                        setUploadCapsuleState(.finalizing, stageProgress: 0.2)
                    }
                }

                // CF-01 Part B: Write the main post document first, then attempt all
                // dependent subcollection writes.  If any dependent write throws, roll
                // back by deleting the main document so the author does not end up with
                // a partially-written post visible (or invisible) in Firestore.
                let postRef = FirebaseManager.shared.firestore
                    .collection("posts")
                    .document(postId.uuidString)
                try await postRef.setData(postData)

                do {
                    // Best-effort: index post into community hub so the optimistic PostCard
                    // can show the Inline Object Hub pill as soon as the trusted backend
                    // preview is returned. Errors are swallowed by the service so posting
                    // still succeeds as a normal post.
                    if let smartAttachment, AMENFeatureFlags.shared.communityHubsEnabled {
                        let preview = await AmenCommunityHubService.shared.attachHubPreview(
                            postId: postId.uuidString,
                            url: smartAttachment.canonicalUrl,
                            objectType: smartAttachment.type.rawValue,
                            title: smartAttachment.title
                        )
                        // Preview is now propagated via the Firestore real-time listener:
                        // communityHubPreview is decoded by FirestorePost and flows through toPost().
                        _ = preview
                    }

                    if let checkId = alignmentViewModel.result?.checkId {
                        Task {
                            try? await BiblicalAlignmentService.shared.attachSharedKnowledgeIntegrity(
                                targetType: "post",
                                targetId: postId.uuidString,
                                checkId: checkId
                            )
                        }
                    }

                    if !structuredMediaItems.isEmpty {
                        try await MediaMetadataPersistenceService.shared.persistMetadataMirror(
                            postId: postId.uuidString,
                            authorId: currentUser.uid,
                            mediaItems: structuredMediaItems
                        )
                    }
                } catch {
                    // CF-01 Part B rollback: a dependent write failed after the main post
                    // document was already committed.  Delete the orphaned main document so
                    // the author does not see a partially-written, unmoderated post.
                    dlog("⚠️ [CF-01] Subcollection write failed after main post write — rolling back post \(postId.uuidString): \(error)")
                    try? await postRef.delete()
                    throw error  // re-throw so the outer catch surfaces the error to the user
                }
                
                dlog("✅ Post saved to Firestore successfully!")
                dlog("   Post ID: \(newPost.id)")
                dlog("   Category: \(newPost.category.rawValue)")
                dlog("   Author: \(newPost.authorName)")

                await MainActor.run {
                    clearPendingUploadCleanupPaths()
                }

                // Increment user's post count (fire-and-forget, same as FirebasePostService.createPost)
                let _uid = currentUser.uid
                Task.detached(priority: .utility) {
                    try? await FirebaseManager.shared.firestore
                        .collection("users").document(_uid)
                        .updateData(["postsCount": FieldValue.increment(Int64(1))])
                }

                // HeyFeed authoring signal — records intent + audience choice for post-level feed learning
                let _hfPostId = postId.uuidString
                let _hfIntentRaw = selectedPostIntent?.rawValue
                let _hfFeedTopicKey = selectedPostIntent?.feedTopicKey
                let _hfAudienceHintId = selectedAudienceHint?.id
                let _hfDetectedIntent = insightEngine.result.intent.rawValue
                let _hfHasVerse = verseAttachmentVM.attachedScripture != nil || !attachedVerseReference.isEmpty
                Task.detached(priority: .utility) {
                    var doc: [String: Any] = [
                        "postId": _hfPostId,
                        "detectedIntent": _hfDetectedIntent,
                        "scriptureAttached": _hfHasVerse,
                        "createdAt": Timestamp(date: Date())
                    ]
                    if let intent = _hfIntentRaw { doc["selectedIntent"] = intent }
                    if let key = _hfFeedTopicKey { doc["feedTopicKey"] = key }
                    if let hint = _hfAudienceHintId { doc["audienceHint"] = hint }
                    try? await FirebaseManager.shared.firestore
                        .collection("users").document(_uid)
                        .collection("heyfeedAuthoring").document(_hfPostId)
                        .setData(doc)
                }

                // ⚡ FIRE-AND-FORGET: Post-write content moderation pipeline.
                // ContentModerationService (Cloud Function, 500–1500ms) runs after the
                // Firestore write so the user sees instant confirmation.
                // If the post is flagged it is deleted silently server-side.
                let capturedPostIdStr = postId.uuidString
                let capturedContent = content
                let capturedContentCategory = contentCategory
                let capturedSignals = signals
                Task.detached(priority: .utility) {
                    guard let modResult = try? await ContentModerationService.moderateContent(
                        text: capturedContent,
                        category: capturedContentCategory,
                        signals: capturedSignals,
                        parentContentId: nil
                    ) else { return }

                    let shouldDelete = await MainActor.run { modResult.action == .reject }
                    if shouldDelete {
                        do {
                            try await FirebaseManager.shared.firestore
                                .collection("posts")
                                .document(capturedPostIdStr)
                                .delete()
                            dlog("🛡️ [Post-write] Post \(capturedPostIdStr) removed by async moderation pipeline")
                        } catch {
                            dlog("⚠️ [Post-write] Failed to remove flagged post: \(error)")
                        }
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: Notification.Name("postRemovedByModeration"),
                                object: nil,
                                userInfo: ["postId": capturedPostIdStr]
                            )
                        }
                    }
                }

                // TRUST & SAFETY: Track post for rate limiting and reset tracker
                rateLimiter.trackPost(category: .post)
                integrityTracker.reset()
                
                // 📧 Send mention notifications (non-blocking background task)
                if !mentions.isEmpty {
                    Task {
                        await NotificationService.shared.sendMentionNotifications(
                            mentions: mentions.map { $0.userId },
                            actorId: currentUser.uid,
                            actorName: currentUser.displayName ?? "User",
                            actorUsername: userData?["username"] as? String,
                            postId: postId.uuidString,
                            contentType: "post"
                        )
                    }
                }

                Task { @MainActor in
                    await IntelligentSocialPipeline.shared.handlePostCreated(
                        post: newPost,
                        authenticitySignals: signals,
                        currentSurface: "post_creation"
                    )
                }
                
                // P0-2 FIX: Only dismiss AFTER Firestore confirms success
                // GUARDIAN PRE-GATE: Post is now in Firestore with visibility="under_review".
                // It is NOT yet visible to other users — the serverSidePostModeration CF
                // will promote it to requestedVisibility once the safety check passes.
                // We show "Your post is being reviewed" instead of the instant "Posted!" pill
                // so the author knows content moderation is running.  The post will appear
                // in their own feed (author-side) and in public feeds once approved.
                await MainActor.run {
                    dlog("📬 Sending notification to update UI...")
                    // Do NOT send .newPostCreated with isOptimistic=true here because the
                    // post has visibility="under_review" — it should not appear in public
                    // feed cells.  The real-time listener on posts/ will fire and add it
                    // once the CF upgrades visibility to "everyone".
                    dlog("✅ Post submitted for review (visibility=under_review)")

                    // Clear state (P0-1, P1-2)
                    inFlightPostId = nil
                    draftVM.markPublished()
                    postContentSource = nil  // reset source label for next post
                    UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
                    shouldPersistDraftOnExit = false
                    clearPendingPublishSession()
                    // CF-01 Part A: Publish succeeded — clear idempotency key so a future
                    // post gets a fresh key rather than reusing this completed one.
                    postIdempotencyKey = nil

                    // Show contextual success feedback
                    if hasAttachedMedia {
                        markAllUploadCapsuleMediaReady()
                        completeUploadCapsuleSession()
                    } else {
                        cameraCoordinator.removeAttachedMedia()
                        mediaMetadataDraft = CreatePostMediaMetadataDraft()
                        // Show "being reviewed" notice instead of "Posted!" pill.
                        // showingSuccessNotice still triggers the pill — we reuse it
                        // and override the pill text via postPendingReview flag below.
                        withAnimation(reduceMotion ? nil : .default) {
                            postPendingReview = true
                            showingSuccessNotice = true
                            uploadState = .success  // P1-1: driven by publish pipeline, not fixed timer
                        }
                        scheduleDelayedAction(seconds: 0.9) {
                            withAnimation(Motion.adaptive(.spring(response: 0.34, dampingFraction: 0.88))) {
                                uploadState = .idle
                            }
                        }
                    }

                    // Record post for community guidelines eligibility tracking
                    CommunityGuidelinesEligibilityService.shared.recordPostPublished()
                    // analytics: postPublished event not yet defined in AMENAnalyticsEvent

                    // P0-2 FIX: Critical - cancellable dismiss task
                    scheduleDelayedAction(seconds: hasAttachedMedia ? 1.0 : 0.15) {
                        cameraCoordinator.removeAttachedMedia()
                        mediaMetadataDraft = CreatePostMediaMetadataDraft()
                        postPendingReview = false
                        dlog("Dismissing CreatePostView (safe after Firestore)")
                        dismiss()
                    }

                    // Reset publishing state
                    isPublishing = false
                    dlog("Post creation flow completed (pending moderation review)!")
                }
                
                // Success! Sync to Algolia for search (non-blocking background task)
                dlog("🔍 Syncing to Algolia in background...")
                syncPostToAlgolia(newPost)
                
                // Crisis detection now runs pre-publish (see above)
            } catch let error as NSError {
                // ⚠️ Post creation failed in background - user already saw success
                dlog("❌ Failed to create post in background (NSError)")
                dlog("   Error domain: \(error.domain)")
                dlog("   Error code: \(error.code)")
                dlog("   Error description: \(error.localizedDescription)")
                dlog("   Error userInfo: \(error.userInfo)")
                dlog("   Localized failure reason: \(error.localizedFailureReason ?? "none")")
                dlog("   Localized recovery suggestion: \(error.localizedRecoverySuggestion ?? "none")")

                await MainActor.run {
                    cleanupPendingUploadArtifacts()
                }

                await MainActor.run {
                    presentFailedUploadCapsule(message: "Post failed to send. Please try again.")
                    stopPublishAttempt(markDraftFailed: true)
                    notifyPostingFailed()
                    // 4.4 FIX: Surface actionable message for email-verification PERMISSION_DENIED.
                    // Firestore rules reject writes from unverified email/password accounts —
                    // the generic "try again" toast is misleading because retrying will also fail.
                    let isPermissionDenied = error.domain == "FIRFirestoreErrorDomain" && error.code == 7
                    let user = Auth.auth().currentUser
                    let isPasswordUser = user?.providerData.first?.providerID == "password"
                    let isUnverified = user?.isEmailVerified == false
                    if isPermissionDenied && isPasswordUser && isUnverified {
                        ToastManager.shared.show(ToastNotification(
                            message: "Please verify your email before posting. Check your inbox for the verification link.",
                            style: .error
                        ))
                    } else {
                        ToastManager.shared.show(ToastNotification(
                            message: "Post failed to send. Please try again.",
                            style: .error,
                            action: { publishPost() },
                            actionLabel: "Retry"
                        ))
                    }
                }
            } catch {
                // ⚠️ Post creation failed in background - user already saw success
                dlog("❌ Failed to create post in background (Generic Error)")
                dlog("   Error: \(error)")
                dlog("   Error type: \(type(of: error))")
                dlog("   Error description: \(String(describing: error))")

                // Try to get more details
                if let error = error as? LocalizedError {
                    dlog("   Error description: \(error.errorDescription ?? "none")")
                    dlog("   Failure reason: \(error.failureReason ?? "none")")
                    dlog("   Recovery suggestion: \(error.recoverySuggestion ?? "none")")
                }

                await MainActor.run {
                    cleanupPendingUploadArtifacts()
                }

                await MainActor.run {
                    presentFailedUploadCapsule(message: "Post failed to send. Please try again.")
                    stopPublishAttempt(markDraftFailed: true)
                    notifyPostingFailed()
                    ToastManager.shared.show(ToastNotification(
                        message: "Post failed to send. Please try again.",
                        style: .error,
                        action: { publishPost() },
                        actionLabel: "Retry"
                    ))
                }
            }
        }
    }
    
    private func resolveMentions(_ usernames: [String], viewerId: String) async -> [MentionedUser] {
        var results: [MentionedUser] = []
        await withTaskGroup(of: MentionedUser?.self) { group in
            for username in usernames {
                group.addTask {
                    do {
                        let query = try await FirebaseManager.shared.firestore
                            .collection("users")
                            .whereField("username", isEqualTo: username)
                            .limit(to: 1)
                            .getDocuments()
                        guard let doc = query.documents.first else { return nil }
                        let userId = doc.documentID
                        let displayName = doc.data()["displayName"] as? String ?? username
                        let canMention = try await TrustByDesignService.shared.canMention(from: viewerId, mention: userId)
                        guard canMention else { return nil }
                        return MentionedUser(userId: userId, username: username, displayName: displayName)
                    } catch {
                        return nil
                    }
                }
            }
            for await mention in group {
                if let mention { results.append(mention) }
            }
        }
        return results
    }

    /// Async wrapper for publishPost() - called by CirclePostButton
    @MainActor
    private func publishPostAsync() async {
        publishPost()
    }

    /// Drives LiquidGlassPostButton visual states while calling the real publish pipeline.
    private func triggerLiquidPost() {
        guard uploadState == .idle else { return }
        Task {
            withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.72))) {
                uploadState = .pressed
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.82))) {
                uploadState = .uploading(progress: 0.05)
            }
            await MainActor.run { publishPost() }
            // Success/failure states are set by the publish pipeline itself
        }
    }

    private var uploadCapsuleMediaItems: [UploadCapsuleMediaItem] {
        var items: [UploadCapsuleMediaItem] = selectedImageData.enumerated().map { index, data in
            UploadCapsuleMediaItem(
                id: uploadCapsuleImageId(for: index),
                thumbnailImage: UIImage(data: data),
                kind: .image,
                status: uploadCapsuleMediaStatuses[uploadCapsuleImageId(for: index)] ?? .waiting
            )
        }

        if let attachment = cameraCoordinator.attachedWitnessMedia {
            let thumbnailImage: UIImage? = {
                if let url = attachment.thumbnailFileURL,
                   let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
                if !attachment.isVideo,
                   let url = attachment.finalFileURL,
                   let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
                return nil
            }()

            items.append(
                UploadCapsuleMediaItem(
                    id: uploadCapsuleWitnessId,
                    thumbnailImage: thumbnailImage,
                    kind: attachment.isVideo ? .video : .image,
                    status: uploadCapsuleMediaStatuses[uploadCapsuleWitnessId] ?? .waiting
                )
            )
        }

        return items
    }

    private var uploadCapsuleUploadedCount: Int {
        uploadCapsuleMediaItems.reduce(into: 0) { count, item in
            switch item.status {
            case .uploaded, .processing, .moderating, .passed, .reviewRequired:
                count += 1
            default:
                break
            }
        }
    }

    private var retryUploadCapsuleAction: (() -> Void)? {
        guard case .failed = uploadCapsuleState else { return nil }
        return {
            guard !isPublishing else { return }
            publishPost()
        }
    }

    private var uploadCapsuleWitnessId: String {
        "witness-\(cameraCoordinator.attachedWitnessMedia?.id ?? "none")"
    }

    private func uploadCapsuleImageId(for index: Int) -> String {
        "image-\(index)"
    }

    @MainActor
    private func ensurePendingPublishSession() -> String {
        if let pendingPublishPostID {
            if uploadCapsuleIdempotencyKey == nil {
                uploadCapsuleIdempotencyKey = pendingPublishPostID
            }
            if uploadCapsuleClientRequestId == nil {
                uploadCapsuleClientRequestId = pendingPublishPostID
            }
            return pendingPublishPostID
        }

        let postID = UUID().uuidString
        pendingPublishPostID = postID
        uploadCapsuleIdempotencyKey = postID
        uploadCapsuleClientRequestId = postID
        return postID
    }

    @MainActor
    private func clearPendingPublishSession() {
        pendingPublishPostID = nil
        uploadCapsuleClientRequestId = nil
        uploadCapsuleIdempotencyKey = nil
    }

    @MainActor
    private func beginUploadCapsuleSession() {
        _ = ensurePendingPublishSession()
        uploadCapsuleMediaStatuses = Dictionary(uniqueKeysWithValues: uploadCapsuleMediaItems.map { ($0.id, .waiting) })
        uploadCapsuleState = .preparing
        uploadCapsuleProgress = UploadCapsuleMetrics.weightedProgress(for: .preparing, stageProgress: 0.15)
        isUploadCapsuleExpanded = false
    }

    @MainActor
    private func setUploadCapsuleState(_ state: UploadCapsuleState, stageProgress: Double) {
        uploadCapsuleState = state
        uploadCapsuleProgress = UploadCapsuleMetrics.weightedProgress(for: state, stageProgress: stageProgress)
    }

    @MainActor
    private func updateUploadCapsuleMediaStatus(for id: String, to status: UploadCapsuleMediaStatus) {
        uploadCapsuleMediaStatuses[id] = status
    }

    @MainActor
    private func markAllUploadCapsuleMediaReady() {
        for item in uploadCapsuleMediaItems {
            uploadCapsuleMediaStatuses[item.id] = .passed
        }
    }

    @MainActor
    private func completeUploadCapsuleSession() {
        uploadCapsuleState = .success
        uploadCapsuleProgress = 1
        isUploadCapsuleExpanded = false
    }

    @MainActor
    private func presentFailedUploadCapsule(message: String) {
        guard uploadCapsuleState != nil else { return }
        uploadCapsuleState = .failed(message: message)
        uploadCapsuleProgress = max(uploadCapsuleProgress, 0.22)
        isUploadCapsuleExpanded = true
        UIAccessibility.post(notification: .announcement, argument: "Upload failed. Tap retry.")
    }

    @MainActor
    private func presentBlockedUploadCapsule(reason: String) {
        guard uploadCapsuleState != nil else { return }
        uploadCapsuleState = .blocked(reason: reason)
        uploadCapsuleProgress = max(uploadCapsuleProgress, 0.84)
        isUploadCapsuleExpanded = true
        UIAccessibility.post(notification: .announcement, argument: "Cannot post media. Review the selected media.")
    }
    
    /// Sync post to Algolia for instant search (non-blocking).
    /// Only public, feed-eligible posts are indexed so drafts, private/followers-only,
    /// pending moderation, and removed posts cannot leak through search.
    private func syncPostToAlgolia(_ post: Post) {
        guard post.visibility == .everyone, post.isEligibleForFeedDisplay else {
            dlog("⏭️ Skipping Algolia sync for non-public or non-approved post: \(post.id.uuidString)")
            return
        }

        // Run in background - don't block UI or show errors
        Task.detached(priority: .background) {
            do {
                // Convert Post to dictionary for Algolia
                let postData: [String: Any] = [
                    "content": post.content,
                    "authorId": post.authorId,
                    "authorName": post.authorName,
                    "category": post.category.rawValue,
                    "amenCount": post.amenCount,
                    "commentCount": post.commentCount,
                    "repostCount": post.repostCount,
                    "createdAt": post.createdAt.timeIntervalSince1970,
                    "isPublic": post.visibility == .everyone,
                    "visibility": post.visibility.rawValue,
                    "shareCount": 0  // Add shareCount for Algolia
                ]
                
                try await AlgoliaSyncService.shared.syncPost(
                    postId: post.id.uuidString,
                    postData: postData
                )
                
                dlog("✅ Post synced to Algolia: \(post.id.uuidString)")
            } catch {
                // Silently log - Algolia sync is non-critical
                dlog("⚠️ Failed to sync post to Algolia (non-critical): \(error)")
            }
        }
    }
    
    /// Upload all selected images and return their download URLs along with the Storage group path
    /// so callers can delete the whole folder if the subsequent Firestore write fails.
    private func uploadImages() async throws -> (urls: [String], groupPath: String, storagePaths: [String]) {
        var imageURLs: [String] = []
        var storagePaths: [String] = []
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "CreatePostView",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        // Validate image data before upload
        guard !selectedImageData.isEmpty else {
            return (urls: [], groupPath: "", storagePaths: [])
        }
        
        await MainActor.run {
            isUploadingImages = true
            uploadProgress = 0.0
            setUploadCapsuleState(.uploading, stageProgress: 0)
        }
        
        var failedUploads = 0
        let totalImages = selectedImageData.count
        // Stable folder ID groups all images for this post under post_media/{userId}/{uploadGroupId}/
        let uploadGroupId = await MainActor.run { ensurePendingPublishSession() }
        let groupPath = "post_media/\(userId)/\(uploadGroupId)"

        await MainActor.run {
            trackPendingUploadCleanupPath(groupPath)
        }

        for (index, imageData) in selectedImageData.enumerated() {
            guard !Task.isCancelled else {
                dlog("⚠️ Image upload cancelled")
                break
            }

            do {
                await MainActor.run {
                    updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .preparing)
                }
                // Create a unique filename under the canonical post_media path
                let filename = "image_\(index).jpg"
                let storageRef = FirebaseManager.shared.storage.reference()
                    .child("post_media")
                    .child(userId)
                    .child(uploadGroupId)
                    .child(filename)
                
                // PERF-1 FIX: Compress image on background thread (CPU-intensive)
                let compressedData = await Task.detached {
                    self.compressImage(imageData, maxSizeInMB: 1.0)
                }.value
                
                guard let compressedData = compressedData else {
                    dlog("⚠️ Failed to compress image \(index)")
                    await MainActor.run {
                        updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .failed)
                    }
                    failedUploads += 1
                    continue
                }
                
                // ✅ SAFESEARCH MODERATION: Check image safety before upload
                do {
                    let moderationDecision = try await ImageModerationService.shared.moderateImage(
                        imageData: compressedData,
                        userId: userId,
                        context: .postImage
                    )
                    
                    switch moderationDecision {
                    case .approved:
                        break
                    case .review:
                        dlog("ℹ️ [IMAGE MOD] Image \(index + 1) queued for server-side review; continuing upload")
                        await MainActor.run {
                            updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .moderating)
                        }
                    case .blocked:
                        await MainActor.run {
                            isUploadingImages = false
                            uploadProgress = 0.0
                            updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .blocked)
                        }
                        throw NSError(
                            domain: "ImageModeration",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: moderationDecision.userMessage]
                        )
                    }
                } catch let moderationError as ImageModerationError {
                    await MainActor.run {
                        isUploadingImages = false
                        uploadProgress = 0.0
                        updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .failed)
                    }
                    throw NSError(
                        domain: "ImageModeration",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: moderationError.userMessage]
                    )
                }
                
                // Upload image
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                
                let _ = try await storageRef.putDataAsync(compressedData, metadata: metadata)
                
                // Get download URL
                let downloadURL = try await storageRef.downloadURL()
                imageURLs.append(downloadURL.absoluteString)
                storagePaths.append(storageRef.fullPath)
                
                // Update progress
                let progress = Double(index + 1) / Double(totalImages)
                await MainActor.run {
                    uploadProgress = progress
                    updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .uploaded)
                    setUploadCapsuleState(.uploading, stageProgress: progress)
                }
                
                dlog("✅ Uploaded image \(index + 1)/\(totalImages)")
            } catch {
                dlog("❌ Failed to upload image \(index): \(error)")
                failedUploads += 1
                await MainActor.run {
                    updateUploadCapsuleMediaStatus(for: uploadCapsuleImageId(for: index), to: .failed)
                }
                
                // If more than half the images fail, throw error
                if failedUploads > totalImages / 2 {
                    await MainActor.run {
                        isUploadingImages = false
                        uploadProgress = 0.0
                    }
                    throw NSError(
                        domain: "ImageUpload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Too many images failed to upload. Please check your connection and try again."]
                    )
                }
            }
        }
        
        await MainActor.run {
            isUploadingImages = false
            uploadProgress = 0.0
        }

        // If ANY image failed, throw — don't silently post with fewer images than the user selected.
        // A user who selected 4 images expects all 4 to appear. Posting with 3 is a silent failure.
        if failedUploads > 0 {
            throw NSError(
                domain: "ImageUpload",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "\(failedUploads) of \(totalImages) image\(failedUploads == 1 ? "" : "s") failed to upload. Please check your connection and try again."]
            )
        }

        return (urls: imageURLs, groupPath: groupPath, storagePaths: storagePaths)
    }

    private func uploadWitnessAttachment(
        _ attachment: WitnessDraftAttachment,
        startingOrder: Int
    ) async throws -> WitnessUploadResult {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "CreatePostView",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }

        guard let finalURL = attachment.finalFileURL else {
            throw NSError(
                domain: "WitnessUpload",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Witness capture file is missing."]
            )
        }

        WitnessCameraAnalytics.track("witness_upload_started", parameters: [
            "mode": attachment.mode.rawValue
        ])

        let storage = FirebaseManager.shared.storage.reference()
        let postID = await MainActor.run { ensurePendingPublishSession() }
        let rootPath = "post_media/\(userId)/\(postID)/witness"

        await MainActor.run {
            trackPendingUploadCleanupPath(rootPath)
        }

        let finalRef = storage.child(rootPath).child("final").child(finalURL.lastPathComponent)
        let finalData = try Data(contentsOf: finalURL)
        let finalMetadata = StorageMetadata()
        finalMetadata.contentType = attachment.isVideo ? "video/mp4" : "image/jpeg"
        _ = try await finalRef.putDataAsync(finalData, metadata: finalMetadata)
        let finalDownloadURL = try await finalRef.downloadURL()

        var thumbnailDescriptor: WitnessMediaAssetDescriptor?
        var thumbnailDownloadURL: URL?
        if let thumbnailURL = attachment.thumbnailFileURL {
            let thumbnailRef = storage.child(rootPath).child("thumbs").child(thumbnailURL.lastPathComponent)
            let thumbnailData = try Data(contentsOf: thumbnailURL)
            let thumbnailMetadata = StorageMetadata()
            thumbnailMetadata.contentType = "image/jpeg"
            _ = try await thumbnailRef.putDataAsync(thumbnailData, metadata: thumbnailMetadata)
            let downloadURL = try await thumbnailRef.downloadURL()
            thumbnailDownloadURL = downloadURL
            thumbnailDescriptor = WitnessMediaAssetDescriptor(
                url: downloadURL.absoluteString,
                storagePath: thumbnailRef.fullPath,
                thumbnailURL: nil,
                width: attachment.thumbnailAsset?.width,
                height: attachment.thumbnailAsset?.height,
                durationSec: nil,
                contentType: "image/jpeg"
            )
        }

        func uploadRawAsset(_ asset: WitnessMediaAssetDescriptor?, folder: String) async throws -> WitnessMediaAssetDescriptor? {
            guard let asset, let localPath = asset.localPath else { return nil }
            let sourceURL = URL(fileURLWithPath: localPath)
            let ref = storage.child(rootPath).child("raw").child(folder).child(sourceURL.lastPathComponent)
            let data = try Data(contentsOf: sourceURL)
            let metadata = StorageMetadata()
            metadata.contentType = asset.contentType
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let downloadURL = try await ref.downloadURL()
            return WitnessMediaAssetDescriptor(
                url: downloadURL.absoluteString,
                storagePath: ref.fullPath,
                width: asset.width,
                height: asset.height,
                durationSec: asset.durationSec,
                contentType: asset.contentType
            )
        }

        let uploadedFrontAsset = try await uploadRawAsset(attachment.frontAsset, folder: "front")
        let uploadedBackAsset = try await uploadRawAsset(attachment.backAsset, folder: "back")

        let finalDescriptor = WitnessMediaAssetDescriptor(
            url: finalDownloadURL.absoluteString,
            storagePath: finalRef.fullPath,
            thumbnailURL: thumbnailDownloadURL?.absoluteString,
            width: attachment.finalAsset.width,
            height: attachment.finalAsset.height,
            durationSec: attachment.durationSec,
            contentType: attachment.finalAsset.contentType
        )

        let mediaItem = PostMediaItem(
            type: attachment.postMediaType,
            url: finalDownloadURL.absoluteString,
            thumbnailURL: thumbnailDownloadURL?.absoluteString,
            aspectRatio: {
                guard let width = attachment.finalAsset.width,
                      let height = attachment.finalAsset.height,
                      height > 0 else { return nil }
                return CGFloat(width) / CGFloat(height)
            }(),
            order: startingOrder,
            duration: attachment.durationSec,
            fileSize: Int64(finalData.count),
            width: attachment.finalAsset.width,
            height: attachment.finalAsset.height
        )

        let metadata = PostWitnessMediaMetadata(
            mode: attachment.mode,
            layout: attachment.layout,
            durationSec: attachment.durationSec,
            frontAsset: uploadedFrontAsset,
            backAsset: uploadedBackAsset,
            finalAsset: finalDescriptor,
            thumbnailAsset: thumbnailDescriptor,
            captureTimestamp: attachment.captureTimestamp,
            retakesUsed: attachment.retakeCount,
            deviceMultiCamSupported: attachment.deviceMultiCamSupported
        )

        WitnessCameraAnalytics.track("witness_upload_completed", parameters: [
            "mode": attachment.mode.rawValue
        ])
        return WitnessUploadResult(mediaItem: mediaItem, metadata: metadata, storageRootPath: rootPath)
    }

    /// Delete an entire Storage folder path to clean up orphaned images after a failed post write.
    private func deleteStorageFolder(path: String) {
        let folderRef = FirebaseManager.shared.storage.reference().child(path)
        Task.detached(priority: .utility) {
            do {
                let listing = try await folderRef.listAll()
                for item in listing.items {
                    do {
                        try await item.delete()
                    } catch {
                        dlog("⚠️ CreatePostView: failed to delete orphaned upload — \(error)")
                    }
                }
                dlog("🗑️ Cleaned up orphaned upload folder: \(path)")
            } catch {
                dlog("⚠️ Failed to clean up orphaned upload folder \(path): \(error)")
            }
        }
    }

    /// Compress image to target size
    nonisolated private func compressImage(_ data: Data, maxSizeInMB: Double) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        let maxBytes = Int(maxSizeInMB * 1024 * 1024)
        var compression: CGFloat = 0.9
        var imageData = image.jpegData(compressionQuality: compression)
        
        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }
        
        return imageData
    }
    
    // MARK: - Thread Publishing

    /// Publishes each post in the thread sequentially, linking them via a shared threadId.
    /// The head post (index 0) gets isThreadHead=true and threadPostCount=N.
    private func publishThread(
        posts: [String],
        category: Post.PostCategory,
        topicTag: String?,
        allowComments: Bool
    ) {
        dlog("🧵 [Thread DEBUG] publishThread() called with \(posts.count) posts")
        
        let filledPosts = posts.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        dlog("🧵 [Thread DEBUG] Filtered to \(filledPosts.count) non-empty posts")
        
        guard filledPosts.count > 1 else {
            dlog("🧵 [Thread DEBUG] Less than 2 posts, falling back to publishImmediately")
            publishImmediately(
                content: filledPosts.first ?? "",
                category: category,
                topicTag: topicTag,
                allowComments: allowComments,
                linkURL: linkURL.isEmpty ? linkController.activeURL?.absoluteString : linkURL
            )
            return
        }

        activePublishTask?.cancel()
        activePublishTask = Task {
            defer {
                Task { @MainActor in
                    if isPublishing { stopPublishAttempt() }
                }
            }

            dlog("🧵 [Thread DEBUG] Task started, checking currentUser...")
            
            guard let currentUser = Auth.auth().currentUser else {
                dlog("❌ [Thread DEBUG] No currentUser found!")
                await MainActor.run {
                    stopPublishAttempt()
                    errorMessage = "You must be signed in to post."
                    showingErrorAlert = true
                }
                return
            }
            
            dlog("🧵 [Thread DEBUG] currentUser found: \(currentUser.uid)")

            let threadId = UUID().uuidString
            let threadCount = filledPosts.count
            var authorProfileImageURL: String? = nil

            // Fetch author profile image once
            authorProfileImageURL = UserProfileImageCache.shared.cachedProfileImageURL

            dlog("🧵 [Thread DEBUG] Profile image URL: \(authorProfileImageURL ?? "nil")")
            dlog("🧵 [Thread] Publishing \(threadCount) posts with threadId: \(threadId)")

            // Seed per-segment Firestore document IDs on first attempt; reuse on retry
            // so setData() is idempotent — a partial-failure retry overwrites the same
            // documents rather than creating duplicates.
            await MainActor.run {
                if pendingThreadSegmentIds.count != threadCount {
                    pendingThreadSegmentIds = (0..<threadCount).map { _ in UUID().uuidString }
                }
            }
            let segmentIds = await MainActor.run { pendingThreadSegmentIds }

            // CF-01 Part B: Track successfully-written segment IDs so we can roll them
            // back (delete) if a later segment write fails, preventing a partial thread.
            var writtenSegmentIds: [String] = []

            for (index, postContent) in filledPosts.enumerated() {
                dlog("🧵 [Thread DEBUG] Preparing post \(index + 1)/\(threadCount)...")

                let postId = segmentIds[index]
                let timestamp = Date().addingTimeInterval(Double(index) * 0.05)

                dlog("🧵 [Thread DEBUG] Post ID: \(postId), timestamp: \(timestamp)")

                var postData: [String: Any] = [
                    "authorId": currentUser.uid,
                    "authorName": currentUser.displayName ?? "User",
                    "authorInitials": String((currentUser.displayName ?? "U").prefix(1)),
                    "content": postContent,
                    "category": category.rawValue,
                    "topicTag": topicTag as Any,
                    "visibility": postVisibility.rawValue,
                    "allowComments": allowComments,
                    "createdAt": Timestamp(date: timestamp),
                    "amenCount": 0,
                    "commentCount": 0,
                    "repostCount": 0,
                    "lightbulbCount": 0,
                    "threadId": threadId,
                    "threadIndex": index,
                    "isThreadHead": index == 0,
                    "threadPostCount": index == 0 ? threadCount : 0,
                    "moderationStatus": "pending",
                    "clientSafetyVersion": 1,
                    // CF-01 Part A: segment document ID doubles as the idempotency key;
                    // it is stable across retries (pendingThreadSegmentIds is preserved).
                    "idempotencyKey": postId
                ]

                dlog("🧵 [Thread DEBUG] Base postData created")

                if let url = authorProfileImageURL {
                    postData["authorProfileImageURL"] = url
                }
                if hasSensitiveContent {
                    postData["hasSensitiveContent"] = true
                }
                // First post in thread carries link preview if any
                if index == 0, let lm = linkController.metadata {
                    postData["linkPreviewTitle"] = lm.title as Any
                    postData["linkPreviewDescription"] = lm.description as Any
                    postData["linkPreviewImageURL"] = lm.imageURL?.absoluteString as Any
                    postData["linkPreviewSiteName"] = lm.siteName as Any
                    dlog("🧵 [Thread DEBUG] Added link preview to first post")
                }
                if index == 0, let smartAttachment,
                   let encodedAttachment = try? Firestore.Encoder().encode(smartAttachment) {
                    postData["smartAttachment"] = encodedAttachment
                    postData["hasSmartAttachment"] = true
                    postData["attachmentCount"] = 1
                    postData["primaryAttachmentId"] = smartAttachment.id
                    postData["soundtrackEnabled"] = useSmartAttachmentAsSoundtrack
                    postData["smartObjectIds"] = [smartAttachment.id]
                    postData["primarySmartObjectId"] = smartAttachment.id
                    postData["objectType"] = smartAttachment.type.rawValue
                    postData["sourceProvider"] = smartAttachment.provider.rawValue
                    postData["canonicalUrl"] = smartAttachment.canonicalUrl
                    postData["safetyState"] = smartAttachment.safetyStatus.rawValue
                    postData["explicitContentState"] = smartAttachment.safetyStatus == .blocked ? "blocked" : "unknown"
                }

                dlog("🧵 [Thread DEBUG] Writing post \(index + 1) to Firestore...")

                do {
                    try await FirebaseManager.shared.firestore
                        .collection("posts")
                        .document(postId)
                        .setData(postData)
                    writtenSegmentIds.append(postId)  // CF-01: record for rollback
                    dlog("✅ [Thread] Post \(index + 1)/\(threadCount) published successfully")
                    // Wire hub preview for the thread head post
                    if index == 0, let smartAttachment, AMENFeatureFlags.shared.communityHubsEnabled {
                        _ = await AmenCommunityHubService.shared.attachHubPreview(
                            postId: postId,
                            url: smartAttachment.canonicalUrl,
                            objectType: smartAttachment.type.rawValue,
                            title: smartAttachment.title
                        )
                    }
                } catch {
                    dlog("❌ [Thread] Failed to publish post \(index + 1): \(error)")
                    dlog("❌ [Thread DEBUG] Error details: \(error.localizedDescription)")
                    // CF-01 Part B rollback: delete all segments already written so the
                    // author does not see an incomplete thread in their feed.
                    if !writtenSegmentIds.isEmpty {
                        dlog("🔄 [CF-01] Rolling back \(writtenSegmentIds.count) written thread segment(s)...")
                        let db = FirebaseManager.shared.firestore
                        for writtenId in writtenSegmentIds {
                            try? await db.collection("posts").document(writtenId).delete()
                        }
                    }
                    await MainActor.run {
                        stopPublishAttempt(markDraftFailed: true)
                        errorMessage = "Thread post \(index + 1) failed to publish. Please try again."
                        showingErrorAlert = true
                    }
                    return
                }
            }

            dlog("🧵 [Thread DEBUG] All posts written successfully, cleaning up UI state...")

            // Increment user's post count by the number of thread segments published
            let _uid = currentUser.uid
            let _count = threadCount
            Task.detached(priority: .utility) {
                try? await FirebaseManager.shared.firestore
                    .collection("users").document(_uid)
                    .updateData(["postsCount": FieldValue.increment(Int64(_count))])
            }

            await MainActor.run {
                dlog("🧵 [Thread DEBUG] On MainActor, resetting state...")
                inFlightPostId = nil
                draftVM.markPublished()
                pendingThreadSegmentIds = []  // Clear so a future thread gets fresh IDs
                isThreadMode = false
                threadPosts = [""]
                currentThreadIndex = 0
                linkController.reset()
                UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
                shouldPersistDraftOnExit = false
                cameraCoordinator.removeAttachedMedia()
                mediaMetadataDraft = CreatePostMediaMetadataDraft()
                // CF-01 Part A: Thread published successfully — clear idempotency key.
                postIdempotencyKey = nil
                withAnimation(reduceMotion ? nil : .default) { showingSuccessNotice = true }
                HapticManager.notification(type: .success)
                // Record post for community guidelines eligibility tracking
                CommunityGuidelinesEligibilityService.shared.recordPostPublished()
                dlog("[Thread] Scheduling dismiss...")
                scheduleDelayedAction(seconds: 0.15) { dismiss() }
            }

            dlog("[Thread] All \(threadCount) posts published successfully")
        }
    }

    private func schedulePost(
        content: String,
        category: Post.PostCategory,
        topicTag: String?,
        allowComments: Bool,
        linkURL: String?,
        scheduledFor: Date
    ) {
        let scheduledPostId = ensurePendingPublishSession()
        let scheduledClientRequestId = uploadCapsuleClientRequestId ?? scheduledPostId
        let scheduledIdempotencyKey = uploadCapsuleIdempotencyKey ?? scheduledPostId
        activePublishTask?.cancel()
        activePublishTask = Task {
            do {
                // Upload images first if any
                var imageURLs: [String]? = nil
                var mediaItems: [PostMediaItem] = []
                var witnessMedia: PostWitnessMediaMetadata? = nil
                if !selectedImageData.isEmpty {
                    let uploadResult = try await uploadImages()
                    imageURLs = uploadResult.urls
                    mediaItems = applyMetadataToImageItems(urls: uploadResult.urls)
                }

                if let witnessAttachment = cameraCoordinator.attachedWitnessMedia {
                    let witnessUpload = try await uploadWitnessAttachment(witnessAttachment, startingOrder: mediaItems.count)
                    mediaItems.append(applyMetadataToVideoItem(witnessUpload.mediaItem))
                    witnessMedia = witnessUpload.metadata
                }
                
                // MARK: - ✅ IMPLEMENTED: Scheduled Posts with Cloud Functions
                dlog("📅 Scheduling post via Cloud Functions...")
                
                // Save to Firestore scheduled_posts collection
                guard let scheduledAuthorId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "CreatePostView", code: 401,
                                  userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
                }
                
                let scheduledPostData: [String: Any] = [
                    "content": content,
                    "category": category.rawValue,
                    "topicTag": topicTag as Any,
                    "allowComments": allowComments,
                    "linkURL": linkURL as Any,
                    "imageURLs": imageURLs as Any,
                    "scheduledFor": Timestamp(date: scheduledFor),
                    "createdAt": Timestamp(date: Date()),
                    "authorId": scheduledAuthorId,
                    "status": "pending",
                    "clientRequestId": scheduledClientRequestId,
                    "idempotencyKey": scheduledIdempotencyKey
                ]
                var mutableScheduledPostData = scheduledPostData
                if !mediaItems.isEmpty,
                   let encodedMediaItems = try? Firestore.Encoder().encode(mediaItems) {
                    mutableScheduledPostData["mediaItems"] = encodedMediaItems
                }
                if let witnessMedia,
                   let encodedWitnessMedia = try? Firestore.Encoder().encode(witnessMedia) {
                    mutableScheduledPostData["witnessMedia"] = encodedWitnessMedia
                }
                
                try await FirebaseManager.shared.firestore
                    .collection("scheduled_posts")
                    .document(scheduledPostId)
                    .setData(mutableScheduledPostData)
                
                await MainActor.run {

                    withAnimation(reduceMotion ? nil : .default) {
                        showingSuccessNotice = true
                    }

                    isPublishing = false
                    inFlightPostId = nil  // FIX: clear hash so user can post again after scheduling
                    draftVM.markPublished()
                    shouldPersistDraftOnExit = false
                    clearPendingPublishSession()
                    clearPendingUploadCleanupPaths()
                    cameraCoordinator.removeAttachedMedia()
                    
                    // P0-2 FIX: Cancellable dismiss
                    scheduleDelayedAction(seconds: 0.5) {
                        dismiss()
                    }
                    
                    dlog("✅ Post scheduled successfully for: \(scheduledFor)")
                }
                
                // ✅ executeScheduledPosts Cloud Function deployed in scheduledPostsFunctions.js
                // Runs every 5 minutes via Cloud Scheduler — queries scheduled_posts where
                // status="pending" and scheduledFor <= now, creates real posts, marks as "published".
                
            } catch {
                await MainActor.run {
                    cleanupPendingUploadArtifacts()
                    let friendlyError = getUserFriendlyError(from: error)
                    
                    // P1-6 FIX: Offer retry for network errors
                    let nsError = error as NSError
                    let isNetworkError = nsError.domain == NSURLErrorDomain || 
                                         nsError.code == NSURLErrorNotConnectedToInternet ||
                                         nsError.code == NSURLErrorTimedOut ||
                                         nsError.localizedDescription.lowercased().contains("network") ||
                                         nsError.localizedDescription.lowercased().contains("connection")
                    
                    showError(
                        title: friendlyError.title, 
                        message: friendlyError.message,
                        isRetryable: isNetworkError,
                        retry: isNetworkError ? {
                            publishPost()
                        } : nil
                    )
                    stopPublishAttempt(markDraftFailed: true)
                }
            }
        }
    }
    
    // MARK: - ✅ IMPLEMENTED: Mention Users
    
    /// Search for users to mention
    private func searchForMentions(query: String) {
        guard !query.isEmpty else {
            withAnimation(reduceMotion ? nil : .default) {
                showMentionSuggestions = false
                mentionSuggestions = []
            }
            return
        }

        // Cancel any in-flight search so a stale callback cannot write to @State
        // after the TextEditor's keyboard session has been torn down, which would
        // trigger RTIInputSystemClient UIEmojiSearchOperations on a null session → SIGABRT.
        mentionSearchTask?.cancel()
        mentionSearchTask = Task {
            do {
                let results = try await AlgoliaSearchService.shared.searchUsers(query: query)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .default) {
                        // Limit to 5 results
                        mentionSuggestions = Array(results.prefix(5))
                        showMentionSuggestions = !results.isEmpty
                    }
                }
            } catch {
                dlog("⚠️ Failed to search for mentions: \(error)")
            }
        }
    }

    /// Insert mention into text
    private func insertMention(_ user: AlgoliaUser) {
        // Find the last @ symbol and replace from there
        if let lastAtIndex = postText.lastIndex(of: "@") {
            let beforeMention = postText[..<lastAtIndex]
            postText = beforeMention + "@\(user.username) "
        }

        withAnimation(reduceMotion ? nil : .default) {
            showMentionSuggestions = false
            mentionSuggestions = []
        }
    }
    
    // MARK: - ✅ IMPLEMENTED: Draft Auto-Save (Every 30s)
    
    /// Start auto-save task using Swift Concurrency
    private func startAutoSaveTimer() {
        autoSaveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 second heartbeat (text-change path handles frequent saves)
                if !Task.isCancelled {
                    autoSaveDraft()
                }
            }
        }
    }

    /// P1-4: Debounced autosave triggered by text changes — saves 3 seconds after the user stops typing
    private func scheduleAutosave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds after last keystroke
            guard !Task.isCancelled else { return }
            autoSaveDraft()
            // Resume heartbeat loop after the debounce fires
            startAutoSaveTimer()
        }
    }
    
    /// Auto-save draft silently
    private func autoSaveDraft() {
        // P1-2 FIX: Don't auto-save while publishing
        guard !isPublishing else {
            dlog("⏭️ [P1-2] Skipping auto-save - post is publishing")
            return
        }
        
        // Only auto-save if there's content
        let hasText = !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText
            || cameraCoordinator.attachedWitnessMedia != nil
            || !selectedImageData.isEmpty
            || showingPoll
            || isThreadMode else {
            return
        }
        
        // Save to UserDefaults for quick recovery
        // Note: UserDefaults cannot store nil values, so we only add non-empty values
        var autoSaveDraft: [String: Any] = [
            "content": postText,
            "category": selectedCategory.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Only add optional fields if they have values
        if !selectedTopicTag.isEmpty {
            autoSaveDraft["topicTag"] = selectedTopicTag
        }
        
        if !linkURL.isEmpty {
            autoSaveDraft["linkURL"] = linkURL
        }

        if let witnessAttachment = cameraCoordinator.attachedWitnessMedia,
           let encoded = try? JSONEncoder().encode(witnessAttachment),
           let encodedString = String(data: encoded, encoding: .utf8) {
            autoSaveDraft["witnessAttachment"] = encodedString
        }

        if let encodedMetadata = try? JSONEncoder().encode(mediaMetadataDraft),
           let encodedString = String(data: encodedMetadata, encoding: .utf8) {
            autoSaveDraft["mediaMetadataDraft"] = encodedString
        }

        let effectiveVerseReference = verseAttachmentVM.attachedScripture?.canonicalReference ?? attachedVerseReference
        let effectiveVerseText = verseAttachmentVM.attachedScripture?.previewText ?? attachedVerseText
        autoSaveDraft["showingPoll"] = showingPoll
        autoSaveDraft["pollQuestion"] = pollQuestion
        autoSaveDraft["pollOptions"] = pollOptions
        autoSaveDraft["pollDuration"] = pollDuration.rawValue
        autoSaveDraft["attachedVerseReference"] = effectiveVerseReference
        autoSaveDraft["attachedVerseText"] = effectiveVerseText
        autoSaveDraft["isThreadMode"] = isThreadMode
        autoSaveDraft["threadPosts"] = threadPosts
        autoSaveDraft["currentThreadIndex"] = currentThreadIndex
        
        UserDefaults.standard.set(autoSaveDraft, forKey: "autoSavedDraft")

        // Persist to SwiftData via ViewModel — includes phase state alongside content snapshot
        draftVM.persistSnapshot(
            postText: postText,
            categoryRawValue: selectedCategory.rawValue,
            topicTag: selectedTopicTag,
            linkURL: linkURL,
            pollQuestion: pollQuestion,
            pollOptions: pollOptions,
            pollDurationRawValue: pollDuration.rawValue,
            showingPoll: showingPoll,
            isThreadMode: isThreadMode,
            threadPosts: threadPosts,
            currentThreadIndex: currentThreadIndex,
            postVisibilityRawValue: postVisibility.rawValue,
            commentPermissionRawValue: commentPermission.rawValue,
            attachedVerseReference: effectiveVerseReference,
            attachedVerseText: effectiveVerseText,
            taggedChurchId: taggedChurchId,
            taggedChurchName: taggedChurchName,
            hideEngagementCounts: hideEngagementCounts,
            hasSensitiveContent: hasSensitiveContent,
            sensitiveContentReason: sensitiveContentReason,
            imageAltTexts: imageAltTexts,
            imageCount: selectedImageData.count,
            witnessAttachmentJSON: autoSaveDraft["witnessAttachment"] as? String,
            mediaMetadataDraftJSON: autoSaveDraft["mediaMetadataDraft"] as? String
        )

        dlog("💾 Auto-saved draft at \(Date())")
    }
    
    /// Check for draft recovery on appear
    private func checkForDraftRecovery() {
        // P1-14: Don't offer recovery if the user has already started typing
        guard postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Prefer SwiftData via ViewModel — restores phase state + returns content draft
        if let sd = draftVM.restoreIfAvailable() {
            let draft = Draft(
                id: UUID().uuidString,
                content: sd.postText,
                category: sd.categoryRawValue.isEmpty ? selectedCategory.rawValue : sd.categoryRawValue,
                topicTag: sd.topicTag.isEmpty ? nil : sd.topicTag,
                linkURL: sd.linkURL.isEmpty ? nil : sd.linkURL,
                visibility: sd.postVisibilityRawValue,
                createdAt: sd.createdAt,
                witnessAttachment: Self.decodeWitnessAttachment(from: sd.witnessAttachmentJSON),
                mediaMetadataDraft: Self.decodeMediaMetadataDraft(from: sd.mediaMetadataDraftJSON),
                attachedVerseReference: sd.attachedVerseReference,
                attachedVerseText: sd.attachedVerseText,
                showingPoll: sd.showingPoll,
                pollQuestion: sd.pollQuestion,
                pollOptions: sd.pollOptions,
                pollDurationRawValue: sd.pollDurationRawValue.isEmpty ? nil : sd.pollDurationRawValue,
                isThreadMode: sd.isThreadMode,
                threadPosts: sd.threadPosts,
                currentThreadIndex: sd.currentThreadIndex
            )
            recoveredDraft = draft
            if sd.inFlightPostId != nil || sd.uploadPhaseRawValue == LocalPostDraftUploadPhase.uploading.rawValue {
                if let recoveredPostId = sd.inFlightPostId, !recoveredPostId.isEmpty {
                    pendingPublishPostID = recoveredPostId
                    uploadCapsuleClientRequestId = recoveredPostId
                    uploadCapsuleIdempotencyKey = recoveredPostId
                }
                draftVM.markFailed()
                publishFailureBannerMessage = "Your last publish did not finish. Review the draft and try again."
            }
            showDraftRecovery = true
            return
        }

        // Fall back to UserDefaults (legacy, non-user-scoped)
        guard let autoSaved = UserDefaults.standard.dictionary(forKey: "autoSavedDraft"),
              let timestamp = autoSaved["timestamp"] as? TimeInterval else {
            return
        }
        let content = autoSaved["content"] as? String ?? ""
        let witnessAttachment = Self.decodeWitnessAttachment(from: autoSaved["witnessAttachment"] as? String)
        let metadataDraft = Self.decodeMediaMetadataDraft(from: autoSaved["mediaMetadataDraft"] as? String)
        let recoveredThreadPosts = autoSaved["threadPosts"] as? [String] ?? [""]
        let recoveredIsThreadMode = autoSaved["isThreadMode"] as? Bool ?? false
        let recoveredShowingPoll = autoSaved["showingPoll"] as? Bool ?? false
        let recoveredPollOptions = autoSaved["pollOptions"] as? [String] ?? ["", ""]
        guard !content.isEmpty
            || witnessAttachment != nil
            || recoveredShowingPoll
            || recoveredIsThreadMode
            || recoveredThreadPosts.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        
        // Only offer recovery if draft is less than 24 hours old
        let draftAge = Date().timeIntervalSince1970 - timestamp
        guard draftAge < 86400 else { // 24 hours
            clearRecoveredDraft()
            return
        }
        
        // Create recovered draft
        let draft = Draft(
            id: UUID().uuidString,
            content: content,
            category: autoSaved["category"] as? String ?? selectedCategory.rawValue,
            topicTag: autoSaved["topicTag"] as? String,
            linkURL: autoSaved["linkURL"] as? String,
            visibility: "everyone",
            createdAt: Date(timeIntervalSince1970: timestamp),
            witnessAttachment: witnessAttachment,
            mediaMetadataDraft: metadataDraft,
            attachedVerseReference: autoSaved["attachedVerseReference"] as? String ?? "",
            attachedVerseText: autoSaved["attachedVerseText"] as? String ?? "",
            showingPoll: recoveredShowingPoll,
            pollQuestion: autoSaved["pollQuestion"] as? String ?? "",
            pollOptions: recoveredPollOptions,
            pollDurationRawValue: autoSaved["pollDuration"] as? String,
            isThreadMode: recoveredIsThreadMode,
            threadPosts: recoveredThreadPosts,
            currentThreadIndex: autoSaved["currentThreadIndex"] as? Int ?? 0
        )
        
        recoveredDraft = draft
        showDraftRecovery = true
    }
    
    /// Load recovered draft
    private func loadDraft(_ draft: Draft) {
        postText = draft.content
        
        if let categoryString = draft.category,
           let category = PostCategory.allCases.first(where: { $0.rawValue == categoryString }) {
            selectedCategory = category
        }
        
        selectedTopicTag = draft.topicTag ?? ""
        linkURL = draft.linkURL ?? ""
        attachedVerseReference = draft.attachedVerseReference
        attachedVerseText = draft.attachedVerseText
        if !draft.attachedVerseReference.isEmpty {
            verseAttachmentVM.restoreFromLegacy(reference: draft.attachedVerseReference, text: draft.attachedVerseText)
        }
        cameraCoordinator.restoreDraftAttachment(draft.witnessAttachment)
        mediaMetadataDraft = draft.mediaMetadataDraft ?? CreatePostMediaMetadataDraft()
        showingPoll = draft.showingPoll
        pollQuestion = draft.pollQuestion
        pollOptions = max(2, draft.pollOptions.count) >= 2 ? draft.pollOptions : ["", ""]
        if let rawValue = draft.pollDurationRawValue,
           let duration = PollDuration(rawValue: rawValue) {
            pollDuration = duration
        } else {
            pollDuration = .oneDay
        }
        isThreadMode = draft.isThreadMode
        threadPosts = draft.threadPosts.isEmpty ? [""] : draft.threadPosts
        currentThreadIndex = min(draft.currentThreadIndex, max(threadPosts.count - 1, 0))
        syncMediaMetadataDraftFromCurrentAttachments()
        
        dlog("✅ Recovered draft from \(draft.createdAt)")
    }
    
    /// Clear recovered draft
    private func clearRecoveredDraft() {
        draftVM.clearDraft()  // clears SwiftData + UserDefaults "autoSavedDraft"
        recoveredDraft = nil
    }

    private static func decodeWitnessAttachment(from string: String?) -> WitnessDraftAttachment? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WitnessDraftAttachment.self, from: data)
    }

    private static func decodeMediaMetadataDraft(from string: String?) -> CreatePostMediaMetadataDraft? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CreatePostMediaMetadataDraft.self, from: data)
    }
    
    // Link preview is handled by linkController (ComposerLinkPreviewController).
    
    // MARK: - ScheduledWhenLine Helper View
    
    private struct ScheduledWhenLine: View {
        let date: Date
        var body: some View {
            HStack(spacing: 0) {
                Text(date, style: .date)
                    .font(AMENFont.bold(14))
                    .foregroundStyle(.primary)
                Text(" at ")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                Text(date, style: .time)
                    .font(AMENFont.bold(14))
                    .foregroundStyle(.primary)
            }
        }
    }
    
    // MARK: - EditorPlaceholderView Helper
    
    private struct EditorPlaceholderView: View {
        let isEmpty: Bool
        let placeholder: String
        let description: String
        
        var body: some View {
            Group {
                if isEmpty {
                    Text(placeholder)
                        .font(AMENFont.regular(17))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Circle Post Button

enum PostButtonState {
    case idle
    case ready
    case posting
    case sent
}

struct CirclePostButton: View {
    @Binding var postText: String
    let onPost: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var buttonState: PostButtonState = .idle
    @State private var isPressed = false
    @State private var iconScale: CGFloat = 1
    @State private var iconOpacity: Double = 1
    @State private var iconRotation: Double = 0
    @State private var showSpinner = false
    @State private var showCheck = false
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0
    @State private var ringProgress: CGFloat = 0
    @State private var pulseTimer: Timer?
    
    var body: some View {
        ZStack {
            // 1. Pulse ring (bottom layer, behind everything)
            if buttonState == .ready {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 42, height: 42)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .onAppear {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 2).repeatForever(autoreverses: false)) {
                            pulseScale = 1.3
                            pulseOpacity = 0
                        }
                        // Reset pulse for continuous animation — timer is stored and invalidated on disappear
                        pulseTimer?.invalidate()
                        pulseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                            pulseScale = 1
                            pulseOpacity = 0.3
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 2)) {
                                pulseScale = 1.3
                                pulseOpacity = 0
                            }
                        }
                    }
                    .onDisappear {
                        pulseTimer?.invalidate()
                        pulseTimer = nil
                    }
            }
            
            // 2. Solid fill circle (button background)
            Circle()
                .fill(circleBackgroundColor)
                .frame(width: 42, height: 42)
                .shadow(
                    color: buttonState == .ready ? Color.white.opacity(0.15) : .clear,
                    radius: 10
                )
            
            // 3. Border ring overlay (with animated stroke for READY state)
            if buttonState == .ready {
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        Color.white.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))
                    .onAppear {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                            ringProgress = 1.0
                        }
                    }
            } else if buttonState == .idle {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                    .frame(width: 42, height: 42)
            }
            
            // 4. Icons ZStack (send / spinner / check) on top
            ZStack {
                // Send icon (paperplane)
                Image(systemName: "paperplane.fill")
                    .font(.systemScaled(17, weight: .medium))
                    .foregroundStyle(iconColor)
                    .opacity(iconOpacity)
                    .scaleEffect(iconScale)
                    .rotationEffect(.degrees(iconRotation))
                
                // Spinner (posting state)
                if showSpinner {
                    SpinnerRing()
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Checkmark (sent state)
                if showCheck {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(14, weight: .bold))
                        .foregroundStyle(.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 18, height: 18)
        }
        .scaleEffect(isPressed ? 0.86 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && buttonState == .ready {
                        isPressed = true
                        HapticManager.impact(style: .light)
                    }
                }
                .onEnded { _ in
                    if isPressed && buttonState == .ready {
                        isPressed = false
                        triggerPost()
                    }
                }
        )
        .onChange(of: postText) { oldValue, newValue in
            updateButtonState(for: newValue)
        }
    }

    // MARK: - Computed Properties

    private var circleBackgroundColor: Color {
        switch buttonState {
        case .idle:
            return Color(.tertiarySystemFill)   // adaptive gray, visible on light & dark nav bar
        case .ready:
            return Color(.label)                // black in light mode, white in dark mode
        case .posting:
            return Color(.tertiarySystemFill)
        case .sent:
            return Color(.label)
        }
    }

    private var iconColor: Color {
        switch buttonState {
        case .idle:
            return Color(.secondaryLabel)       // medium gray, clearly visible on any bg
        case .ready, .sent:
            return Color(.systemBackground)     // white on black / black on white
        case .posting:
            return Color(.systemBackground)
        }
    }
    
    // MARK: - State Management
    
    private func updateButtonState(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty && buttonState == .idle {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                buttonState = .ready
                ringProgress = 0
            }
        } else if trimmed.isEmpty && buttonState == .ready {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                buttonState = .idle
                ringProgress = 0
            }
        }
    }

    private func triggerPost() {
        guard buttonState == .ready else { return }

        // Transition to posting state
        buttonState = .posting

        // Icon launch animation
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.28)) {
            iconRotation = 35
            iconScale = 0.15
            iconOpacity = 0
        }

        // Show spinner after 220ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.65))) {
                showSpinner = true
            }

            // Execute post action
            Task {
                await onPost()

                // Transition to sent state after posting completes
                await MainActor.run {
                    transitionToSent()
                }
            }
        }
    }

    private func transitionToSent() {
        buttonState = .sent

        // Collapse spinner
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showSpinner = false
        }

        // Show checkmark after 150ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.55))) {
                showCheck = true
            }

            // Reset to idle after 1.2s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                    resetToIdle()
                }
            }
        }
    }
    
    private func resetToIdle() {
        buttonState = .idle
        showCheck = false
        iconScale = 1
        iconOpacity = 1
        iconRotation = 0
        ringProgress = 0
        pulseScale = 1
        pulseOpacity = 0
    }
}

// MARK: - Threads-Style Post Button

struct ThreadsPostButton: View {
    @Binding var postText: String
    let onPost: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var buttonState: PostButtonState = .idle
    @State private var isPressed = false
    @State private var showSpinner = false
    @State private var showCheck = false
    
    var body: some View {
        Button {
            guard buttonState == .ready else { return }
            triggerPost()
        } label: {
            ZStack {
                // "Post" text (idle/ready state)
                if !showSpinner && !showCheck {
                    Text("Post")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(buttonState == .ready ? Color.primary : Color.secondary)
                }
                
                // Spinner (posting state)
                if showSpinner {
                    ProgressView()
                        .tint(.primary)
                        .scaleEffect(0.8)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Checkmark (sent state)
                if showCheck {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(14, weight: .bold))
                        .foregroundStyle(.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minWidth: 44)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showSpinner)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showCheck)
        }
        .buttonStyle(.plain)
        .disabled(buttonState != .ready)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && buttonState == .ready {
                        isPressed = true
                        HapticManager.impact(style: .light)
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .onChange(of: postText) { oldValue, newValue in
            updateButtonState(for: newValue)
        }
    }
    
    private func updateButtonState(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty && buttonState == .idle {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                buttonState = .ready
            }
        } else if trimmed.isEmpty && buttonState == .ready {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                buttonState = .idle
            }
        }
    }

    private func triggerPost() {
        guard buttonState == .ready else { return }

        // Transition to posting state
        buttonState = .posting

        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            showSpinner = true
        }

        // Execute post action
        Task {
            await onPost()

            // Transition to sent state after posting completes
            await MainActor.run {
                transitionToSent()
            }
        }
    }

    private func transitionToSent() {
        buttonState = .sent

        // Hide spinner
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showSpinner = false
        }

        // Show checkmark after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6))) {
                showCheck = true
            }

            // Reset to idle after 1s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                    resetToIdle()
                }
            }
        }
    }

    private func resetToIdle() {
        buttonState = .idle
        showCheck = false
    }
}

// MARK: - Spinner Ring

struct SpinnerRing: View {
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Outer track circle
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                .frame(width: 20, height: 20)

            // Spinning arc
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    Color.white.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        }
    }
}

// MARK: - Supporting Views

// MARK: - Glass Category Bar
// Frosted-glass capsule pill with a sliding selection lens.
// Matches the Apple Music floating control reference: single blurred container,
// moving inner-capsule "lens" behind the selected segment, haptic on selection.

struct GlassCategoryBar: View {
    let categories: [CreatePostView.PostCategory]
    @Binding var selected: CreatePostView.PostCategory
    let namespace: Namespace.ID
    let onSelect: (CreatePostView.PostCategory) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(categories, id: \.self) { category in
                GlassCategorySegment(
                    category: category,
                    isSelected: selected == category,
                    namespace: namespace
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.78))) {
                        selected = category
                    }
                    onSelect(category)
                }
                .id(category)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .frame(height: 48)
        // Outer pill — glass container
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
        )
        .clipShape(Capsule())
        // Static neon-red border around the outer capsule
        .overlay(
            Capsule()
                .strokeBorder(
                    Color.primary.opacity(0.75),
                    lineWidth: 1.5
                )
        )
    }
}


/// A single segment inside GlassCategoryBar.
private struct GlassCategorySegment: View {
    let category: CreatePostView.PostCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Label always visible so users can read every category at a glance.
    private var showLabel: Bool { true }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Sliding selection lens — matched geometry so it travels between segments
                if isSelected {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.80),
                                            Color.white.opacity(0.20)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                        .matchedGeometryEffect(id: "selectionLens", in: namespace)
                }

                // Icon + optional label
                HStack(spacing: 5) {
                    Image(systemName: category.icon)
                        .font(.systemScaled(13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .symbolRenderingMode(.hierarchical)

                    if showLabel {
                        Text(segmentLabel)
                            .font(.systemScaled(11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, isSelected ? 10 : 8)
                .padding(.vertical, 6)
            }
            // Minimum 44pt height for accessibility
            .frame(minHeight: 38)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Press feedback via a simultaneous DragGesture with zero threshold
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(Motion.adaptive(.spring(response: 0.18, dampingFraction: 0.7))) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) { isPressed = false }
                }
        )
        .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    // Short label to keep the pill compact
    private var segmentLabel: String {
        switch category {
        case .openTable:      return "OpenTable"
        case .testimonies:    return "Testimony"
        case .prayer:         return "Prayer"
        case .tip:            return "Tip"
        case .funFact:        return "Fun Fact"
        }
    }
}

// Enhanced Toolbar Button with label
struct EnhancedToolbarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                isPressed = true
            }
            
            // Button animation reset (non-critical, safe to use DispatchQueue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                    isPressed = false
                }
            }
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : Color.primary.opacity(0.6))
                
                Text(label)
                    .font(AMENFont.semiBold(10))
                    .foregroundStyle(isActive ? activeColor : .secondary)
            }
            .frame(width: 54, height: 48)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .opacity(isPressed ? 0.7 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Topic Tag Sheet for #OPENTABLE and Prayer Types
struct TopicTagSheet: View {
    @Binding var selectedTag: String
    @Binding var isPresented: Bool
    @Binding var selectedCategory: CreatePostView.PostCategory
    @ObservedObject private var premiumManager = PremiumManager.shared
    @State private var searchText = ""
    @State private var newCustomTag = ""
    @State private var customTopicTags = TopicTagSheet.loadCustomTopicTags()
    @State private var isSyncingCustomTopicTags = false
    @State private var showCustomTagLimitPaywall = false
    @State private var showPremiumUpgrade = false
    @State private var customTagErrorMessage: String?

    private static let customTopicTagsBaseKey = "amen.createPost.customTopicTags"
    
    // OpenTable topic tags
    var openTableTags: [(String, String, Color)] {
        var tags: [(String, String, Color)] = []
        // Technical topics
        tags.append(("AI & Technology", "cpu", .blue))
        tags.append(("Machine Learning", "brain", .purple))
        tags.append(("Ethics & Morality", "scale.3d", .indigo))
        tags.append(("Innovation", "lightbulb.max.fill", .orange))
        tags.append(("Digital Ministry", "app.connected.to.app.below.fill", .green))
        tags.append(("Future of Faith", "clock.arrow.2.circlepath", .cyan))
        tags.append(("Theology & Tech", "brain.head.profile", .pink))
        tags.append(("Social Media & Faith", "bubble.left.and.bubble.right.fill", .mint))
        tags.append(("Automation & Work", "gearshape.2.fill", .teal))
        tags.append(("Blockchain & Web3", "link.circle.fill", .orange))
        tags.append(("Metaverse & VR", "visionpro.fill", .purple))
        tags.append(("Cybersecurity", "lock.shield.fill", .red))
        tags.append(("Data Privacy", "eye.slash.fill", .blue))
        tags.append(("Artificial Intelligence", "sparkles", .yellow))
        tags.append(("Quantum Computing", "atom", .cyan))
        tags.append(("Biotechnology", "cross.vial.fill", .green))
        
        // Business & Career topics
        tags.append(("Entrepreneurship", "briefcase.circle.fill", .blue))
        tags.append(("Business Ethics", "building.2.fill", .green))
        tags.append(("Workplace Faith", "desktopcomputer", .purple))
        tags.append(("Career Development", "chart.line.uptrend.xyaxis", .orange))
        tags.append(("Leadership & Management", "person.crop.circle.badge.checkmark", .indigo))
        tags.append(("Marketing & Media", "megaphone.fill", .pink))
        tags.append(("Startups & Innovation", "rocket.fill", .orange))
        
        // Faith & Life topics
        tags.append(("Faith & Culture", "globe.americas.fill", .blue))
        tags.append(("Relationships", "heart.circle.fill", .pink))
        tags.append(("Family Life", "house.fill", .orange))
        tags.append(("Mental Health", "brain.head.profile", .teal))
        tags.append(("Worship & Music", "music.note", .purple))
        tags.append(("Biblical Studies", "book.closed.fill", .indigo))
        tags.append(("Leadership", "person.3.fill", .green))
        tags.append(("Community", "person.2.fill", .mint))
        tags.append(("Apologetics", "shield.fill", .red))
        tags.append(("Evangelism", "megaphone.fill", .orange))
        tags.append(("Spiritual Growth", "leaf.fill", .green))
        tags.append(("Church Life", "building.columns.fill", .blue))
        tags.append(("Missions", "airplane", .cyan))
        tags.append(("Justice & Mercy", "hand.raised.fill", .yellow))
        tags.append(("Forgiveness", "heart.fill", .pink))
        tags.append(("Hope & Encouragement", "sun.max.fill", .orange))
        tags.append(("Wisdom & Discernment", "eye.fill", .purple))
        tags.append(("Creativity & Arts", "paintpalette.fill", .pink))
        tags.append(("Health & Wellness", "heart.text.square.fill", .red))
        tags.append(("Finance & Stewardship", "dollarsign.circle.fill", .green))
        tags.append(("Education & Learning", "book.fill", .blue))
        tags.append(("Science & Faith", "flask.fill", .cyan))
        tags.append(("Parenting", "figure.2.and.child.holdinghands", .orange))
        return tags
    }
    
    // Prayer types
    let prayerTypes = [
        ("Prayer Request", "hands.sparkles.fill", Color(red: 0.4, green: 0.7, blue: 1.0)),
        ("Praise Report", "hands.clap.fill", Color(red: 1.0, green: 0.7, blue: 0.4)),
        ("Answered Prayer", "checkmark.seal.fill", Color(red: 0.4, green: 0.85, blue: 0.7))
    ]

    // Testimony category tags — must match TestimonyCategory.title values for filtering
    let testimonyTags: [(String, String, Color)] = [
        ("Healing", "heart.fill", .pink),
        ("Career", "briefcase.fill", .green),
        ("Relationships", "heart.circle.fill", .red),
        ("Financial", "dollarsign.circle.fill", .orange),
        ("Spiritual Growth", "sparkles", .purple),
        ("Family", "house.fill", .blue)
    ]
    
    var defaultDisplayTags: [(String, String, Color)] {
        switch selectedCategory {
        case .prayer: return prayerTypes
        case .testimonies: return testimonyTags
        default: return openTableTags
        }
    }

    var displayTags: [(String, String, Color)] {
        defaultDisplayTags + customTopicTags.map { ($0, "tag.fill", Color.secondary) }
    }
    
    var filteredTags: [(String, String, Color)] {
        if searchText.isEmpty {
            return displayTags
        }
        return displayTags.filter { tag in
            tag.0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var sanitizedCustomTag: String {
        Self.normalizedTag(newCustomTag)
    }

    private var customTagsRemainingText: String {
        guard let limit = premiumManager.customTopicTagLimit else {
            return "Unlimited custom tags with \(premiumManager.currentTier.displayName)"
        }
        let remaining = max(limit - customTopicTags.count, 0)
        return "\(remaining) of \(limit) custom tags remaining on \(premiumManager.currentTier.displayName)"
    }
    
    @ViewBuilder
    private var tagListContent: some View {
        if filteredTags.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(40))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No topics found")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.secondary)
                Text("Create it as a custom tag above")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(filteredTags, id: \.0) { tag in
                    TopicTagCard(
                        title: tag.0,
                        icon: tag.1,
                        color: tag.2,
                        isSelected: selectedTag == tag.0
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            selectedTag = tag.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isPresented = false
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var headerTitle: String {
        selectedCategory == .prayer ? "Choose Prayer Type" : selectedCategory == .testimonies ? "Testimony Category" : "Choose a Topic Tag"
    }

    private var headerSubtitle: String {
        selectedCategory == .prayer ? "Optional: let others know what kind of prayer this is" :
        selectedCategory == .testimonies ? "Optional: choose a category so others can find your testimony" :
        "Optional: help others discover your post in #OPENTABLE"
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerTitle).font(AMENFont.bold(20))
            Text(headerSubtitle).font(AMENFont.regular(14)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var searchBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.4))
            TextField("Search topics...", text: $searchText)
                .font(AMENFont.regular(15))
                .autocorrectionDisabled()
                .accessibilityLabel("Search topics")
            if !searchText.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(.black.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.1), lineWidth: 0.5))
        )
        .padding(.horizontal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    searchBox
                    customTopicTagComposer.padding(.horizontal)
                    tagListContent
                }
                .padding(.vertical)
            }
            .navigationTitle(selectedCategory == .prayer ? "Prayer Type" : "Topic Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                if !selectedTag.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            selectedTag = ""
                            isPresented = false
                        }
                    }
                }
            }
        }
        .alert("Custom tag limit reached", isPresented: $showCustomTagLimitPaywall) {
            Button("Upgrade") {
                showPremiumUpgrade = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Free includes 3 custom tags. AMEN Plus includes 15, and AMEN Pro removes the limit.")
        }
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
        }
        .alert("Could not create tag", isPresented: Binding(
            get: { customTagErrorMessage != nil },
            set: { if !$0 { customTagErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { customTagErrorMessage = nil }
        } message: {
            Text(customTagErrorMessage ?? "Please try again.")
        }
        .task {
            await loadRemoteCustomTopicTags()
        }
        .presentationDetents([.large])
    }

    private var customTopicTagComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(.blue)

                TextField("Create your own topic tag", text: $newCustomTag)
                    .font(AMENFont.regular(15))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Custom topic tag")

                Button("Create") {
                    Task { await createCustomTopicTag() }
                }
                .font(AMENFont.semiBold(14))
                .disabled(sanitizedCustomTag.isEmpty || isSyncingCustomTopicTags)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            Text(customTagsRemainingText)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    private func createCustomTopicTag() async {
        let tag = sanitizedCustomTag
        guard !tag.isEmpty else { return }

        if displayTags.contains(where: { $0.0.caseInsensitiveCompare(tag) == .orderedSame }) {
            selectedTag = tag
            isPresented = false
            return
        }

        guard premiumManager.canCreateCustomTopicTag(currentCount: customTopicTags.count) else {
            showCustomTagLimitPaywall = true
            return
        }

        isSyncingCustomTopicTags = true
        defer { isSyncingCustomTopicTags = false }

        do {
            let createdTag = try await Self.createRemoteCustomTopicTag(tag)
            if !customTopicTags.contains(where: { $0.caseInsensitiveCompare(createdTag) == .orderedSame }) {
                customTopicTags.append(createdTag)
                Self.saveCustomTopicTags(customTopicTags)
            }
            selectedTag = createdTag
            isPresented = false
        } catch {
            if (error as NSError).code == FunctionsErrorCode.resourceExhausted.rawValue {
                showCustomTagLimitPaywall = true
            } else {
                customTagErrorMessage = "AMEN could not save this topic tag securely. Please try again."
            }
        }
    }

    private func loadRemoteCustomTopicTags() async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            let remoteTags = try await Self.loadRemoteCustomTopicTags()
            customTopicTags = remoteTags
            Self.saveCustomTopicTags(remoteTags)
        } catch {
            dlog("⚠️ Could not load custom topic tags: \(error.localizedDescription)")
        }
    }

    private static func normalizedTag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .prefix(32)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func customTopicTagsKey() -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return "\(customTopicTagsBaseKey).\(uid)"
        }
        return customTopicTagsBaseKey
    }

    private static func loadCustomTopicTags() -> [String] {
        UserDefaults.standard.stringArray(forKey: customTopicTagsKey()) ?? []
    }

    private static func saveCustomTopicTags(_ tags: [String]) {
        UserDefaults.standard.set(tags, forKey: customTopicTagsKey())
    }

    private static func loadRemoteCustomTopicTags() async throws -> [String] {
        let result = try await Functions.functions().httpsCallable("listCustomTopicTags").call([:])
        guard let data = result.data as? [String: Any],
              let tags = data["tags"] as? [String] else {
            return []
        }
        return tags
    }

    private static func createRemoteCustomTopicTag(_ label: String) async throws -> String {
        let result = try await Functions.functions().httpsCallable("createCustomTopicTag").call([
            "label": label
        ])
        guard let data = result.data as? [String: Any],
              let tag = data["tag"] as? String else {
            return label
        }
        return tag
    }
}

struct TopicTagCard: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    isPressed = false
                }
            }
            
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.2), color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(color)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                
                Text(title)
                    .font(AMENFont.bold(13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? color.opacity(0.3) : .black.opacity(0.05), radius: isSelected ? 12 : 8, y: 4)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

// Schedule Post Sheet - Premium Widget Design
struct SchedulePostSheet: View {
    @Binding var isPresented: Bool
    @Binding var scheduledDate: Date?
    @State private var selectedDateTime = Date()

    // MARK: Design tokens — adaptive to light/dark mode
    private let ink        = Color(uiColor: .label)
    private let surface    = Color(uiColor: .secondarySystemBackground)
    private let accent     = Color(red: 0.98, green: 0.82, blue: 0.18)   // warm amber-yellow accent
    private let accentDark = Color(red: 0.14, green: 0.10, blue: 0.02)   // text on accent (always dark on yellow)
    private let subtext    = Color(uiColor: .secondaryLabel)

    // Minimum schedule time is 5 minutes from now
    private var minimumDate: Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
    }

    // MARK: Formatted display helpers
    private var dayOfWeek: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: selectedDateTime).uppercased()
    }
    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: selectedDateTime)
    }
    private var monthYear: String {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f.string(from: selectedDateTime).uppercased()
    }
    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: selectedDateTime)
    }
    private var timezoneString: String {
        TimeZone.current.abbreviation() ?? "LOCAL"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ── TOP NAV BAR ──────────────────────────────────────────
                HStack {
                    Button { isPresented = false } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.06))
                                .frame(width: 34, height: 34)
                            Image(systemName: "xmark")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(ink)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Schedule Post")
                        .font(AMENFont.bold(15))
                        .foregroundStyle(ink)
                    Spacer()
                    // balance
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 34, height: 34)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // ── HERO DATE WIDGET ────────────────────────────────────
                // Two-zone card: dark left panel + light right panel
                HStack(spacing: 0) {

                    // LEFT — dark panel, large selected date
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        Text(dayOfWeek)
                            .font(AMENFont.bold(11))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(1.5)

                        Text(dayNumber)
                            .font(.systemScaled(64, weight: .black, design: .default))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text(monthYear)
                            .font(AMENFont.semiBold(11))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(1.0)

                        Spacer()

                        // Time badge — accent block
                        HStack(spacing: 5) {
                            Image(systemName: "clock.fill")
                                .font(.systemScaled(10, weight: .semibold))
                                .foregroundStyle(accentDark)
                            Text(timeString)
                                .font(AMENFont.bold(13))
                                .foregroundStyle(accentDark)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(accent)
                        )

                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.systemScaled(9))
                                .foregroundStyle(Color.white.opacity(0.45))
                            Text(timezoneString)
                                .font(AMENFont.regular(10))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                    }
                    .padding(20)
                    .frame(width: 140)
                    .frame(maxHeight: .infinity)
                    .background(ink)

                    // RIGHT — light panel, native date picker
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PICK DATE & TIME")
                            .font(AMENFont.bold(10))
                            .foregroundStyle(subtext)
                            .tracking(1.2)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 2)

                        DatePicker(
                            "",
                            selection: $selectedDateTime,
                            in: minimumDate...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .tint(ink)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 10)
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                    .background(surface)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.black.opacity(0.10), radius: 16, y: 4)
                .padding(.horizontal, 20)

                // ── INFO ROW ────────────────────────────────────────────
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accent.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.systemScaled(13))
                            .foregroundStyle(Color(red: 0.55, green: 0.44, blue: 0.02))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-publishes at selected time")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(ink)
                        Text("Minimum 5 minutes from now · \(timezoneString)")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(subtext)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(surface)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
                )
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // ── SCHEDULED SUMMARY (when a date is already set) ──────
                if scheduledDate != nil {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ink.opacity(0.06))
                                .frame(width: 32, height: 32)
                            Image(systemName: "calendar.badge.clock")
                                .font(.systemScaled(13))
                                .foregroundStyle(ink)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Currently scheduled")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(subtext)
                            if let sd = scheduledDate {
                                Text("\(sd, style: .date)  \(sd, style: .time)")
                            }
                        }
                        .font(AMENFont.bold(13))
                        .foregroundStyle(ink)
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accent.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(accent.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                Spacer(minLength: 28)

                // ── CTA BUTTONS ─────────────────────────────────────────
                VStack(spacing: 10) {
                    // PRIMARY — Schedule Post
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        scheduledDate = selectedDateTime
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.systemScaled(15, weight: .bold))
                            Text("Schedule Post")
                                .font(AMENFont.bold(16))
                        }
                        .foregroundStyle(accentDark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(accent)
                                .shadow(color: accent.opacity(0.45), radius: 10, y: 4)
                        )
                    }
                    .buttonStyle(SquishButtonStyle())

                    // SECONDARY — Remove schedule (if already set)
                    if scheduledDate != nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            scheduledDate = nil
                            isPresented = false
                        } label: {
                            Text("Remove Schedule")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(ink.opacity(0.70))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(ink.opacity(0.14), lineWidth: 1.5)
                                        )
                                )
                        }
                        .buttonStyle(SquishButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            // Initialize with minimum date if not already set
            if selectedDateTime < minimumDate {
                selectedDateTime = minimumDate
            }
        }
    }
}

struct MinimalCategoryButton: View {
    let category: CreatePostView.PostCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                action()
            }
        }) {
            VStack(spacing: 6) {
                Text(category.displayName)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.4))
                
                if isSelected {
                    Capsule()
                        .fill(Color.primary)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "underline", in: namespace)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GlassToolbarButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                isPressed = true
            }
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.systemScaled(22, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 48, height: 48)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .opacity(isActive ? 1.0 : 0.5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EnhancedCategoryChip: View {
    let category: CreatePostView.PostCategory
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    // Simplified gradient properties
    private var iconGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [category.primaryColor, category.secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.gray],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var textGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [category.primaryColor, category.secondaryColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [Color.secondary],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    private var strokeGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [category.primaryColor, category.secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var backgroundFill: Color {
        isSelected ? category.primaryColor.opacity(0.15) : Color(.systemGray6)
    }
    
    private var shadowColor: Color {
        isSelected ? category.primaryColor.opacity(0.2) : Color.clear
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundStyle(iconGradient)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(backgroundFill)
                    )
                
                Text(category.displayName)
                    .font(AMENFont.bold(13))
                    .foregroundStyle(textGradient)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: shadowColor,
                        radius: 8,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(strokeGradient, lineWidth: 2)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.6))) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.6))) {
                        isPressed = false
                    }
                }
        )
    }
}

struct ConsolidatedToolbar: View {
    @Binding var selectedImageData: [Data]
    @Binding var linkURL: String
    @Binding var showingSuggestions: Bool
    @Binding var showingImagePicker: Bool
    @Binding var showingLinkSheet: Bool
    @Binding var showDraftsSheet: Bool
    @Binding var showingScheduleSheet: Bool
    @Binding var allowComments: Bool
    let draftsCount: Int
    let onSaveDraft: () -> Void
    let onClearAll: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            // Photo button
            CompactToolbarButton(
                icon: "photo",
                isActive: !selectedImageData.isEmpty
            ) {
                showingImagePicker = true
            }
            
            // Hashtag button
            CompactToolbarButton(
                icon: "number",
                isActive: showingSuggestions
            ) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showingSuggestions.toggle()
                }
            }
            
            Spacer()
            
            // More menu
            Menu {
                Button {
                    showingLinkSheet = true
                } label: {
                    Label(linkURL.isEmpty ? "Add Link" : "Edit Link", systemImage: "link")
                }
                
                // Comments Toggle
                Button {
                    allowComments.toggle()
                } label: {
                    Label(
                        allowComments ? "Disable Comments" : "Enable Comments",
                        systemImage: allowComments ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
                    )
                }
                
                Divider()
                
                Button {
                    onSaveDraft()
                } label: {
                    Label("Save as Draft", systemImage: "square.and.arrow.down")
                }
                
                if draftsCount > 0 {
                    Button {
                        showDraftsSheet = true
                    } label: {
                        Label("View Drafts (\(draftsCount))", systemImage: "doc.text")
                    }
                }
                
                Button {
                    showingScheduleSheet = true
                } label: {
                    Label("Schedule Post", systemImage: "calendar.badge.clock")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onClearAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }
}

// MARK: - Compact Toolbar Button

struct CompactToolbarButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.6))) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.6))) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.5))
                .frame(width: 36, height: 36)
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Glassmorphic Button (X button in toolbar)

struct GlassmorphicButton: View {
    let icon: String
    let style: ButtonStyle
    var isEnabled: Bool = true
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
    }
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                    isPressed = false
                }
            }
            
            action()
        }) {
            ZStack {
                // Liquid glass base
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                
                // Border with gradient
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 40, height: 40)
                
                // Icon
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Glass Toolbar Icon (Matching Design Image)

struct GlassToolbarIcon: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.65))) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.65))) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.systemScaled(18, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.4))
                .frame(width: 36, height: 36)
                .scaleEffect(isPressed ? 0.85 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Camera Image Picker

/// Wraps UIImagePickerController to give instant camera access from SwiftUI.
struct ComposerSchedulePill: View {
    var scheduledDate: Date?
    var onTap: () -> Void
    var onClear: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isScheduled: Bool { scheduledDate != nil }

    private var formattedDate: String {
        guard let date = scheduledDate else { return "" }
        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"
        return df.string(from: date)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    Image(systemName: isScheduled ? "calendar.badge.clock" : "calendar")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(isScheduled ? Color.primary : Color.secondary)

                    Text(isScheduled ? "Scheduled · \(formattedDate)" : "Schedule")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(isScheduled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, isScheduled ? 10 : 8)
                .padding(.trailing, isScheduled ? 6 : 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // X clear button — only when scheduled
            if isScheduled {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(9, weight: .bold))
                        .foregroundStyle(Color(white: 0.50))
                        .padding(.trailing, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(isScheduled ? Color.white.opacity(0.80) : Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(
                    isScheduled ? Color.black.opacity(0.18) : Color(white: 0.88).opacity(0.5),
                    lineWidth: isScheduled ? 1.0 : 0.5
                ))
        )
        .shadow(color: isScheduled ? Color.black.opacity(0.08) : Color.black.opacity(0.04), radius: isScheduled ? 8 : 4, x: 0, y: 2)
        .scaleEffect(appeared ? 1.0 : 0.88)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) { appeared = true }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.78), value: isScheduled)
        .animation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.78), value: scheduledDate)
    }
}

// MARK: - Minimal Toolbar Button (Inspired by design)

struct MinimalToolbarButton: View {
    let icon: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.65))) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.65))) {
                    isPressed = false
                }
            }
            action()
        }) {
            ZStack {
                // Background circle when active
                if isActive {
                    Circle()
                        .fill(activeColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .strokeBorder(activeColor.opacity(0.3), lineWidth: 1)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Icon
                Image(systemName: icon)
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : Color.primary.opacity(0.4))
                    .frame(width: 36, height: 36)
            }
            .scaleEffect(isPressed ? 0.88 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Liquid Glass Post Button (Matching Design)

// MARK: - Upward Arrow Icon
/// Bold chunky upward arrow — matches the reference button style (thick rounded stem + arrowhead).
/// Pure Canvas vector, crisp at any size.
struct UpwardArrowIcon: View {
    var size: CGFloat = 24
    var color: Color = Color(red: 0.92, green: 0.15, blue: 0.26)

    var body: some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let lw = w * 0.22        // stroke line-width — chunky like the reference

            // Vertical stem: runs from ~bottom-centre up to ~mid-height
            let stemPath = Path { p in
                p.move(to:    CGPoint(x: w * 0.50, y: h * 0.92))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.40))
            }
            ctx.stroke(stemPath, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // Arrowhead: two diagonal lines from the tip
            let arrowPath = Path { p in
                // Left wing
                p.move(to:    CGPoint(x: w * 0.18, y: h * 0.60))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.10))
                // Right wing
                p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.60))
            }
            ctx.stroke(arrowPath, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

struct LiquidGlassPostButton: View {
    let isEnabled: Bool
    let isPublishing: Bool
    let isScheduled: Bool
    let action: () -> Void

    private let red = Color(red: 0.92, green: 0.15, blue: 0.26)

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            guard isEnabled && !isPublishing else { return }
            withAnimation(Motion.adaptive(.spring(response: 0.20, dampingFraction: 0.65))) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.70))) { isPressed = false }
            }
            action()
        }) {
            ZStack {
                // Soft light-gray circle — matches reference exactly
                Circle()
                    .fill(Color(red: 0.91, green: 0.91, blue: 0.93).opacity(isEnabled ? 1.0 : 0.50))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.black.opacity(isEnabled ? 0.12 : 0.04), radius: 8, x: 0, y: 3)

                if isPublishing {
                    ProgressView()
                        .tint(red)
                        .scaleEffect(1.1)
                } else if isScheduled {
                    Image(systemName: "calendar.badge.clock")
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(isEnabled ? red : red.opacity(0.30))
                } else {
                    // Bold chunky upward arrow
                    UpwardArrowIcon(
                        size: 26,
                        color: isEnabled ? red : red.opacity(0.30)
                    )
                }
            }
            .scaleEffect(isPressed ? 0.90 : 1.0)
        }
        .disabled(!isEnabled || isPublishing)
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CreatePostView()
}

// MARK: - Supporting Models & Services

/// Draft model for recovery
struct Draft: Identifiable {
    let id: String
    let content: String
    let category: String?
    let topicTag: String?
    let linkURL: String?
    let visibility: String
    let createdAt: Date

    let witnessAttachment: WitnessDraftAttachment?
    let mediaMetadataDraft: CreatePostMediaMetadataDraft?
    let attachedVerseReference: String
    let attachedVerseText: String
    let showingPoll: Bool
    let pollQuestion: String
    let pollOptions: [String]
    let pollDurationRawValue: String?
    let isThreadMode: Bool
    let threadPosts: [String]
    let currentThreadIndex: Int

    init(
        id: String,
        content: String,
        category: String?,
        topicTag: String?,
        linkURL: String?,
        visibility: String,
        createdAt: Date,
        witnessAttachment: WitnessDraftAttachment? = nil,
        mediaMetadataDraft: CreatePostMediaMetadataDraft? = nil,
        attachedVerseReference: String = "",
        attachedVerseText: String = "",
        showingPoll: Bool = false,
        pollQuestion: String = "",
        pollOptions: [String] = ["", ""],
        pollDurationRawValue: String? = nil,
        isThreadMode: Bool = false,
        threadPosts: [String] = [""],
        currentThreadIndex: Int = 0
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.topicTag = topicTag
        self.linkURL = linkURL
        self.visibility = visibility
        self.createdAt = createdAt
        self.witnessAttachment = witnessAttachment
        self.mediaMetadataDraft = mediaMetadataDraft
        self.attachedVerseReference = attachedVerseReference
        self.attachedVerseText = attachedVerseText
        self.showingPoll = showingPoll
        self.pollQuestion = pollQuestion
        self.pollOptions = pollOptions
        self.pollDurationRawValue = pollDurationRawValue
        self.isThreadMode = isThreadMode
        self.threadPosts = threadPosts
        self.currentThreadIndex = currentThreadIndex
    }
}

// MARK: - Authenticity Prompt Sheet

/// ✅ Gentle prompt to add personal context when content seems copy-pasted
struct AuthenticityPromptSheet: View {
    let message: String
    @Binding var personalContext: String
    let onContinue: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.1))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "sparkles")
                                .font(.systemScaled(22))
                                .foregroundStyle(Color.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add a Personal Touch")
                                .font(AMENFont.bold(20))
                                .foregroundStyle(.primary)
                            
                            Text("Make it uniquely yours")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text(message)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                
                // Text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share your personal thoughts:")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $personalContext)
                        .font(AMENFont.regular(15))
                        .frame(height: 120)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                        .accessibilityLabel("Personal thoughts")
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text("\(personalContext.count)/280")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(personalContext.count > 280 ? .red : .secondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onContinue) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Continue Posting")
                                .font(AMENFont.semiBold(16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            personalContext.isEmpty || personalContext.count > 280 ? 
                            Color.gray.opacity(0.3) : Color.black
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(personalContext.isEmpty || personalContext.count > 280)
                    
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
// MARK: - Verse Badge View

private struct VerseBadgeView: View {
    let reference: String
    let text: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed.fill")
                    .font(.systemScaled(11))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference)
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if !text.isEmpty {
                        Text(text.prefix(50) + (text.count > 50 ? "..." : ""))
                            .font(.systemScaled(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.08))
            )
        }
    }
}

// MARK: - Tagged Users View

private struct TaggedUsersView: View {
    @Binding var users: [MentionedUser]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(users, id: \.userId) { user in
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(.purple)
                        
                        Text("@\(user.username)")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                                users.removeAll { $0.userId == user.userId }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.08))
                    )
                }
            }
        }
    }
}

// MARK: - Dynamic Island–style "Posted" pill

// MARK: - Upload Ring Capsule

/// Thin determinate ring around a black center dot, enclosed in a glass capsule.
/// Shows upload progress with the percentage as the only text — no spinner, no label.
private struct UploadRingCapsule: View {
    let progress: Double   // 0.0 – 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ringSize: CGFloat   = 22
    private let dotSize: CGFloat    = 5
    private let strokeWidth: CGFloat = 2

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                // Track
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: strokeWidth)
                    .frame(width: ringSize, height: ringSize)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? .none : .linear(duration: 0.15), value: progress)

                // Center dot
                Circle()
                    .fill(Color.primary)
                    .frame(width: dotSize, height: dotSize)
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        )
    }
}

// MARK: - Posted Pill

private struct PostedPill: View {
    /// Override the final "Posted" label — used when the post is under moderation review.
    /// Pass `"Under Review"` to show the GUARDIAN pre-gate status to the author.
    var finalLabel: String = "Posted"

    // Blocks animation state
    @State private var blocksOpacity: Double = 0
    @State private var blocksScale: CGFloat = 0.5
    @State private var blocksPulse: Bool = false

    // Checkmark animation state
    @State private var checkmarkProgress: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var checkmarkScale: CGFloat = 0.6

    // Label animation state
    @State private var labelOpacity: Double = 0
    @State private var labelOffset: CGFloat = 8
    @State private var labelText: String = "Posting..."

    var body: some View {
        HStack(spacing: 10) {
            // Icon area — switches between blocks and checkmark
            ZStack {
                // Phase 1: pixel/blocks grid in pink–red gradient
                PixelBlocksIcon()
                    .scaleEffect(blocksPulse ? 1.08 : 1.0)
                    .opacity(blocksOpacity)
                    .scaleEffect(blocksScale)

                // Phase 2: stroke checkmark in white
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    AnimatedCheckmark(progress: checkmarkProgress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 13, height: 10)
                }
                .opacity(checkmarkOpacity)
                .scaleEffect(checkmarkScale)
            }
            .frame(width: 26, height: 26)

            Text(labelText)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white)
                .opacity(labelOpacity)
                .offset(x: labelOffset)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(Color.black)
                .shadow(color: .black.opacity(0.40), radius: 22, x: 0, y: 8)
        )
        .onAppear {
            // Phase 1: blocks fade + scale in
            withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.72))) {
                blocksOpacity = 1
                blocksScale = 1
            }
            withAnimation(Motion.adaptive(.spring(response: 0.36, dampingFraction: 0.78)).delay(0.12)) {
                labelOpacity = 1
                labelOffset = 0
            }
            // Subtle pulse on blocks
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(0.25)) {
                blocksPulse = true
            }
            // Phase 2: transition to checkmark after brief moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                // Swap label text
                withAnimation(.easeInOut(duration: 0.18)) {
                    labelOpacity = 0
                }
                // Blocks exit
                withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82)).delay(0.08)) {
                    blocksOpacity = 0
                    blocksScale = 0.4
                }
                // Checkmark enters
                withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.70)).delay(0.18)) {
                    checkmarkOpacity = 1
                    checkmarkScale = 1
                }
                withAnimation(.linear(duration: 0.36).delay(0.20)) {
                    checkmarkProgress = 1
                }
                // Label updates to finalLabel ("Posted" or "Under Review") + haptic success
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    labelText = finalLabel
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(Motion.adaptive(.spring(response: 0.34, dampingFraction: 0.76))) {
                        labelOpacity = 1
                        labelOffset = 0
                    }
                }
            }
        }
    }
}

// 2×2 grid of rounded squares with pink–red gradient
private struct PixelBlocksIcon: View {
    private let gradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.28, blue: 0.36), Color(red: 0.95, green: 0.18, blue: 0.52)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private let blockSize: CGFloat = 7
    private let gap: CGFloat = 2.5

    var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(gradient).frame(width: blockSize, height: blockSize)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(gradient).frame(width: blockSize, height: blockSize).opacity(0.70)
            }
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(gradient).frame(width: blockSize, height: blockSize).opacity(0.70)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(gradient).frame(width: blockSize, height: blockSize)
            }
        }
    }
}

// Draws the checkmark tick as a trimmed path (progress 0→1)
private struct AnimatedCheckmark: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let p1 = CGPoint(x: 0, y: h * 0.52)
        let p2 = CGPoint(x: w * 0.38, y: h)
        let p3 = CGPoint(x: w, y: 0)

        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        return path.trimmedPath(from: 0, to: progress)
    }
}

// MARK: - Berean Tone Button (toolbar)

/// AMEN-logo glass circle button that triggers Berean tone analysis.
/// Matches the Berean nav button design in the main feed.
private struct BereanToneButton: View {
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseScale: CGFloat = 1.0
    @State private var isAnimating = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                
                if isLoading {
                    // Pulsing dots while AI is thinking
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.primary.opacity(0.6))
                                .frame(width: 3.5, height: 3.5)
                                .scaleEffect(pulseScale)
                                .animation(
                                    reduceMotion ? .none : .easeInOut(duration: 0.55)
                                        .repeatForever()
                                        .delay(Double(i) * 0.18),
                                    value: pulseScale
                                )
                        }
                    }
                } else {
                    Image("amen-logo")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .blendMode(.multiply)
                        .rotationEffect(.degrees(isAnimating ? 2 : 0))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
        .accessibilityLabel("Berean tone assist")
        .onAppear {
            if isLoading { pulseScale = 1.4 }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
        .onChange(of: isLoading) { _, loading in
            pulseScale = loading ? 1.4 : 1.0
        }
    }
}

// MARK: - Algolia Mention Suggestion Row

/// Mention row for CreatePostView's inline @-trigger, which uses AlgoliaUser.
struct PostAudienceSheet: View {
    @Binding var selectedVisibility: Post.PostVisibility
    @Environment(\.dismiss) private var dismiss

    private let options: [Post.PostVisibility] = [.everyone, .followers, .community]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header description
                VStack(spacing: 6) {
                    Text("Who can see this post?")
                        .font(AMENFont.bold(17))
                        .foregroundStyle(.primary)
                    Text("Choose who will be able to view and interact with your post.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selectedVisibility = option
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(option.tintColor.opacity(0.12))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: option.icon)
                                        .font(.systemScaled(16, weight: .semibold))
                                        .foregroundStyle(option.tintColor)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Text(option.audienceDescription)
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedVisibility == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(option.tintColor)
                                        .font(.systemScaled(20))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if option != options.last {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                Spacer()
            }
            .navigationTitle("Audience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(16))
                }
            }
        }
    }
}

private extension Post.PostVisibility {
    var audienceDescription: String {
        switch self {
        case .everyone: return "Visible to everyone on AMEN"
        case .followers: return "Only people who follow you"
        case .community: return "Only verified church community members"
        case .underReview: return "This post is under review"
        }
    }
}

// MARK: - Post Verse Picker Sheet

struct PostVersePickerSheet: View {
    @Binding var verseReference: String
    @Binding var verseText: String
    @Binding var isPresented: Bool

    // Selected verse — starts pre-populated if the post already has a verse attached
    @State private var selectedReference: String = ""
    @State private var selectedText: String = ""

    // Search state
    @State private var searchQuery: String = ""
    @State private var searchResults: [ScripturePassage] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    // Version picker
    @State private var selectedVersion: ScripturePassage.BibleVersion = .niv

    @FocusState private var searchFocused: Bool

    private let bibleService = YouVersionBibleService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Search bar ──────────────────────────────────────────────
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.systemScaled(16))
                        TextField("Search a verse or type reference (e.g. John 3:16)", text: $searchQuery)
                            .font(AMENFont.regular(15))
                            .focused($searchFocused)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .accessibilityLabel("Search verse or reference")
                            .onSubmit { triggerSearch() }
                            .onChange(of: searchQuery) { _, newValue in
                                scheduleSearch(newValue)
                            }
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if !searchQuery.isEmpty {
                            Button { searchQuery = ""; searchResults = []; searchError = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    // Version picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([ScripturePassage.BibleVersion.niv,
                                     .esv, .kjv, .nkjv, .nlt, .nasb], id: \.self) { version in
                                Button {
                                    selectedVersion = version
                                    if !searchQuery.isEmpty { triggerSearch() }
                                } label: {
                                    Text(version.rawValue.uppercased())
                                        .font(AMENFont.semiBold(12))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(selectedVersion == version
                                                      ? Color.indigo
                                                      : Color(uiColor: .secondarySystemBackground))
                                        )
                                        .foregroundStyle(selectedVersion == version ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)

                    Divider()
                }

                // ── Main content area ───────────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // Error state
                        if let error = searchError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                        }

                        // Search results list
                        if !searchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(searchResults, id: \.reference) { passage in
                                    Button {
                                        selectPassage(passage)
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: selectedReference == passage.reference
                                                  ? "checkmark.circle.fill" : "book.closed")
                                                .font(.systemScaled(18))
                                                .foregroundStyle(selectedReference == passage.reference
                                                                 ? .indigo : .secondary)
                                                .frame(width: 24)
                                                .padding(.top, 2)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(passage.reference)
                                                    .font(AMENFont.semiBold(15))
                                                    .foregroundStyle(.primary)
                                                if !passage.text.isEmpty {
                                                    Text(passage.text)
                                                        .font(AMENFont.regular(13))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(3)
                                                        .italic()
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(
                                        selectedReference == passage.reference
                                        ? Color.indigo.opacity(0.06)
                                        : Color.clear
                                    )

                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        } else if searchQuery.isEmpty && selectedReference.isEmpty {
                            // Empty state — hints
                            VStack(spacing: 16) {
                                Image(systemName: "book.closed.fill")
                                    .font(.systemScaled(40))
                                    .foregroundStyle(Color.indigo.opacity(0.4))
                                Text("Search by keyword or reference")
                                    .font(AMENFont.semiBold(16))
                                    .foregroundStyle(.primary)
                                VStack(spacing: 6) {
                                    ForEach(["\"strength\"", "\"peace\"", "\"Philippians 4:13\"", "\"John 3:16\""], id: \.self) { hint in
                                        Button {
                                            searchQuery = hint.replacingOccurrences(of: "\"", with: "")
                                            triggerSearch()
                                        } label: {
                                            Text(hint)
                                                .font(AMENFont.regular(14))
                                                .foregroundStyle(.indigo)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.indigo.opacity(0.08))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                            .padding(.horizontal, 24)
                        } else if !searchQuery.isEmpty && searchResults.isEmpty && !isSearching {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.systemScaled(32))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("No results for \"\(searchQuery)\"")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                        }

                        // ── Selected verse preview card ───────────────────
                        if !selectedReference.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected Verse")
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book.closed.fill")
                                            .font(.systemScaled(12))
                                            .foregroundStyle(.indigo)
                                        Text(selectedReference)
                                            .font(AMENFont.bold(13))
                                            .foregroundStyle(.indigo)
                                        Spacer()
                                        Text(selectedVersion.rawValue.uppercased())
                                            .font(AMENFont.regular(11))
                                            .foregroundStyle(Color.indigo.opacity(0.7))
                                    }
                                    if !selectedText.isEmpty {
                                        Text(selectedText)
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.primary)
                                            .italic()
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.indigo.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .padding(.horizontal, 16)

                                // Clear selection
                                Button(role: .destructive) {
                                    selectedReference = ""
                                    selectedText = ""
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .font(AMENFont.regular(13))
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                            }
                            .padding(.top, searchResults.isEmpty ? 0 : 16)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Attach Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .font(AMENFont.regular(16))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        verseReference = selectedReference
                        verseText = selectedText
                        isPresented = false
                    }
                    .font(AMENFont.semiBold(16))
                    .disabled(selectedReference.isEmpty)
                }
            }
            .onAppear {
                // Pre-populate if an existing verse is already attached
                selectedReference = verseReference
                selectedText = verseText
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    searchFocused = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            searchError = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    private func triggerSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { await performSearch(trimmed) }
    }

    @MainActor
    private func performSearch(_ query: String) async {
        isSearching = true
        searchError = nil
        do {
            let results = try await bibleService.searchVerses(query: query, version: selectedVersion, limit: 12)
            searchResults = results
            if results.isEmpty {
                // Try fetching as a direct reference (e.g. "John 3:16")
                let passage = try await bibleService.fetchVerse(reference: query, version: selectedVersion)
                searchResults = [passage]
            }
        } catch {
            // If direct reference fetch also fails, show a gentle message
            searchError = "No results found. Try a different reference or keyword."
            searchResults = []
        }
        isSearching = false
    }

    private func selectPassage(_ passage: ScripturePassage) {
        selectedReference = passage.reference
        selectedText = passage.text
        searchFocused = false
    }
}

// MARK: - Post Church Tag Sheet

struct PostChurchTagSheet: View {
    @Binding var taggedChurchId: String
    @Binding var taggedChurchName: String
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var searchResults: [(id: String, name: String, city: String)] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private var db: Firestore { Firestore.firestore() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.systemScaled(15))
                    TextField("Search churches by name", text: $searchText)
                        .font(AMENFont.regular(15))
                        .focused($searchFocused)
                        .accessibilityLabel("Search churches")
                        .onChange(of: searchText) { _, newValue in
                            triggerSearch(query: newValue)
                        }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider()

                if searchText.isEmpty {
                    // Current selection or prompt
                    if !taggedChurchId.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.purple)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.purple.opacity(0.1)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(taggedChurchName)
                                    .font(AMENFont.semiBold(15))
                                Text("Currently tagged")
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                taggedChurchId = ""
                                taggedChurchName = ""
                                isPresented = false
                            } label: {
                                Text("Remove")
                                    .font(AMENFont.regular(14))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                        Divider().padding(.horizontal, 20)
                    }

                    VStack(spacing: 8) {
                        Image(systemName: "building.columns")
                            .font(.systemScaled(32))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        Text("Search for a church to tag")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)

                } else if isSearching {
                    ProgressView()
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else if searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(28))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        Text("No churches found for \"\(searchText)\"")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else {
                    List(searchResults, id: \.id) { church in
                        Button {
                            taggedChurchId = church.id
                            taggedChurchName = church.name
                            isPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.columns.fill")
                                    .font(.systemScaled(14))
                                    .foregroundStyle(.purple)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.purple.opacity(0.1)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(church.name)
                                        .font(AMENFont.semiBold(14))
                                        .foregroundStyle(.primary)
                                    if !church.city.isEmpty {
                                        Text(church.city)
                                            .font(AMENFont.regular(12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if taggedChurchId == church.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.purple)
                                        .font(.systemScaled(14, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.5))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Tag a Church")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .font(AMENFont.regular(16))
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    searchFocused = true
                }
            }
        }
    }

    private func triggerSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            do {
                let snapshot = try await db.collection("churches")
                    .whereField("name", isGreaterThanOrEqualTo: trimmed)
                    .whereField("name", isLessThan: trimmed + "\u{f8ff}")
                    .limit(to: 20)
                    .getDocuments()
                guard !Task.isCancelled else { return }
                let results: [(id: String, name: String, city: String)] = snapshot.documents.compactMap { doc in
                    guard let name = doc.data()["name"] as? String else { return nil }
                    let city = doc.data()["city"] as? String ?? ""
                    return (id: doc.documentID, name: name, city: city)
                }
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run { isSearching = false }
            }
        }
    }
}



private extension String {
    /// Returns nil if the string is empty, otherwise returns self.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Upload Visual State

enum UploadVisualState: Equatable {
    case idle
    case pressed
    case uploading(progress: CGFloat)
    case success
}

// MARK: - Liquid Glass Post Button (Demo Version)

struct LiquidGlassPostButtonAnimated: View {
    let state: UploadVisualState
    let action: () -> Void

    var body: some View {
        GeometryReader { geo in
            let width = min(max(geo.size.width * 0.46, 148), 178)
            let height = min(max(width * 0.355, 54), 62)
            let cornerRadius = height / 2

            ZStack {
                ambientAura(size: max(width * 1.7, 220))

                switch state {
                case .idle, .pressed:
                    postCapsule(width: width, height: height, cornerRadius: cornerRadius)
                        .scaleEffect(state == .pressed ? 0.95 : 1.0)

                case .uploading(let progress):
                    progressGlass(progress: progress, size: max(height + 8, 62))
                        .transition(.scale(scale: 0.88).combined(with: .opacity))

                case .success:
                    successCapsule(width: width + 4, height: height, cornerRadius: cornerRadius)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                action()
            }
        }
        .frame(height: 210)
    }

    // MARK: - Idle / Pressed Capsule

    private func postCapsule(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.78), Color.white.opacity(0.44)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width - 24, height: height * 0.28)
                .offset(y: -height * 0.22)
                .blur(radius: 0.4)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 22, height: 22)
                    Image(systemName: "arrow.up")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Text("Post")
                    .font(.systemScaled(min(max(height * 0.30, 17), 19), weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
        }
        .frame(width: width, height: height)
        .overlay(movingHighlight(cornerRadius: cornerRadius).clipShape(Capsule()))
    }

    // MARK: - Uploading

    private func progressGlass(progress: CGFloat, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.84), Color.white.opacity(0.50)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)

            Circle()
                .stroke(Color.black.opacity(0.10), lineWidth: 6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.black, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.systemScaled(13, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Success

    private func successCapsule(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.80), Color.white.opacity(0.56)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.95), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width - 26, height: height * 0.28)
                .offset(y: -height * 0.22)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Posted")
                    .font(.systemScaled(min(max(height * 0.29, 16), 18), weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
        }
        .frame(width: width, height: height)
        .overlay(movingHighlight(cornerRadius: cornerRadius).clipShape(Capsule()))
    }

    // MARK: - Shared Visual Layers

    private func ambientAura(size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.75), Color.white.opacity(0.16), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.45
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 10)
    }

    private func movingHighlight(cornerRadius: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 40)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((sin(t * 1.2) + 1) / 2)
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.48), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 66, height: 180)
            .rotationEffect(.degrees(18))
            .offset(x: -54 + (phase * 108))
            .blur(radius: 3.6)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Composer Cue Pill

private struct ComposerCuePill: View {
    let action: ComposerSuggestedAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.systemScaled(11, weight: .semibold))
                Text(action.label)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.horizontal, AmenSpacing.chipH)
            .padding(.vertical, AmenSpacing.chipV)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Demo Preview Screen

struct LiquidGlassPostButtonDemoView: View {
    @State private var uploadState: UploadVisualState = .idle

    var body: some View {
        ZStack {
            AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Liquid Glass Post Button")
                        .font(.systemScaled(28, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("White background, black text, native-feeling glass, responsive across phones.")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                LiquidGlassPostButtonAnimated(state: uploadState, action: runDemoSequence)
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    private func runDemoSequence() {
        guard uploadState == .idle else { return }
        Task {
            withAnimation(Motion.adaptive(.spring(response: 0.24, dampingFraction: 0.72))) { uploadState = .pressed }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.82))) { uploadState = .uploading(progress: 0.08) }
            let values: [CGFloat] = [0.16, 0.26, 0.38, 0.52, 0.66, 0.79, 0.91, 1.0]
            for value in values {
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.linear(duration: 0.12)) { uploadState = .uploading(progress: value) }
            }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(Motion.adaptive(.spring(response: 0.34, dampingFraction: 0.84))) { uploadState = .success }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(Motion.adaptive(.spring(response: 0.36, dampingFraction: 0.9))) { uploadState = .idle }
        }
    }
}

private struct PostAIGlassCard: View {
    var onImproveWriting: () -> Void
    var onFindScripture: () -> Void
    var onAddHashtags: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            row(icon: "wand.and.stars",   title: "Improve Writing",  action: onImproveWriting)
            Divider().padding(.leading, 52)
            row(icon: "book.pages.fill",  title: "Find Scripture",   action: onFindScripture)
            Divider().padding(.leading, 52)
            row(icon: "number",           title: "Add Hashtags",     action: onAddHashtags)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 280)
        .background(cardBackground)
        .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .frame(width: 26, height: 26)
                Text(title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .amenGlassEffect(Color(.systemBackground).opacity(0.35), cornerRadius: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                }
        }
    }
}

#Preview("Liquid Glass Button Demo") {
    LiquidGlassPostButtonDemoView()
}
