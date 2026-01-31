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
    @State private var keyboardHeight: CGFloat = 0
    @State private var showingSuggestions = false
    @State private var hashtagSuggestions: [String] = []
    @State private var showingDraftSavedNotice = false
    @State private var selectedTopicTag = ""
    @State private var showingTopicTagSheet = false
    @State private var showingScheduleSheet = false
    @State private var isPublishing = false
    @State private var showDraftsSheet = false
    @State private var scheduledDate: Date?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var errorTitle = "Error"
    @State private var showingSuccessNotice = false
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var categoryNamespace
    
    // MARK: - New Features State
    @State private var autoSaveTimer: Timer?
    @State private var showMentionSuggestions = false
    @State private var mentionSuggestions: [AlgoliaUser] = []
    @State private var currentMentionQuery = ""
    @State private var linkMetadata: LinkMetadata?
    @State private var isLoadingLinkPreview = false
    @State private var showDraftRecovery = false
    @State private var recoveredDraft: Draft?
    @State private var uploadProgress: Double = 0.0
    @State private var isUploadingImages = false
    
    enum PostCategory: String, CaseIterable {
        case openTable = "openTable"      // ✅ Firebase-safe (no special chars)
        case testimonies = "testimonies"  // ✅ Firebase-safe (lowercase)
        case prayer = "prayer"            // ✅ Firebase-safe (lowercase)
        
        /// Display name for UI (with special formatting)
        var displayName: String {
            switch self {
            case .openTable: return "#OPENTABLE"
            case .testimonies: return "Testimonies"
            case .prayer: return "Prayer"
            }
        }
        
        var icon: String {
            switch self {
            case .openTable: return "lightbulb.fill"
            case .testimonies: return "star.fill"
            case .prayer: return "hands.sparkles.fill"
            }
        }
        
        var primaryColor: Color {
            switch self {
            case .openTable: return .orange
            case .testimonies: return .yellow
            case .prayer: return .blue
            }
        }
        
        var secondaryColor: Color {
            switch self {
            case .openTable: return .yellow
            case .testimonies: return .orange
            case .prayer: return .cyan
            }
        }
        
        var description: String {
            switch self {
            case .openTable: return "Discussions about AI, tech & faith"
            case .testimonies: return "Share your faith journey"
            case .prayer: return "Prayer requests & praise reports"
            }
        }
        
        /// Convert to Post.PostCategory for backend
        var toPostCategory: Post.PostCategory {
            switch self {
            case .openTable: return .openTable
            case .testimonies: return .testimonies
            case .prayer: return .prayer
            }
        }
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
                }
            }
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassmorphicButton(
                        icon: "xmark",
                        style: .secondary
                    ) {
                        if !postText.isEmpty {
                            saveDraft()
                        }
                        dismiss()
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Saves draft if content exists and closes the post editor")
                }
                
                // Keyboard dismiss button (shows when keyboard is visible)
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        
                        Button {
                            isTextFieldFocused = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Done")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                            }
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
                
                // Add Drafts button
                ToolbarItem(placement: .navigationBarLeading) {
                    if !draftsManager.drafts.isEmpty {
                        Button {
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
                
                // Post Button - Top Right
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        print("🔵 Post button tapped!")
                        print("   canPost: \(canPost)")
                        print("   isPublishing: \(isPublishing)")
                        print("   postText: '\(postText)'")
                        print("   selectedCategory: \(selectedCategory.rawValue)")
                        print("   selectedTopicTag: '\(selectedTopicTag)'")
                        
                        guard canPost && !isPublishing else {
                            print("❌ Button action blocked - canPost=\(canPost), isPublishing=\(isPublishing)")
                            return
                        }
                        
                        print("✅ Calling publishPost()")
                        publishPost()
                    }) {
                        ZStack {
                            // Dark glass background
                            Circle()
                                .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                .frame(width: 36, height: 36)
                            
                            // Metallic rainbow shimmer border when enabled
                            if canPost {
                                Circle()
                                    .strokeBorder(
                                        AngularGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.5, green: 0.8, blue: 1.0),
                                                Color(red: 0.8, green: 0.5, blue: 1.0),
                                                Color(red: 1.0, green: 0.7, blue: 0.5),
                                                Color(red: 1.0, green: 1.0, blue: 0.7),
                                                Color(red: 0.5, green: 0.8, blue: 1.0),
                                            ]),
                                            center: .center
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 36, height: 36)
                            } else {
                                Circle()
                                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                            }
                            
                            // Icon
                            if isPublishing {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: scheduledDate != nil ? "calendar.badge.clock" : "arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(canPost ? Color.white : Color.white.opacity(0.4))
                            }
                        }
                    }
                    .disabled(!canPost || isPublishing)
                    .accessibilityLabel(scheduledDate != nil ? "Schedule post" : "Publish post")
                    .accessibilityHint(canPost ? "Double tap to publish" : "Post is incomplete or invalid")
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomToolbar
            }
            .sheet(isPresented: $showingImagePicker) {
                PhotosPicker(selection: $selectedImages, maxSelectionCount: 4, matching: .images) {
                    Text("Select Photos")
                }
                .onChange(of: selectedImages) { _, newItems in
                    Task {
                        selectedImageData = []
                        var oversizedImages = 0
                        
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                // Check if image is too large (max 10MB)
                                let maxSize = 10 * 1024 * 1024 // 10MB
                                if data.count > maxSize {
                                    oversizedImages += 1
                                    print("⚠️ Image exceeds 10MB limit, skipping")
                                    continue
                                }
                                selectedImageData.append(data)
                            }
                        }
                        
                        // Show warning if some images were too large
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
            .sheet(isPresented: $showingLinkSheet) {
                LinkInputSheet(url: $linkURL, isPresented: $showingLinkSheet) { url in
                    fetchLinkMetadata(for: url)
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
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = 0
                }
            }
        }
        .alert(errorTitle, isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {
                isPublishing = false
            }
        } message: {
            Text(errorMessage)
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
            // Stop auto-save timer when view disappears
            autoSaveTimer?.invalidate()
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
        
        print("🔍 canPost check:")
        print("   hasContent: \(hasContent)")
        print("   isWithinLimit: \(isWithinLimit)")
        print("   postText length: \(postText.count)")
        print("   selectedCategory: \(selectedCategory.rawValue)")
        print("   selectedTopicTag: '\(selectedTopicTag)'")
        
        // Block posting if over character limit
        guard isWithinLimit else {
            print("   ❌ Over character limit")
            return false
        }
        
        // If posting to #OPENTABLE or Prayer, topic tag is required
        if selectedCategory == .openTable || selectedCategory == .prayer {
            let result = hasContent && !selectedTopicTag.isEmpty
            print("   Topic tag required - result: \(result)")
            return result
        }
        
        print("   ✅ Can post: \(hasContent)")
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
    
    private var placeholderText: String {
        switch selectedCategory {
        case .openTable:
            return "Share your thoughts on AI, technology, and faith..."
        case .testimonies:
            return "Share how God has been working in your life..."
        case .prayer:
            return "Share a prayer request or praise report..."
        }
    }
    
    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if selectedCategory == .openTable || selectedCategory == .prayer {
                    topicTagSelectorView
                }
                textEditorView
                if !selectedImageData.isEmpty {
                    ImagePreviewGrid(images: $selectedImageData)
                        .padding(.horizontal, 20)
                }
                if !linkURL.isEmpty {
                    LinkPreviewCardView(
                        url: linkURL,
                        metadata: linkMetadata,
                        isLoading: isLoadingLinkPreview
                    ) {
                        linkURL = ""
                        linkMetadata = nil
                    }
                    .padding(.horizontal, 20)
                }
                if let scheduledDate = scheduledDate {
                    scheduleIndicatorView(scheduledDate: scheduledDate)
                }
                characterCountView
            }
        }
        .scrollDismissesKeyboard(.interactively) // ✅ Dismiss keyboard on scroll
        .onTapGesture {
            // ✅ Dismiss keyboard when tapping outside
            isTextFieldFocused = false
        }
    }
    
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // Character count indicator above toolbar
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
            }
            
            // Sleek glass toolbar (matching design image)
            HStack(spacing: 16) {
                // Photo button
                GlassToolbarIcon(
                    icon: "photo.fill",
                    isActive: !selectedImageData.isEmpty
                ) {
                    showingImagePicker = true
                }
                .accessibilityLabel("Add photos")
                
                // Link button
                GlassToolbarIcon(
                    icon: "link",
                    isActive: !linkURL.isEmpty
                ) {
                    showingLinkSheet = true
                }
                .accessibilityLabel("Add link")
                
                // Schedule button
                GlassToolbarIcon(
                    icon: "calendar",
                    isActive: scheduledDate != nil
                ) {
                    showingScheduleSheet = true
                }
                .accessibilityLabel("Schedule post")
                
                // Allow comments toggle
                GlassToolbarIcon(
                    icon: "bubble.left.and.bubble.right.fill",
                    isActive: allowComments
                ) {
                    allowComments.toggle()
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }
                .accessibilityLabel("Comments")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Glass effect background
                    Capsule()
                        .fill(.ultraThinMaterial)
                    
                    // Subtle white gradient overlay
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
                    
                    // Inner border highlight
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
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
            .shadow(color: .white.opacity(0.5), radius: 8, y: -2)
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - View Components
    
    private var categorySelectorView: some View {
        HStack(spacing: 0) {
            ForEach(PostCategory.allCases, id: \.self) { category in
                LiquidGlassCategoryButton(
                    category: category,
                    isSelected: selectedCategory == category,
                    namespace: categoryNamespace
                ) {
                    handleCategorySelection(category)
                }
            }
        }
        .padding(4)
        .background(categorySelectorBackground)
    }
    
    private var categorySelectorBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
    }
    
    private var topicTagSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            topicTagHeaderView
            
            Button {
                showingTopicTagSheet = true
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
                .foregroundStyle(.black)
            
            Text(selectedCategory == .openTable ? "Topic Tag" : "Prayer Type")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if selectedTopicTag.isEmpty {
                Text("Required")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.1))
                    )
            }
        }
    }
    
    private var topicTagButtonContent: some View {
        HStack {
            if selectedTopicTag.isEmpty {
                Text(selectedCategory == .openTable ? "Select a topic tag" : "Select prayer type")
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
            ZStack(alignment: .topLeading) {
                // Background that dismisses keyboard on tap
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Only dismiss if tapping empty space
                        if postText.isEmpty {
                            isTextFieldFocused = false
                        }
                    }
                
                GeometryReader { geometry in
                    TextEditor(text: $postText)
                        .font(.custom("OpenSans-Regular", size: 17))
                        .focused($isTextFieldFocused)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            EditorPlaceholderView(
                                isEmpty: postText.isEmpty,
                                placeholder: placeholderText,
                                description: selectedCategory.description
                            )
                        }
                        .onChange(of: postText) { _, newValue in
                            detectHashtags(in: newValue)
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
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Mention Suggestions View
    
    private var mentionSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "at")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.purple)
                
                Text("Mention User")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(mentionSuggestions, id: \.objectID) { user in
                    Button {
                        insertMention(user)
                    } label: {
                        HStack(spacing: 12) {
                            // Avatar placeholder
                            Circle()
                                .fill(Color.purple.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(user.displayName.prefix(1))
                                        .font(.custom("OpenSans-Bold", size: 14))
                                        .foregroundStyle(.purple)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.primary)
                                
                                Text("@\(user.username)")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
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
                self.scheduledDate = nil
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
        .transition(.move(edge: .top).combined(with: .opacity))
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedCategory = category
            updateHashtagSuggestions()
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
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
    
    /// Display user-friendly error message
    private func showError(title: String = "Oops!", message: String) {
        errorTitle = title
        errorMessage = message
        showingErrorAlert = true
        
        // Error haptic
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.error)
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
              let host = url.host,
              ["http", "https"].contains(scheme.lowercased()) else {
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingDraftSavedNotice = false
            }
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    private func publishPost() {
        print("🔵 publishPost() called")
        print("   isPublishing: \(isPublishing)")
        print("   canPost: \(canPost)")
        
        guard !isPublishing else {
            print("⚠️ Already publishing, skipping")
            return
        }
        
        // Dismiss keyboard
        isTextFieldFocused = false
        
        // Validate content
        let sanitizedContent = sanitizeContent(postText)
        print("📝 Post content: '\(sanitizedContent)'")
        print("   Content length: \(sanitizedContent.count)")
        
        guard !sanitizedContent.isEmpty else {
            print("❌ Empty post detected")
            showError(
                title: "Empty Post",
                message: "Please write something before posting."
            )
            return
        }
        
        guard sanitizedContent.count <= 500 else {
            print("❌ Post too long: \(sanitizedContent.count) characters")
            showError(
                title: "Post Too Long",
                message: "Your post is \(sanitizedContent.count - 500) characters over the limit. Please shorten it to 500 characters or less."
            )
            return
        }
        
        // Validate topic tag for #OPENTABLE and Prayer
        if (selectedCategory == .openTable || selectedCategory == .prayer) && selectedTopicTag.isEmpty {
            print("❌ Topic tag required but missing")
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
            print("❌ Invalid link URL: \(linkURL)")
            showError(
                title: "Invalid Link",
                message: "The link you provided is not valid. Please enter a complete URL starting with http:// or https://"
            )
            return
        }
        
        // Validate image count
        if selectedImageData.count > 4 {
            print("❌ Too many images: \(selectedImageData.count)")
            showError(
                title: "Too Many Images",
                message: "You can only attach up to 4 images per post. Please remove \(selectedImageData.count - 4) image(s)."
            )
            return
        }
        
        print("✅ All validations passed!")
        print("   Setting isPublishing = true")
        isPublishing = true
        
        // Convert CreatePostView.PostCategory to Post.PostCategory for backend
        let postCategory = selectedCategory.toPostCategory
        print("   Post category: \(postCategory.rawValue)")
        
        // Check if post is scheduled
        if let scheduledDate = scheduledDate {
            print("📅 Scheduling post for: \(scheduledDate)")
            // Handle scheduled post
            schedulePost(
                content: sanitizedContent,
                category: postCategory,
                topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
                allowComments: allowComments,
                linkURL: linkURL.isEmpty ? nil : linkURL,
                scheduledFor: scheduledDate
            )
        } else {
            print("📤 Publishing immediately")
            // Publish immediately
            publishImmediately(
                content: sanitizedContent,
                category: postCategory,
                topicTag: selectedTopicTag.isEmpty ? nil : selectedTopicTag,
                allowComments: allowComments,
                linkURL: linkURL.isEmpty ? nil : linkURL
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
                print("🚀 Starting post creation...")
                print("   Content length: \(content.count)")
                print("   Category: \(category.rawValue)")
                print("   Topic tag: \(topicTag ?? "none")")
                print("   Allow comments: \(allowComments)")
                print("   Link URL: \(linkURL ?? "none")")
                print("   Images: \(selectedImageData.count)")
                
                // Upload images first if any
                var imageURLs: [String]? = nil
                if !selectedImageData.isEmpty {
                    print("📤 Uploading \(selectedImageData.count) images...")
                    do {
                        imageURLs = try await uploadImages()
                        print("✅ Images uploaded: \(imageURLs?.count ?? 0)")
                    } catch {
                        print("❌ Image upload failed: \(error)")
                        throw error
                    }
                }
                
                // 🔥 FIX: Use Firestore directly (RealtimePostService has schema mismatch)
                print("📝 Creating post in Firestore...")
                
                let newPost: Post
                do {
                    guard let currentUser = Auth.auth().currentUser else {
                        throw NSError(domain: "CreatePostView", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
                    }
                    
                    let postId = UUID()
                    let timestamp = Date()
                    
                    // Create Post object
                    newPost = Post(
                        id: postId,
                        authorId: currentUser.uid,
                        authorName: currentUser.displayName ?? "User",
                        authorInitials: String((currentUser.displayName ?? "U").prefix(1)),
                        timeAgo: "now",
                        content: content,
                        category: category,
                        topicTag: topicTag,
                        visibility: .everyone,
                        allowComments: allowComments,
                        imageURLs: imageURLs,
                        linkURL: linkURL,
                        createdAt: timestamp,
                        amenCount: 0,
                        lightbulbCount: 0,
                        commentCount: 0,
                        repostCount: 0
                    )
                    
                    print("   ✅ Post object created: \(postId)")
                    
                    // Save to Firestore
                    let postData: [String: Any] = [
                        "authorId": currentUser.uid,
                        "authorName": currentUser.displayName ?? "User",
                        "authorInitials": String((currentUser.displayName ?? "U").prefix(1)),
                        "content": content,
                        "category": category.rawValue,
                        "topicTag": topicTag as Any,
                        "visibility": "everyone",
                        "allowComments": allowComments,
                        "imageURLs": imageURLs as Any,
                        "linkURL": linkURL as Any,
                        "createdAt": Timestamp(date: timestamp),
                        "amenCount": 0,
                        "commentCount": 0,
                        "repostCount": 0,
                        "lightbulbCount": 0
                    ]
                    
                    print("   📤 Saving to Firestore...")
                    try await FirebaseManager.shared.firestore
                        .collection("posts")
                        .document(postId.uuidString)
                        .setData(postData)
                    
                    print("✅ Post saved to Firestore successfully!")
                    print("   Post ID: \(newPost.id)")
                    print("   Category: \(newPost.category.rawValue)")
                    print("   Author: \(newPost.authorName)")
                } catch {
                    print("❌ RealtimePostService.createPost failed: \(error)")
                    if let nsError = error as NSError? {
                        print("   Domain: \(nsError.domain)")
                        print("   Code: \(nsError.code)")
                        print("   UserInfo: \(nsError.userInfo)")
                    }
                    throw error
                }
                
                await MainActor.run {
                    print("📬 Sending notification to update UI...")
                    
                    // 📬 CRITICAL: Send notification for INSTANT ProfileView update
                    NotificationCenter.default.post(
                        name: .newPostCreated,
                        object: nil,
                        userInfo: [
                            "post": newPost,
                            "category": newPost.category.rawValue,
                            "isOptimistic": true
                        ]
                    )
                    
                    print("✅ Notification sent successfully")
                    
                    // Success! Sync to Algolia for search (non-blocking)
                    print("🔍 Syncing to Algolia in background...")
                    syncPostToAlgolia(newPost)
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Show brief success notice
                    withAnimation {
                        showingSuccessNotice = true
                    }
                    
                    // Dismiss after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("👋 Dismissing CreatePostView")
                        dismiss()
                    }
                    
                    // Reset publishing state
                    isPublishing = false
                    print("✅ Post creation flow completed!")
                }
            } catch let error as NSError {
                await MainActor.run {
                    print("❌ Failed to create post (NSError)")
                    print("   Error domain: \(error.domain)")
                    print("   Error code: \(error.code)")
                    print("   Error description: \(error.localizedDescription)")
                    print("   Error userInfo: \(error.userInfo)")
                    print("   Localized failure reason: \(error.localizedFailureReason ?? "none")")
                    print("   Localized recovery suggestion: \(error.localizedRecoverySuggestion ?? "none")")
                    
                    // Convert to user-friendly error
                    let friendlyError = getUserFriendlyError(from: error)
                    showError(title: friendlyError.title, message: friendlyError.message)
                    
                    isPublishing = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to create post (Generic Error)")
                    print("   Error: \(error)")
                    print("   Error type: \(type(of: error))")
                    print("   Error description: \(String(describing: error))")
                    
                    // Try to get more details
                    if let error = error as? LocalizedError {
                        print("   Error description: \(error.errorDescription ?? "none")")
                        print("   Failure reason: \(error.failureReason ?? "none")")
                        print("   Recovery suggestion: \(error.recoverySuggestion ?? "none")")
                    }
                    
                    // Convert to user-friendly error
                    let friendlyError = getUserFriendlyError(from: error)
                    showError(title: friendlyError.title, message: friendlyError.message)
                    
                    isPublishing = false
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
                
                print("✅ Post synced to Algolia: \(post.id.uuidString)")
            } catch {
                // Silently log - Algolia sync is non-critical
                print("⚠️ Failed to sync post to Algolia (non-critical): \(error)")
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
        
        await MainActor.run {
            isUploadingImages = true
            uploadProgress = 0.0
        }
        
        var failedUploads = 0
        
        for (index, imageData) in selectedImageData.enumerated() {
            do {
                // Create a unique filename
                let filename = "\(UUID().uuidString)_\(index).jpg"
                let storageRef = FirebaseManager.shared.storage.reference()
                    .child("posts")
                    .child(userId)
                    .child(filename)
                
                // Compress image before upload (max 1MB)
                guard let compressedData = compressImage(imageData, maxSizeInMB: 1.0) else {
                    print("⚠️ Failed to compress image \(index)")
                    failedUploads += 1
                    continue
                }
                
                // Upload image
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                
                let _ = try await storageRef.putDataAsync(compressedData, metadata: metadata)
                
                // Get download URL
                let downloadURL = try await storageRef.downloadURL()
                imageURLs.append(downloadURL.absoluteString)
                
                // Update progress
                let progress = Double(index + 1) / Double(selectedImageData.count)
                await MainActor.run {
                    uploadProgress = progress
                }
                
                print("✅ Uploaded image \(index + 1)/\(selectedImageData.count)")
            } catch {
                print("❌ Failed to upload image \(index): \(error)")
                failedUploads += 1
                
                // If more than half the images fail, throw error
                if failedUploads > selectedImageData.count / 2 {
                    await MainActor.run {
                        isUploadingImages = false
                    }
                    throw NSError(
                        domain: "ImageUpload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Too many images failed to upload"]
                    )
                }
            }
        }
        
        await MainActor.run {
            isUploadingImages = false
        }
        
        // Warn user if some images failed but post can still be created
        if failedUploads > 0 && !imageURLs.isEmpty {
            print("⚠️ \(failedUploads) image(s) failed to upload, but continuing with \(imageURLs.count) successful upload(s)")
        }
        
        return imageURLs
    }
    
    /// Compress image to target size
    private func compressImage(_ data: Data, maxSizeInMB: Double) -> Data? {
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
                print("📅 Scheduling post via Cloud Functions...")
                
                // Save to Firestore scheduled_posts collection
                let scheduledPostData: [String: Any] = [
                    "content": content,
                    "category": category.rawValue,
                    "topicTag": topicTag as Any,
                    "allowComments": allowComments,
                    "linkURL": linkURL as Any,
                    "imageURLs": imageURLs as Any,
                    "scheduledFor": Timestamp(date: scheduledFor),
                    "createdAt": Timestamp(date: Date()),
                    "authorId": Auth.auth().currentUser?.uid ?? "",
                    "status": "pending"
                ]
                
                try await FirebaseManager.shared.firestore
                    .collection("scheduled_posts")
                    .addDocument(data: scheduledPostData)
                
                await MainActor.run {
                    // Success feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    withAnimation {
                        showingSuccessNotice = true
                    }
                    
                    isPublishing = false
                    
                    // Dismiss after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                    
                    print("✅ Post scheduled successfully for: \(scheduledFor)")
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
                    showError(title: friendlyError.title, message: friendlyError.message)
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
        
        Task {
            do {
                let results = try await AlgoliaSearchService.shared.searchUsers(query: query)
                
                await MainActor.run {
                    withAnimation {
                        // Limit to 5 results
                        mentionSuggestions = Array(results.prefix(5))
                        showMentionSuggestions = !results.isEmpty
                    }
                }
            } catch {
                print("⚠️ Failed to search for mentions: \(error)")
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
    
    /// Start auto-save timer
    private func startAutoSaveTimer() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            autoSaveDraft()
        }
    }
    
    /// Auto-save draft silently
    private func autoSaveDraft() {
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
        
        print("💾 Auto-saved draft at \(Date())")
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
        
        print("✅ Recovered draft from \(draft.createdAt)")
    }
    
    /// Clear recovered draft
    private func clearRecoveredDraft() {
        UserDefaults.standard.removeObject(forKey: "autoSavedDraft")
        recoveredDraft = nil
    }
    
    // MARK: - ✅ IMPLEMENTED: Link Previews
    
    /// Fetch link metadata when URL is added
    private func fetchLinkMetadata(for url: String) {
        guard isValidURL(url) else { return }
        
        isLoadingLinkPreview = true
        
        Task {
            do {
                let metadata = try await LinkPreviewService.shared.fetchMetadata(url: url)
                
                await MainActor.run {
                    linkMetadata = metadata
                    isLoadingLinkPreview = false
                }
            } catch {
                print("⚠️ Failed to fetch link preview: \(error)")
                await MainActor.run {
                    isLoadingLinkPreview = false
                }
            }
        }
    }
    
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(placeholder)
                            .font(.custom("OpenSans-Regular", size: 17))
                            .foregroundStyle(.secondary)
                        Text(description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Supporting Views

// Liquid Glass Category Button (matching the image design)
struct LiquidGlassCategoryButton: View {
    let category: CreatePostView.PostCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .black.opacity(0.7))
                
                if isSelected {
                    Text(category.displayName)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, isSelected ? 14 : 11)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.black)
                            .matchedGeometryEffect(id: "selectedCategory", in: namespace)
                            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
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
    let openTableTags = [
        ("AI & Technology", "cpu", Color.blue),
        ("Ethics & Morality", "scale.3d", Color.purple),
        ("Innovation", "lightbulb.max.fill", Color.orange),
        ("Digital Ministry", "app.connected.to.app.below.fill", Color.green),
        ("Future of Faith", "clock.arrow.2.circlepath", Color.cyan),
        ("Theology & Tech", "brain.head.profile", Color.indigo),
        ("Social Media & Faith", "bubble.left.and.bubble.right.fill", Color.pink),
        ("Automation & Work", "gearshape.2.fill", Color.teal)
    ]
    
    // Prayer types
    let prayerTypes = [
        ("Prayer Request", "hands.sparkles.fill", Color(red: 0.4, green: 0.7, blue: 1.0)),
        ("Praise Report", "hands.clap.fill", Color(red: 1.0, green: 0.7, blue: 0.4)),
        ("Answered Prayer", "checkmark.seal.fill", Color(red: 0.4, green: 0.85, blue: 0.7))
    ]
    
    var displayTags: [(String, String, Color)] {
        selectedCategory == .prayer ? prayerTypes : openTableTags
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedCategory == .prayer ? "Select Prayer Type" : "Select a Topic Tag")
                            .font(.custom("OpenSans-Bold", size: 20))
                        
                        Text(selectedCategory == .prayer ? 
                             "Let others know what kind of prayer this is" :
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
        Button(action: action) {
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
                    .shadow(color: isSelected ? color.opacity(0.2) : .black.opacity(0.05), radius: isSelected ? 12 : 8, y: 4)
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

// Schedule Post Sheet
struct SchedulePostSheet: View {
    @Binding var isPresented: Bool
    @Binding var scheduledDate: Date?
    @State private var selectedDateTime = Date()
    
    // Minimum schedule time is 5 minutes from now
    private var minimumDate: Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Schedule Post")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            Text("Choose when to publish your post")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date & Time")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.secondary)
                        
                        DatePicker(
                            "Schedule Time",
                            selection: $selectedDateTime,
                            in: minimumDate...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray6))
                        )
                    }
                    
                    // Info box
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your post will be published automatically at the selected time.")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                            
                            Text("Minimum: 5 minutes from now")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                VStack(spacing: 12) {
                    // Schedule button
                    Button {
                        scheduledDate = selectedDateTime
                        isPresented = false
                        
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            
                            Text("Schedule Post")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green)
                                .shadow(color: .green.opacity(0.3), radius: 12, y: 4)
                        )
                    }
                    
                    // Clear schedule button (if already scheduled)
                    if scheduledDate != nil {
                        Button {
                            scheduledDate = nil
                            isPresented = false
                        } label: {
                            Text("Remove Schedule")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
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
                            
                            Button {
                                withAnimation {
                                    _ = images.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.5))
                                            .frame(width: 24, height: 24)
                                    )
                            }
                            .padding(8)
                        }
                    }
                }
            }
        }
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
              let host = url.host,
              ["http", "https"].contains(scheme.lowercased()) else {
            return false
        }
        return true
    }
}

struct LinkPreviewCardView: View {
    let url: String
    let metadata: LinkMetadata?
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
            } else if let imageURL = metadata?.imageURL,
                      let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
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
            Button(action: onRemove) {
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
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
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
            
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
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
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
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
            
            let haptic = UIImpactFeedbackGenerator(style: .heavy)
            haptic.impactOccurred()
            
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

/// Link metadata for rich previews
struct LinkMetadata {
    let title: String?
    let description: String?
    let imageURL: String?
    let siteName: String?
}

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

/// Service to fetch link metadata
actor LinkPreviewService {
    static let shared = LinkPreviewService()
    
    private init() {}
    
    func fetchMetadata(url: String) async throws -> LinkMetadata {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        // Fetch HTML
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        // Parse OpenGraph/meta tags
        let title = extractMetaTag(from: html, property: "og:title") ?? extractTitle(from: html)
        let description = extractMetaTag(from: html, property: "og:description") ?? extractMetaTag(from: html, name: "description")
        let imageURL = extractMetaTag(from: html, property: "og:image")
        let siteName = extractMetaTag(from: html, property: "og:site_name")
        
        return LinkMetadata(
            title: title,
            description: description,
            imageURL: imageURL,
            siteName: siteName
        )
    }
    
    private func extractMetaTag(from html: String, property: String) -> String? {
        let pattern = "<meta\\s+property=\"\(property)\"\\s+content=\"([^\"]+)\""
        return extractPattern(pattern, from: html)
    }
    
    private func extractMetaTag(from html: String, name: String) -> String? {
        let pattern = "<meta\\s+name=\"\(name)\"\\s+content=\"([^\"]+)\""
        return extractPattern(pattern, from: html)
    }
    
    private func extractTitle(from html: String) -> String? {
        let pattern = "<title>([^<]+)</title>"
        return extractPattern(pattern, from: html)
    }
    
    private func extractPattern(_ pattern: String, from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        
        return String(html[contentRange])
    }
}




