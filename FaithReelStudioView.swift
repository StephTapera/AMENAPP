//
//  FaithReelStudioView.swift
//  AMENAPP
//
//  Faith Reel Studio — create short-form video testimonies and worship reels.
//  Dark Liquid Glass design throughout.
//

import SwiftUI
import PhotosUI
import Photos

// MARK: - Models

struct WorshipTrack: Identifiable {
    let id = UUID()
    let name: String
    let artist: String
    let filename: String
}

enum OverlayPosition: String, CaseIterable {
    case top    = "Top"
    case center = "Center"
    case bottom = "Bottom"
}

struct FaithReelMetadata: Codable, Identifiable {
    let id: UUID
    let caption: String
    let tags: [String]
    let createdAt: Date
    let localVideoPath: String?
}

// MARK: - Curated Tracks

private let curatedTracks: [WorshipTrack] = [
    WorshipTrack(name: "Still Waters",    artist: "AMEN Original", filename: "still_waters"),
    WorshipTrack(name: "Morning Light",   artist: "AMEN Original", filename: "morning_light"),
    WorshipTrack(name: "Holy Ground",     artist: "AMEN Original", filename: "holy_ground"),
    WorshipTrack(name: "Faithful One",    artist: "AMEN Original", filename: "faithful_one"),
    WorshipTrack(name: "Lifted Up",       artist: "AMEN Original", filename: "lifted_up"),
    WorshipTrack(name: "River of Peace",  artist: "AMEN Original", filename: "river_of_peace"),
    WorshipTrack(name: "Ancient Paths",   artist: "AMEN Original", filename: "ancient_paths"),
    WorshipTrack(name: "Overflow",        artist: "AMEN Original", filename: "overflow"),
]

// MARK: - Faith Reel Studio Main View

struct FaithReelStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCreator = false
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 2) {
                        Text("Faith Reel Studio")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Create. Witness. Inspire.")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }

                    Spacer()

                    // Balance button width
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 34, height: 34)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)

                VStack(spacing: 16) {
                    // Create New Reel card
                    FaithReelMainCard(
                        icon: "plus.circle.fill",
                        iconColor: Color.purple,
                        title: "Create New Reel",
                        subtitle: "Record, upload or build a slideshow with scripture overlay and worship music",
                        chevron: true
                    ) {
                        showCreator = true
                    }

                    // My Reels card
                    FaithReelMainCard(
                        icon: "film.stack",
                        iconColor: Color.red.opacity(0.85),
                        title: "My Reels",
                        subtitle: "View, re-share or delete your saved Faith Reels",
                        chevron: true
                    ) {
                        showLibrary = true
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Decorative tagline
                Text("Short-form testimonies, worship reels, and scripture moments")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.2))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showCreator) {
            FaithReelCreatorView()
        }
        .sheet(isPresented: $showLibrary) {
            FaithReelLibraryView()
        }
    }
}

// MARK: - Main Card Helper

private struct FaithReelMainCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let chevron: Bool
    let action: () -> Void

    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        Button(action: {
            triggerRipple()
            action()
        }) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                // Top sheen
                VStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Spacer()
                }

                // Ripple
                GeometryReader { geo in
                    Circle()
                        .fill(Color.white.opacity(0.08 * rippleOpacity))
                        .frame(
                            width: max(geo.size.width, geo.size.height) * 1.5 * rippleScale,
                            height: max(geo.size.width, geo.size.height) * 1.5 * rippleScale
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(iconColor.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if chevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func triggerRipple() {
        rippleScale = 0
        rippleOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            rippleScale = 1
            rippleOpacity = 0
        }
    }
}

// MARK: - Faith Reel Creator View (5-Step)

struct FaithReelCreatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 1
    private let totalSteps = 5

    // Step 1 — Media
    @State private var mediaURL: URL?
    @State private var slideshowImages: [UIImage] = []
    @State private var mediaMode: MediaMode = .none
    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showSlideshowPicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera

    // Step 2 — Scripture
    @State private var scriptureText = ""
    @State private var selectedFont: OverlayFont = .sans
    @State private var overlayPosition: OverlayPosition = .bottom

    // Step 3 — Music
    @State private var selectedTrack: WorshipTrack?
    @State private var playingTrackId: UUID?

    // Step 4 — Caption & Tags
    @State private var caption = ""
    @State private var selectedTags: Set<String> = []
    @State private var shareToFeed = true

    // Step 5 — Export
    @State private var exportProgress: CGFloat = 0
    @State private var exportDone = false
    @State private var exportStarted = false
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var errorMessage = ""

    enum MediaMode {
        case none, video, slideshow
    }

    enum OverlayFont: String, CaseIterable {
        case serif   = "Serif"
        case sans    = "Sans"
        case script  = "Script"

        var uiFont: Font {
            switch self {
            case .serif:  return .custom("Georgia", size: 18)
            case .sans:   return .system(size: 18, weight: .regular)
            case .script: return .custom("Georgia-Italic", size: 18)
            }
        }
    }

    private let availableTags = ["#Testimony", "#Worship", "#Scripture", "#Faith", "#Prayer", "#Devotional"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header + close
                HStack {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(stepTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    // Balance
                    Circle().fill(Color.clear).frame(width: 34, height: 34)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Step dots
                stepIndicator
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                // Step content
                ScrollView(showsIndicators: false) {
                    Group {
                        switch currentStep {
                        case 1: step1MediaSource
                        case 2: step2ScriptureOverlay
                        case 3: step3Music
                        case 4: step4CaptionTags
                        case 5: step5Export
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }

                Spacer(minLength: 0)
            }

            // Bottom navigation buttons
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    if currentStep > 1 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                currentStep -= 1
                            }
                        } label: {
                            Text("Back")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if currentStep < totalSteps {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                currentStep += 1
                            }
                        } label: {
                            Text("Next")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.purple)
                                )
                        }
                        .buttonStyle(.plain)
                    } else if currentStep == totalSteps && !exportStarted {
                        Button {
                            startExport()
                        } label: {
                            Text("Export & Share")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.purple)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerRepresentable(sourceType: imagePickerSource, mediaTypes: ["public.movie"]) { url in
                if let url = url { mediaURL = url; mediaMode = .video }
            }
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoLibraryPickerRepresentable { url in
                if let url = url { mediaURL = url; mediaMode = .video }
            }
        }
        .sheet(isPresented: $showSlideshowPicker) {
            SlideshowPickerRepresentable { images in
                slideshowImages = images
                if !images.isEmpty { mediaMode = .slideshow }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Step Title

    private var stepTitle: String {
        switch currentStep {
        case 1: return "Media Source"
        case 2: return "Scripture Overlay"
        case 3: return "Music"
        case 4: return "Caption & Tags"
        case 5: return "Export & Share"
        default: return ""
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step == currentStep ? Color.purple : Color.white.opacity(0.15))
                    .frame(width: step == currentStep ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Media Source

    private var step1MediaSource: some View {
        VStack(spacing: 16) {
            Text("How would you like to create your reel?")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            MediaOptionCard(
                icon: "video.fill",
                iconColor: Color.red,
                title: "Record Video",
                subtitle: "Open camera and record directly",
                isSelected: mediaMode == .video && mediaURL != nil
            ) {
                imagePickerSource = .camera
                showImagePicker = true
            }

            MediaOptionCard(
                icon: "arrow.up.circle.fill",
                iconColor: Color.blue,
                title: "Upload Video",
                subtitle: "Choose a video from your photo library",
                isSelected: mediaMode == .video && mediaURL != nil
            ) {
                showVideoPicker = true
            }

            MediaOptionCard(
                icon: "photo.on.rectangle.angled",
                iconColor: Color.purple,
                title: "Slideshow",
                subtitle: "Select multiple images to build a reel",
                isSelected: mediaMode == .slideshow && !slideshowImages.isEmpty
            ) {
                showSlideshowPicker = true
            }

            if mediaMode == .video, let _ = mediaURL {
                darkGlassInfoRow(icon: "checkmark.circle.fill", color: .green, text: "Video selected")
            } else if mediaMode == .slideshow, !slideshowImages.isEmpty {
                darkGlassInfoRow(icon: "checkmark.circle.fill", color: .green, text: "\(slideshowImages.count) images selected")
            }
        }
    }

    // MARK: - Step 2: Scripture Overlay

    private var step2ScriptureOverlay: some View {
        VStack(spacing: 16) {
            // Text input
            darkGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scripture Verse")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                    TextField("", text: $scriptureText, prompt: Text("Type a verse or reference...").foregroundColor(Color.white.opacity(0.25)))
                        .foregroundStyle(.white)
                        .font(.system(size: 15))
                    Divider().background(Color.white.opacity(0.1))
                }
                .padding(16)
            }

            // Font picker
            darkGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Font Style")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 10) {
                        ForEach(OverlayFont.allCases, id: \.self) { font in
                            Button {
                                selectedFont = font
                            } label: {
                                Text(font.rawValue)
                                    .font(.system(size: 13, weight: selectedFont == font ? .semibold : .regular))
                                    .foregroundStyle(selectedFont == font ? .white : Color.white.opacity(0.4))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedFont == font ? Color.purple.opacity(0.25) : Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(
                                                        selectedFont == font ? Color.purple.opacity(0.5) : Color.white.opacity(0.08),
                                                        lineWidth: 0.5
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }

            // Position picker
            darkGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Text Position")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 10) {
                        ForEach(OverlayPosition.allCases, id: \.self) { pos in
                            Button {
                                overlayPosition = pos
                            } label: {
                                Text(pos.rawValue)
                                    .font(.system(size: 13, weight: overlayPosition == pos ? .semibold : .regular))
                                    .foregroundStyle(overlayPosition == pos ? .white : Color.white.opacity(0.4))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(overlayPosition == pos ? Color.purple.opacity(0.25) : Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(
                                                        overlayPosition == pos ? Color.purple.opacity(0.5) : Color.white.opacity(0.08),
                                                        lineWidth: 0.5
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }

            // Live preview
            darkGlassCard {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.6))
                        .frame(height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )

                    VStack {
                        if overlayPosition == .top { scripturePreviewText; Spacer() }
                        else if overlayPosition == .center { Spacer(); scripturePreviewText; Spacer() }
                        else { Spacer(); scripturePreviewText }
                    }
                    .padding(16)
                }
                .padding(12)
            }
        }
    }

    private var scripturePreviewText: some View {
        Text(scriptureText.isEmpty ? "Your verse will appear here..." : scriptureText)
            .font(selectedFont == .serif ? .custom("Georgia", size: 14) :
                  selectedFont == .script ? .custom("Georgia-Italic", size: 14) :
                  .system(size: 14))
            .foregroundStyle(scriptureText.isEmpty ? Color.white.opacity(0.2) : Color.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Step 3: Music

    private var step3Music: some View {
        VStack(spacing: 12) {
            Text("Choose a worship track for your reel")
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            ForEach(curatedTracks) { track in
                TrackRow(
                    track: track,
                    isSelected: selectedTrack?.id == track.id,
                    isPlaying: playingTrackId == track.id
                ) {
                    selectedTrack = track
                } onPlayPause: {
                    if playingTrackId == track.id {
                        playingTrackId = nil
                    } else {
                        playingTrackId = track.id
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Caption & Tags

    private var step4CaptionTags: some View {
        VStack(spacing: 16) {
            darkGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Caption")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                    TextField("", text: $caption, prompt: Text("Write a caption for your reel...").foregroundColor(Color.white.opacity(0.25)), axis: .vertical)
                        .foregroundStyle(.white)
                        .font(.system(size: 15))
                        .lineLimit(4...)
                }
                .padding(16)
            }

            darkGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                    FlowLayout(spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 13, weight: selectedTags.contains(tag) ? .semibold : .regular))
                                    .foregroundStyle(selectedTags.contains(tag) ? .white : Color.white.opacity(0.45))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(selectedTags.contains(tag) ? Color.purple.opacity(0.3) : Color.white.opacity(0.05))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(
                                                        selectedTags.contains(tag) ? Color.purple.opacity(0.6) : Color.white.opacity(0.10),
                                                        lineWidth: 0.5
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }

            darkGlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share to OpenTable Feed")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                        Text("Your reel will appear in your followers' feeds")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    Spacer()
                    Toggle("", isOn: $shareToFeed)
                        .tint(.purple)
                        .labelsHidden()
                }
                .padding(16)
            }
        }
    }

    // MARK: - Step 5: Export & Share

    private var step5Export: some View {
        VStack(spacing: 24) {
            if !exportStarted {
                darkGlassCard {
                    VStack(spacing: 16) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.purple.opacity(0.7))
                        Text("Ready to Export")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Tap Export & Share below to process your reel")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }
            } else {
                darkGlassCard {
                    VStack(spacing: 20) {
                        if !exportDone {
                            VStack(spacing: 12) {
                                Text("Processing...")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.08))
                                            .frame(height: 8)
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.purple)
                                            .frame(width: geo.size.width * exportProgress, height: 8)
                                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: exportProgress)
                                    }
                                }
                                .frame(height: 8)

                                Text("\(Int(exportProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.green)
                                Text("Reel Ready!")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }

                if exportDone {
                    VStack(spacing: 12) {
                        // Save to Camera Roll
                        exportActionButton(
                            icon: "arrow.down.to.line",
                            title: "Save to Camera Roll",
                            color: Color.blue
                        ) {
                            saveToCameraRoll()
                        }

                        // Share to AMEN Feed
                        exportActionButton(
                            icon: "house.fill",
                            title: "Share to AMEN Feed",
                            color: Color.purple
                        ) {
                            shareToAMENFeed()
                        }

                        // Share via iOS
                        exportActionButton(
                            icon: "square.and.arrow.up",
                            title: "Share via iOS",
                            color: Color.teal
                        ) {
                            shareViaIOS()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Export Actions

    private func startExport() {
        exportStarted = true
        exportProgress = 0
        exportDone = false
        withAnimation(.linear(duration: 2.0)) {
            exportProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            exportDone = true
            saveReelMetadata()
        }
    }

    private func saveToCameraRoll() {
        guard let url = mediaURL else {
            errorMessage = "No video selected. Please go back and choose media."
            showError = true
            return
        }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if !success {
                    errorMessage = error?.localizedDescription ?? "Failed to save to camera roll."
                    showError = true
                }
            }
        }
    }

    private func shareToAMENFeed() {
        // Stub — actual feed post creation wired in a future sprint
        print("[FaithReel] Stub: posting reel to AMEN OpenTable feed. caption=\(caption), tags=\(Array(selectedTags)), shareToFeed=\(shareToFeed)")
        dismiss()
    }

    private func shareViaIOS() {
        guard let url = mediaURL else {
            errorMessage = "No video selected to share."
            showError = true
            return
        }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func saveReelMetadata() {
        let reel = FaithReelMetadata(
            id: UUID(),
            caption: caption,
            tags: Array(selectedTags),
            createdAt: Date(),
            localVideoPath: mediaURL?.path
        )
        var existing = FaithReelLibraryView.loadReels()
        existing.append(reel)
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: "faithReelMetadata")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func darkGlassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.white.opacity(0.04), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Spacer()
            }
            content()
        }
    }

    private func darkGlassInfoRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private func exportActionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Media Option Card

private struct MediaOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.green.opacity(0.3) : Color.white.opacity(0.10),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Track Row

private struct TrackRow: View {
    let track: WorshipTrack
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onPlayPause: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Play/Pause button
            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.purple.opacity(0.25) : Color.white.opacity(0.06))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle().strokeBorder(
                                isPlaying ? Color.purple.opacity(0.5) : Color.white.opacity(0.10),
                                lineWidth: 0.5
                            )
                        )
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isPlaying ? .purple : Color.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)

            // Track info
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.7))
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.purple)
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.purple.opacity(0.08) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.purple.opacity(0.3) : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1 : 0.5
                        )
                )
        )
    }
}

// FlowLayout is defined in FlowLayout.swift (shared across the project)

// MARK: - Faith Reel Library View

struct FaithReelLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reels: [FaithReelMetadata] = []

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("My Reels")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Circle().fill(Color.clear).frame(width: 34, height: 34)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)

                if reels.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.white.opacity(0.15))
                        Text("Your reels will appear here")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.3))
                        Text("Create your first Faith Reel to get started")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.2))
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(reels) { reel in
                                ReelCell(reel: reel) {
                                    deleteReel(reel)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear {
            reels = Self.loadReels()
        }
    }

    static func loadReels() -> [FaithReelMetadata] {
        guard let data = UserDefaults.standard.data(forKey: "faithReelMetadata"),
              let reels = try? JSONDecoder().decode([FaithReelMetadata].self, from: data) else {
            return []
        }
        return reels
    }

    private func deleteReel(_ reel: FaithReelMetadata) {
        reels.removeAll { $0.id == reel.id }
        if let data = try? JSONEncoder().encode(reels) {
            UserDefaults.standard.set(data, forKey: "faithReelMetadata")
        }
    }
}

// MARK: - Reel Cell

private struct ReelCell: View {
    let reel: FaithReelMetadata
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .aspectRatio(9/16, contentMode: .fill)

            Image(systemName: "film.stack")
                .font(.system(size: 22))
                .foregroundStyle(Color.white.opacity(0.12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Caption overlay
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(reel.caption.isEmpty ? "No caption" : reel.caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(Self.dateFormatter.string(from: reel.createdAt))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(8)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                // Re-share stub
                print("[FaithReel] Re-share reel id=\(reel.id)")
            } label: {
                Label("Re-share", systemImage: "arrow.2.squarepath")
            }
        }
    }
}

// MARK: - UIImagePickerController Representable (Camera + video)

struct ImagePickerRepresentable: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let mediaTypes: [String]
    let onPicked: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = mediaTypes
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (URL?) -> Void
        init(onPicked: @escaping (URL?) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let url = info[.mediaURL] as? URL
            picker.dismiss(animated: true)
            onPicked(url)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onPicked(nil)
        }
    }
}

// MARK: - Video Library Picker Representable (PHPickerViewController for video)

struct VideoLibraryPickerRepresentable: UIViewControllerRepresentable {
    let onPicked: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL?) -> Void
        init(onPicked: @escaping (URL?) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { onPicked(nil); return }
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                DispatchQueue.main.async {
                    // Copy to temp dir so the URL stays valid
                    if let url = url {
                        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        self.onPicked(dest)
                    } else {
                        self.onPicked(nil)
                    }
                }
            }
        }
    }
}

// MARK: - Slideshow Picker Representable (multiple images)

struct SlideshowPickerRepresentable: UIViewControllerRepresentable {
    let onPicked: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 20
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([UIImage]) -> Void
        init(onPicked: @escaping ([UIImage]) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var images: [UIImage] = []
            let group = DispatchGroup()
            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.onPicked(images)
            }
        }
    }
}
