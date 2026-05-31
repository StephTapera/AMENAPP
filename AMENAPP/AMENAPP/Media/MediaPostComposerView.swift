// WIRING: Present this sheet from CreatePostView or OpenTableView compose button.
// Pass an onPost closure that calls FirebasePostService.shared.createPost(...)

//
//  MediaPostComposerView.swift
//  AMENAPP
//
//  Full compose flow: pick → preview → caption → post.
//  Shows a thumbnail rail, caption field, scripture chip,
//  audience picker, and translate chip before calling onPost.
//

import SwiftUI
import AVFoundation
import Photos
import Foundation

// MARK: - PostAudience

enum PostAudience: String, CaseIterable {
    case everyone  = "Everyone"
    case followers = "Followers"
    case groups    = "Groups"
}

// MARK: - MediaPostComposerView

struct MediaPostComposerView: View {

    @ObservedObject var coordinator: MediaCaptureCoordinator
    var onPost: ([ImmersiveCapturedItem], String, PostAudience) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var caption: String = ""
    @State private var selectedAudience: PostAudience = .everyone
    @State private var isPosting: Bool = false
    @State private var previewItem: ImmersiveCapturedItem?
    @State private var showPreview: Bool = false
    @State private var showVersePicker: Bool = false
    @State private var selectedVerse: String = ""
    @State private var showAddMore: Bool = false

    // Permission check states
    @State private var cameraPermissionDenied: Bool = false
    @State private var libraryPermissionDenied: Bool = false

    // MARK: - Media attachment state (additive — does not affect existing fields)
    @StateObject private var attachmentManager = AmenSmartAttachmentManager()
    @State private var selectedMusic: AmenMediaAttachment? = nil
    @State private var selectedCommunityId: String? = nil
    @State private var selectedTopicIds: [String] = []
    @State private var showMusicPicker: Bool = false
    @State private var showCommunityPicker: Bool = false
    @State private var showTranslation: Bool = false

    private let captionLimit = 2000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Permission banners
                    permissionBanners

                    // Attachment chip row (community / music / scripture quick-chips)
                    attachmentChipRow

                    // Media thumbnail rail
                    mediaThumbnailRail

                    // Caption editor
                    captionSection

                    // Music card preview (shown below caption when music is attached)
                    if let music = selectedMusic {
                        AmenMusicCardContainer(attachment: music)
                            .transition(.opacity)
                    }

                    // Smart link / URL attachment rail (auto-detected from caption)
                    if !attachmentManager.pendingAttachments.isEmpty {
                        AmenAttachmentRail(
                            attachments: attachmentManager.pendingAttachments,
                            onRemove: { id in attachmentManager.removeAttachment(id: id) }
                        )
                        .transition(.opacity)
                    }

                    // Scripture chip
                    scriptureChip

                    // Audience picker
                    audienceSection

                    // Translate chip + inline translation overlay
                    if !caption.isEmpty {
                        translateChip
                        if showTranslation {
                            PostTranslationButton(originalText: caption)
                                .padding(.top, 4)
                                .transition(.opacity)
                        }
                    }

                    // Bottom spacing so toolbar doesn't overlap content
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .safeAreaInset(edge: .bottom) {
                attachmentToolbar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Post")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AmenTheme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AmenTheme.Colors.textSecondary)
                    }
                    .accessibilityLabel("Close composer")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    postButton
                }
            }
        }
        .onAppear(perform: checkPermissions)
        .sheet(isPresented: $showPreview) {
            if let item = previewItem, let previewMediaItem = item.asImmersiveMediaItem {
                ImmersiveMediaViewer(
                    items: [previewMediaItem],
                    startingIndex: 0,
                    onDismiss: { showPreview = false }
                )
            }
        }
        .sheet(isPresented: $showVersePicker) {
            SimpleVersePickerSheet(selectedVerse: $selectedVerse, isPresented: $showVersePicker)
        }
        .sheet(isPresented: $coordinator.isShowingPicker) {
            AmenImagePickerView(coordinator: coordinator, maxItems: 10)
        }
        .sheet(isPresented: $coordinator.isShowingCamera) {
            MediaCaptureCameraView(coordinator: coordinator, mode: .photo)
        }
        .sheet(isPresented: $showMusicPicker) {
            AmenMusicPickerSheet(selectedMusic: $selectedMusic)
        }
        .sheet(isPresented: $showCommunityPicker) {
            AmenCommunityPickerSheet(
                selectedCommunityId: $selectedCommunityId,
                selectedTopicIds: $selectedTopicIds
            )
        }
        .alert("Error", isPresented: .constant(coordinator.captureError != nil)) {
            Button("OK") { coordinator.captureError = nil }
        } message: {
            Text(coordinator.captureError ?? "")
        }
    }

    // MARK: - Post Button

    private var postButton: some View {
        Button {
            guard !coordinator.capturedItems.isEmpty, !isPosting else { return }
            isPosting = true
            var captionParts = [selectedVerse, caption]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            // TODO: migrate to mediaAttachments array field when backend ready.
            // For now, append music metadata as a structured annotation in the caption
            // using existing linkURL / linkPreview* fields via the onPost closure.
            // The serialized JSON is stored in the caption suffix so the feed renderer
            // can decode it via AmenPostMediaRenderer without a schema migration.
            if let music = selectedMusic,
               let musicJSON = try? JSONEncoder().encode(music),
               let musicString = String(data: musicJSON, encoding: .utf8) {
                captionParts.append("[amenMusic:\(musicString)]")
            }
            let finalCaption = captionParts.joined(separator: "\n\n")
            onPost(coordinator.capturedItems, finalCaption, selectedAudience)
        } label: {
            if isPosting {
                ProgressView()
                    .tint(AmenTheme.Colors.amenGold)
                    .frame(width: 60, height: 32)
            } else {
                Text("Post")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(
                        coordinator.capturedItems.isEmpty
                            ? AmenTheme.Colors.textSecondary
                            : AmenTheme.Colors.amenGold
                    )
                    .frame(width: 60, height: 32)
            }
        }
        .disabled(coordinator.capturedItems.isEmpty || isPosting)
        .accessibilityLabel(isPosting ? "Posting…" : "Post")
        .accessibilityHint("Creates the post and uploads selected media")
    }

    // MARK: - Permission Banners

    @ViewBuilder
    private var permissionBanners: some View {
        if cameraPermissionDenied {
            MediaPermissionBanner(
                title: "Camera Access Needed",
                message: "Allow camera access to take photos or videos for your post."
            )
        }
        if libraryPermissionDenied {
            MediaPermissionBanner(
                title: "Photo Library Access Needed",
                message: "Allow photo library access to select photos and videos for your post."
            )
        }
    }

    // MARK: - Media Thumbnail Rail

    private var mediaThumbnailRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(coordinator.capturedItems) { item in
                    ThumbnailCard(item: item)
                        .onTapGesture {
                            previewItem = item
                            showPreview = true
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                coordinator.removeItem(id: item.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .accessibilityLabel("\(item.type == .photo ? "Photo" : "Video") thumbnail. Tap to preview, long press to delete.")
                }

                // "Add more" button
                Button {
                    coordinator.openPhotoPicker(maxItems: max(1, 10 - coordinator.capturedItems.count))
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                AmenTheme.Colors.borderSoft,
                                style: StrokeStyle(lineWidth: 1.5, dash: [5])
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(AmenTheme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add more media")
                .accessibilityHint("Opens photo library to add more items")
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Caption

    private var captionSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if caption.isEmpty {
                    Text("Add a caption…")
                        .foregroundColor(AmenTheme.Colors.textPlaceholder)
                        .font(.system(size: 15))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $caption)
                    .font(.system(size: 15))
                    .foregroundColor(AmenTheme.Colors.textPrimary)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: caption) { _, newValue in
                        if newValue.count > captionLimit {
                            caption = String(newValue.prefix(captionLimit))
                        }
                        // Detect URLs and smart-resolve media attachments from caption text
                        Task { await attachmentManager.processText(newValue) }
                    }
                    .accessibilityLabel("Caption")
                    .accessibilityHint("Add a caption for your post")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceInput)
            )

            // Character count
            Text("\(caption.count) / \(captionLimit)")
                .font(.caption2)
                .foregroundColor(
                    caption.count > captionLimit - 50
                        ? AmenTheme.Colors.statusWarning
                        : AmenTheme.Colors.textTertiary
                )
                .accessibilityLabel("\(caption.count) of \(captionLimit) characters used")
        }
    }

    // MARK: - Scripture Chip

    private var scriptureChip: some View {
        Button {
            showVersePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AmenTheme.Colors.amenPurple)
                    .accessibilityHidden(true)

                Text(selectedVerse.isEmpty ? "Add a verse?" : selectedVerse)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(
                        selectedVerse.isEmpty
                            ? AmenTheme.Colors.amenPurple
                            : AmenTheme.Colors.textPrimary
                    )
                    .lineLimit(1)

                if !selectedVerse.isEmpty {
                    Spacer()
                    Button {
                        selectedVerse = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AmenTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove verse")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.amenPurple.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(AmenTheme.Colors.amenPurple.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedVerse.isEmpty ? "Add a Bible verse to your post" : "Selected verse: \(selectedVerse). Tap to change.")
    }

    // MARK: - Audience

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audience")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AmenTheme.Colors.textSecondary)

            Picker("Audience", selection: $selectedAudience) {
                ForEach(PostAudience.allCases, id: \.self) { audience in
                    Text(audience.rawValue).tag(audience)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Post audience")
        }
    }

    // MARK: - Translate Chip

    private var translateChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTranslation.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(showTranslation ? "Hide translation" : "Translate before posting")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(AmenTheme.Colors.amenBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.amenBlue.opacity(showTranslation ? 0.18 : 0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(AmenTheme.Colors.amenBlue.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showTranslation ? "Hide translation" : "Translate caption before posting")
        .accessibilityHint("Shows a translated preview of your caption using UniversalTranslationService")
    }

    // MARK: - Attachment Chip Row

    private var attachmentChipRow: some View {
        AmenComposerChipRow(
            communityName: selectedCommunityId.map { _ in "Community" }, // display name resolved separately
            musicTitle: selectedMusic?.title,
            scriptureRef: selectedVerse.isEmpty ? nil : selectedVerse,
            onTapCommunity: { showCommunityPicker = true },
            onTapMusic: { showMusicPicker = true },
            onTapScripture: { showVersePicker = true },
            onRemoveCommunity: {
                selectedCommunityId = nil
                selectedTopicIds = []
            },
            onRemoveMusic: { selectedMusic = nil },
            onRemoveScripture: { selectedVerse = "" }
        )
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: selectedMusic?.id)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: selectedCommunityId)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: selectedVerse)
    }

    // MARK: - Attachment Toolbar

    private var attachmentToolbar: some View {
        AmenComposerAttachmentToolbar(
            onPhoto: {
                coordinator.openPhotoPicker(maxItems: max(1, 10 - coordinator.capturedItems.count))
            },
            onVideo: {
                coordinator.openPhotoPicker(maxItems: max(1, 10 - coordinator.capturedItems.count))
            },
            onGIF: {
                // TODO: wire to GIF picker when available
            },
            onMusic: { showMusicPicker = true },
            onScripture: { showVersePicker = true },
            onPrayer: {
                // TODO: wire to prayer request composer
            },
            onMore: {
                // TODO: wire to extended attachment options sheet
            }
        )
        .background(AmenTheme.Colors.backgroundPrimary)
    }

    // MARK: - Helpers

    private func checkPermissions() {
        // Camera
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermissionDenied = (camStatus == .denied || camStatus == .restricted)

        // Photo library
        let libStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        libraryPermissionDenied = (libStatus == .denied || libStatus == .restricted)
    }
}

// MARK: - ThumbnailCard

private struct ThumbnailCard: View {
    let item: ImmersiveCapturedItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.7)
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            )

            if item.type == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - SimpleVersePickerSheet

private struct SimpleVersePickerSheet: View {
    @Binding var selectedVerse: String
    @Binding var isPresented: Bool
    @State private var query: String = ""

    private let suggestions = [
        "Psalm 23:1 — The Lord is my shepherd; I shall not want.",
        "John 3:16 — For God so loved the world…",
        "Philippians 4:13 — I can do all things through Christ who strengthens me.",
        "Romans 8:28 — All things work together for good…",
        "Proverbs 3:5-6 — Trust in the Lord with all your heart…",
        "Isaiah 40:31 — They that wait upon the Lord shall renew their strength.",
        "Jeremiah 29:11 — For I know the plans I have for you…",
        "Matthew 5:16 — Let your light shine before others.",
    ]

    private var filtered: [String] {
        query.isEmpty ? suggestions : suggestions.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AmenTheme.Colors.textSecondary)
                        .accessibilityHidden(true)
                    TextField("Search verses…", text: $query)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search Bible verses")
                }
                .padding(10)
                .background(AmenTheme.Colors.surfaceInput)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

                List(filtered, id: \.self) { verse in
                    Button {
                        selectedVerse = verse
                        isPresented = false
                    } label: {
                        Text(verse)
                            .font(.system(size: 14))
                            .foregroundColor(AmenTheme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select verse: \(verse)")
                }
                .listStyle(.plain)
            }
            .navigationTitle("Choose a Verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { isPresented = false }
                        .accessibilityLabel("Cancel verse selection")
                }
            }
        }
    }
}

// MARK: - ImmersiveCapturedItem + Preview Helper

private extension ImmersiveCapturedItem {
    /// Converts a captured item into an ImmersiveMediaItem for preview purposes.
    var asImmersiveMediaItem: ImmersiveMediaItem? {
        switch type {
        case .photo:
            guard let image = image else { return nil }
            // Write image to temp file for AsyncImage
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension("jpg")
            if !FileManager.default.fileExists(atPath: url.path) {
                _ = try? image.jpegData(compressionQuality: 0.9).map {
                    try $0.write(to: url)
                }
            }
            return ImmersiveMediaItem(
                id: id.uuidString,
                type: .photo,
                url: url,
                caption: caption.isEmpty ? nil : caption,
                authorName: "You",
                authorId: ""
            )
        case .video:
            guard let videoURL else { return nil }
            return ImmersiveMediaItem(
                id: id.uuidString,
                type: .video,
                url: videoURL,
                caption: caption.isEmpty ? nil : caption,
                authorName: "You",
                authorId: ""
            )
        }
    }
}
