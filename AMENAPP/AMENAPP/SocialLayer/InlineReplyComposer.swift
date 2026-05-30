// InlineReplyComposer.swift
// AMENAPP — SocialLayer/
//
// Compact inline reply composer.  Appears pinned above the keyboard when the
// user taps a "Reply" button on any ReplyNodeRow.
//
// Types: ReplyNode, ComposerAttachment, ComposerGIFAttachment, ComposerStickerAttachment
//        (ComposerContract.swift — do NOT redeclare)

import SwiftUI
import FirebaseAuth

// MARK: - InlineReplyComposer

struct InlineReplyComposer: View {

    /// The reply target.  nil = replying directly to the original post.
    let replyingToNode: ReplyNode?
    let rootPostId: String

    /// Called when the user taps Send.
    var onSend: (String, [ComposerAttachment]) -> Void
    /// Called when the user dismisses the reply context (✕ button).
    var onDismiss: () -> Void

    // MARK: State

    @State private var text: String = ""
    @State private var attachments: [ComposerAttachment] = []
    @State private var showGIFSheet   = false
    @State private var showStickerSheet = false
    @State private var isShakingEmpty = false
    @FocusState private var isFocused: Bool

    private let maxCharacters = 280

    // MARK: Derived

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty || !attachments.isEmpty
    }

    private var remaining: Int {
        maxCharacters - text.count
    }

    private var contextAuthorName: String {
        replyingToNode?.authorName ?? "the post"
    }

    private var contextUsername: String {
        if let username = replyingToNode?.authorUsername {
            return "@\(username)"
        }
        return "@\(replyingToNode?.authorName ?? "post")"
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Hairline separator
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(height: 0.5)

            VStack(spacing: 8) {
                // Reply context label (if replying to someone specific)
                if replyingToNode != nil {
                    replyContextBanner
                }

                // Main composer row
                composerRow

                // Attachment rail
                if !attachments.isEmpty {
                    attachmentRail
                }

                // Character counter (visible when <= 60 chars remain)
                if remaining <= 60 {
                    HStack {
                        Spacer()
                        Text("\(remaining)")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(
                                remaining < 0 ? AmenTheme.Colors.statusError
                                : remaining <= 20 ? AmenTheme.Colors.statusWarning
                                : AmenTheme.Colors.textTertiary
                            )
                            .monospacedDigit()
                            .padding(.trailing, 16)
                    }
                }
            }
            .padding(.vertical, 10)
            .background(AmenTheme.Colors.surfaceElevated)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showGIFSheet) {
            ComposerGIFPickerSheet { gifAttachment in
                withAnimation(Motion.adaptive(Motion.appearEase)) {
                    attachments.append(.gif(gifAttachment))
                }
                showGIFSheet = false
            }
        }
        .sheet(isPresented: $showStickerSheet) {
            ComposerStickerPickerSheet { stickerAttachment in
                withAnimation(Motion.adaptive(Motion.appearEase)) {
                    attachments.append(.sticker(stickerAttachment))
                }
                showStickerSheet = false
            }
        }
        .onAppear {
            // Auto-focus when the composer slides in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFocused = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Reply Context Banner

    private var replyContextBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 11))
                .foregroundStyle(AmenTheme.Colors.amenBlue)

            Text("Replying to \(contextUsername)")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)

            Spacer()

            // Dismiss context
            Button {
                HapticManager.impact(style: .light)
                withAnimation(Motion.adaptive(Motion.appearEase)) {
                    onDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss reply context")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Composer Row

    private var composerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // Current user avatar
            currentUserAvatar

            // Text field + attachment controls
            HStack(alignment: .center, spacing: 6) {
                TextField(
                    "Reply…",
                    text: $text,
                    axis: .vertical
                )
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1...3)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    // Enforce 280-char limit
                    if newValue.count > maxCharacters {
                        text = String(newValue.prefix(maxCharacters))
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 10)
                .accessibilityLabel(
                    "Reply text field, replying to \(replyingToNode?.authorName ?? "post") context"
                )

                // Attachment buttons (compact) — only when text field is focused
                if isFocused {
                    HStack(spacing: 4) {
                        // GIF
                        Button {
                            isFocused = false
                            HapticManager.impact(style: .light)
                            showGIFSheet = true
                        } label: {
                            Text("GIF")
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AmenTheme.Colors.surfaceChip)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add GIF")

                        // Sticker
                        Button {
                            isFocused = false
                            HapticManager.impact(style: .light)
                            showStickerSheet = true
                        } label: {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 14))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add sticker")
                    }
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.pill, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.pill, style: .continuous)
                    .strokeBorder(
                        AmenTheme.Colors.glassStroke,
                        lineWidth: 0.5
                    )
            )
            .shakeOnError(isShakingEmpty)

            // Send button
            sendButton
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Current User Avatar

    private var currentUserAvatar: some View {
        Group {
            if let photoURL = Auth.auth().currentUser?.photoURL {
                CachedAsyncImage(url: photoURL) { img in
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                } placeholder: {
                    defaultAvatar
                }
            } else {
                defaultAvatar
            }
        }
        .frame(width: 34, height: 34)
    }

    private var defaultAvatar: some View {
        let displayName = Auth.auth().currentUser?.displayName ?? "Me"
        let initials = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()

        return Circle()
            .fill(
                LinearGradient(
                    colors: [AmenTheme.Colors.amenBlue.opacity(0.7),
                             AmenTheme.Colors.amenPurple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 34)
            .overlay(
                Text(initials.isEmpty ? "ME" : initials)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.white)
            )
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            guard canSend else {
                // Shake + haptic if tried to send empty
                HapticManager.notification(type: .error)
                withAnimation(Motion.shakeLinear) { isShakingEmpty = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isShakingEmpty = false }
                return
            }
            HapticManager.notification(type: .success)
            let capturedText = trimmedText
            let capturedAttachments = attachments
            text = ""
            attachments = []
            isFocused = false
            onSend(capturedText, capturedAttachments)
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(canSend ? .white : AmenTheme.Colors.textTertiary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(canSend ? AmenTheme.Colors.amenBlue : AmenTheme.Colors.surfaceChip)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(Motion.adaptive(Motion.popToggle), value: canSend)
        .accessibilityLabel("Send reply")
        .accessibilityHint(canSend ? "Sends your reply" : "Type something first")
    }

    // MARK: - Attachment Rail

    private var attachmentRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        withAnimation(Motion.adaptive(Motion.appearEase)) {
                            attachments.removeAll { $0.id == attachment.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - AttachmentChip

private struct AttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            attachmentIcon
            Text(attachmentLabel)
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)

            Button {
                HapticManager.impact(style: .light)
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(AmenTheme.Colors.surfaceChip)
        )
    }

    @ViewBuilder
    private var attachmentIcon: some View {
        switch attachment.kind {
        case .gif:
            Text("GIF")
                .font(AMENFont.semiBold(10))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        case .sticker:
            Image(systemName: "face.smiling")
                .font(.system(size: 12))
                .foregroundStyle(AmenTheme.Colors.amenGold)
        default:
            Image(systemName: "paperclip")
                .font(.system(size: 12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    private var attachmentLabel: String {
        switch attachment.kind {
        case .gif:     return attachment.gif?.title ?? "GIF"
        case .sticker: return "Sticker"
        default:       return attachment.kind.rawValue.capitalized
        }
    }
}

// ComposerGIFPickerSheet and ComposerStickerPickerSheet are in SocialLayer/
// and are used directly — no shims needed.
