// ComposerMediaReorderGrid.swift
// AMENAPP / SocialLayer
//
// Drag-to-reorder horizontal grid for photo/video attachments in the composer.
// Supports alt-text editing per item, remove button, video duration badge,
// and long-press drag-to-reorder.
//
// INTEGRATION NOTE (Phase 4 — CreatePostView.swift):
// --------------------------------------------------
// 1. Add state:
//      @State private var mediaAttachments: [ComposerAttachment] = []
//
// 2. Place the grid inside your composer's ScrollView body, below the text editor:
//      if !mediaAttachments.isEmpty {
//          ComposerMediaReorderGrid(
//              attachments: $mediaAttachments,
//              onRemove: { id in
//                  mediaAttachments.removeAll { $0.id == id }
//              }
//          )
//          .padding(.horizontal, 16)
//      }
//
// 3. When the user picks photos from AmenImagePickerView or ComposerGIFPickerSheet,
//    append to `mediaAttachments` using the static factories on ComposerAttachment:
//      mediaAttachments.append(.photo(ComposerPhotoAttachment(localURL: url)))
//      mediaAttachments.append(.gif(gifAttachment))
//
// 4. Hide the add-media button when mediaAttachments.count >= 4 by checking:
//      mediaAttachments.count < 4
//
// Maximum 4 attachments is enforced by hiding the add button; the grid itself
// accepts any array passed to it and will render all items.

import SwiftUI

// MARK: - ComposerMediaReorderGrid

struct ComposerMediaReorderGrid: View {
    @Binding var attachments: [ComposerAttachment]
    var onRemove: (UUID) -> Void

    // Internal drag state
    @State private var draggingId: UUID? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var dragTargetIndex: Int? = nil

    // Alt-text editing
    @State private var expandedAltTextId: UUID? = nil

    private let maxItems = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header label
            if !attachments.isEmpty {
                HStack {
                    Text("Attachments")
                        .font(AMENFont.medium(13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(attachments.count)/\(maxItems)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Attachments, \(attachments.count) of \(maxItems)")
            }

            // Scrollable cell row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        AttachmentCell(
                            attachment: attachment,
                            index: index,
                            totalCount: attachments.count,
                            isDragging: draggingId == attachment.id,
                            isDropTarget: dragTargetIndex == index && draggingId != attachment.id,
                            isAltTextExpanded: expandedAltTextId == attachment.id,
                            onRemove: {
                                withAnimation(Motion.adaptive(Motion.springRelease)) {
                                    onRemove(attachment.id)
                                }
                            },
                            onToggleAltText: {
                                withAnimation(Motion.adaptive(Motion.springPress)) {
                                    if expandedAltTextId == attachment.id {
                                        expandedAltTextId = nil
                                    } else {
                                        expandedAltTextId = attachment.id
                                    }
                                }
                            },
                            altTextBinding: altTextBinding(for: attachment.id)
                        )
                        .onDrag {
                            draggingId = attachment.id
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            return NSItemProvider(object: attachment.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: ReorderDropDelegate(
                                item: attachment,
                                attachments: $attachments,
                                draggingId: $draggingId,
                                dragTargetIndex: $dragTargetIndex,
                                currentIndex: index
                            )
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: attachment, index: index))
                        .accessibilityHint("Long press to drag and reorder")
                        .accessibilityAction(named: "Remove") {
                            withAnimation(Motion.adaptive(Motion.springRelease)) {
                                onRemove(attachment.id)
                            }
                        }
                    }

                    // Add more button — hidden when max reached
                    if attachments.count < maxItems {
                        AddMorePlaceholder()
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .animation(Motion.adaptive(Motion.springPress), value: attachments.map(\.id))
            }
        }
    }

    // MARK: - Alt Text Binding

    private func altTextBinding(for id: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return "" }
                return attachments[idx].photo?.altText ?? ""
            },
            set: { newValue in
                guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }
                attachments[idx].photo?.altText = newValue
            }
        )
    }

    // MARK: - Accessibility Labels

    private func accessibilityLabel(for attachment: ComposerAttachment, index: Int) -> String {
        switch attachment.kind {
        case .photo:
            return "Photo \(index + 1) — drag to reorder"
        case .video:
            let dur = attachment.video.map { formattedDuration($0.durationSeconds) } ?? ""
            return "Video \(index + 1)\(dur.isEmpty ? "" : ", \(dur)") — drag to reorder"
        case .gif:
            let title = attachment.gif?.title ?? "GIF"
            return "\(title) — drag to reorder"
        default:
            return "Attachment \(index + 1) — drag to reorder"
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - AttachmentCell

private struct AttachmentCell: View {
    let attachment: ComposerAttachment
    let index: Int
    let totalCount: Int
    let isDragging: Bool
    let isDropTarget: Bool
    let isAltTextExpanded: Bool
    let onRemove: () -> Void
    let onToggleAltText: () -> Void
    @Binding var altText: String

    @Environment(\.colorScheme) private var colorScheme

    private let cellSize: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Thumbnail
                thumbnailContent
                    .frame(width: cellSize, height: cellSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isDropTarget
                                    ? AmenTheme.Colors.amenGold
                                    : AmenTheme.Colors.borderSoft,
                                lineWidth: isDropTarget ? 2 : 0.5
                            )
                    )
                    .shadow(
                        color: isDragging
                            ? AmenTheme.Colors.amenGold.opacity(0.25)
                            : AmenTheme.Colors.shadowCard,
                        radius: isDragging ? 12 : 4,
                        x: 0, y: isDragging ? 6 : 2
                    )
                    .scaleEffect(isDragging ? 1.06 : 1.0)
                    .opacity(isDragging ? 0.85 : 1.0)
                    .animation(Motion.adaptive(Motion.springPress), value: isDragging)

                // Alt text toggle button (bottom overlay, tappable)
                if attachment.kind == .photo {
                    VStack {
                        Spacer()
                        Button(action: onToggleAltText) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 10, weight: .medium))
                                Text("ALT")
                                    .font(AMENFont.medium(10))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.52))
                            )
                            .padding(.bottom, 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit alt text")
                        .accessibilityHint("Opens alt text editor for this photo")
                    }
                    .frame(width: cellSize, height: cellSize)
                }

                // Video duration badge (top-left)
                if attachment.kind == .video,
                   let video = attachment.video,
                   video.durationSeconds > 0 {
                    VStack {
                        HStack {
                            Text(formattedDuration(video.durationSeconds))
                                .font(AMENFont.medium(10))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.55))
                                )
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: cellSize, height: cellSize)
                }

                // GIF badge (top-left for GIFs)
                if attachment.kind == .gif {
                    VStack {
                        HStack {
                            Text("GIF")
                                .font(AMENFont.medium(10))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(AmenTheme.Colors.amenPurple.opacity(0.85))
                                )
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: cellSize, height: cellSize)
                }

                // Remove button (top-right)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onRemove) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.60))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(AmenPressStyle(scale: 0.88))
                        .padding(6)
                        .accessibilityLabel("Remove attachment")
                        .accessibilityHint("Removes this item from your post")
                    }
                    Spacer()
                }
                .frame(width: cellSize, height: cellSize)
            }
            .frame(width: cellSize, height: cellSize)

            // Alt text field (expandable below the cell)
            if isAltTextExpanded && attachment.kind == .photo {
                altTextEditor
                    .frame(width: cellSize)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: cellSize)
    }

    // MARK: - Thumbnail Content

    @ViewBuilder
    private var thumbnailContent: some View {
        switch attachment.kind {
        case .photo:
            if let localURL = attachment.photo?.localURL,
               let uiImage = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = attachment.photo?.remoteURL,
                      let url = URL(string: remoteURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
        case .video:
            if let thumbURL = attachment.video?.thumbnailURL,
               let url = URL(string: thumbURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        videoPlaceholder
                    }
                }
            } else if let localURL = attachment.video?.localURL,
                      let thumb = generateVideoThumbnail(url: localURL) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                videoPlaceholder
            }
        case .gif:
            if let previewURL = attachment.gif?.previewURL ?? attachment.gif?.url,
               let url = URL(string: previewURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AmenTheme.Colors.shimmerBase)
                            .amenSkeleton()
                    default:
                        gifPlaceholder
                    }
                }
            } else {
                gifPlaceholder
            }
        default:
            photoPlaceholder
        }
    }

    // MARK: - Placeholders

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AmenTheme.Colors.surfaceInput)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            )
    }

    private var videoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AmenTheme.Colors.amenBlack)
            .overlay(
                Image(systemName: "video.fill")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
            )
    }

    private var gifPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AmenTheme.Colors.amenPurple.opacity(0.15))
            .overlay(
                Text("GIF")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
            )
    }

    // MARK: - Alt Text Editor

    private var altTextEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alt text")
                .font(AMENFont.medium(10))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .padding(.top, 6)

            TextField("Describe this photo…", text: $altText, axis: .vertical)
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(3)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.30), lineWidth: 0.5)
                        )
                )
                .accessibilityLabel("Alt text for photo \(index + 1)")
                .accessibilityHint("Describes the photo for VoiceOver users")
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func formattedDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func generateVideoThumbnail(url: URL) -> UIImage? {
        // Synchronous thumbnail generation for local video files only.
        // Heavy thumbnails should be pre-generated off-main and stored in the attachment.
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        let time = CMTime(seconds: 0, preferredTimescale: 1)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - AddMorePlaceholder

private struct AddMorePlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    AmenTheme.Colors.borderSoft,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)  // Caller owns the add button action
    }
}

// MARK: - ReorderDropDelegate

private struct ReorderDropDelegate: DropDelegate {
    let item: ComposerAttachment
    @Binding var attachments: [ComposerAttachment]
    @Binding var draggingId: UUID?
    @Binding var dragTargetIndex: Int?
    let currentIndex: Int

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        dragTargetIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingId,
              let fromIndex = attachments.firstIndex(where: { $0.id == draggingId }),
              fromIndex != currentIndex else { return }

        dragTargetIndex = currentIndex

        withAnimation(Motion.adaptive(Motion.springPress)) {
            attachments.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: currentIndex > fromIndex ? currentIndex + 1 : currentIndex
            )
            // Update sortOrder to match new positions
            for (i, _) in attachments.enumerated() {
                attachments[i].photo?.sortOrder = i
                attachments[i].video?.sortOrder = i
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dragTargetIndex = nil
    }
}

// MARK: - AVFoundation import (local only)

import AVFoundation
