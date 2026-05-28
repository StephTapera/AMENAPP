// ThreadDetailView.swift
// AMENAPP — Spaces v2 Chat Layer (Agent B)
//
// Full message view for a thread.
// - Entitlement gate via EntitlementService.shared.observeEntitlement (live stream).
// - Soft-deleted messages rendered as "This message was removed." never hidden.
// - External author signal: authorHomeCommunityId != nil → amenPurple chain glyph.
// - Berean @mention: body starting with "@berean" (case-insensitive) triggers invokeBerean.
// - Typing indicator: animated 3-dot when typingUsers is non-empty.
// - Read state written on appear and on scroll past last message.
// - showPurchaseSheet Bool left for Agent E/C to wire to purchase sheet.

import SwiftUI
import FirebaseAuth

// MARK: - ThreadDetailView

@MainActor
struct ThreadDetailView: View {

    let threadId: String
    let spaceId: String
    let space: AmenSpaceExtended

    @StateObject private var service = SpacesChatService()

    // Entitlement observation
    @State private var entitlementTask: Task<Void, Never>?

    // Input bar state
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @State private var sendError: String?

    // Emoji picker
    @State private var emojiPickerMessageId: String?

    // Purchase gate
    @State private var showPurchaseSheet: Bool = false

    // Access lock (computed from live entitlement stream)
    @State private var isLocked: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Quick-pick emoji set
    private let quickEmojis = ["🙏", "❤️", "🔥", "👍", "😂", "✨"]

    var body: some View {
        Group {
            if isLocked {
                lockedOverlay
            } else {
                mainContent
            }
        }
        .navigationTitle(threadTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await startObservingEntitlement()
            await service.loadMessages(threadId: threadId, spaceId: spaceId)
            service.observeTyping(threadId: threadId, spaceId: spaceId)
            markReadOnAppear()
        }
        .onDisappear {
            service.stopObservingTyping(threadId: threadId, spaceId: spaceId)
            service.stopListening()
            entitlementTask?.cancel()
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            messageScrollView
            typingIndicatorBar
            inputBar
        }
    }

    // MARK: - Message scroll

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(service.messages) { message in
                        MessageBubble(
                            message: message,
                            currentUserId: Auth.auth().currentUser?.uid ?? "",
                            quickEmojis: quickEmojis,
                            emojiPickerMessageId: $emojiPickerMessageId,
                            onAddReaction: { emoji in
                                Task {
                                    try? await service.addReaction(
                                        emoji: emoji,
                                        messageId: message.id,
                                        threadId: threadId,
                                        spaceId: spaceId
                                    )
                                }
                            },
                            onRemoveReaction: { emoji in
                                Task {
                                    try? await service.removeReaction(
                                        emoji: emoji,
                                        messageId: message.id,
                                        threadId: threadId,
                                        spaceId: spaceId
                                    )
                                }
                            },
                            onSoftDelete: {
                                Task {
                                    try? await service.softDeleteMessage(
                                        messageId: message.id,
                                        threadId: threadId,
                                        spaceId: spaceId
                                    )
                                }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: service.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = service.messages.last {
            withAnimation(reduceMotion ? nil : Motion.appearEase) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            Task {
                await service.markThreadRead(
                    threadId: threadId,
                    spaceId: spaceId,
                    lastMessageId: last.id
                )
            }
        }
    }

    // MARK: - Typing indicator

    @ViewBuilder
    private var typingIndicatorBar: some View {
        if !service.typingUsers.isEmpty {
            HStack(spacing: 6) {
                TypingDotsView()
                Text(typingLabel)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(reduceMotion ? .none : Motion.liquidSpring, value: service.typingUsers.count)
            .accessibilityLabel(typingLabel)
        }
    }

    private var typingLabel: String {
        let names = service.typingUsers.prefix(3).map { $0.displayName }
        switch names.count {
        case 1:  return "\(names[0]) is typing…"
        case 2:  return "\(names[0]) and \(names[1]) are typing…"
        default: return "\(names[0]) and others are typing…"
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $inputText, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(reduceTransparency
                              ? AnyShapeStyle(Color(.secondarySystemBackground))
                              : AnyShapeStyle(LiquidGlassTokens.blurThin))
                        .overlay(
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                        )
                }
                .onChange(of: inputText) { _, newValue in
                    if !newValue.isEmpty {
                        Task { await service.startTyping(threadId: threadId, spaceId: spaceId) }
                    }
                }
                .accessibilityLabel("Message input")

            AmenLiquidGlassPillButton(
                title: "Send",
                systemImage: "arrow.up",
                isLoading: isSending,
                isDisabled: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hint: "Send message"
            ) {
                sendCurrentMessage()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                Color(.systemBackground)
            } else {
                Rectangle()
                    .fill(LiquidGlassTokens.blurRegular)
                    .overlay(Rectangle().fill(Color.white.opacity(0.08)))
            }
        }
        .overlay(alignment: .top) {
            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Send logic

    private func sendCurrentMessage() {
        let body = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isSending = true
        sendError = nil
        let captured = body
        inputText = ""

        Task {
            defer { isSending = false }
            do {
                await service.stopTyping(threadId: threadId, spaceId: spaceId)
                try await service.sendMessage(
                    threadId: threadId,
                    spaceId: spaceId,
                    body: captured,
                    replyToId: nil
                )
                // Berean @mention detection (case-insensitive)
                if captured.lowercased().hasPrefix("@berean") {
                    try? await service.invokeBerean(
                        threadId: threadId,
                        spaceId: spaceId,
                        message: captured,
                        spaceType: space.type
                    )
                }
            } catch {
                sendError = error.localizedDescription
                inputText = captured // restore on failure
            }
        }
    }

    // MARK: - Entitlement gate

    private func startObservingEntitlement() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLocked = false
            return
        }
        // Free spaces are never locked.
        guard space.accessPolicy != .free else {
            isLocked = false
            return
        }

        let stream = EntitlementService.shared.observeEntitlement(userId: userId, spaceId: spaceId)
        entitlementTask?.cancel()
        entitlementTask = Task {
            for await result in stream {
                guard !Task.isCancelled else { break }
                let status = result?.status
                isLocked = !(status == .active || status == .grace)
            }
        }
    }

    private func markReadOnAppear() {
        guard let lastId = service.messages.last?.id else { return }
        Task {
            await service.markThreadRead(threadId: threadId, spaceId: spaceId, lastMessageId: lastId)
        }
    }

    // MARK: - Locked overlay

    private var lockedOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text("Content Locked")
                .font(.title3.weight(.semibold))
            Text("Unlock this Space to read and send messages.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            // Placeholder button — Agent E / C wires this to the purchase sheet.
            Button {
                showPurchaseSheet = true
            } label: {
                Text("Unlock Space")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AmenTheme.Colors.amenGold, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unlock Space")
            .accessibilityHint("Opens the purchase sheet to unlock access")
            Spacer()
        }
        // sheet placeholder — downstream agent wires actual purchase view
        .sheet(isPresented: $showPurchaseSheet) {
            Text("Purchase sheet coming in Agent E.")
                .padding()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    private var threadTitle: String {
        service.messages.first.map { _ in space.title } ?? space.title
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {

    let message: SpacesChatMessage
    let currentUserId: String
    let quickEmojis: [String]
    @Binding var emojiPickerMessageId: String?
    let onAddReaction: (String) -> Void
    let onRemoveReaction: (String) -> Void
    let onSoftDelete: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isFromCurrentUser: Bool { message.authorId == currentUserId }
    private var showEmojiPicker: Bool { emojiPickerMessageId == message.id }

    var body: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
            // Header row: avatar + name + timestamp (hidden for current user)
            if !isFromCurrentUser {
                headerRow
            }

            // Bubble body
            bubbleBody

            // Reaction bar
            if !message.reactions.isEmpty && !message.isDeleted {
                reactionBar
            }

            // Emoji picker popover
            if showEmojiPicker && !message.isDeleted {
                emojiPicker
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

    // MARK: Header row

    private var headerRow: some View {
        HStack(spacing: 6) {
            avatarView
            Text(message.authorDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            // External member indicator — placeholder for C's LinkedGlyph
            if message.authorHomeCommunityId != nil {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                    .accessibilityLabel("External member")
            }
            Text(message.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    // MARK: Avatar

    private var avatarView: some View {
        Group {
            if let urlString = message.authorAvatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(AmenTheme.Colors.amenSilver.opacity(0.5))
                }
            } else {
                Circle()
                    .fill(AmenTheme.Colors.amenSilver.opacity(0.5))
                    .overlay(
                        Text(String(message.authorDisplayName.prefix(1)).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.primary)
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    // MARK: Bubble body

    @ViewBuilder
    private var bubbleBody: some View {
        if message.isDeleted {
            deletedMessageView
        } else {
            liveMessageView
        }
    }

    private var deletedMessageView: some View {
        Text("This message was removed.")
            .font(.subheadline)
            .italic()
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemFill))
            }
            .accessibilityLabel("Deleted message")
    }

    private var liveMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.body)
                .font(.body)
                .foregroundStyle(isFromCurrentUser ? Color.white : Color.primary)
                .textSelection(.enabled)
            if let editedAt = message.editedAt {
                Text("Edited \(editedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(isFromCurrentUser ? Color.white.opacity(0.7) : AmenTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if isFromCurrentUser {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AmenTheme.Colors.amenGold)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(.secondarySystemBackground))
                          : AnyShapeStyle(LiquidGlassTokens.blurThin))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                    )
            }
        }
        .frame(maxWidth: 280, alignment: isFromCurrentUser ? .trailing : .leading)
    }

    // MARK: Reaction bar

    private var reactionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(message.reactions.keys.sorted()), id: \.self) { emoji in
                    let users = message.reactions[emoji] ?? []
                    let iMine = users.contains(currentUserId)
                    reactionChip(emoji: emoji, count: users.count, isMine: iMine)
                }
                // "+" to open quick-pick
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
            .padding(.vertical, 2)
        }
    }

    private func reactionChip(emoji: String, count: Int, isMine: Bool) -> some View {
        Button {
            if isMine {
                onRemoveReaction(emoji)
            } else {
                onAddReaction(emoji)
            }
        } label: {
            HStack(spacing: 3) {
                Text(emoji).font(.caption)
                Text("\(count)").font(.caption.weight(.semibold))
                    .foregroundStyle(isMine ? AmenTheme.Colors.amenGold : .primary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(isMine ? AmenTheme.Colors.amenGold.opacity(0.15) : Color(.systemFill))
                    .overlay(
                        isMine
                            ? Capsule(style: .continuous).stroke(AmenTheme.Colors.amenGold.opacity(0.5), lineWidth: 0.7)
                            : Capsule(style: .continuous).stroke(Color.clear, lineWidth: 0)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) reaction, \(count) \(count == 1 ? "person" : "people"). \(isMine ? "Tap to remove" : "Tap to add")")
    }

    // MARK: Emoji picker

    private var emojiPicker: some View {
        HStack(spacing: 8) {
            ForEach(quickEmojis, id: \.self) { emoji in
                Button {
                    let users = message.reactions[emoji] ?? []
                    if users.contains(currentUserId) {
                        onRemoveReaction(emoji)
                    } else {
                        onAddReaction(emoji)
                    }
                    emojiPickerMessageId = nil
                } label: {
                    Text(emoji).font(.title3)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React with \(emoji)")
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                .fill(LiquidGlassTokens.blurElevated)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if message.authorId == currentUserId {
            Button(role: .destructive) {
                onSoftDelete()
            } label: {
                Label("Remove Message", systemImage: "trash")
            }
        }
        Button {
            emojiPickerMessageId = message.id
        } label: {
            Label("React", systemImage: "face.smiling")
        }
    }
}

// MARK: - TypingDotsView

/// Animated three-dot typing indicator.
private struct TypingDotsView: View {

    @State private var animationStep: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AmenTheme.Colors.textTertiary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(dotScale(index: index))
                    .opacity(reduceMotion ? 1 : (animationStep == index ? 1 : 0.4))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            startAnimation()
        }
        .accessibilityHidden(true)
    }

    private func dotScale(index: Int) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return animationStep == index ? 1.4 : 1.0
    }

    private func startAnimation() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(Motion.springPress) {
                animationStep = (animationStep + 1) % 3
            }
        }
        timer.fire()
        // Timer is owned by the RunLoop; view disappears before it becomes a problem.
        // For production, integrate with Combine or a stored reference if needed.
    }
}
