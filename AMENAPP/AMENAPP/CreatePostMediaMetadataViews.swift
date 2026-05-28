import SwiftUI
import AVKit

struct MediaMetadataAuthoringSheet: View {
    @Binding var draft: CreatePostMediaMetadataDraft
    let photoPreviewImages: [UIImage]
    let witnessAttachment: WitnessDraftAttachment?
    let onDone: () -> Void

    @State private var selectedTab: MediaMetadataAuthoringTab = .captions

    private var hasVideo: Bool {
        witnessAttachment?.isVideo == true
    }

    private var hasPhotos: Bool {
        !photoPreviewImages.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard

                    if hasVideo {
                        videoTabPicker
                        videoContent
                    }

                    if hasPhotos {
                        photoTabPicker
                        photoContent
                    }
                }
                .padding(16)
            }
            .background(Color.white)
            .navigationTitle("Media setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onDone)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .font(AMENFont.semiBold(14))
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prepare captions, key moments, and featured frames before publishing.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.black.opacity(0.72))
            HStack(spacing: 8) {
                statusPill(title: "Processing", value: draft.videoDraft?.processingState.rawValue.capitalized ?? "Ready")
                if hasVideo {
                    statusPill(title: "Captions", value: draft.videoDraft?.captionGenerationState.rawValue.capitalized ?? "Queued")
                    statusPill(title: "Moments", value: draft.videoDraft?.keyMomentsGenerationState.rawValue.capitalized ?? "Queued")
                }
            }
        }
        .padding(16)
        .background(AMENMediaGlassCard(cornerRadius: 24))
    }

    private func statusPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AMENFont.regular(11))
                .foregroundStyle(.black.opacity(0.42))
            Text(value)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.black.opacity(0.78))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    private var videoTabPicker: some View {
        metadataTabPicker(options: [.captions, .moments, .featured])
    }

    private var photoTabPicker: some View {
        metadataTabPicker(options: hasVideo ? [.frames] : [.frames, .featured])
    }

    private func metadataTabPicker(options: [MediaMetadataAuthoringTab]) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(selectedTab == tab ? .black : .black.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedTab == tab ? Color.white : Color.black.opacity(0.03))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    @ViewBuilder
    private var videoContent: some View {
        switch selectedTab {
        case .captions:
            if let videoDraftBinding = Binding($draft.videoDraft) {
                UploadCaptionEditorView(draft: videoDraftBinding)
            }
        case .moments:
            if let videoDraftBinding = Binding($draft.videoDraft) {
                UploadKeyMomentsEditorView(draft: videoDraftBinding)
            }
        case .featured:
            if let videoDraftBinding = Binding($draft.videoDraft), let url = witnessAttachment?.finalFileURL {
                FeaturedVideoFramePickerView(draft: videoDraftBinding, videoURL: url, duration: witnessAttachment?.durationSec ?? 0)
            }
        case .frames:
            EmptyView()
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        switch selectedTab {
        case .frames:
            PhotoModeFrameCaptionEditor(
                frameDrafts: $draft.frameCaptions,
                featuredFrameIndex: $draft.featuredFrameIndex,
                previewImages: photoPreviewImages
            )
        case .featured:
            FeaturedPhotoFramePickerView(
                previewImages: photoPreviewImages,
                featuredFrameIndex: $draft.featuredFrameIndex
            )
        case .captions, .moments:
            EmptyView()
        }
    }
}

private enum MediaMetadataAuthoringTab: CaseIterable {
    case captions
    case moments
    case featured
    case frames

    var title: String {
        switch self {
        case .captions: return "Captions"
        case .moments: return "Key moments"
        case .featured: return "Featured frame"
        case .frames: return "Frame captions"
        }
    }
}

struct UploadCaptionEditorView: View {
    @Binding var draft: VideoMetadataDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle("Captions on by default", isOn: $draft.captionsEnabledByDefault)
                    .font(AMENFont.semiBold(14))
                Spacer()
                CaptionStylePicker(selectedStyle: $draft.captionStyle)
            }

            CaptionGenerationStatusView(
                state: draft.captionGenerationState,
                retryTitle: "Regenerate"
            ) {
                draft.captionGenerationState = .generating
            }

            ForEach($draft.captionCues) { $cue in
                CaptionCueEditorRow(cue: $cue) {
                    draft.captionCues.removeAll { $0.id == cue.id }
                    draft.userEdited = true
                }
            }

            Button {
                let lastEnd = draft.captionCues.last?.endTime ?? 0
                draft.captionCues.append(
                    VideoCaptionCueDraft(startTime: lastEnd, endTime: lastEnd + 4, text: "New cue")
                )
                draft.userEdited = true
            } label: {
                Label("Add cue", systemImage: "plus")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(AMENMediaGlassCard(cornerRadius: 24))
    }
}

struct CaptionStylePicker: View {
    @Binding var selectedStyle: MediaCaptionStyle

    var body: some View {
        Menu {
            ForEach(MediaCaptionStyle.allCases, id: \.self) { style in
                Button(style.title) {
                    selectedStyle = style
                }
            }
        } label: {
            Label(selectedStyle.title, systemImage: "captions.bubble.fill")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.black.opacity(0.72))
        }
    }
}

struct CaptionCueEditorRow: View {
    @Binding var cue: VideoCaptionCueDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timeLabel)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.black.opacity(0.5))
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }

            TextField("Caption text", text: $cue.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.03))
        )
    }

    private var timeLabel: String {
        "\(format(cue.startTime)) - \(format(cue.endTime))"
    }

    private func format(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct CaptionGenerationStatusView: View {
    let state: MediaGenerationState
    let retryTitle: String
    let onRetry: () -> Void

    var body: some View {
        HStack {
            Text("Generation: \(state.rawValue.capitalized)")
                .font(AMENFont.medium(12))
                .foregroundStyle(.black.opacity(0.6))
            Spacer()
            if state == .failed || state == .queued {
                Button(retryTitle, action: onRetry)
                    .font(AMENFont.semiBold(12))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

struct UploadKeyMomentsEditorView: View {
    @Binding var draft: VideoMetadataDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CaptionGenerationStatusView(
                state: draft.keyMomentsGenerationState,
                retryTitle: "Refresh suggestions"
            ) {
                draft.keyMomentsGenerationState = .generating
            }

            ForEach($draft.keyMoments) { $moment in
                KeyMomentRow(moment: $moment) {
                    draft.keyMoments.removeAll { $0.id == moment.id }
                    draft.userEdited = true
                }
            }

            Button {
                draft.keyMoments.append(
                    KeyMomentDraft(timestamp: draft.keyMoments.last?.timestamp ?? 0, label: "New moment", kind: .mainPoint)
                )
                draft.userEdited = true
            } label: {
                Label("Add key moment", systemImage: "plus")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(AMENMediaGlassCard(cornerRadius: 24))
    }
}

struct KeyMomentRow: View {
    @Binding var moment: KeyMomentDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Label", text: $moment.label)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }

            HStack {
                TextField(
                    "00:00",
                    value: $moment.timestamp,
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

                Picker("Type", selection: $moment.kind) {
                    ForEach(MediaKeyMomentKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.03))
        )
    }
}

struct FeaturedVideoFramePickerView: View {
    @Binding var draft: VideoMetadataDraft
    let videoURL: URL
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreatorCoverFrameScrubber(
                videoURL: videoURL,
                durationMs: Int(max(duration, 1) * 1000),
                frameTimeMs: Binding(
                    get: { Int(draft.featuredFrameTime * 1000) },
                    set: { draft.featuredFrameTime = Double($0) / 1000 }
                )
            ) {}

            Text("The selected frame becomes the main preview for the feed, profile, and detail handoff.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.black.opacity(0.52))
        }
        .padding(16)
        .background(AMENMediaGlassCard(cornerRadius: 24))
    }
}

struct PhotoModeFrameCaptionEditor: View {
    @Binding var frameDrafts: [FrameCaptionDraft]
    @Binding var featuredFrameIndex: Int
    let previewImages: [UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach($frameDrafts) { $frame in
                VStack(alignment: .leading, spacing: 10) {
                    if previewImages.indices.contains(frame.frameIndex) {
                        Image(uiImage: previewImages[frame.frameIndex])
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    TextField("Frame title", text: $frame.title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Frame caption", text: $frame.text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    TextField("Verse reference", text: $frame.verseReference)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Featured frame", isOn: Binding(
                        get: { featuredFrameIndex == frame.frameIndex },
                        set: { isFeatured in
                            if isFeatured {
                                featuredFrameIndex = frame.frameIndex
                            }
                        }
                    ))
                    .font(AMENFont.medium(12))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.03))
                )
            }
        }
        .padding(16)
        .background(AMENMediaGlassCard(cornerRadius: 24))
    }
}

struct FeaturedPhotoFramePickerView: View {
    let previewImages: [UIImage]
    @Binding var featuredFrameIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(previewImages.enumerated()), id: \.offset) { index, image in
                    Button {
                        featuredFrameIndex = index
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(featuredFrameIndex == index ? Color.black : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AMENMediaGlassCard(cornerRadius: 24))
    }
}

// MARK: - AMENMediaGlassCard

private struct AMENMediaGlassCard: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.systemBackground).opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }
}
