// SelahStoryComposerView.swift
// AMENAPP/SelahStories
//
// Phase 5 — Selah Stories
// Formation-first story composer. No streaks, no "Everyone" audience.
// Premium AI features (verse recognition, Reflect mode, audio matching)
// are shown as locked upsell cards when selahStoriesPremiumAI is OFF,
// and as live features when the flag is ON AND the user holds Berean+.
//
// Gate: returns EmptyView when selahStories flag is OFF.
// UI: All surfaces use AmenGlassKit (GlassCard, GlassChip, GlassButton, GlassSheet).
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage

// MARK: - SelahStoryComposerView

/// Formation-first story composer for Selah Stories.
///
/// Feature-flag gated — callers should check `AMENFeatureFlags.shared.selahStories`
/// before presenting this view, but the view also self-guards.
struct SelahStoryComposerView: View {

    // MARK: Environment / Dependencies

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var viewModel = SelahStoryComposerViewModel()

    // MARK: Body

    var body: some View {
        // Hard feature-flag gate — callers should pre-check, but the view is self-guarding.
        if !AMENFeatureFlags.shared.selahStories {
            EmptyView()
        } else {
            composerContent
        }
    }

    // MARK: Composer Content

    private var composerContent: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        mediaPickerSection
                        storyKindSection
                        audienceSection
                        formationStickersSection
                        captionSection
                        premiumSection
                        postButton
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("New Selah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $viewModel.showAudienceSheet) {
                audienceSheet
            }
            .sheet(isPresented: $viewModel.showSeasonSheet) {
                seasonSheet
            }
        }
    }

    // MARK: - Sections

    // MARK: Media Picker

    private var mediaPickerSection: some View {
        PhotosPicker(
            selection: $viewModel.selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 220)

                if let previewImage = viewModel.previewImage {
                    previewImage
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text("Add a photo or video")
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if viewModel.previewImage != nil {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .background(Circle().fill(Color(uiColor: .systemBackground)).padding(2))
                        .padding(10)
                }
            }
        }
        .accessibilityLabel(viewModel.previewImage != nil ? "Change photo or video" : "Add photo or video")
        .accessibilityHint("Double tap to open your photo library")
    }

    // MARK: Story Kind

    private var storyKindSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "heart.text.square", title: "Story Type")
            HStack(spacing: 10) {
                ForEach(StoryKind.allCases, id: \.self) { kind in
                    GlassChip(
                        icon: kind.icon,
                        label: kind.displayName,
                        isSelected: viewModel.selectedKind == kind,
                        accentColor: kind.accentColor
                    ) {
                        viewModel.selectedKind = kind
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: Audience

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "person.2", title: "Who can see this")
            HStack(spacing: 10) {
                ForEach(StoryAudience.allCases, id: \.self) { audience in
                    GlassChip(
                        icon: audience.icon,
                        label: audience.displayName,
                        isSelected: viewModel.selectedAudience == audience,
                        accentColor: AmenTheme.Colors.amenPurple
                    ) {
                        viewModel.selectedAudience = audience
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                Spacer()
            }

            // Audience explanation note
            Text(viewModel.selectedAudience.audienceExplanation)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .padding(.top, 2)
        }
    }

    // MARK: Formation Stickers

    private var formationStickersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "sparkles", title: "Formation Tags")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Verse Card sticker
                    GlassChip(
                        icon: "book.closed",
                        label: "Verse Card",
                        isSelected: viewModel.hasVerseCard,
                        accentColor: AmenTheme.Colors.amenGold
                    ) {
                        viewModel.hasVerseCard.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    // "Pray for this" sticker
                    GlassChip(
                        icon: "hands.sparkles",
                        label: "Pray for this",
                        isSelected: viewModel.hasPrayForThis,
                        accentColor: AmenTheme.Colors.amenPurple
                    ) {
                        viewModel.hasPrayForThis.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    // "Ask me about this" sticker
                    GlassChip(
                        icon: "bubble.left.and.bubble.right",
                        label: "Ask me",
                        isSelected: viewModel.hasAskMe,
                        accentColor: AmenTheme.Colors.amenBlue
                    ) {
                        viewModel.hasAskMe.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    // Liturgical season tag
                    GlassChip(
                        icon: "calendar",
                        label: viewModel.selectedSeason?.displayName ?? "Season Tag",
                        isSelected: viewModel.selectedSeason != nil,
                        accentColor: Color.amenEmerald
                    ) {
                        viewModel.showSeasonSheet = true
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Caption

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "text.alignleft", title: "Caption (optional)")
            GlassCard {
                TextField("A brief reflection, prayer, or praise...", text: $viewModel.caption, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(14)
            }
        }
    }

    // MARK: Premium AI Section

    @ViewBuilder
    private var premiumSection: some View {
        let flagOn = AMENFeatureFlags.shared.selahStoriesPremiumAI
        let hasSubscription = AmenSubscriptionService.shared.tier >= .berean

        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "brain.head.profile", title: "Berean AI Assist")

            if flagOn && hasSubscription {
                // Live premium features
                livePremiumCards
            } else {
                // Locked upsell cards
                lockedPremiumCards
            }
        }
    }

    private var livePremiumCards: some View {
        VStack(spacing: 10) {
            // Verse Recognition
            GlassCard(accentTint: AmenTheme.Colors.amenGold) {
                HStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recognize a Verse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text(viewModel.recognizedRef.map { "\($0.book) \($0.chapter):\($0.verse.map(String.init) ?? "–")" }
                             ?? "Point your camera at printed scripture")
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    Spacer()
                    if viewModel.isRecognizingVerse {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await viewModel.recognizeVerse() }
                }
            }
            .accessibilityLabel("Recognize a verse")
            .accessibilityHint("Double tap to scan printed scripture with your camera")

            // Reflection Prompt
            if let ref = viewModel.recognizedRef {
                GlassCard(accentTint: AmenTheme.Colors.amenPurple) {
                    HStack(spacing: 14) {
                        Image(systemName: "lightbulb.max")
                            .font(.system(size: 22))
                            .foregroundStyle(AmenTheme.Colors.amenPurple)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reflect Mode")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Text(viewModel.reflectionPrompt ?? "Generate a reflection prompt for \(ref.book) \(ref.chapter)")
                                .font(.caption)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                                .lineLimit(3)
                        }
                        Spacer()
                        if viewModel.isGeneratingPrompt {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AmenTheme.Colors.amenPurple)
                        }
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.generateReflectionPrompt(for: ref) }
                    }
                }
                .accessibilityLabel("Generate reflection prompt")
                .accessibilityHint("Double tap to generate a scripture-grounded reflection")
            }

            // Audio Match
            GlassCard(accentTint: AmenTheme.Colors.amenBlue) {
                HStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Match Worship Audio")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        if let audio = viewModel.matchedAudio {
                            Text("\(audio.title)\(audio.artistName.map { " · \($0)" } ?? "")")
                                .font(.caption)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        } else {
                            Text("Find worship music for this scripture")
                                .font(.caption)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    if viewModel.isMatchingAudio {
                        ProgressView()
                    } else {
                        Image(systemName: viewModel.matchedAudio != nil ? "checkmark.circle.fill" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.matchedAudio != nil
                                             ? AmenTheme.Colors.amenBlue
                                             : AmenTheme.Colors.textTertiary)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let ref = viewModel.recognizedRef {
                        Task { await viewModel.matchAudio(for: ref) }
                    }
                }
            }
            .accessibilityLabel("Match worship audio")
            .accessibilityHint("Double tap to find worship music that complements this scripture")
        }
    }

    private var lockedPremiumCards: some View {
        VStack(spacing: 10) {
            ForEach(LockedPremiumFeature.allCases, id: \.self) { feature in
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.7))
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(feature.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AmenTheme.Colors.amenGold)
                            }
                            Text(feature.subtitle)
                                .font(.caption)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Text("Berean")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(AmenTheme.Colors.amenGold)
                            )
                    }
                    .padding(14)
                }
                .accessibilityLabel("\(feature.title), requires Berean subscription")
                .accessibilityHint("Upgrade to Berean to unlock this feature")
            }
        }
    }

    // MARK: Post Button

    private var postButton: some View {
        GlassButton(
            "Share Story",
            icon: "sparkles",
            style: .primary,
            isLoading: viewModel.isPosting,
            isDisabled: !viewModel.canPost,
            hint: "Double tap to share this story with your selected audience"
        ) {
            Task { await viewModel.postStory() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityLabel("Cancel")
                .accessibilityHint("Double tap to discard this story")
        }
    }

    // MARK: Sheets

    private var audienceSheet: some View {
        GlassSheet(title: "Who can see this", subtitle: "Stories are never public") {
            VStack(spacing: 12) {
                ForEach(StoryAudience.allCases, id: \.self) { audience in
                    Button {
                        viewModel.selectedAudience = audience
                        viewModel.showAudienceSheet = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: audience.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(AmenTheme.Colors.amenPurple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audience.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                                Text(audience.audienceExplanation)
                                    .font(.caption)
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                            }
                            Spacer()
                            if viewModel.selectedAudience == audience {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                            }
                        }
                        .padding(14)
                        .amenGlass(.thin, cornerRadius: 14)
                    }
                    .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(audience.displayName)
                    .accessibilityHint(audience.audienceExplanation)
                    .accessibilityAddTraits(viewModel.selectedAudience == audience ? [.isSelected] : [])
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var seasonSheet: some View {
        GlassSheet(title: "Liturgical Season", subtitle: "Tag this story with the current season") {
            VStack(spacing: 8) {
                // "None" option
                Button {
                    viewModel.selectedSeason = nil
                    viewModel.showSeasonSheet = false
                } label: {
                    HStack {
                        Text("No season tag")
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                        Spacer()
                        if viewModel.selectedSeason == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.amenEmerald)
                        }
                    }
                    .padding(12)
                    .amenGlass(.thin, cornerRadius: 12)
                }
                .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel("No season tag")

                ForEach(LiturgicalSeasonKind.allCases, id: \.self) { season in
                    Button {
                        viewModel.selectedSeason = season
                        viewModel.showSeasonSheet = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: season.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.amenEmerald)
                                .frame(width: 24)
                            Text(season.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Spacer()
                            if viewModel.selectedSeason == season {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.amenEmerald)
                            }
                        }
                        .padding(12)
                        .amenGlass(.thin, cornerRadius: 12)
                    }
                    .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(season.displayName)
                    .accessibilityAddTraits(viewModel.selectedSeason == season ? [.isSelected] : [])
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helper Views

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}

// MARK: - SelahStoryComposerViewModel

@MainActor
final class SelahStoryComposerViewModel: ObservableObject {

    // MARK: Form State

    @Published var selectedPhotoItem: PhotosPickerItem? {
        didSet { Task { await loadSelectedPhoto() } }
    }
    @Published private(set) var previewImage: Image?
    private var selectedImageData: Data?
    private let storage = Storage.storage()

    @Published var selectedKind: StoryKind = .reflection
    @Published var selectedAudience: StoryAudience = .closeFriends
    @Published var caption: String = ""

    // Formation stickers
    @Published var hasVerseCard: Bool = false
    @Published var hasPrayForThis: Bool = false
    @Published var hasAskMe: Bool = false
    @Published var selectedSeason: LiturgicalSeasonKind? = LiturgicalSeasonKind.current

    // Premium AI state
    @Published private(set) var recognizedRef: ScriptureRef?
    @Published private(set) var reflectionPrompt: String?
    @Published private(set) var matchedAudio: StoryAudio?

    @Published private(set) var isRecognizingVerse = false
    @Published private(set) var isGeneratingPrompt = false
    @Published private(set) var isMatchingAudio = false
    @Published private(set) var isPosting = false

    // Sheet visibility
    @Published var showAudienceSheet = false
    @Published var showSeasonSheet = false

    // Error handling
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Computed

    var canPost: Bool {
        !isPosting && selectedImageData != nil
    }

    // MARK: - Photo Loading

    private func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                if let uiImage = UIImage(data: data) {
                    previewImage = Image(uiImage: uiImage)
                }
            }
        } catch {
            showError(error)
        }
    }

    // MARK: - Premium AI Actions

    func recognizeVerse() async {
        guard let imageData = selectedImageData else {
            showError(message: "Add a photo first to recognize a verse.")
            return
        }
        isRecognizingVerse = true
        defer { isRecognizingVerse = false }
        do {
            recognizedRef = try await SelahStoryService.shared.recognizeVerse(from: imageData)
        } catch {
            showError(error)
        }
    }

    func generateReflectionPrompt(for ref: ScriptureRef) async {
        isGeneratingPrompt = true
        defer { isGeneratingPrompt = false }
        do {
            reflectionPrompt = try await SelahStoryService.shared.generateReflectionPrompt(for: ref)
        } catch {
            showError(error)
        }
    }

    func matchAudio(for ref: ScriptureRef) async {
        isMatchingAudio = true
        defer { isMatchingAudio = false }
        do {
            matchedAudio = try await SelahStoryService.shared.matchAudio(
                for: ref,
                season: selectedSeason
            )
        } catch {
            showError(error)
        }
    }

    // MARK: - Post

    func postStory() async {
        guard let imageData = selectedImageData else {
            showError(message: "Please add a photo or video before sharing.")
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            showError(message: "Please sign in to share a story.")
            return
        }

        isPosting = true
        defer { isPosting = false }

        let mediaId = UUID().uuidString
        let mediaURL: String
        do {
            mediaURL = try await uploadSelectedImage(imageData, mediaId: mediaId, uid: uid)
        } catch {
            showError(error)
            return
        }

        let media = StoryMedia(
            id: mediaId,
            url: mediaURL,
            mediaType: "photo",
            durationSeconds: nil
        )

        // Build overlays from stickers
        var overlays: [StoryOverlay] = []
        if hasVerseCard, let ref = recognizedRef {
            overlays.append(StoryOverlay(
                id: UUID().uuidString,
                text: "\(ref.book) \(ref.chapter)\(ref.verse.map { ":\($0)" } ?? "")",
                positionX: 0.5,
                positionY: 0.15,
                scriptureRef: ref
            ))
        }
        if let prompt = reflectionPrompt, !prompt.isEmpty {
            overlays.append(StoryOverlay(
                id: UUID().uuidString,
                text: prompt,
                positionX: 0.5,
                positionY: 0.8,
                scriptureRef: nil
            ))
        }

        let story = SelahStory(
            id: UUID().uuidString,
            ownerUid: uid,
            kind: selectedKind,
            audience: selectedAudience,
            media: [media],
            overlays: overlays,
            audio: matchedAudio,
            scriptureRef: recognizedRef,
            caption: caption.isEmpty ? nil : caption,
            liturgicalSeason: selectedSeason,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .hour, value: 24, to: Date())
        )

        do {
            _ = try await SelahStoryService.shared.create(story)
        } catch {
            showError(error)
        }
    }

    private func uploadSelectedImage(_ imageData: Data, mediaId: String, uid: String) async throws -> String {
        let path = "selahStories/\(uid)/\(mediaId).jpg"
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL().absoluteString
    }

    // MARK: - Error Helpers

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Locked Premium Feature Enum

private enum LockedPremiumFeature: CaseIterable {
    case verseRecognition
    case reflectMode
    case audioMatch

    var icon: String {
        switch self {
        case .verseRecognition: return "camera.viewfinder"
        case .reflectMode:      return "lightbulb.max"
        case .audioMatch:       return "music.note.list"
        }
    }

    var title: String {
        switch self {
        case .verseRecognition: return "Verse Recognition"
        case .reflectMode:      return "Reflect Mode"
        case .audioMatch:       return "Worship Audio Match"
        }
    }

    var subtitle: String {
        switch self {
        case .verseRecognition: return "Scan printed scripture to attach a verse card"
        case .reflectMode:      return "Get a scripture-grounded reflection prompt"
        case .audioMatch:       return "Pair this story with matching worship music"
        }
    }
}

// MARK: - StoryKind Display Helpers

extension StoryKind: CaseIterable {
    public static var allCases: [StoryKind] { [.reflection, .prayer, .praise] }

    var displayName: String {
        switch self {
        case .reflection: return "Reflect"
        case .prayer:     return "Prayer"
        case .praise:     return "Praise"
        }
    }

    var icon: String {
        switch self {
        case .reflection: return "text.bubble"
        case .prayer:     return "hands.sparkles"
        case .praise:     return "hands.raised"
        }
    }

    var accentColor: Color {
        switch self {
        case .reflection: return AmenTheme.Colors.amenBlue
        case .prayer:     return AmenTheme.Colors.amenPurple
        case .praise:     return AmenTheme.Colors.amenGold
        }
    }
}

// MARK: - StoryAudience Display Helpers

extension StoryAudience: CaseIterable {
    public static var allCases: [StoryAudience] { [.closeFriends, .churchGroup, .accountabilityPartner] }

    var displayName: String {
        switch self {
        case .closeFriends:           return "Close Friends"
        case .churchGroup:            return "Church Group"
        case .accountabilityPartner:  return "Partner"
        }
    }

    var icon: String {
        switch self {
        case .closeFriends:           return "person.2.fill"
        case .churchGroup:            return "building.columns"
        case .accountabilityPartner:  return "person.badge.shield.checkmark"
        }
    }

    var audienceExplanation: String {
        switch self {
        case .closeFriends:
            return "Visible only to people you've added as close friends."
        case .churchGroup:
            return "Visible to members of your connected church group."
        case .accountabilityPartner:
            return "Visible only to your accountability partner."
        }
    }
}

// MARK: - LiturgicalSeasonKind Display Helpers

extension LiturgicalSeasonKind {
    var displayName: String {
        switch self {
        case .ordinary:   return "Ordinary Time"
        case .advent:     return "Advent"
        case .christmas:  return "Christmas"
        case .epiphany:   return "Epiphany"
        case .lent:       return "Lent"
        case .holyWeek:   return "Holy Week"
        case .easter:     return "Easter"
        case .pentecost:  return "Pentecost"
        }
    }

    var icon: String {
        switch self {
        case .ordinary:   return "calendar"
        case .advent:     return "star"
        case .christmas:  return "gift"
        case .epiphany:   return "sparkle"
        case .lent:       return "leaf"
        case .holyWeek:   return "cross"
        case .easter:     return "sun.max"
        case .pentecost:  return "flame"
        }
    }
}
