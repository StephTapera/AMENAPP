import SwiftUI
import UIKit
import FirebaseFunctions

// MARK: - Response model

private struct BereanSharePayload {
    let pullQuote: String
    let verseRef: String
    let caption: String
    let framingLine: String

    init?(data: Any) {
        guard let dict = data as? [String: Any],
              let pq = dict["pullQuote"] as? String,
              let vr = dict["verseRef"] as? String,
              let cap = dict["caption"] as? String,
              let fl = dict["framingLine"] as? String
        else { return nil }
        self.pullQuote = pq
        self.verseRef = vr
        self.caption = cap
        self.framingLine = fl
    }
}

// MARK: - Sheet

/// The primary share surface for AMEN posts.
/// Calls `bereanShareAssist` to generate AI-powered share card content,
/// then shows an editable live preview before sharing.
struct BereanShareSheet: View {
    let post: Post
    let authorAvatar: UIImage?

    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var pullQuote: String = ""
    @State private var verseRef: String = ""
    @State private var caption: String = ""
    @State private var framingLine: String = ""
    @State private var previewSize: ShareCardSize = .story
    @State private var isSharingStory = false
    @State private var showSavedToast = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if isLoading {
                    bereanLoadingView
                } else if let err = loadError {
                    errorView(message: err)
                } else {
                    contentScroll
                }
            }
            .navigationTitle(isLoading ? "Berean is thinking…" : "Share with Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await loadBereanSuggestions() }
    }

    // MARK: - Loading

    private var bereanLoadingView: some View {
        VStack(spacing: 32) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    BereanPulseRing(delay: Double(i) * 0.4)
                }
                Text("AMEN")
                    .font(.system(size: 22, weight: .black))
                    .tracking(4)
                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                Text("Berean is crafting your share card")
                    .font(.headline)
                Text("Finding the right verse and pull-quote…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            AmenLiquidGlassPillButton(
                title: "Try again",
                systemImage: "arrow.clockwise",
                isLoading: false,
                isDisabled: false
            ) {
                loadError = nil
                isLoading = true
                Task { await loadBereanSuggestions() }
            }
            Button("Share without Berean") {
                ShareService.presentSystemSheet(for: makeContent())
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 20) {
                framingPill

                cardPreview

                sizePicker

                editFields

                actionButtons
            }
            .padding()
        }
    }

    private var framingPill: some View {
        Group {
            if !framingLine.isEmpty {
                Text(framingLine)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var cardPreview: some View {
        let previewWidth: CGFloat = 270
        let previewHeight: CGFloat = previewSize == .story ? 480 : 270
        let scale: CGFloat = previewSize == .story ? 0.25 : (270.0 / 1080.0)

        return ShareCard(
            post: post,
            size: previewSize,
            pullQuote: pullQuote,
            verseRef: verseRef,
            authorAvatar: authorAvatar
        )
        .frame(width: previewSize.pixelSize.width, height: previewSize.pixelSize.height)
        .scaleEffect(scale, anchor: .center)
        .frame(width: previewWidth, height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var sizePicker: some View {
        Picker("Card size", selection: $previewSize) {
            Text("Story (9:16)").tag(ShareCardSize.story)
            Text("Square (1:1)").tag(ShareCardSize.square)
        }
        .pickerStyle(.segmented)
    }

    private var editFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            editField(
                label: "Pull Quote",
                placeholder: "The spiritual hook of this post",
                text: $pullQuote,
                limit: 180
            )
            editField(
                label: "Verse",
                placeholder: "e.g. James 1:19",
                text: $verseRef,
                limit: 40
            )
            editField(
                label: "Caption",
                placeholder: "Instagram caption",
                text: $caption,
                limit: 300
            )
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func editField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        limit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.caption2)
                    .foregroundStyle(text.wrappedValue.count > limit ? Color.red : Color.secondary.opacity(0.6))
            }
            TextField(placeholder, text: text, axis: .vertical)
                .font(.body)
                .lineLimit(3...6)
                .onChange(of: text.wrappedValue) { _, new in
                    if new.count > limit {
                        text.wrappedValue = String(new.prefix(limit))
                    }
                }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary: Share to Story
            AmenLiquidGlassPillButton(
                title: "Share to Story",
                systemImage: "play.square.stack",
                isLoading: isSharingStory,
                isDisabled: isSharingStory
            ) {
                Task { await shareToStory() }
            }

            HStack(spacing: 12) {
                AmenLiquidGlassPillButton(
                    title: "Send to friend",
                    systemImage: "paperplane",
                    isLoading: false,
                    isDisabled: false
                ) {
                    ShareService.presentSystemSheet(for: makeContent())
                }

                AmenLiquidGlassPillButton(
                    title: "Copy",
                    systemImage: "link",
                    isLoading: false,
                    isDisabled: false
                ) {
                    Task { await copyLink() }
                }

                AmenLiquidGlassPillButton(
                    title: "Save",
                    systemImage: "arrow.down.to.line",
                    isLoading: false,
                    isDisabled: false
                ) {
                    Task { await saveImage() }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func shareToStory() async {
        isSharingStory = true
        defer { isSharingStory = false }
        await ShareService.share(makeContent(), to: .instagramStory)
    }

    private func copyLink() async {
        await ShareService.share(makeContent(), to: .copyLink)
    }

    private func saveImage() async {
        guard let image = await MainActor.run(body: {
            ShareCardRenderer.renderImage(
                post: post,
                size: previewSize,
                pullQuote: pullQuote,
                verseRef: verseRef,
                authorAvatar: authorAvatar
            )
        }) else { return }

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        HapticManager.notification(type: .success)
        ToastManager.shared.success("Card saved to Photos")
    }

    private func makeContent() -> ShareContent {
        ShareContent(
            post: post,
            pullQuote: pullQuote.isEmpty ? nil : pullQuote,
            verseRef: verseRef.isEmpty ? nil : verseRef,
            caption: caption.isEmpty ? nil : caption,
            authorAvatar: authorAvatar
        )
    }

    // MARK: - Data loading

    private func loadBereanSuggestions() async {
        do {
            let callable = Functions.functions().httpsCallable("bereanShareAssist")
            let result = try await callable.call(["postId": post.firestoreId])
            guard let payload = BereanSharePayload(data: result.data) else {
                throw BereanShareError.malformedResponse
            }
            await MainActor.run {
                pullQuote = payload.pullQuote
                verseRef = payload.verseRef
                caption = payload.caption
                framingLine = payload.framingLine
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Berean couldn't generate your card. Please try again."
                isLoading = false
            }
        }
    }
}

// MARK: - Pulse animation

private struct BereanPulseRing: View {
    let delay: Double

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .stroke(Color(red: 0.83, green: 0.69, blue: 0.22).opacity(opacity), lineWidth: 1.5)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.6)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    scale = 1.8
                    opacity = 0
                }
            }
    }
}

// MARK: - Error type

private enum BereanShareError: LocalizedError {
    case malformedResponse
    var errorDescription: String? { "Unexpected response from Berean." }
}
