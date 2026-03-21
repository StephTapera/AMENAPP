//
//  RepostQuoteComponents.swift
//  AMENAPP
//
//  Repost action sheet + Quote Post full-screen composer.
//  Matches AMEN's dark glassmorphic design system.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

// MARK: - Design Tokens

private let amenDeepBackground = Color(red: 0.039, green: 0.039, blue: 0.059) // #0A0A0F
private let amenGlassCard = Color.white.opacity(0.08)
private let amenGlassBorder = Color.white.opacity(0.15)
private let amenPurpleStart = Color(red: 0.486, green: 0.227, blue: 0.929) // #7C3AED
private let amenPurpleEnd   = Color(red: 0.659, green: 0.333, blue: 0.969) // #A855F7

private let purpleGradient = LinearGradient(
    colors: [amenPurpleStart, amenPurpleEnd],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// MARK: - RepostActionSheet

/// Bottom action sheet presented when the user taps the Repost button on a PostCard.
/// Shows "Repost" (instant) and "Quote" (opens full composer) options.
struct RepostActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post

    var onRepost: (() -> Void)?
    var onQuote: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Threads-style bottom pill — two compact rows
            VStack(spacing: 0) {
                // Repost only
                Button {
                    HapticManager.impact(style: .medium)
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onRepost?()
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "repeat")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(.label))
                        Text("Repost")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(.label))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RepostRowPressStyle())

                // Divider
                Rectangle()
                    .fill(Color(.separator).opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.leading, 52)

                // Quote
                Button {
                    HapticManager.impact(style: .light)
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onQuote?()
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(.label))
                        Text("Quote")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(.label))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RepostRowPressStyle())
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.25),
                            lineWidth: 0.75
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.001)) // Tap-to-dismiss backdrop
        .onTapGesture { dismiss() }
    }
}

// MARK: - RepostRowPressStyle

private struct RepostRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color(.label).opacity(0.06)
                    : Color.clear
            )
    }
}

// MARK: - GlassRowButtonStyle

private struct GlassRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.07)
                    : Color.clear
            )
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - QuotePostComposerView

/// Full-screen composer for adding a quote post on top of an original post.
/// Matches CreatePostView's Threads-style design: system background, adaptive colors.
struct QuotePostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let originalPost: Post

    var onPublish: ((_ quoteText: String, _ originalPost: Post) -> Void)?

    // MARK: - State
    @State private var quoteText: String = ""
    @State private var isPublishing = false
    @FocusState private var isFocused: Bool
    @State private var selectedCategory: Post.PostCategory = .openTable

    // Media
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachedImages: [UIImage] = []
    @State private var showingCamera = false
    @State private var cameraImage: UIImage? = nil

    // @ Mention
    @State private var showMentionSuggestions = false
    @State private var mentionSuggestions: [AlgoliaUser] = []
    @State private var currentMentionQuery = ""
    @State private var mentionSearchTask: Task<Void, Never>?

    // # Hashtag
    @State private var showHashtagSuggestions = false
    @State private var hashtagSuggestions: [String] = []

    private var canPublish: Bool { !quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPublishing }
    private var charCount: Int { quoteText.count }
    private let charLimit = 500

    /// Categories available for quote posts (excludes Tip and Fun Fact)
    private var availableCategories: [Post.PostCategory] {
        Post.PostCategory.allCases.filter { $0 != .tip && $0 != .funFact }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // User row with avatar + category selector
                            quoteUserRow
                                .padding(.horizontal, 16)
                                .padding(.top, 12)

                            // Compose area with thread connector
                            HStack(alignment: .top, spacing: 12) {
                                // Thread connector line
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(width: 1)
                                }
                                .frame(width: 44)
                                .padding(.top, 4)

                                // Text input + attachments
                                VStack(alignment: .leading, spacing: 12) {
                                    quoteTextEditorView

                                    // Mention suggestions
                                    if showMentionSuggestions && !mentionSuggestions.isEmpty {
                                        quoteMentionSuggestionsView
                                    }

                                    // Hashtag suggestions
                                    if showHashtagSuggestions && !hashtagSuggestions.isEmpty {
                                        quoteHashtagSuggestionsView
                                    }

                                    // Camera photo preview
                                    if let capturedImage = cameraImage {
                                        quoteCameraPreview(capturedImage)
                                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                                    }

                                    // Library photo grid
                                    if !attachedImages.isEmpty {
                                        quoteImageStrip
                                    }
                                }
                            }
                            .padding(.horizontal, 16)

                            // Quoted post embed
                            quotedPostCard
                                .padding(.leading, 72)
                                .padding(.trailing, 16)
                                .padding(.top, 12)

                            // Add to thread row
                            quoteAddToThreadRow
                        }
                        .padding(.bottom, 120)
                    }
                }

                // Bottom toolbar
                VStack {
                    Spacer()
                    quoteBottomToolbar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("Quote Post")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(Color(.label))
                }
                ToolbarItem(placement: .confirmationAction) {
                    quotePublishButton
                }
            }
        }
        .onAppear {
            isFocused = true
            updateQuoteHashtagSuggestions()
        }
        .interactiveDismissDisabled(canPublish || !quoteText.isEmpty)
        .sheet(isPresented: $showingCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
    }

    // MARK: - Publish Button

    private var quotePublishButton: some View {
        Button {
            guard canPublish else { return }
            submitQuotePost()
        } label: {
            Group {
                if isPublishing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                        .frame(width: 64, height: 32)
                } else {
                    Text("Post")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
            }
            .background(canPublish ? Color(.label) : Color(.label).opacity(0.3))
            .clipShape(Capsule())
        }
        .disabled(!canPublish)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: canPublish)
    }

    // MARK: - User Row

    private var quoteUserRow: some View {
        HStack(spacing: 12) {
            quoteCurrentUserAvatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Auth.auth().currentUser?.displayName ?? "You")
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(Color(.label))

                    quoteCategoryPill
                }
            }
        }
    }

    private var quoteCurrentUserAvatar: some View {
        let cachedURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        let resolvedURL: URL? = {
            if let firebaseURL = Auth.auth().currentUser?.photoURL {
                return firebaseURL
            } else if let cached = cachedURL, let url = URL(string: cached) {
                return url
            }
            return nil
        }()

        return ZStack {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 44, height: 44)

            if let url = resolvedURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } placeholder: {
                    Text(quoteUserInitials)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                }
            } else {
                Text(quoteUserInitials)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var quoteUserInitials: String {
        let name = Auth.auth().currentUser?.displayName ?? "U"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var quoteCategoryPill: some View {
        Menu {
            ForEach(availableCategories, id: \.self) { cat in
                Button {
                    selectedCategory = cat
                    updateQuoteHashtagSuggestions()
                } label: {
                    Label(cat.displayName, systemImage: categoryIcon(for: cat))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedCategory.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(categoryColor(for: selectedCategory))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(categoryColor(for: selectedCategory).opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(categoryColor(for: selectedCategory).opacity(0.25), lineWidth: 1))
        }
    }

    private func categoryIcon(for cat: Post.PostCategory) -> String {
        switch cat {
        case .openTable: return "lightbulb.fill"
        case .testimonies: return "star.fill"
        case .prayer: return "hands.sparkles.fill"
        case .tip: return "info.circle.fill"
        case .funFact: return "sparkles"
        }
    }

    private func categoryColor(for cat: Post.PostCategory) -> Color {
        switch cat {
        case .openTable: return .orange
        case .testimonies: return .yellow
        case .prayer: return .blue
        case .tip: return .green
        case .funFact: return .purple
        }
    }

    // MARK: - Text Editor

    private var quoteTextEditorView: some View {
        ZStack(alignment: .topLeading) {
            if quoteText.isEmpty {
                Text("Share your thoughts…")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .allowsHitTesting(false)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }
            TextEditor(text: $quoteText)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(Color(.label))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .focused($isFocused)
                .frame(minHeight: 80)
                .onChange(of: quoteText) { _, newValue in
                    if newValue.count > charLimit {
                        quoteText = String(newValue.prefix(charLimit))
                    }
                    detectQuoteMentionsAndHashtags(in: newValue)
                }
        }
    }

    // MARK: - Mention Suggestions

    private var quoteMentionSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        HapticManager.impact(style: .light)
                        insertQuoteMention(user)
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

    // MARK: - Hashtag Suggestions

    private var quoteHashtagSuggestionsView: some View {
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
                            insertQuoteHashtag(tag)
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

    // MARK: - Camera Preview

    private func quoteCameraPreview(_ image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    cameraImage = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(8)
            }
        }
    }

    // MARK: - Image Strip

    private var quoteImageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, img in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                attachedImages.remove(at: idx)
                                if idx < selectedPhotoItems.count {
                                    selectedPhotoItems.remove(at: idx)
                                }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .padding(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quoted Post Card

    private var quotedPostCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 22, height: 22)

                    if let urlString = originalPost.authorProfileImageURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(originalPost.authorInitials)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text(originalPost.authorInitials)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                Text(originalPost.authorName)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(Color(.label))

                if let username = originalPost.authorUsername {
                    Text("@\(username)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                quoteCategoryBadge(for: originalPost.category)
            }

            // Original content
            Text(originalPost.content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(Color(.label).opacity(0.8))
                .lineLimit(5)

            // Attached image strip (if any)
            if let urls = originalPost.imageURLs, !urls.isEmpty {
                HStack(spacing: 6) {
                    ForEach(urls.prefix(3), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.systemGray5))
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            )
                    }
                    if urls.count > 3 {
                        Text("+\(urls.count - 3)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func quoteCategoryBadge(for category: Post.PostCategory) -> some View {
        Text(category.displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(categoryColor(for: category))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(categoryColor(for: category).opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Add to Thread

    private var quoteAddToThreadRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
                .padding(.leading, 6)

            Text("Add to thread")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .onTapGesture {
            HapticManager.impact(style: .light)
        }
    }

    // MARK: - Bottom Toolbar

    private var quoteBottomToolbar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 18) {
                // Photo gallery picker
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Photo")
                .onChange(of: selectedPhotoItems) { _, items in
                    loadQuoteSelectedPhotos(items)
                }

                // Camera
                Button {
                    HapticManager.impact(style: .light)
                    showingCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Camera")

                // @ Mention
                Button {
                    HapticManager.impact(style: .light)
                    quoteText += quoteText.isEmpty || quoteText.hasSuffix(" ") ? "@" : " @"
                    isFocused = true
                } label: {
                    Image(systemName: "at")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Mention")

                // # Hashtag
                Button {
                    HapticManager.impact(style: .light)
                    quoteText += quoteText.isEmpty || quoteText.hasSuffix(" ") ? "#" : " #"
                    isFocused = true
                    withAnimation {
                        showHashtagSuggestions = true
                    }
                } label: {
                    Image(systemName: "number")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Hashtag")

                Spacer()

                // Character counter with circular progress
                if charCount > 0 {
                    let remaining = charLimit - charCount
                    let progress = Double(charCount) / Double(charLimit)

                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                remaining < 20 ? Color.red :
                                remaining < 50 ? Color.orange :
                                Color.primary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .frame(width: 24, height: 24)
                            .rotationEffect(.degrees(-90))

                        if remaining <= 20 {
                            Text("\(remaining)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(remaining < 0 ? .red : .secondary)
                                .monospacedDigit()
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: charCount)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Detection Logic

    private func detectQuoteMentionsAndHashtags(in text: String) {
        let words = text.components(separatedBy: .whitespacesAndNewlines)

        // Mention detection: @username
        if let lastWord = words.last, lastWord.hasPrefix("@") && lastWord.count > 1 {
            currentMentionQuery = String(lastWord.dropFirst())
            searchForQuoteMentions(query: currentMentionQuery)
        } else {
            withAnimation {
                showMentionSuggestions = false
                mentionSuggestions = []
            }
        }

        // Hashtag detection: #tag
        if let lastWord = words.last, lastWord.hasPrefix("#") && lastWord.count > 1 {
            withAnimation {
                showHashtagSuggestions = true
            }
        } else if !(words.last?.hasPrefix("#") ?? false) {
            withAnimation {
                showHashtagSuggestions = false
            }
        }
    }

    // MARK: - Mention Search (Algolia)

    private func searchForQuoteMentions(query: String) {
        guard !query.isEmpty else {
            withAnimation {
                showMentionSuggestions = false
                mentionSuggestions = []
            }
            return
        }

        mentionSearchTask?.cancel()
        mentionSearchTask = Task {
            do {
                let results = try await AlgoliaSearchService.shared.searchUsers(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    withAnimation {
                        mentionSuggestions = Array(results.prefix(5))
                        showMentionSuggestions = !results.isEmpty
                    }
                }
            } catch {
                dlog("⚠️ [QuoteComposer] Failed to search mentions: \(error)")
            }
        }
    }

    private func insertQuoteMention(_ user: AlgoliaUser) {
        if let lastAtIndex = quoteText.lastIndex(of: "@") {
            let beforeMention = quoteText[..<lastAtIndex]
            quoteText = beforeMention + "@\(user.username) "
        }
        withAnimation {
            showMentionSuggestions = false
            mentionSuggestions = []
        }
    }

    // MARK: - Hashtag Logic

    private func updateQuoteHashtagSuggestions() {
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

    private func insertQuoteHashtag(_ tag: String) {
        if quoteText.isEmpty || quoteText.last == " " {
            quoteText += tag + " "
        } else {
            // Replace partial hashtag being typed
            let words = quoteText.components(separatedBy: " ")
            if let last = words.last, last.hasPrefix("#") {
                let withoutLast = words.dropLast().joined(separator: " ")
                quoteText = withoutLast.isEmpty ? tag + " " : withoutLast + " " + tag + " "
            } else {
                quoteText += " " + tag + " "
            }
        }
        withAnimation {
            showHashtagSuggestions = false
        }
    }

    // MARK: - Photo Loading

    private func loadQuoteSelectedPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    loaded.append(img)
                }
            }
            await MainActor.run { attachedImages = loaded }
        }
    }

    // MARK: - Submit

    private func submitQuotePost() {
        let trimmed = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        HapticManager.notification(type: .success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isPublishing = true
        }

        // Include camera image in attached images if present
        var allImages = attachedImages
        if let camImg = cameraImage {
            allImages.insert(camImg, at: 0)
        }
        // Snapshot for upload
        let imagesToUpload = allImages

        onPublish?(trimmed, originalPost)

        if onPublish == nil {
            writeQuotePostToFirestore(text: trimmed, images: imagesToUpload)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Fire-and-forget Firestore write when no parent callback is provided.
    /// Uploads any attached images to Storage first, then writes the post doc.
    private func writeQuotePostToFirestore(text: String, images: [UIImage] = []) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let docId = db.collection("posts").document().documentID
        let docRef = db.collection("posts").document(docId)

        Task {
            var imageURLs: [String] = []
            if !images.isEmpty {
                imageURLs = await withTaskGroup(of: String?.self) { group in
                    for (i, img) in images.enumerated() {
                        group.addTask {
                            guard let data = img.jpegData(compressionQuality: 0.82) else { return nil }
                            let path = "posts/\(uid)/\(docId)/image_\(i).jpg"
                            let ref = Storage.storage().reference().child(path)
                            let meta = StorageMetadata(); meta.contentType = "image/jpeg"
                            guard (try? await ref.putDataAsync(data, metadata: meta)) != nil,
                                  let url = try? await ref.downloadURL()
                            else { return nil }
                            return url.absoluteString
                        }
                    }
                    var urls: [String] = []
                    for await result in group { if let u = result { urls.append(u) } }
                    return urls
                }
            }

            // Extract hashtags from content for indexing
            let hashtags = extractHashtags(from: text)

            var data: [String: Any] = [
                "authorId": uid,
                "content": text,
                "category": selectedCategory.rawValue,
                "isQuotePost": true,
                "quotedPostId": originalPost.firebaseId ?? originalPost.id.uuidString,
                "quotedAuthorId": originalPost.authorId,
                "quotedAuthorName": originalPost.authorName,
                "quotedContent": originalPost.content,
                "createdAt": FieldValue.serverTimestamp(),
                "repostCount": 0,
                "amenCount": 0,
                "commentCount": 0,
                "lightbulbCount": 0,
                "visibility": Post.PostVisibility.everyone.rawValue,
                "isRepost": false
            ]
            if !imageURLs.isEmpty { data["imageURLs"] = imageURLs }
            if !hashtags.isEmpty { data["hashtags"] = hashtags }
            try? await docRef.setData(data)

            // Index hashtags for search/discovery
            if !hashtags.isEmpty {
                await indexHashtags(hashtags, postId: docId)
            }

            NotificationCenter.default.post(
                name: .newPostCreated,
                object: nil,
                userInfo: ["category": selectedCategory.rawValue]
            )
        }
    }

    // MARK: - Hashtag Indexing for Search

    /// Extracts all hashtags from post content
    private func extractHashtags(from text: String) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words
            .filter { $0.hasPrefix("#") && $0.count > 1 }
            .map { $0.lowercased() }
    }

    /// Indexes hashtags in Firestore for discovery.
    /// Each hashtag gets a document in `hashtags` collection with a post count and recent posts array.
    private func indexHashtags(_ hashtags: [String], postId: String) async {
        let db = Firestore.firestore()
        for tag in hashtags {
            let cleanTag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
            guard !cleanTag.isEmpty else { continue }
            let tagRef = db.collection("hashtags").document(cleanTag.lowercased())
            do {
                _ = try await db.runTransaction { transaction, errorPointer in
                    let snapshot: DocumentSnapshot
                    do {
                        snapshot = try transaction.getDocument(tagRef)
                    } catch let error as NSError {
                        errorPointer?.pointee = error
                        return nil
                    }
                    if snapshot.exists {
                        transaction.updateData([
                            "postCount": FieldValue.increment(Int64(1)),
                            "recentPostIds": FieldValue.arrayUnion([postId]),
                            "lastUsed": FieldValue.serverTimestamp()
                        ], forDocument: tagRef)
                    } else {
                        transaction.setData([
                            "tag": cleanTag.lowercased(),
                            "postCount": 1,
                            "recentPostIds": [postId],
                            "createdAt": FieldValue.serverTimestamp(),
                            "lastUsed": FieldValue.serverTimestamp()
                        ], forDocument: tagRef)
                    }
                    return nil
                }
            } catch {
                dlog("⚠️ [QuoteComposer] Failed to index hashtag \(tag): \(error)")
            }
        }
    }
}

// MARK: - Previews

#Preview("Repost Action Sheet") {
    let sample = Post(
        id: UUID(),
        firebaseId: "abc123",
        authorId: "user1",
        authorName: "Marcus Webb",
        authorUsername: "marcuswebb",
        authorInitials: "MW",
        authorProfileImageURL: nil,
        timeAgo: "2h",
        content: "Grateful for God's faithfulness in every season. His mercies are new every morning — Lamentations 3:22-23 🙏",
        category: .testimonies,
        topicTag: nil,
        visibility: .everyone,
        allowComments: true,
        commentPermissions: nil,
        imageURLs: nil,
        linkURL: nil,
        linkPreviewTitle: nil,
        linkPreviewDescription: nil,
        linkPreviewImageURL: nil,
        linkPreviewSiteName: nil,
        linkPreviewType: nil,
        verseReference: nil,
        verseText: nil,
        createdAt: Date(),
        amenCount: 42,
        lightbulbCount: 7,
        commentCount: 14,
        repostCount: 3
    )

    RepostActionSheet(post: sample, onRepost: {}, onQuote: {})
}

#Preview("Quote Composer") {
    let sample = Post(
        id: UUID(),
        firebaseId: "abc123",
        authorId: "user1",
        authorName: "Marcus Webb",
        authorUsername: "marcuswebb",
        authorInitials: "MW",
        authorProfileImageURL: nil,
        timeAgo: "2h",
        content: "Grateful for God's faithfulness in every season. His mercies are new every morning — Lamentations 3:22-23 🙏",
        category: .testimonies,
        topicTag: nil,
        visibility: .everyone,
        allowComments: true,
        commentPermissions: nil,
        imageURLs: nil,
        linkURL: nil,
        linkPreviewTitle: nil,
        linkPreviewDescription: nil,
        linkPreviewImageURL: nil,
        linkPreviewSiteName: nil,
        linkPreviewType: nil,
        verseReference: nil,
        verseText: nil,
        createdAt: Date(),
        amenCount: 42,
        lightbulbCount: 7,
        commentCount: 14,
        repostCount: 3
    )

    QuotePostComposerView(originalPost: sample)
}
