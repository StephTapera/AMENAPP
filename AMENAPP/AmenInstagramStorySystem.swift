//
//  AmenInstagramStorySystem.swift
//  AMENAPP
//
//  Complete Instagram Story sharing system — story card design, renderer,
//  pasteboard handoff, and full-screen composer with live preview.
//
//  Entry point: AmenStoryShareView(content:)
//  Requires Info.plist: LSApplicationQueriesSchemes → instagram-stories
//

import SwiftUI

// MARK: - Story Style

enum AmenStoryStyle: String, CaseIterable, Identifiable {
    case pureWhite      = "pureWhite"
    case glassCard      = "glassCard"
    case scriptureFocus = "scriptureFocus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pureWhite:      return "Pure White"
        case .glassCard:      return "Glass Card"
        case .scriptureFocus: return "Scripture"
        }
    }

    var icon: String {
        switch self {
        case .pureWhite:      return "square"
        case .glassCard:      return "square.stack"
        case .scriptureFocus: return "text.book.closed"
        }
    }
}

// MARK: - Story Content

struct AmenStoryContent {
    let label: String      // e.g. "CHURCH NOTE", "#OPENTABLE"
    let bodyText: String
    let metadata: String   // e.g. "@username", "John 3:16", "Elevation Church"
    var showLogo: Bool = true

    // MARK: Factory helpers

    static func from(post: Post, showLogo: Bool = true) -> AmenStoryContent {
        let label: String
        switch post.category {
        case .prayer:      label = "PRAYER"
        case .testimonies: label = "ANSWERED PRAYER"
        case .openTable:   label = "#OPENTABLE"
        case .tip:         label = "TIP"
        case .funFact:     label = "FUN FACT"
        }
        let by = post.authorUsername.flatMap { $0.isEmpty ? nil : "@\($0)" } ?? post.authorName
        return AmenStoryContent(label: label, bodyText: post.content, metadata: by, showLogo: showLogo)
    }

    static func from(churchNote note: ChurchNote, showLogo: Bool = true) -> AmenStoryContent {
        let body: String
        if !note.keyPoints.isEmpty {
            body = note.keyPoints.prefix(3).map { "· \($0)" }.joined(separator: "\n\n")
        } else {
            body = String(note.content.prefix(240))
        }
        let meta = [note.sermonTitle, note.churchName]
            .compactMap { $0 }.joined(separator: " · ")
        return AmenStoryContent(
            label: "CHURCH NOTE",
            bodyText: body,
            metadata: meta.isEmpty ? note.date.formatted(date: .abbreviated, time: .omitted) : meta,
            showLogo: showLogo
        )
    }

    static func verse(reference: String, text: String, showLogo: Bool = true) -> AmenStoryContent {
        AmenStoryContent(label: "VERSE OF THE DAY", bodyText: text, metadata: reference, showLogo: showLogo)
    }
}

// MARK: - Story Card

/// Exportable story card — 360 × 640 logical points → 1080 × 1920 at 3× scale.
struct AmenInstagramStoryCard: View {
    let content: AmenStoryContent
    let style: AmenStoryStyle

    var body: some View {
        ZStack {
            Color.white

            atmosphereLayer

            VStack(spacing: 0) {
                // AMEN logo
                HStack {
                    if content.showLogo {
                        Image("amen-logo")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(height: 26)
                    }
                    Spacer()
                }
                .padding(.leading, 36)
                .padding(.top, 54)

                Spacer(minLength: 28)

                // Main content card
                mainCard
                    .padding(.horizontal, 22)

                Spacer()

                // Footer
                Text("Shared from AMEN")
                    .font(.systemScaled(11, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.35))
                    .padding(.bottom, 42)
            }
        }
        .frame(width: 360, height: 640)
    }

    // MARK: Atmosphere

    @ViewBuilder
    private var atmosphereLayer: some View {
        if style != .pureWhite {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 320, height: 320)
                    .blur(radius: 48)
                    .offset(x: -88, y: -172)

                Circle()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 240, height: 240)
                    .blur(radius: 38)
                    .offset(x: 108, y: 190)
            }
        }
    }

    // MARK: Main card

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category label
            Text(content.label)
                .font(.systemScaled(10, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(.black.opacity(0.48))
                .padding(.bottom, 14)

            // Body
            Text(content.bodyText)
                .font(bodyFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(style == .scriptureFocus ? 7 : 4)
                .minimumScaleFactor(0.68)
                .lineLimit(style == .scriptureFocus ? 8 : 11)
                .padding(.bottom, 18)

            // Thin divider
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.75)
                .padding(.bottom, 14)

            // Metadata
            Text(content.metadata)
                .font(.systemScaled(12, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.48))
                .lineLimit(1)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var bodyFont: Font {
        switch style {
        case .pureWhite, .glassCard:
            return .system(size: 24, weight: .semibold, design: .rounded)
        case .scriptureFocus:
            return .system(size: 27, weight: .bold, design: .serif)
        }
    }

    private var cardPadding: CGFloat { style == .scriptureFocus ? 28 : 24 }

    @ViewBuilder
    private var cardBackground: some View {
        switch style {
        case .pureWhite:
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 5)

        case .glassCard:
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.80))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.52), Color.white.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.055), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.055), radius: 18, x: 0, y: 7)

        case .scriptureFocus:
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                // Specular top highlight
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.58), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.32)
                        )
                    )
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.055), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 8)
        }
    }
}

// MARK: - Renderer

@MainActor
enum StoryCardRenderer {
    /// Renders the story card to UIImage at 1080 × 1920 (3× scale of 360 × 640).
    static func render(_ card: AmenInstagramStoryCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderer.proposedSize = ProposedViewSize(width: 360, height: 640)
        return renderer.uiImage
    }
}

// MARK: - Instagram Manager

enum InstagramStoryShareError: LocalizedError {
    case notInstalled
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:   return "Instagram is not installed on this device."
        case .encodingFailed: return "Could not prepare the image for sharing."
        }
    }
}

@MainActor
final class InstagramStoryShareManager {
    static let shared = InstagramStoryShareManager()
    private init() {}

    var isInstagramInstalled: Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Writes image to pasteboard with Instagram's key and opens the Stories URL scheme.
    func share(image: UIImage) throws {
        guard let png = image.pngData() else { throw InstagramStoryShareError.encodingFailed }
        guard isInstagramInstalled, let url = URL(string: "instagram-stories://share") else {
            throw InstagramStoryShareError.notInstalled
        }
        UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": png]],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        UIApplication.shared.open(url)
    }

    func saveToPhotos(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Full-Screen Composer

/// Full-screen story preview and export composer — present as .fullScreenCover.
struct AmenStoryShareView: View {
    let content: AmenStoryContent
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStyle: AmenStoryStyle = .glassCard
    @State private var showLogo = true
    @State private var isSharing = false
    @State private var isSaving  = false
    @State private var errorMessage: String?
    @State private var savedSuccess = false

    // Entrance animation
    @State private var cardOffset:  CGFloat = 32
    @State private var cardOpacity: Double  = 0

    // Specular sweep: -1 = not started, 0→1 = sweeping
    @State private var sweepProgress: CGFloat = -1

    private var liveContent: AmenStoryContent {
        AmenStoryContent(
            label: content.label,
            bodyText: content.bodyText,
            metadata: content.metadata,
            showLogo: showLogo
        )
    }

    private var card: AmenInstagramStoryCard {
        AmenInstagramStoryCard(content: liveContent, style: selectedStyle)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar

                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            storyPreview
                                .padding(.top, 20)

                            if !InstagramStoryShareManager.shared.isInstagramInstalled {
                                Label("Instagram not installed — you can still save to photos",
                                      systemImage: "info.circle")
                                    .font(.systemScaled(12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            if let error = errorMessage {
                                Text(error)
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            Spacer(minLength: 140)
                        }
                        .frame(minWidth: geo.size.width)
                    }
                }
            }

            // Floating bottom bar
            VStack {
                Spacer()
                bottomBar
            }
        }
        .onAppear { runEntranceAnimation() }
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .pressableButton()

            Spacer()

            Text("Instagram Story")
                .font(.systemScaled(17, weight: .semibold))

            Spacer()

            // Logo toggle
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.75))) { showLogo.toggle() }
            } label: {
                Image(systemName: showLogo ? "a.circle.fill" : "a.circle")
                    .font(.systemScaled(21))
                    .foregroundStyle(showLogo ? Color.primary : Color.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .pressableButton()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Story preview

    private var storyPreview: some View {
        let previewW: CGFloat = 234
        let previewH: CGFloat = previewW * (16.0 / 9.0)

        return ZStack {
            card
                .frame(width: previewW, height: previewH)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.11), radius: 26, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.045), lineWidth: 0.8)
                )
                .offset(y: cardOffset)
                .opacity(cardOpacity)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: cardOffset)
                .animation(.easeOut(duration: 0.38), value: cardOpacity)

            // Specular highlight sweep
            if sweepProgress >= 0 {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.16), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: previewW, height: previewH)
                    .offset(x: (sweepProgress - 0.5) * previewW * 2.4)
                    .clipped()
                    .animation(.easeInOut(duration: 0.65), value: sweepProgress)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: previewW, height: previewH)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // Style chips
            HStack(spacing: 8) {
                ForEach(AmenStoryStyle.allCases) { style in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.76))) {
                            selectedStyle = style
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: style.icon)
                                .font(.systemScaled(11, weight: .medium))
                            Text(style.displayName)
                                .font(.systemScaled(13, weight: selectedStyle == style ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedStyle == style ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selectedStyle == style ? Color.black : Color(.systemGray5))
                        )
                    }
                    .buttonStyle(.plain)
                    .pressableButton()
                }
            }
            .padding(.horizontal, 20)

            // Action buttons
            HStack(spacing: 10) {
                saveButton
                shareButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, max(20, safeAreaBottom))
        }
        .padding(.top, 14)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var saveButton: some View {
        Button(action: saveToPhotos) {
            HStack(spacing: 8) {
                Group {
                    if isSaving {
                        ProgressView().tint(.primary).scaleEffect(0.8)
                    } else if savedSuccess {
                        Image(systemName: "checkmark").font(.systemScaled(14, weight: .semibold))
                    } else {
                        Image(systemName: "arrow.down.to.line").font(.systemScaled(14, weight: .semibold))
                    }
                }
                Text(savedSuccess ? "Saved!" : "Save")
                    .font(.systemScaled(15, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.07), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .pressableButton()
        .disabled(isSaving)
    }

    private var shareButton: some View {
        let igAvailable = InstagramStoryShareManager.shared.isInstagramInstalled
        return Button(action: shareToInstagram) {
            HStack(spacing: 8) {
                if isSharing {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: igAvailable ? "camera.fill" : "square.and.arrow.up")
                        .font(.systemScaled(14, weight: .semibold))
                }
                Text(igAvailable ? "Instagram Story" : "Share Image")
                    .font(.systemScaled(15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
            )
        }
        .buttonStyle(.plain)
        .pressableButton()
        .disabled(isSharing)
    }

    // MARK: Helpers

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.safeAreaInsets.bottom ?? 0
    }

    private func runEntranceAnimation() {
        withAnimation {
            cardOffset  = 0
            cardOpacity = 1
        }
        // Specular sweep after card settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            sweepProgress = 0
            withAnimation(.easeInOut(duration: 0.65)) { sweepProgress = 1 }
        }
    }

    private func shareToInstagram() {
        guard !isSharing else { return }
        isSharing = true
        errorMessage = nil

        guard let image = StoryCardRenderer.render(card) else {
            errorMessage = "Could not render the story card."
            isSharing = false
            return
        }

        if InstagramStoryShareManager.shared.isInstagramInstalled {
            do {
                try InstagramStoryShareManager.shared.share(image: image)
                isSharing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
                isSharing = false
            }
        } else {
            isSharing = false
            let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }
        }
    }

    private func saveToPhotos() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        guard let image = StoryCardRenderer.render(card) else {
            errorMessage = "Could not render the story card."
            isSaving = false
            return
        }
        InstagramStoryShareManager.shared.saveToPhotos(image: image)
        withAnimation { savedSuccess = true; isSaving = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { savedSuccess = false }
        }
    }
}

// MARK: - Preview

#Preview {
    AmenStoryShareView(content: .init(
        label: "#OPENTABLE",
        bodyText: "Today I was reminded that God's timing is always perfect. Even when the path feels unclear, there is purpose in every step of the journey.",
        metadata: "@faithwalker",
        showLogo: true
    ))
}
