// SpacesChatView.swift
// AMENAPP — Spaces Chat Core (Agent B)
//
// The chat render surface that Agent C embeds into SpaceDetailView.
//
// How Agent C embeds this view:
//   SpacesChatView(viewModel: chatVM, spaceId: space.spaceId)
//
// Responsibilities:
//   - Message list with: author avatar (exposes authorHomeCommunityId), body,
//     timestamp, reactions row (data only), soft-deleted tombstone.
//   - Composer: text field + send button.
//   - Typing indicator bar (animated 3-dot when typingUserIds is non-empty).
//   - Does NOT implement the paywall — caller handles the entitlement gate.
//
// Design tokens: AmenTheme (AmenTheme.swift) — no local color literals.
// No Combine. No hard-deletes.
//
// Types:
//   SpacesChatMessage    — AMENAPP/Spaces/Chat/SpacesChatModels.swift
//   SpacesChatMessageRow — this file (renamed to avoid conflict with PrivateCommunitiesView.ChatMessageRow)

import SwiftUI
import FirebaseAuth

// MARK: - SpacesChatView

@MainActor
struct SpacesChatView: View {

    @ObservedObject var viewModel: SpacesChatViewModel
    let spaceId: String

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let quickEmojiChars = ["🙏", "❤️", "🔥", "👍", "😂", "✨"]

    @State private var emojiPickerMessageId: String?

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            messageList
            typingBar
            composerBar
        }
        .background(AmenTheme.Colors.backgroundPrimary)
        .task {
            await viewModel.loadSpace(spaceId: spaceId)
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.messages) { message in
                        SpacesChatMessageRow(
                            message: message,
                            currentUserId: Auth.auth().currentUser?.uid ?? "",
                            quickEmojis: quickEmojiChars,
                            emojiPickerMessageId: $emojiPickerMessageId,
                            onToggleReaction: { emoji in
                                Task {
                                    await viewModel.toggleReaction(
                                        emoji: emoji, messageId: message.id)
                                }
                            },
                            onSoftDelete: {
                                Task { await viewModel.softDeleteMessage(id: message.id) }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        viewModel.markActiveThreadRead()
    }

    // MARK: - Typing Indicator Bar

    @ViewBuilder
    private var typingBar: some View {
        if !viewModel.typingUserIds.isEmpty {
            HStack(spacing: 6) {
                SpacesChatTypingDotsView()
                Text(typingLabel)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(
                reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8),
                value: viewModel.typingUserIds.count
            )
            .accessibilityLabel(typingLabel)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var typingLabel: String {
        switch viewModel.typingUserIds.count {
        case 1:  return "Someone is typing..."
        case 2:  return "2 people are typing..."
        default: return "Several people are typing..."
        }
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            composerTextField
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                Color(.systemBackground)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(AmenTheme.Colors.glassFill))
            }
        }
        .overlay(errorBanner, alignment: .top)
    }

    private var composerTextField: some View {
        TextField("Message...", text: $viewModel.draftBody, axis: .vertical)
            .font(.body)
            .lineLimit(1...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
            }
            .onChange(of: viewModel.draftBody) { _, newValue in
                if newValue.isEmpty {
                    viewModel.stopTyping()
                } else {
                    viewModel.startTyping()
                }
            }
            .accessibilityLabel("Message input")
            .accessibilityHint("Type your message here")
    }

    private var isSendable: Bool {
        !viewModel.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButton: some View {
        Button {
            sendMessage()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    isSendable ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textTertiary,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!isSendable)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSendable)
        .accessibilityLabel("Send message")
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.error {
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.statusError)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Send

    private func sendMessage() {
        let body = viewModel.draftBody
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.stopTyping()
        Task { await viewModel.sendMessage(body: body) }
    }
}

// MARK: - SpacesChatMessageRow

/// Single message bubble.
/// Renamed `SpacesChatMessageRow` (not `ChatMessageRow`) to avoid conflict with
/// the existing `ChatMessageRow` in `PrivateCommunitiesView.swift`.
///
/// `message.authorHomeCommunityId` is non-nil for external/cross-community authors.
/// Agent C replaces the placeholder link.circle.fill glyph with its LinkedGlyph component.
@MainActor
struct SpacesChatMessageRow: View {

    let message: SpacesChatMessage
    let currentUserId: String
    let quickEmojis: [String]
    @Binding var emojiPickerMessageId: String?
    let onToggleReaction: (String) -> Void
    let onSoftDelete: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isFromCurrentUser: Bool { message.authorId == currentUserId }
    private var showEmojiPicker: Bool { emojiPickerMessageId == message.id }

    var body: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
            if !isFromCurrentUser {
                messageHeader
            }
            messageBubble
            if !message.reactions.isEmpty, !message.isDeleted {
                reactionRow
            }
            if showEmojiPicker, !message.isDeleted {
                emojiPickerRow
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
        .padding(.vertical, 4)
        .contextMenu {
            if !message.isDeleted {
                contextMenuItems
            }
        }
    }

    // MARK: Header

    private var messageHeader: some View {
        HStack(spacing: 6) {
            authorAvatar
            Text(message.authorDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            // External member signal: authorHomeCommunityId non-nil = cross-community author.
            // Agent C replaces this with its LinkedGlyph component.
            if message.authorHomeCommunityId != nil {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .accessibilityLabel("External member from linked community")
            }
            Text(message.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    // MARK: Avatar

    /// `message.authorHomeCommunityId` is exposed here for Agent C to badge.
    private var authorAvatar: some View {
        Group {
            if let urlString = message.authorAvatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(AmenTheme.Colors.surfaceChip)
                }
            } else {
                Circle()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .overlay(
                        Text(String(message.authorDisplayName.prefix(1)).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    // MARK: Bubble

    @ViewBuilder
    private var messageBubble: some View {
        if message.isDeleted {
            tombstone
        } else {
            liveBubble
        }
    }

    private var tombstone: some View {
        Text("This message was removed.")
            .font(.subheadline)
            .italic()
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Deleted message")
    }

    private var liveBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.body)
                .font(.body)
                .foregroundStyle(isFromCurrentUser ? Color.white : AmenTheme.Colors.textPrimary)
                .textSelection(.enabled)
            if let editedAt = message.editedAt {
                Text("Edited \(editedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(
                        isFromCurrentUser ? Color.white.opacity(0.70) : AmenTheme.Colors.textTertiary
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if isFromCurrentUser {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AmenTheme.Colors.amenGold)
            } else if reduceTransparency {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                    )
            }
        }
        .frame(maxWidth: 280, alignment: isFromCurrentUser ? .trailing : .leading)
    }

    // MARK: Reaction row (data only — Agent C adds the glyph badge)

    private var reactionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(message.reactions.keys.sorted(), id: \.self) { emoji in
                    let users = message.reactions[emoji] ?? []
                    reactionChip(
                        emoji: emoji,
                        count: users.count,
                        isMine: users.contains(currentUserId)
                    )
                }
                addReactionButton
            }
            .padding(.vertical, 2)
        }
    }

    private func reactionChip(emoji: String, count: Int, isMine: Bool) -> some View {
        Button {
            onToggleReaction(emoji)
        } label: {
            HStack(spacing: 3) {
                Text(emoji).font(.caption)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isMine ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textPrimary
                    )
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                isMine ? AmenTheme.Colors.amenGold.opacity(0.15) : Color(.systemFill),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isMine ? AmenTheme.Colors.amenGold.opacity(0.5) : Color.clear,
                        lineWidth: 0.7
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(emoji) reaction, \(count) \(count == 1 ? "person" : "people"). \(isMine ? "Tap to remove" : "Tap to add")"
        )
    }

    private var addReactionButton: some View {
        Button {
            emojiPickerMessageId = showEmojiPicker ? nil : message.id
        } label: {
            Text("+")
                .font(.caption.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .frame(width: 28, height: 24)
                .background(Color(.systemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add reaction")
    }

    // MARK: Emoji picker

    private var emojiPickerRow: some View {
        HStack(spacing: 8) {
            ForEach(quickEmojis, id: \.self) { emoji in
                Button {
                    onToggleReaction(emoji)
                    emojiPickerMessageId = nil
                } label: {
                    Text(emoji)
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React with \(emoji)")
            }
        }
        .padding(8)
        .background(
            AmenTheme.Colors.surfaceElevated,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 10, y: 4)
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            emojiPickerMessageId = message.id
        } label: {
            Label("React", systemImage: "face.smiling")
        }
        if message.authorId == currentUserId {
            Button(role: .destructive) {
                onSoftDelete()
            } label: {
                Label("Remove Message", systemImage: "trash")
            }
        }
    }
}

// MARK: - SpacesChatTypingDotsView

/// Animated three-dot typing indicator for SpacesChatView.
/// Renamed `SpacesChatTypingDotsView` to avoid any future conflicts.
@MainActor
private struct SpacesChatTypingDotsView: View {

    @State private var step: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AmenTheme.Colors.textTertiary)
                    .frame(width: 5, height: 5)
                    .scaleEffect((!reduceMotion && step == i) ? 1.4 : 1.0)
                    .opacity(reduceMotion ? 1 : (step == i ? 1 : 0.4))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            animate()
        }
        .accessibilityHidden(true)
    }

    private func animate() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    step = (step + 1) % 3
                }
            }
        }
        .fire()
    }
}
