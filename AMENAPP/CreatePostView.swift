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
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var postsManager: PostsManager = .shared
    @ObservedObject private var draftsManager: DraftsManager = .shared
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
    @State private var keyboardHeight: CGFloat = 0
    @State private var showingSuggestions = false
    @State private var hashtagSuggestions: [String] = []
    @State private var showingDraftSavedNotice = false
    @State private var selectedTopicTag = ""
    @State private var showingTopicTagSheet = false
    @State private var showingScheduleSheet = false
    @State private var isPublishing = false
    @State private var showDraftsSheet = false
    @State private var showFirstPostGuidelinesPrompt = false
    @State private var scheduledDate: Date?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var errorTitle = "Error"
    @State private var showingSuccessNotice = false
    
    // P1-6 FIX: Better error recovery
    @State private var isRetryableError = false
    @State private var retryAction: (() -> Void)?
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var categoryNamespace
    
    // MARK: - New Features State
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var mentionSearchTask: Task<Void, Never>?
    @StateObject private var linkController = ComposerLinkPreviewController()
    @State private var showMentionSuggestions = false
    @State private var mentionSuggestions: [AlgoliaUser] = []
    @State private var currentMentionQuery = ""
    @State private var showDraftRecovery = false
    @State private var recoveredDraft: Draft?
    @State private var uploadProgress: Double = 0.0
    @State private var isUploadingImages = false
    
    // Tag people
    @State private var taggedUsers: [MentionedUser] = []
    @State private var showingTagPeopleSheet = false
    
    // P0-1 FIX: Prevent duplicate post creation
    @State private var inFlightPostHash: Int? = nil
    
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
    
    // Berean AI tone assist
    @State private var bereanToneSuggestion: String?
    @State private var isLoadingBereanTone = false
    @State private var showBereanToneSheet = false
    
    // MARK: - Initializer
    
    init(initialCategory: PostCategory? = nil) {
        if let category = initialCategory {
            _selectedCategory = State(initialValue: category)
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
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    categorySelectorView
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    
                    contentScroll
                }
                
                // Upload progress overlay
                if isUploadingImages {
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            ProgressView(value: uploadProgress, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(.blue)
                            
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(.blue)
                                
                                Text("Uploading images... \(Int(uploadProgress * 100))%")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                        )
                        .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.2), value: isUploadingImages)
                }
                
                // Draft saved notification
                if showingDraftSavedNotice {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                            
                            Text("Draft saved successfully")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        )
                        .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.2), value: showingDraftSavedNotice)
                }
                
                // Success notification — Dynamic Island–style black pill
                if showingSuccessNotice {
                    VStack {
                        Spacer()
                        PostedPill()
                            .padding(.bottom, 36)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.45, dampingFraction: 0.72), value: showingSuccessNotice)
                }
            }
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Drafts button (leading)
                ToolbarItem(placement: .navigationBarLeading) {
                    if !draftsManager.drafts.isEmpty {
                        Button {
                            isTextFieldFocused = false
                            showDraftsSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 14))
                                
                                Text("\(draftsManager.drafts.count)")
                                    .font(.custom("OpenSans-Bold", size: 11))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue)
                                    )
                            }
                            .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("View drafts")
                        .accessibilityValue("\(draftsManager.drafts.count) drafts available")
                    }
                }
                
                // Berean AI tone assist — black/white pill button
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPublishing {
                        BereanToneButton(isLoading: isLoadingBereanTone) {
                            requestBereanToneAssist()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomToolbar
            }
            // Photo picker — uses the system modifier (not a sheet wrapper) so
            // onChange fires in the main view scope and selectedImageData is updated.
            .photosPicker(
                isPresented: $showingImagePicker,
                selection: $selectedImages,
                maxSelectionCount: 2,
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
                SchedulePostSheet(isPresented: $showingScheduleSheet, scheduledDate: $scheduledDate)
            }
            .sheet(isPresented: $showDraftsSheet) {
                DraftsView()
            }
            .sheet(isPresented: $showCommentControls) {
                PostCommentControlsSheet(selectedPermission: $commentPermission)
                    .onChange(of: commentPermission) { oldValue, newValue in
                        // Update allowComments based on permission
                        allowComments = (newValue != .nobody)
                    }
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
            .sheet(isPresented: $showThinkFirstPrompt) {
                thinkFirstPromptSheetContent
            }
            .sheet(isPresented: $showBereanToneSheet) {
                bereanToneSheetContent
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.2)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    keyboardHeight = 0
                }
            }
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
        .alert(errorTitle, isPresented: $showingErrorAlert) {
            // P1-6 FIX: Show retry button for network/upload errors
            if isRetryableError, let retry = retryAction {
                Button("Retry", role: .none) {
                    retry()
                }
                Button("Cancel", role: .cancel) {
                    isPublishing = false
                    isRetryableError = false
                    retryAction = nil
                }
            } else {
                Button("OK", role: .cancel) {
                    isPublishing = false
                }
            }
        } message: {
            Text(errorMessage)
        }
        .alert("Share Your Own Voice", isPresented: $showAIContentAlert) {
            Button("Edit Post", role: .cancel) {
                isPublishing = false
                // User can edit their post
            }
        } message: {
            Text("AMEN is a community for authentic, personal sharing. We noticed this content may not be written in your own words.\n\nPlease share your personal thoughts, experiences, and reflections. We want to hear from you, not from AI tools.")
        }
        .sheet(isPresented: $showFirstPostGuidelinesPrompt) {
            CommunityGuidelinesPrompt {
                showFirstPostGuidelinesPrompt = false
                // Re-call publishPost after user acknowledges
                publishPost()
            }
        }
        .onAppear {
            isTextFieldFocused = true
            updateHashtagSuggestions()
            
            // Check for auto-saved draft recovery
            checkForDraftRecovery()
            
            // Start auto-save timer (every 30 seconds)
            startAutoSaveTimer()
        }
        .onDisappear {
            // Stop auto-save task when view disappears
            autoSaveTask?.cancel()
            autoSaveTask = nil
            
            // Cancel in-flight mention search so its callback cannot write to @State
            // after the TextEditor's UITextView is torn down (prevents RTIInputSystemClient SIGABRT)
            mentionSearchTask?.cancel()
            mentionSearchTask = nil
            
            // Cancel pending link preview
            linkController.reset()
            
            // P0-2 FIX: Cancel all delayed tasks to prevent crash on rapid navigation
            delayedTasks.forEach { $0.cancel() }
            delayedTasks.removeAll()
        }
        .alert("Recover Draft?", isPresented: $showDraftRecovery) {
            Button("Recover") {
                if let draft = recoveredDraft {
                    loadDraft(draft)
                }
            }
            Button("Discard", role: .destructive) {
                clearRecoveredDraft()
            }
        } message: {
            Text("You have an unsaved draft from earlier. Would you like to continue editing it?")
        }
    }
    
    // MARK: - Computed Properties
    private var canPost: Bool {
        // Content validation - must have text and be within character limit
        let hasContent = !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isWithinLimit = postText.count <= 500
        
        // Block posting if over character limit
        guard isWithinLimit else {
            return false
        }
        
        // If posting to #OPENTABLE or Prayer, topic tag is required
        if selectedCategory == .openTable || selectedCategory == .prayer {
            return hasContent && !selectedTopicTag.isEmpty
        }
        
        return hasContent
    }
    
    private var characterCountText: String {
        "\(postText.count)/500 characters"
    }
    
    private var characterCountColor: Color {
        if postText.count > 500 {
            return .red
        } else if postText.count > 450 {
            return .orange
        } else {
            return .secondary
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
                    // User chose to proceed anyway
                    proceedWithPublish()
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    private var placeholderText: String {
        switch selectedCategory {
        case .openTable:
            return "Share your thoughts on AI, technology, and faith..."
        case .testimonies:
            return "Share how God has been working in your life..."
        case .prayer:
            return "Share a prayer request or praise report..."
        case .tip:
            return "Share a helpful tip or advice..."
        case .funFact:
            return "Share an interesting fun fact..."
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
                textEditorView
                if !selectedImageData.isEmpty {
                    VStack(spacing: 8) {
                        ImagePreviewGrid(images: $selectedImageData)
                        
                        // P1-4 FIX: Show upload progress when uploading
                        if isUploadingImages {
                            HStack(spacing: 12) {
                                ProgressView(value: uploadProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.31, green: 0.22, blue: 0.58)))
                                    .frame(maxWidth: .infinity)
                                
                                Text("\(Int(uploadProgress * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .frame(width: 40)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                ComposerLinkPreview(controller: linkController)
                    .padding(.horizontal, 20)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: linkController.activeURL)

                // Rich link card — shown when user manually adds a link URL via the sheet
                if !linkURL.isEmpty && linkController.activeURL == nil {
                    LinkCardView(urlString: linkURL, onRemove: { linkURL = "" })
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: linkURL)
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
    
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // Character count indicator above toolbar (only when approaching limit)
            if postText.count > 400 {
                HStack(spacing: 3) {
                    Image(systemName: characterCountIcon)
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(postText.count)/500")
                        .font(.custom("OpenSans-SemiBold", size: 10))
                }
                .foregroundStyle(characterCountColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground))
                        .shadow(color: characterCountColor.opacity(0.2), radius: 4, y: 1)
                )
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.15), value: postText.count > 400)
            }
            
            // Unified bottom toolbar: X | Draft | tools | POST
            HStack(spacing: 10) {
                // X (close) button — leftmost
                CompactGlassButton(icon: "xmark", isActive: false) {
                    isTextFieldFocused = false
                    if !postText.isEmpty { saveDraft() }
                    dismiss()
                }
                .accessibilityLabel("Close")
                
                // Draft button (slides in when text exists)
                if !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    CompactGlassButton(icon: "square.and.arrow.down", isActive: false) {
                        isTextFieldFocused = false
                        saveDraft()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showingDraftSavedNotice = true
                        }
                        scheduleDelayedAction(seconds: 1.5) {
                            withAnimation { showingDraftSavedNotice = false }
                        }
                    }
                    .accessibilityLabel("Save draft")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                
                // Thin divider
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 0.5, height: 22)
                
                // Photo button
                CompactGlassButton(
                    icon: "photo.fill",
                    isActive: !selectedImageData.isEmpty,
                    count: selectedImageData.count
                ) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showingImagePicker = true
                    }
                }
                .accessibilityLabel("Add photos")
                
                // Link button
                CompactGlassButton(
                    icon: "link",
                    isActive: !linkURL.isEmpty || linkController.activeURL != nil
                ) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showingLinkSheet = true
                    }
                }
                .accessibilityLabel("Add link")
                
                // Schedule button
                CompactGlassButton(
                    icon: "calendar",
                    isActive: scheduledDate != nil
                ) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showingScheduleSheet = true
                    }
                }
                .accessibilityLabel("Schedule post")
                
                // Comment controls
                CompactGlassButton(
                    icon: allowComments ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right",
                    isActive: allowComments
                ) {
                    showCommentControls = true
                }
                .accessibilityLabel("Comment controls")
                
                // Tag people button
                CompactGlassButton(
                    icon: "person.badge.plus",
                    isActive: !taggedUsers.isEmpty,
                    count: taggedUsers.count
                ) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showingTagPeopleSheet = true
                    }
                }
                .accessibilityLabel("Tag people")
                
                // Thin divider
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 0.5, height: 22)
                
                // POST button — rightmost, neumorphic send style
                Button(action: {
                    guard canPost && !isPublishing else { return }
                    isTextFieldFocused = false
                    publishPost()
                }) {
                    ZStack {
                        // Outer neumorphic raised circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(.systemBackground).opacity(canPost ? 1.0 : 0.7),
                                        Color(.secondarySystemBackground).opacity(canPost ? 1.0 : 0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            // Light shadow (top-left highlight)
                            .shadow(color: Color.white.opacity(0.8), radius: 3, x: -2, y: -2)
                            // Dark shadow (bottom-right depth)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 2, y: 2)
                        
                        // Inner pressed inset when disabled/inactive
                        if !canPost {
                            Circle()
                                .fill(Color(.tertiarySystemBackground).opacity(0.6))
                                .frame(width: 28, height: 28)
                                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 1, y: 1)
                        }
                        
                        if isPublishing {
                            ProgressView()
                                .tint(Color(.label))
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: scheduledDate != nil ? "calendar.badge.clock" : "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(canPost ? Color(.label) : Color(.label).opacity(0.3))
                        }
                    }
                }
                .disabled(!canPost || isPublishing || isUploadingImages)
                .accessibilityLabel(scheduledDate != nil ? "Schedule post" : "Publish post")
                .modifier(ShakeEffect(shakes: shakePublishButton ? 3 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
            .shadow(color: .white.opacity(0.4), radius: 6, y: -1)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
        .animation(.easeOut(duration: 0.15), value: selectedImageData.count)
        .animation(.easeOut(duration: 0.15), value: linkURL)
        .animation(.easeOut(duration: 0.15), value: scheduledDate)
        .animation(.easeOut(duration: 0.15), value: allowComments)
        .animation(.easeOut(duration: 0.15), value: taggedUsers.count)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: postText.isEmpty)
        .sheet(isPresented: $showingTagPeopleSheet) {
            TagPeopleSheet(taggedUsers: $taggedUsers)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - View Components
    
    private var categorySelectorView: some View {
        GlassCategoryBar(
            categories: PostCategory.allCases,
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
                withAnimation(.easeOut(duration: 0.2)) {
                    showingTopicTagSheet = true
                }
            } label: {
                topicTagButtonContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var topicTagHeaderView: some View {
        HStack {
            Image(systemName: "tag.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
            
            Text(selectedCategory == .testimonies ? "Testimony Category" : selectedCategory == .openTable ? "Topic Tag" : "Prayer Type")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if selectedTopicTag.isEmpty && selectedCategory != .testimonies {
                Text("Required")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.1))
                    )
            } else if selectedTopicTag.isEmpty && selectedCategory == .testimonies {
                Text("Optional")
                    .font(.custom("OpenSans-SemiBold", size: 12))
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
                Text(selectedCategory == .testimonies ? "Select a category (optional)" : selectedCategory == .openTable ? "Select a topic tag" : "Select prayer type")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            } else {
                // Show icon for prayer types
                if selectedCategory == .prayer {
                    Image(systemName: prayerTypeIcon(for: selectedTopicTag))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(prayerTypeColor(for: selectedTopicTag))
                }
                
                Text(selectedTopicTag)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.black)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private var textEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $postText)
                        .font(.custom("OpenSans-Regular", size: 17))
                        .focused($isTextFieldFocused)
                        .scrollContentBackground(.hidden)
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
            .frame(minHeight: 150, maxHeight: 300)
            
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
        .padding(.horizontal, 20)
    }
    
    private var taggedUsersChipsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.purple)
                Text("Tagged")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(taggedUsers, id: \.userId) { user in
                        HStack(spacing: 5) {
                            Text("@\(user.username)")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.purple)
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    taggedUsers.removeAll { $0.userId == user.userId }
                                }
                                HapticManager.impact(style: .light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Mention User")
                    .font(.custom("OpenSans-SemiBold", size: 12))
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
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: mentionSuggestions.count)
    }
    
    private var hashtagSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.blue)
                
                Text("Suggested Hashtags")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hashtagSuggestions, id: \.self) { tag in
                        Button {
                            insertHashtag(tag)
                        } label: {
                            Text(tag)
                                .font(.custom("OpenSans-SemiBold", size: 13))
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
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled for")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.secondary)
                
                ScheduledWhenLine(date: scheduledDate)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.scheduledDate = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var characterCountView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: characterCountIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(characterCountColor)
                    
                    Text(characterCountText)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(characterCountColor)
                }
                
                // Enhanced validation messages
                if postText.count > 500 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Character limit exceeded - cannot post")
                            .font(.custom("OpenSans-Bold", size: 11))
                    }
                    .foregroundStyle(.red)
                } else if postText.count > 450 {
                    Text("Consider shortening your post")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private func handleCategorySelection(_ category: PostCategory) {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedCategory = category
            updateHashtagSuggestions()
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
            return .mentioned  // Map mutuals to mentioned (closest match)
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
        switch selectedCategory {
        case .openTable:
            hashtagSuggestions = ["#AIandFaith", "#TechEthics", "#Innovation", "#DigitalMinistry", "#TechForGood"]
        case .testimonies:
            hashtagSuggestions = ["#Testimony", "#FaithJourney", "#Blessed", "#Miracle", "#GodIsGood"]
        case .prayer:
            hashtagSuggestions = ["#PrayerRequest", "#PraiseReport", "#Intercession", "#DailyPrayer", "#PrayerWarrior"]
        case .tip:
            hashtagSuggestions = ["#TipOfTheDay", "#HelpfulTips", "#ProTip", "#LifeHack", "#Advice"]
        case .funFact:
            hashtagSuggestions = ["#FunFact", "#DidYouKnow", "#Interesting", "#TodayILearned", "#Facts"]
        }
    }
    
    private func detectHashtags(in text: String) {
        // Detect if user is typing a hashtag
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        if let lastWord = words.last, lastWord.hasPrefix("#") && lastWord.count > 1 {
            withAnimation {
                showingSuggestions = true
            }
        }
        
        // MARK: - Mention Detection
        // Detect if user is typing a mention (@username)
        if let lastWord = words.last, lastWord.hasPrefix("@") && lastWord.count > 1 {
            currentMentionQuery = String(lastWord.dropFirst()) // Remove @
            searchForMentions(query: currentMentionQuery)
        } else {
            withAnimation {
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
        
        withAnimation {
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
    
    private func saveDraft() {
        // Save post using DraftsManager
        draftsManager.saveDraft(
            content: postText,
            category: selectedCategory.rawValue,
            topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
            linkURL: linkURL.isEmpty ? nil : linkURL,
            visibility: "everyone"
        )
        
        withAnimation {
            showingDraftSavedNotice = true
        }
        
        // P0-2 FIX: Use cancellable task instead of DispatchQueue
        scheduleDelayedAction(seconds: 2) {
            withAnimation {
                showingDraftSavedNotice = false
            }
        }
        
    }
    
    /// Triggers a short shake animation on the publish button to signal rejection.
    private func triggerPublishShake() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.error)
        withAnimation(.default) {
            shakePublishButton = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            shakePublishButton = false
        }
    }

    private func publishPost() {
        dlog("🔵 publishPost() called")
        dlog("   isPublishing: \(isPublishing)")
        dlog("   canPost: \(canPost)")

        // First-post community guidelines prompt (shown once, gated by UserDefaults)
        let hasSeenGuidelinesKey = "hasSeenFirstPostGuidelines"
        if !UserDefaults.standard.bool(forKey: hasSeenGuidelinesKey) {
            showFirstPostGuidelinesPrompt = true
            UserDefaults.standard.set(true, forKey: hasSeenGuidelinesKey)
            return  // publishPost() will be called again after user dismisses the prompt
        }

        // Cancel auto-save immediately — no point saving a post that's about to be published
        autoSaveTask?.cancel()
        autoSaveTask = nil
        
        // Cancel in-flight mention search (keyboard is about to be dismissed)
        mentionSearchTask?.cancel()
        mentionSearchTask = nil
        showMentionSuggestions = false
        mentionSuggestions = []
        
        // P0-3 FIX: Block duplicate post attempts using a stable hash of
        // the actual content + category so rapid double-taps are deduplicated.
        let contentHash = "\(postText)|\(selectedCategory.rawValue)|\(selectedTopicTag)".hashValue
        if let existingHash = inFlightPostHash, existingHash == contentHash {
            dlog("⚠️ [P0-1] Duplicate post blocked (hash: \(contentHash))")
            return
        }
        
        guard !isPublishing else {
            dlog("⚠️ Already publishing, skipping")
            return
        }
        
        // P0-4 FIX: Check rate limiting before posting
        if rateLimiter.isRateLimited(for: .post) {
            let unlockMessage: String
            if let unlockDate = rateLimiter.getUnlockTime(for: .post) {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let seconds = Int(unlockDate.timeIntervalSinceNow)
                let mins = max(1, (seconds + 59) / 60)
                unlockMessage = "You can post again at \(formatter.string(from: unlockDate)) (\(mins) min\(mins == 1 ? "" : "s") from now)."
            } else {
                unlockMessage = "Please wait a few minutes before sharing more."
            }
            showError(
                title: "Slow Down",
                message: "You're posting quite frequently. \(unlockMessage)"
            )
            inFlightPostHash = nil
            return
        }
        
        // Set in-flight hash immediately to block duplicates
        inFlightPostHash = contentHash
        
        // Dismiss keyboard
        isTextFieldFocused = false
        
        // Validate content
        let sanitizedContent = sanitizeContent(postText)
        dlog("📝 Post content: '\(sanitizedContent)'")
        dlog("   Content length: \(sanitizedContent.count)")
        
        guard !sanitizedContent.isEmpty else {
            dlog("❌ Empty post detected")
            inFlightPostHash = nil  // P1 FIX: Allow retry after fixing validation error
            showError(
                title: "Empty Post",
                message: "Please write something before posting."
            )
            return
        }
        
        guard sanitizedContent.count <= 500 else {
            dlog("❌ Post too long: \(sanitizedContent.count) characters")
            inFlightPostHash = nil  // P1 FIX: Allow retry after fixing validation error
            showError(
                title: "Post Too Long",
                message: "Your post is \(sanitizedContent.count - 500) characters over the limit. Please shorten it to 500 characters or less."
            )
            return
        }
        
        // Validate topic tag for #OPENTABLE and Prayer
        if (selectedCategory == .openTable || selectedCategory == .prayer) && selectedTopicTag.isEmpty {
            dlog("❌ Topic tag required but missing")
            inFlightPostHash = nil  // P1 FIX: Allow retry after fixing validation error
            showError(
                title: "Topic Tag Required",
                message: selectedCategory == .openTable ? 
                    "Please select a topic tag for your #OPENTABLE post." :
                    "Please select a prayer type for your prayer post."
            )
            return
        }
        
        // Validate link URL if provided
        if !linkURL.isEmpty && !isValidURL(linkURL) {
            dlog("❌ Invalid link URL: \(linkURL)")
            inFlightPostHash = nil  // P1 FIX: Allow retry after fixing validation error
            showError(
                title: "Invalid Link",
                message: "The link you provided is not valid. Please enter a complete URL starting with http:// or https://"
            )
            return
        }
        
        // Validate image count
        if selectedImageData.count > 4 {
            dlog("❌ Too many images: \(selectedImageData.count)")
            inFlightPostHash = nil  // P1 FIX: Allow retry after fixing validation error
            showError(
                title: "Too Many Images",
                message: "You can only attach up to 4 images per post. Please remove \(selectedImageData.count - 4) image(s)."
            )
            return
        }
        
        dlog("✅ All validations passed!")
        
        // ============================================================================
        // ✅ HEY FEED: Think First Guardrails + MODERATION CONSTITUTION Stage 1
        // ============================================================================
        Task {
            // ── Stage 1: ModerationIngestService (local guard + doxxing + grooming) ──
            let authorId = Auth.auth().currentUser?.uid ?? ""
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
                    inFlightPostHash = nil
                    showError(title: "Can't Post This", message: reason)
                }
                return
            case .requireEdit(let message, let redacted):
                await MainActor.run {
                    inFlightPostHash = nil
                    if let redacted { postText = redacted }
                    showError(title: "Edit Required", message: message)
                }
                return
            case .softPrompt(let message, let canOverride):
                if !canOverride {
                    await MainActor.run {
                        inFlightPostHash = nil
                        showError(title: "Content Notice", message: message)
                    }
                    return
                }
                dlog("⚠️ [ModerationIngest] Soft prompt (continuing): \(message)")
            case .allow:
                break
            }

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
            
            let checkResult = await ThinkFirstGuardrailsService.shared.checkContent(
                sanitizedContent,
                context: context
            )
            
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
                    proceedWithPublish()
                    
                case .softPrompt:
                    // Show gentle prompt but allow posting
                    #if DEBUG
                    dlog("⚠️ Think First: Soft prompt - showing user suggestions")
                    #endif
                    showThinkFirstPrompt = true
                    
                case .requireEdit:
                    // Strongly recommend editing (e.g., PII detected with auto-redaction)
                    #if DEBUG
                    dlog("⚠️ Think First: Edit required - showing redaction options")
                    #endif
                    showThinkFirstPrompt = true
                    
                case .block:
                    // Hard block for policy violations
                    #if DEBUG
                    dlog("🚫 Think First: Content blocked")
                    #endif
                    showThinkFirstPrompt = true
                }
            }
        }
    }
    
    /// Fires the .postingFailed notification so ContentView hides the posting bar.
    /// Call this on every path that sets isPublishing = false due to an error.
    @MainActor private func notifyPostingFailed() {
        NotificationCenter.default.post(name: .postingFailed, object: nil)
    }

    // ============================================================================
    // ✅ NEW: Proceed with publish after guardrails check
    // ============================================================================
    private func proceedWithPublish() {
        let sanitizedContent = pendingPostContent.isEmpty ? sanitizeContent(postText) : pendingPostContent
        
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
        } else {
            dlog("📤 Publishing immediately")
            // Publish immediately
            publishImmediately(
                content: sanitizedContent,
                category: postCategory,
                topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
                allowComments: allowComments,
                linkURL: linkURL.isEmpty ? linkController.activeURL?.absoluteString : linkURL
            )
        }
    }
    
    private func publishImmediately(
        content: String,
        category: Post.PostCategory,
        topicTag: String?,
        allowComments: Bool,
        linkURL: String?
    ) {
        Task {
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
                        isPublishing = false
                        inFlightPostHash = nil
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
                let contentCategory: ContentCategory = category == .prayer ? .post : .post
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
                        isPublishing = false
                        inFlightPostHash = nil
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
                        isPublishing = false
                        inFlightPostHash = nil
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
                
                let postId = UUID()
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
                if !selectedImageData.isEmpty {
                    dlog("📤 Uploading \(selectedImageData.count) images (blocking)...")
                    do {
                        imageURLs = try await uploadImages()
                        dlog("✅ Images uploaded: \(imageURLs?.count ?? 0)")
                        
                        // Verify we got URLs back
                        if imageURLs == nil || imageURLs!.isEmpty {
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
                            isPublishing = false
                            inFlightPostHash = nil
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
                    
                    // Fetch all mentions in parallel using TaskGroup
                    await withTaskGroup(of: MentionedUser?.self) { group in
                        for username in mentionUsernames {
                            group.addTask {
                                do {
                                    let userQuery = try await FirebaseManager.shared.firestore
                                        .collection("users")
                                        .whereField("username", isEqualTo: username)
                                        .limit(to: 1)
                                        .getDocuments()
                                    
                                    if let userDoc = userQuery.documents.first {
                                        let userId = userDoc.documentID
                                        let displayName = userDoc.data()["displayName"] as? String ?? username
                                        dlog("   ✓ Resolved @\(username) -> \(userId)")
                                        
                                        // ✅ PRIVACY CHECK: Verify user can mention this person
                                        let canMention = try await TrustByDesignService.shared.canMention(
                                            from: currentUser.uid,
                                            mention: userId
                                        )
                                        
                                        if canMention {
                                            dlog("   ✅ Mention permission granted for @\(username)")
                                            return MentionedUser(
                                                userId: userId,
                                                username: username,
                                                displayName: displayName
                                            )
                                        } else {
                                            dlog("   ⚠️ Mention permission denied for @\(username) - skipping")
                                            return nil
                                        }
                                    }
                                } catch {
                                    dlog("   ⚠️ Failed to resolve @\(username): \(error)")
                                }
                                return nil
                            }
                        }
                        
                        // Collect all results
                        for await mention in group {
                            if let mention = mention {
                                mentions.append(mention)
                            }
                        }
                    }
                    
                    dlog("✅ [P1-3] Resolved \(mentions.count)/\(mentionUsernames.count) mentions in parallel")
                }
                
                // Create Post object with mentions
                var newPost = Post(
                    id: postId,
                    firebaseId: nil, // Will be set after Firestore save
                    authorId: currentUser.uid,
                    authorName: currentUser.displayName ?? "User",
                    authorUsername: authorUsername,
                    authorInitials: String((currentUser.displayName ?? "U").prefix(1)),
                    authorProfileImageURL: authorProfileImageURL, // ✅ Include profile picture!
                    timeAgo: "now",
                    content: content,
                    category: category,
                    topicTag: topicTag,
                    visibility: .everyone,
                    allowComments: allowComments,
                    commentPermissions: allowComments ? mapToPostCommentPermissions(commentPermission) : .off,
                    imageURLs: imageURLs,
                    linkURL: linkURL ?? linkController.activeURL?.absoluteString,
                    linkPreviewTitle: linkController.metadata?.title,
                    linkPreviewDescription: linkController.metadata?.description,
                    linkPreviewImageURL: linkController.metadata?.imageURL?.absoluteString,
                    linkPreviewSiteName: linkController.metadata?.siteName,
                    createdAt: timestamp,
                    amenCount: 0,
                    lightbulbCount: 0,
                    commentCount: 0,
                    repostCount: 0
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
                
                dlog("   ✅ Post object created: \(postId)")
                
                // Save to Firestore immediately
                var postData: [String: Any] = [
                    "authorId": currentUser.uid,
                    "authorName": currentUser.displayName ?? "User",
                    "authorInitials": String((currentUser.displayName ?? "U").prefix(1)),
                    "content": content,
                    "category": category.rawValue,
                    "topicTag": topicTag as Any,
                    "visibility": "everyone",
                    "allowComments": allowComments,
                    "imageURLs": imageURLs as Any,
                    "linkURL": (linkURL ?? linkController.activeURL?.absoluteString) as Any? as Any,
                    "createdAt": Timestamp(date: timestamp),
                    "amenCount": 0,
                    "commentCount": 0,
                    "repostCount": 0,
                    "lightbulbCount": 0
                ]
                
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
                
                // P0-4 FIX: Check if post already exists (idempotency)
                dlog("   🔍 Checking for existing post (idempotency)...")
                let existingPost = try? await FirebaseManager.shared.firestore
                    .collection("posts")
                    .document(postId.uuidString)
                    .getDocument()
                
                if let existing = existingPost, existing.exists {
                    dlog("⏭️ [P0-4] Post already created (idempotency): \(postId.uuidString)")
                    // Post already exists, skip creation but still show success
                    await MainActor.run {
                        inFlightPostHash = nil
                        linkController.reset()
                        UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
                        withAnimation { showingSuccessNotice = true }
                        // P0-2 FIX: Critical - cancellable dismiss task
                        scheduleDelayedAction(seconds: 0.15) {
                            dismiss()
                        }
                        isPublishing = false
                    }
                    return
                }
                
                dlog("   📤 Saving to Firestore immediately...")
                try await FirebaseManager.shared.firestore
                    .collection("posts")
                    .document(postId.uuidString)
                    .setData(postData)
                
                dlog("✅ Post saved to Firestore successfully!")
                dlog("   Post ID: \(newPost.id)")
                dlog("   Category: \(newPost.category.rawValue)")
                dlog("   Author: \(newPost.authorName)")

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
                            mentions: mentions,
                            actorId: currentUser.uid,
                            actorName: currentUser.displayName ?? "User",
                            actorUsername: userData?["username"] as? String,
                            postId: postId.uuidString,
                            contentType: "post"
                        )
                    }
                }
                
                // P0-2 FIX: Only dismiss AFTER Firestore confirms success
                await MainActor.run {
                    dlog("📬 Sending notification to update UI...")
                    NotificationCenter.default.post(
                        name: .newPostCreated,
                        object: nil,
                        userInfo: [
                            "post": newPost,
                            "category": newPost.category.rawValue,
                            "isOptimistic": true
                        ]
                    )
                    dlog("✅ Notification sent successfully")
                    
                    // Clear state (P0-1, P1-2)
                    inFlightPostHash = nil
                    postContentSource = nil  // reset source label for next post
                    UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
                    
                    // ✅ Show success and dismiss ONLY after Firestore success
                    withAnimation {
                        showingSuccessNotice = true
                    }
                    
                    // P0-2 FIX: Critical - cancellable dismiss task
                    scheduleDelayedAction(seconds: 0.15) {
                        dlog("👋 Dismissing CreatePostView (safe after Firestore)")
                        dismiss()
                    }
                    
                    // Reset publishing state
                    isPublishing = false
                    dlog("✅ Post creation flow completed!")
                }
                
                // Success! Sync to Algolia for search (non-blocking background task)
                dlog("🔍 Syncing to Algolia in background...")
                syncPostToAlgolia(newPost)
                
                // ============================================================================
                // ✅ CRISIS DETECTION (for prayer requests - in background after dismiss)
                // ============================================================================
                if category == .prayer {
                    dlog("🚨 Running crisis detection for prayer request in background...")
                    Task {
                        do {
                            let crisisResult = try await CrisisDetectionService.shared.detectCrisis(
                                in: content,
                                userId: currentUserId
                            )
                            
                            // If crisis detected, show resources (post already created and dismissed)
                            if crisisResult.isCrisis {
                                await MainActor.run {
                                    showCrisisResourcesAlert(crisisResult: crisisResult)
                                }
                                dlog("🚨 Crisis detected: \(crisisResult.crisisTypes.map { $0.displayName })")
                            }
                        } catch {
                            dlog("⚠️ Crisis detection failed (non-critical): \(error)")
                        }
                    }
                }
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
                    isPublishing = false
                    inFlightPostHash = nil  // P0-1 FIX: Clear hash on error
                    notifyPostingFailed()
                    ToastManager.shared.show(ToastNotification(
                        message: "Post failed to send. Please try again.",
                        style: .error,
                        action: { publishPost() },
                        actionLabel: "Retry"
                    ))
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
                    isPublishing = false
                    inFlightPostHash = nil  // P0-1 FIX: Clear hash on error
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
    
    /// Sync post to Algolia for instant search (non-blocking)
    private func syncPostToAlgolia(_ post: Post) {
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
                    "isPublic": true,
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
    
    private func uploadImages() async throws -> [String] {
        var imageURLs: [String] = []
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "CreatePostView",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        // Validate image data before upload
        guard !selectedImageData.isEmpty else {
            return []
        }
        
        await MainActor.run {
            isUploadingImages = true
            uploadProgress = 0.0
        }
        
        var failedUploads = 0
        let totalImages = selectedImageData.count
        // Stable folder ID groups all images for this post under post_media/{userId}/{uploadGroupId}/
        let uploadGroupId = UUID().uuidString

        for (index, imageData) in selectedImageData.enumerated() {
            guard !Task.isCancelled else {
                dlog("⚠️ Image upload cancelled")
                break
            }

            do {
                // Create a unique filename under the canonical post_media path
                let filename = "\(UUID().uuidString)_\(index).jpg"
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
                    
                    if !moderationDecision.isApproved {
                        await MainActor.run {
                            isUploadingImages = false
                            uploadProgress = 0.0
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
                
                // Update progress
                let progress = Double(index + 1) / Double(totalImages)
                await MainActor.run {
                    uploadProgress = progress
                }
                
                dlog("✅ Uploaded image \(index + 1)/\(totalImages)")
            } catch {
                dlog("❌ Failed to upload image \(index): \(error)")
                failedUploads += 1
                
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
        
        // Warn user if some images failed but post can still be created
        if failedUploads > 0 && !imageURLs.isEmpty {
            dlog("⚠️ \(failedUploads) image(s) failed to upload, but continuing with \(imageURLs.count) successful upload(s)")
        }
        
        return imageURLs
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
    
    private func schedulePost(
        content: String,
        category: Post.PostCategory,
        topicTag: String?,
        allowComments: Bool,
        linkURL: String?,
        scheduledFor: Date
    ) {
        Task {
            do {
                // Upload images first if any
                var imageURLs: [String]? = nil
                if !selectedImageData.isEmpty {
                    imageURLs = try await uploadImages()
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
                    "status": "pending"
                ]
                
                try await FirebaseManager.shared.firestore
                    .collection("scheduled_posts")
                    .addDocument(data: scheduledPostData)
                
                await MainActor.run {
                    
                    withAnimation {
                        showingSuccessNotice = true
                    }
                    
                    isPublishing = false
                    inFlightPostHash = nil  // FIX: clear hash so user can post again after scheduling
                    
                    // P0-2 FIX: Cancellable dismiss
                    scheduleDelayedAction(seconds: 0.5) {
                        dismiss()
                    }
                    
                    dlog("✅ Post scheduled successfully for: \(scheduledFor)")
                }
                
                // NOTE: Cloud Function will publish at scheduled time
                // Example Cloud Function (deploy separately):
                // exports.publishScheduledPosts = functions.pubsub.schedule('every 1 minutes')
                //   .onRun(async (context) => {
                //     const now = admin.firestore.Timestamp.now();
                //     const scheduled = await admin.firestore().collection('scheduled_posts')
                //       .where('scheduledFor', '<=', now)
                //       .where('status', '==', 'pending')
                //       .get();
                //     // Process and publish each post
                //   });
                
            } catch {
                await MainActor.run {
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
                    isPublishing = false
                }
            }
        }
    }
    
    // MARK: - ✅ IMPLEMENTED: Mention Users
    
    /// Search for users to mention
    private func searchForMentions(query: String) {
        guard !query.isEmpty else {
            withAnimation {
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
                    withAnimation {
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
        
        withAnimation {
            showMentionSuggestions = false
            mentionSuggestions = []
        }
    }
    
    // MARK: - ✅ IMPLEMENTED: Draft Auto-Save (Every 30s)
    
    /// Start auto-save task using Swift Concurrency
    private func startAutoSaveTimer() {
        autoSaveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if !Task.isCancelled {
                    autoSaveDraft()
                }
            }
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
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        
        UserDefaults.standard.set(autoSaveDraft, forKey: "autoSavedDraft")
        
        dlog("💾 Auto-saved draft at \(Date())")
    }
    
    /// Check for draft recovery on appear
    private func checkForDraftRecovery() {
        guard let autoSaved = UserDefaults.standard.dictionary(forKey: "autoSavedDraft"),
              let content = autoSaved["content"] as? String,
              let timestamp = autoSaved["timestamp"] as? TimeInterval,
              !content.isEmpty else {
            return
        }
        
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
            createdAt: Date(timeIntervalSince1970: timestamp)
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
        
        dlog("✅ Recovered draft from \(draft.createdAt)")
    }
    
    /// Clear recovered draft
    private func clearRecoveredDraft() {
        UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
        recoveredDraft = nil
    }
    
    // Link preview is handled by linkController (ComposerLinkPreviewController).
    
    // MARK: - ScheduledWhenLine Helper View
    
    private struct ScheduledWhenLine: View {
        let date: Date
        var body: some View {
            HStack(spacing: 0) {
                Text(date, style: .date)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                Text(" at ")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                Text(date, style: .time)
                    .font(.custom("OpenSans-Bold", size: 14))
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
                        .font(.custom("OpenSans-Regular", size: 17))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(categories, id: \.self) { category in
                        GlassCategorySegment(
                            category: category,
                            isSelected: selected == category,
                            namespace: namespace
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                selected = category
                            }
                            onSelect(category)
                        }
                        .id(category)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
            }
            .frame(height: 48)
            // Outer pill — the glass container
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Subtle top-edge specular highlight
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
            .onChange(of: selected) { _, newVal in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    proxy.scrollTo(newVal, anchor: .center)
                }
            }
        }
    }
}

/// A single segment inside GlassCategoryBar.
private struct GlassCategorySegment: View {
    let category: CreatePostView.PostCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isPressed = false

    // Label only shows for selected — matches Apple Music shrink-to-icon-when-unselected.
    private var showLabel: Bool { isSelected }

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
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .symbolRenderingMode(.hierarchical)

                    if showLabel {
                        Text(segmentLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .padding(.horizontal, isSelected ? 13 : 11)
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
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isPressed = false }
                }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    // Short label to keep the pill compact
    private var segmentLabel: String {
        switch category {
        case .openTable:   return "OpenTable"
        case .testimonies: return "Testimony"
        case .prayer:      return "Prayer"
        case .tip:         return "Tip"
        case .funFact:     return "Fun Fact"
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical, safe to use DispatchQueue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : .black.opacity(0.6))
                
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 10))
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
        
        // Non-technical topics
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
    
    var displayTags: [(String, String, Color)] {
        switch selectedCategory {
        case .prayer: return prayerTypes
        case .testimonies: return testimonyTags
        default: return openTableTags
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedCategory == .prayer ? "Select Prayer Type" : selectedCategory == .testimonies ? "Testimony Category" : "Select a Topic Tag")
                            .font(.custom("OpenSans-Bold", size: 20))
                        
                        Text(selectedCategory == .prayer ?
                             "Let others know what kind of prayer this is" :
                             selectedCategory == .testimonies ?
                             "Choose a category so others can find your testimony" :
                             "Help others discover your post in #OPENTABLE")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(displayTags, id: \.0) { tag in
                            TopicTagCard(
                                title: tag.0,
                                icon: tag.1,
                                color: tag.2,
                                isSelected: selectedTag == tag.0
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTag = tag.0
                                }
                                // Animation reset (non-critical)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isPresented = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
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
            }
        }
        .presentationDetents([.large])
    }
}

struct TopicTagCard: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 13))
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

// Schedule Post Sheet - Black & White Glassmorphic Design
struct SchedulePostSheet: View {
    @Binding var isPresented: Bool
    @Binding var scheduledDate: Date?
    @State private var selectedDateTime = Date()
    
    // Minimum schedule time is 5 minutes from now
    private var minimumDate: Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main content
            VStack(spacing: 24) {
                // Header with glassmorphic design
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                            
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Schedule Post")
                                .font(.custom("OpenSans-Bold", size: 20))
                                .foregroundStyle(.black)
                            
                            Text("Choose when to publish")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60) // Space for X button
                
                // Date picker with glassmorphic background
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DATE & TIME")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.black.opacity(0.5))
                            .tracking(1)
                        
                        DatePicker(
                            "Schedule Time",
                            selection: $selectedDateTime,
                            in: minimumDate...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .padding(16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            }
                        )
                    }
                    
                    // Info box with glassmorphic design
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.black.opacity(0.7))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-publishes at selected time")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.black.opacity(0.8))
                            
                            Text("Minimum: 5 minutes from now")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.black.opacity(0.6))
                        }
                    }
                    .padding(14)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(.ultraThinMaterial)
                            
                            Capsule()
                                .fill(Color.black.opacity(0.03))
                            
                            Capsule()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        }
                    )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                VStack(spacing: 12) {
                    // Schedule button - Black glassmorphic
                    Button {
                        scheduledDate = selectedDateTime
                        isPresented = false
                        
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            
                            Text("Schedule Post")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(Color.black)
                                
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Clear schedule button (if already scheduled)
                    if scheduledDate != nil {
                        Button {
                            scheduledDate = nil
                            isPresented = false
                        } label: {
                            Text("Remove Schedule")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.black.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            
            // X button - Top right
            Button {
                isPresented = false
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }) {
            VStack(spacing: 6) {
                Text(category.displayName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(isSelected ? .black : .black.opacity(0.4))
                
                if isSelected {
                    Capsule()
                        .fill(Color.black)
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.black)
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
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconGradient)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(backgroundFill)
                    )
                
                Text(category.displayName)
                    .font(.custom("OpenSans-Bold", size: 13))
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
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

struct ImagePreviewGrid: View {
    @Binding var images: [Data]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(images.indices, id: \.self) { index in
                    if let uiImage = UIImage(data: images[index]) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .transition(.scale.combined(with: .opacity))
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    _ = images.remove(at: index)
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.7))
                                        .frame(width: 28, height: 28)
                                    
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(8)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: images.count)
    }
}

struct LinkInputSheet: View {
    @Binding var url: String
    @Binding var isPresented: Bool
    @State private var inputURL = ""
    var onLinkAdded: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerView
                
                urlInputField
                
                Spacer()
                
                addLinkButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.height(300)])
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Link")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text("Paste or enter a URL to add to your post")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var urlInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("https://example.com", text: $inputURL)
                .font(.custom("OpenSans-Regular", size: 16))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .autocapitalization(.none)
                .keyboardType(.URL)
                .textContentType(.URL)
            
            if !inputURL.isEmpty && !isValidURL(inputURL) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    
                    Text("Please enter a valid URL")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var addLinkButton: some View {
        Button {
            url = inputURL
            onLinkAdded?(inputURL)
            isPresented = false
        } label: {
            Text("Add Link")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isValidURL(inputURL) ? Color.black : Color.black.opacity(0.3))
                        .shadow(color: isValidURL(inputURL) ? Color.black.opacity(0.2) : Color.clear, radius: 8, y: 2)
                )
        }
        .disabled(!isValidURL(inputURL))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private func isValidURL(_ string: String) -> Bool {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            return false
        }
        return true
    }
}

struct LinkPreviewCardView: View {
    let url: String
    let metadata: LinkPreviewMetadata?
    let isLoading: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            if isLoading {
                ProgressView()
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
            } else if let imageURL = metadata?.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    linkIconPlaceholder
                }
            } else {
                linkIconPlaceholder
            }
            
            // URL text and metadata
            VStack(alignment: .leading, spacing: 4) {
                if let title = metadata?.title {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } else {
                    Text("Link")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                }
                
                if let description = metadata?.description {
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Text(url)
                    .font(.custom("OpenSans-Regular", size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Remove button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onRemove()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    private var linkIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
                .frame(width: 60, height: 60)
            
            Image(systemName: "link")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.blue)
        }
    }
}

// MARK: - Floating Post Button (Removed - Using LiquidGlassPostButton instead)

// MARK: - Consolidated Toolbar

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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(width: 36, height: 36)
            }
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? .black : .black.opacity(0.5))
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                    .font(.system(size: 16, weight: .semibold))
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.4))
                .frame(width: 36, height: 36)
                .scaleEffect(isPressed ? 0.85 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Glass Button (NEW - Smaller, Production-Ready)

struct CompactGlassButton: View {
    let icon: String
    let isActive: Bool
    var count: Int = 0
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isPressed = true
            }
            action()
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
        }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPressed ? 0.85 : 1.0)
                
                // Badge for count (e.g., image count)
                if count > 0 {
                    Text("\(count)")
                        .font(.custom("OpenSans-Bold", size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                        .offset(x: 8, y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
    }
}

// MARK: - Minimal Toolbar Button (Inspired by design)

struct MinimalToolbarButton: View {
    let icon: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : Color.primary.opacity(0.4))
                    .frame(width: 36, height: 36)
            }
            .scaleEffect(isPressed ? 0.88 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Liquid Glass Post Button (Matching Design)

struct LiquidGlassPostButton: View {
    let isEnabled: Bool
    let isPublishing: Bool
    let isScheduled: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        Button(action: {
            guard isEnabled && !isPublishing else { return }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            // Button animation reset (non-critical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            
            action()
        }) {
            ZStack {
                // Dark glass background
                Circle()
                    .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                    .frame(width: 56, height: 56)
                
                // Inner dark circle for depth
                Circle()
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .frame(width: 54, height: 54)
                
                // Metallic rainbow shimmer border (matching design)
                if isEnabled {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.5, green: 0.8, blue: 1.0),  // Light blue
                                    Color(red: 0.8, green: 0.5, blue: 1.0),  // Purple
                                    Color(red: 1.0, green: 0.7, blue: 0.5),  // Orange
                                    Color(red: 1.0, green: 1.0, blue: 0.7),  // Yellow
                                    Color(red: 0.5, green: 0.8, blue: 1.0),  // Back to light blue
                                ]),
                                center: .center,
                                startAngle: .degrees(shimmerPhase),
                                endAngle: .degrees(shimmerPhase + 360)
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 56, height: 56)
                        .opacity(0.8)
                        .shadow(color: Color.cyan.opacity(0.4), radius: 8, x: 0, y: 0)
                        .shadow(color: Color.purple.opacity(0.3), radius: 12, x: 0, y: 0)
                } else {
                    // Disabled state border
                    Circle()
                        .strokeBorder(
                            Color.gray.opacity(0.3),
                            lineWidth: 2
                        )
                        .frame(width: 56, height: 56)
                }
                
                // Icon or loading
                if isPublishing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                } else {
                    Image(systemName: isScheduled ? "calendar.badge.clock" : "arrow.up")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.4))
                        .rotationEffect(.degrees(isPressed ? -5 : 0))
                }
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .shadow(
                color: isEnabled ? Color.black.opacity(0.4) : Color.clear,
                radius: 20,
                y: 8
            )
        }
        .disabled(!isEnabled || isPublishing)
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Animate shimmer continuously
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmerPhase = 360
            }
        }
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
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.1))
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add a Personal Touch")
                                .font(.custom("OpenSans-Bold", size: 20))
                                .foregroundStyle(.primary)
                            
                            Text("Make it uniquely yours")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text(message)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                
                // Text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share your personal thoughts:")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $personalContext)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .frame(height: 120)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text("\(personalContext.count)/280")
                        .font(.custom("OpenSans-Regular", size: 12))
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
                                .font(.custom("OpenSans-SemiBold", size: 16))
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
                            .font(.custom("OpenSans-Regular", size: 15))
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
// MARK: - Dynamic Island–style "Posted" pill

private struct PostedPill: View {
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
                .font(.custom("OpenSans-SemiBold", size: 15))
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
            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                blocksOpacity = 1
                blocksScale = 1
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78).delay(0.12)) {
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
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82).delay(0.08)) {
                    blocksOpacity = 0
                    blocksScale = 0.4
                }
                // Checkmark enters
                withAnimation(.spring(response: 0.28, dampingFraction: 0.70).delay(0.18)) {
                    checkmarkOpacity = 1
                    checkmarkScale = 1
                }
                withAnimation(.linear(duration: 0.36).delay(0.20)) {
                    checkmarkProgress = 1
                }
                // Label updates to "Posted"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    labelText = "Posted"
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
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
                                    .easeInOut(duration: 0.55)
                                        .repeatForever()
                                        .delay(Double(i) * 0.18),
                                    value: pulseScale
                                )
                        }
                    }
                } else {
                    Image("amen-logo")
                        .resizable()
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
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .onChange(of: isLoading) { _, loading in
            pulseScale = loading ? 1.4 : 1.0
        }
    }
}

// MARK: - Algolia Mention Suggestion Row

/// Mention row for CreatePostView's inline @-trigger, which uses AlgoliaUser.
private struct AlgoliaMentionSuggestionRow: View {
    let user: AlgoliaUser
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // ── Avatar ─────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 40, height: 40)

                    if let urlStr = user.profileImageURL,
                       !urlStr.isEmpty,
                       let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.displayName.prefix(1).uppercased())
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text(user.displayName.prefix(1).uppercased())
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                    }
                }

                // ── Name + username ────────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    // Display name with yellow marker highlight
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(alignment: .center) {
                            AlgoliaBrushstrokeHighlight()
                                .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.15, opacity: 0.75))
                        }

                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Subtle chevron affordance
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                isPressed
                    ? Color(uiColor: .tertiarySystemFill)
                    : Color.clear
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        ._onButtonGesture { pressing in
            isPressed = pressing
        } perform: {}
    }
}

// MARK: - Brushstroke highlight shape

private struct AlgoliaBrushstrokeHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Slightly irregular rounded rect that mimics a marker sweep
        p.move(to: CGPoint(x: w * 0.02, y: h * 0.55))
        p.addCurve(
            to: CGPoint(x: w * 0.98, y: h * 0.45),
            control1: CGPoint(x: w * 0.25, y: h * 0.20),
            control2: CGPoint(x: w * 0.75, y: h * 0.10)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.04, y: h * 0.95),
            control1: CGPoint(x: w * 0.80, y: h * 1.10),
            control2: CGPoint(x: w * 0.30, y: h * 1.05)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Berean Tone Popup

// MARK: - Berean Tone Popup (Liquid Glass + Sticker Label Aesthetic)
private struct BereanTonePopup: View {
    let suggestion: String?
    let onUse: (String) -> Void
    let onDismiss: () -> Void

    @State private var cardScale: CGFloat = 0.88
    @State private var cardOpacity: Double = 0
    @State private var sparkleRotation: Double = -8
    @State private var usePressed = false
    @State private var keepPressed = false
    @State private var labelWiggle: Double = 0

    // Sticker label highlight color (warm yellow)
    private let stickerYellow = Color(red: 1.0, green: 0.90, blue: 0.25)
    private let stickerMint   = Color(red: 0.72, green: 0.98, blue: 0.88)
    private let stickerBlue   = Color(red: 0.72, green: 0.88, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.opacity(0.01)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Main card: frosted white glass ────────────────────
                VStack(spacing: 0) {
                    // Drag pill
                    Capsule()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 36, height: 4)
                        .padding(.top, 14)
                        .padding(.bottom, 16)

                    // ── Header row ────────────────────────────────────
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Sticker-label title — tilted, on yellow strip
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 17, weight: .black))
                                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                                    .rotationEffect(.degrees(sparkleRotation))
                                Text("Tone Check")
                                    .font(.custom("OpenSans-ExtraBold", size: 19))
                                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(stickerYellow)
                                    .rotationEffect(.degrees(-1.2))
                            )
                            .rotationEffect(.degrees(-1.2))
                            .rotationEffect(.degrees(labelWiggle))

                            Text(suggestion != nil
                                 ? "Here's a kinder way to say this"
                                 : "Your post sounds great as-is!")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        // Close button
                        Button { onDismiss() } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // ── Suggestion area ───────────────────────────────
                    if let suggestion = suggestion {
                        VStack(alignment: .leading, spacing: 12) {
                            // Context label — plain language explanation
                            HStack(spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.35))
                                Text("Suggested rewrite — tap \"Use this\" to replace your post")
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.35))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(stickerMint.opacity(0.7))
                            )
                            .padding(.horizontal, 16)

                            // Suggestion text on frosted glass card
                            Text(suggestion)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(Color.primary)
                                .lineSpacing(5)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.regularMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.7), Color.white.opacity(0.2)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        }
                                )
                                .padding(.horizontal, 16)

                            // ── Action buttons ────────────────────────
                            HStack(spacing: 10) {
                                // "Use this" — replaces the post text with the suggestion
                                Button { onUse(suggestion) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Use this")
                                            .font(.custom("OpenSans-Bold", size: 15))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.25, green: 0.55, blue: 1.0),
                                                        Color(red: 0.45, green: 0.72, blue: 1.0)
                                                    ],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.35), radius: 8, y: 4)
                                    )
                                    .scaleEffect(usePressed ? 0.94 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: usePressed)
                                }
                                .buttonStyle(PlainButtonStyle())
                                ._onButtonGesture { pressing in usePressed = pressing } perform: {}

                                // "Keep mine" — closes popup, post unchanged
                                Button { onDismiss() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Keep mine")
                                            .font(.custom("OpenSans-Bold", size: 15))
                                    }
                                    .foregroundStyle(Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(.regularMaterial)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                            }
                                    )
                                    .scaleEffect(keepPressed ? 0.94 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: keepPressed)
                                }
                                .buttonStyle(PlainButtonStyle())
                                ._onButtonGesture { pressing in keepPressed = pressing } perform: {}
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 36)
                        }
                    } else {
                        // No rewrite needed — tone is already good
                        VStack(spacing: 16) {
                            Text("✅")
                                .font(.system(size: 40))
                            Text("Your post has a great tone!\nNo changes needed.")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                            Button { onDismiss() } label: {
                                Text("Got it")
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.72, blue: 1.0)],
                                                    startPoint: .leading, endPoint: .trailing
                                                )
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 36)
                    }
                }
                // Liquid glass card background: bright frosted white
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.70)) {
                        cardScale = 1.0
                        cardOpacity = 1.0
                    }
                    // Sparkle rocks back and forth
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.3)) {
                        sparkleRotation = 8
                    }
                    // Label has a tiny playful wiggle on appear
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.4).delay(0.45)) {
                        labelWiggle = 2
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                            labelWiggle = 0
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Source Label Prompt (shown when AI/pasted content detected at medium confidence)
private struct SourceLabelPrompt: View {
    let onPostWithSource: (String) -> Void   // passes the source string e.g. "ChatGPT"
    let onEdit: () -> Void                    // user wants to rewrite

    @State private var cardScale: CGFloat = 0.88
    @State private var cardOpacity: Double = 0
    @State private var selectedSource: String = "ChatGPT"
    @State private var postPressed = false
    @State private var editPressed = false

    private let sourceOptions = ["ChatGPT", "External", "Other AI"]
    private let stickerOrange = Color(red: 1.0, green: 0.75, blue: 0.30)
    private let stickerBlue   = Color(red: 0.72, green: 0.88, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.opacity(0.01).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag pill
                    Capsule()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 36, height: 4)
                        .padding(.top, 14)
                        .padding(.bottom, 18)

                    // ── Header ────────────────────────────────────────
                    VStack(spacing: 8) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(stickerOrange.opacity(0.2))
                                .frame(width: 56, height: 56)
                            Text("🔍")
                                .font(.system(size: 26))
                        }

                        // Title on orange sticker label
                        Text("Looks copy-pasted")
                            .font(.custom("OpenSans-ExtraBold", size: 18))
                            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.08))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(stickerOrange)
                                    .rotationEffect(.degrees(-1))
                            )
                            .rotationEffect(.degrees(-1))

                        Text("AMEN values your authentic voice.\nIf this isn't fully your own writing, label it so your community knows.")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)

                    // ── Source picker ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.80))
                            Text("source label")
                                .font(.custom("OpenSans-Bold", size: 10))
                                .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.80))
                                .textCase(.uppercase)
                                .kerning(0.8)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(stickerBlue)
                                .rotationEffect(.degrees(0.6))
                        )
                        .rotationEffect(.degrees(0.6))
                        .padding(.leading, 20)

                        // Pill selector
                        HStack(spacing: 8) {
                            ForEach(sourceOptions, id: \.self) { opt in
                                Button {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                        selectedSource = opt
                                    }
                                } label: {
                                    Text(opt)
                                        .font(.custom(selectedSource == opt ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                                        .foregroundStyle(selectedSource == opt ? .white : Color.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedSource == opt
                                                    ? Color(red: 0.25, green: 0.55, blue: 1.0)
                                                    : Color.primary.opacity(0.08))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)

                    // ── Preview badge ─────────────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                        Text("Your post will show a \"via \(selectedSource)\" label")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // ── Action buttons ────────────────────────────────
                    VStack(spacing: 10) {
                        // Post with source label
                        Button { onPostWithSource(selectedSource) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Post with source label")
                                    .font(.custom("OpenSans-Bold", size: 15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.25, green: 0.55, blue: 1.0),
                                                Color(red: 0.45, green: 0.72, blue: 1.0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.35), radius: 8, y: 4)
                            )
                            .scaleEffect(postPressed ? 0.94 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: postPressed)
                        }
                        .buttonStyle(PlainButtonStyle())
                        ._onButtonGesture { pressing in postPressed = pressing } perform: {}

                        // Edit — write it yourself
                        Button { onEdit() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Write it myself")
                                    .font(.custom("OpenSans-Bold", size: 15))
                            }
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    }
                            )
                            .scaleEffect(editPressed ? 0.94 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: editPressed)
                        }
                        .buttonStyle(PlainButtonStyle())
                        ._onButtonGesture { pressing in editPressed = pressing } perform: {}
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.70)) {
                        cardScale = 1.0
                        cardOpacity = 1.0
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

