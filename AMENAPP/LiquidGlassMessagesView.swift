//
//  LiquidGlassMessagesView.swift
//  AMENAPP
//
//  Liquid Glass conversation UI with AMEN-specific features:
//  - Frosted glass message bubbles with custom shapes
//  - AMEN reaction system (🙏❤️‍🔥✝️🕊️😭🙌)
//  - Special message types (Prayer, Testimony, Scripture)
//  - Animated background with drifting orbs
//  - Floating glass input bar with morphing send button
//

import SwiftUI
import FirebaseAuth
import PhotosUI
import AVFoundation

// MARK: - Message Model

struct AMENMessage: Identifiable, Codable {
    let id: String
    let text: String
    let senderId: String
    let senderName: String
    let senderAvatar: String?
    let timestamp: Date
    let type: MessageType
    var reactions: [String: [String]] // emoji: [userIds]
    let quotedMessageId: String?

    enum MessageType: String, Codable {
        case standard
        case prayer
        case testimony
        case scripture
    }

    var isFromCurrentUser: Bool {
        senderId == Auth.auth().currentUser?.uid
    }
}

// MARK: - Liquid Glass Messages View

struct LiquidGlassMessagesView: View {
    let conversationTitle: String
    let conversationSubtitle: String

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [AMENMessage] = []
    @State private var messageText = ""
    @State private var isTyping = false
    @State private var selectedMessageForReaction: String?
    @State private var quotedMessage: AMENMessage?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardObserverTokens: [NSObjectProtocol] = []
    @State private var showConversationInfo = false
    @State private var showVideoCallAlert = false
    @State private var pendingMessageType: AMENMessage.MessageType = .standard
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @Namespace private var reactionNamespace
    @Namespace private var sendButtonNamespace

    var body: some View {
        ZStack {
            // Animated background with drifting orbs
            AnimatedMeshBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar
                liquidGlassNavigationBar

                // Messages scroll view
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubbleView(
                                    message: message,
                                    selectedForReaction: selectedMessageForReaction == message.id,
                                    namespace: reactionNamespace,
                                    onReactionTap: { emoji in
                                        toggleReaction(messageId: message.id, emoji: emoji)
                                    },
                                    onLongPress: {
                                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                            selectedMessageForReaction = message.id
                                        }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                                    },
                                    onQuoteReply: {
                                        quotedMessage = message
                                    }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                }
                .simultaneousGesture(
                    TapGesture().onEnded { _ in
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                            selectedMessageForReaction = nil
                        }
                    }
                )

                // Floating input bar
                LiquidGlassInputBar(
                    text: $messageText,
                    isTyping: $isTyping,
                    quotedMessage: quotedMessage,
                    namespace: sendButtonNamespace,
                    onSend: sendMessage,
                    onClearQuote: { quotedMessage = nil },
                    onAttachmentRequested: handleAttachment,
                    onSendVoice: handleVoiceMessage
                )
                .padding(.bottom, max(0, keyboardHeight - 34))
            }
        }
        .onAppear {
            setupKeyboardObservers()
            loadMockMessages()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
        .alert("Video Calls Coming Soon", isPresented: $showVideoCallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Video calling will be available in a future AMEN update.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            guard item != nil else { return }
            let msg = AMENMessage(
                id: UUID().uuidString,
                text: "📸 Photo",
                senderId: Auth.auth().currentUser?.uid ?? "",
                senderName: Auth.auth().currentUser?.displayName ?? "You",
                senderAvatar: nil,
                timestamp: Date(),
                type: .standard,
                reactions: [:],
                quotedMessageId: nil
            )
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.72))) {
                messages.append(msg)
            }
            selectedPhotoItem = nil
        }
        .sheet(isPresented: $showConversationInfo) {
            NavigationStack {
                VStack(spacing: 20) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.purple)
                        .padding(.top, 32)
                    VStack(spacing: 6) {
                        Text(conversationTitle)
                            .font(.title2.weight(.bold))
                        Text(conversationSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .navigationTitle("Conversation Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showConversationInfo = false }
                    }
                }
            }
        }
    }

    // MARK: - Navigation Bar

    private var liquidGlassNavigationBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversationTitle)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(conversationSubtitle)
                        .font(.systemScaled(12))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showVideoCallAlert = true
                } label: {
                    Image(systemName: "video.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(.white)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showConversationInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.systemScaled(18))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                ShimmerLine()
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let newMessage = AMENMessage(
            id: UUID().uuidString,
            text: messageText,
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: Auth.auth().currentUser?.displayName ?? "You",
            senderAvatar: nil,
            timestamp: Date(),
            type: pendingMessageType,
            reactions: [:],
            quotedMessageId: quotedMessage?.id
        )

        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.72))) {
            messages.append(newMessage)
        }

        messageText = ""
        quotedMessage = nil
        pendingMessageType = .standard

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollProxy?.scrollTo(newMessage.id, anchor: .bottom)
            }
        }
    }

    private func handleAttachment(_ type: MessageAttachmentType) {
        switch type {
        case .photoLibrary, .camera:
            showPhotoPicker = true
        case .prayerRequest:
            pendingMessageType = .prayer
        case .scripture:
            pendingMessageType = .scripture
        default:
            break
        }
    }

    private func handleVoiceMessage(_ url: URL) {
        let msg = AMENMessage(
            id: UUID().uuidString,
            text: "🎙️ Voice message",
            senderId: Auth.auth().currentUser?.uid ?? "",
            senderName: Auth.auth().currentUser?.displayName ?? "You",
            senderAvatar: nil,
            timestamp: Date(),
            type: .standard,
            reactions: [:],
            quotedMessageId: nil
        )
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.72))) {
            messages.append(msg)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation { scrollProxy?.scrollTo(msg.id, anchor: .bottom) }
        }
    }

    private func toggleReaction(messageId: String, emoji: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        var updatedMessage = messages[index]
        var emojiReactions = updatedMessage.reactions[emoji] ?? []

        if emojiReactions.contains(currentUserId) {
            emojiReactions.removeAll { $0 == currentUserId }
        } else {
            emojiReactions.append(currentUserId)
        }

        if emojiReactions.isEmpty {
            updatedMessage.reactions.removeValue(forKey: emoji)
        } else {
            updatedMessage.reactions[emoji] = emojiReactions
        }

        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            messages[index] = updatedMessage
        }

        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        selectedMessageForReaction = nil
    }

    private func loadMockMessages() {
        messages = [
            AMENMessage(id: "1", text: "Hey! How are you doing today?", senderId: "other", senderName: "Sarah", senderAvatar: nil, timestamp: Date().addingTimeInterval(-3600), type: .standard, reactions: [:], quotedMessageId: nil),
            AMENMessage(id: "2", text: "I'm doing well, thank you! Just finished my morning devotional.", senderId: Auth.auth().currentUser?.uid ?? "", senderName: "You", senderAvatar: nil, timestamp: Date().addingTimeInterval(-3500), type: .standard, reactions: [:], quotedMessageId: nil),
            AMENMessage(id: "3", text: "Please pray for my job interview tomorrow. Feeling a bit anxious about it.", senderId: "other", senderName: "Sarah", senderAvatar: nil, timestamp: Date().addingTimeInterval(-3400), type: .prayer, reactions: ["🙏": ["current"], "❤️‍🔥": ["current"]], quotedMessageId: nil),
            AMENMessage(id: "4", text: "Absolutely! 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.' - Philippians 4:6", senderId: Auth.auth().currentUser?.uid ?? "", senderName: "You", senderAvatar: nil, timestamp: Date().addingTimeInterval(-3300), type: .scripture, reactions: ["✝️": ["other"], "🙌": ["other"]], quotedMessageId: nil),
        ]
    }

    private func setupKeyboardObservers() {
        let showToken = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = frame.height
                }
            }
        }
        let hideToken = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
        keyboardObserverTokens.append(contentsOf: [showToken, hideToken])
    }

    private func removeKeyboardObservers() {
        keyboardObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        keyboardObserverTokens.removeAll()
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: AMENMessage
    let selectedForReaction: Bool
    let namespace: Namespace.ID
    let onReactionTap: (String) -> Void
    let onLongPress: () -> Void
    let onQuoteReply: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !message.isFromCurrentUser {
                // Avatar for incoming messages
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.systemScaled(16))
                            .foregroundStyle(.white.opacity(0.6))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                Spacer()
            }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Message bubble
                messageBubbleContent
                    .scaleEffect(appeared ? 1.0 : 0.85)
                    .opacity(appeared ? 1.0 : 0)
                    .offset(y: appeared ? 0 : 10)

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.systemScaled(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .opacity(appeared ? 1.0 : 0)

                // Reactions
                if !message.reactions.isEmpty {
                    reactionsPill
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if message.isFromCurrentUser {
                Spacer()
            }
        }
        .overlay(alignment: message.isFromCurrentUser ? .topTrailing : .topLeading) {
            if selectedForReaction {
                ReactionBar(
                    namespace: namespace,
                    onSelect: { emoji in
                        onReactionTap(emoji)
                    }
                )
                .offset(y: -60)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.72)).delay(0.05)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var messageBubbleContent: some View {
        let bubbleContent = Text(message.text)
            .font(.systemScaled(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                BubbleShape(isOutgoing: message.isFromCurrentUser)
                    .fill(.clear)
                    .background(.ultraThinMaterial)
                    .background(bubbleGradient)
                    .overlay(bubbleBorder)
                    .overlay(bubbleGlow)
                    .clipShape(BubbleShape(isOutgoing: message.isFromCurrentUser))
            }

        switch message.type {
        case .standard:
            bubbleContent
                .onLongPressGesture(minimumDuration: 0.3) {
                    onLongPress()
                }
        case .prayer:
            prayerBubble(bubbleContent)
        case .testimony:
            testimonyBubble(bubbleContent)
        case .scripture:
            scriptureBubble(bubbleContent)
        }
    }

    private var bubbleGradient: some View {
        LinearGradient(
            colors: message.isFromCurrentUser
                ? [Color(red: 0.47, green: 0.31, blue: 1.0).opacity(0.18), Color(red: 0.47, green: 0.31, blue: 1.0).opacity(0.12)]
                : [Color(red: 1.0, green: 0.94, blue: 0.82).opacity(0.12), Color(red: 1.0, green: 0.94, blue: 0.82).opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleBorder: some View {
        BubbleShape(isOutgoing: message.isFromCurrentUser)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.4), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }

    private var bubbleGlow: some View {
        Rectangle()
            .fill(.clear)
            .shadow(color: .white.opacity(0.15), radius: 6, x: 0, y: 1)
    }

    // MARK: - Special Message Types

    private func prayerBubble(_ content: some View) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .padding(8)
            }
            .overlay {
                BubbleShape(isOutgoing: message.isFromCurrentUser)
                    .stroke(
                        Color.orange.opacity(0.4),
                        lineWidth: 1
                    )
                    .scaleEffect(appeared ? 1.0 : 0.95)
                    .opacity(appeared ? 1.0 : 0.5)
                    .animation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true), value: appeared)
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                onLongPress()
            }
    }

    private func testimonyBubble(_ content: some View) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(8)
            }
            .overlay {
                BubbleShape(isOutgoing: message.isFromCurrentUser)
                    .stroke(
                        LinearGradient(
                            colors: [.yellow.opacity(0.6), .orange.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                onLongPress()
            }
    }

    private func scriptureBubble(_ content: some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.purple)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .background {
            Image(systemName: "cross.fill")
                .font(.systemScaled(60))
                .foregroundStyle(.white.opacity(0.05))
                .offset(x: 20, y: 10)
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            onLongPress()
        }
    }

    private var reactionsPill: some View {
        HStack(spacing: 6) {
            ForEach(Array(message.reactions.keys.sorted()), id: \.self) { emoji in
                if let users = message.reactions[emoji], !users.isEmpty {
                    Button {
                        onReactionTap(emoji)
                    } label: {
                        HStack(spacing: 3) {
                            Text(emoji)
                                .font(.systemScaled(12))
                            Text("\(users.count)")
                                .font(.systemScaled(10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Reaction Bar

struct ReactionBar: View {
    let namespace: Namespace.ID
    let onSelect: (String) -> Void

    private let reactions = ["🙏", "❤️‍🔥", "✝️", "🕊️", "😭", "🙌"]
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(reactions.enumerated()), id: \.offset) { index, emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.systemScaled(28))
                        .scaleEffect(appeared ? 1.0 : 0.3)
                        .opacity(appeared ? 1.0 : 0)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.35, dampingFraction: 0.65).delay(Double(index) * 0.05), value: appeared)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 22
        let tailSize: CGFloat = 8

        if isOutgoing {
            // Outgoing bubble (tail on bottom-right)
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius - tailSize))

            // Tail
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 4, y: rect.maxY),
                            control: CGPoint(x: rect.maxX + 4, y: rect.maxY - 4))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - tailSize - 4, y: rect.maxY - 4),
                            control: CGPoint(x: rect.maxX - 8, y: rect.maxY + 2))

            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Incoming bubble (tail on bottom-left)
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

            // Tail
            path.addLine(to: CGPoint(x: rect.minX + tailSize + 4, y: rect.maxY - 4))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.maxY),
                            control: CGPoint(x: rect.minX + 8, y: rect.maxY + 2))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius - tailSize),
                            control: CGPoint(x: rect.minX - 4, y: rect.maxY - 4))

            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Input Bar

struct LiquidGlassInputBar: View {
    @Binding var text: String
    @Binding var isTyping: Bool
    let quotedMessage: AMENMessage?
    let namespace: Namespace.ID
    let onSend: () -> Void
    let onClearQuote: () -> Void
    let onAttachmentRequested: (MessageAttachmentType) -> Void
    let onSendVoice: (URL) -> Void

    @FocusState private var isFocused: Bool
    @State private var showAttachmentOptions = false
    @State private var isRecordingVoice = false
    @State private var voiceRecorder: AVAudioRecorder? = nil
    @State private var recordingURL: URL? = nil

    private let quickReplies = ["🙏 Praying for you", "❤️ Amen!", "✝️ This is powerful"]

    var body: some View {
        VStack(spacing: 0) {
            // Quick replies (when focused)
            if isFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickReplies, id: \.self) { reply in
                            Button {
                                text = reply
                                onSend()
                                isFocused = false
                            } label: {
                                Text(reply)
                                    .font(.systemScaled(13))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Quoted message preview
            if let quoted = quotedMessage {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(quoted.senderName)
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(quoted.text)
                            .font(.systemScaled(13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        onClearQuote()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input bar
            HStack(spacing: 12) {
                // Attachment button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAttachmentOptions = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .buttonStyle(.plain)

                // Text field
                TextField("Share, pray, encourage...", text: $text, axis: .vertical)
                    .font(.systemScaled(15))
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        isTyping = !newValue.isEmpty
                    }

                // Send / Mic button
                if isTyping {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.purple, Color.orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .matchedGeometryEffect(id: "sendButton", in: namespace)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                        if isRecordingVoice {
                            stopVoiceRecording()
                        } else {
                            startVoiceRecording()
                        }
                    } label: {
                        ZStack {
                            if isRecordingVoice {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .scaleEffect(isRecordingVoice ? 1.15 : 1.0)
                                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isRecordingVoice)
                            }
                            Image(systemName: isRecordingVoice ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.systemScaled(28))
                                .foregroundStyle(
                                    isRecordingVoice
                                        ? LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .matchedGeometryEffect(id: "sendButton", in: namespace)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(28)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: -4)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .confirmationDialog("Add to Message", isPresented: $showAttachmentOptions, titleVisibility: .visible) {
            Button("📸 Photo or Video") { onAttachmentRequested(.photoLibrary) }
            Button("🙏 Mark as Prayer Request") { onAttachmentRequested(.prayerRequest) }
            Button("✝️ Mark as Scripture") { onAttachmentRequested(.scripture) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func startVoiceRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try? session.setActive(true)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        if let recorder = try? AVAudioRecorder(url: tempURL, settings: settings) {
            recorder.record()
            voiceRecorder = recorder
            recordingURL = tempURL
            withAnimation { isRecordingVoice = true }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    private func stopVoiceRecording() {
        voiceRecorder?.stop()
        withAnimation { isRecordingVoice = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
        if let url = recordingURL {
            onSendVoice(url)
            recordingURL = nil
            voiceRecorder = nil
        }
    }
}

// MARK: - Animated Background

struct AnimatedMeshBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Drifting orbs
            Canvas { context, size in
                let orbs: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: Color)] = [
                    (size.width * 0.2 + sin(phase) * 30, size.height * 0.3 + cos(phase * 0.8) * 40, 120, Color.purple.opacity(0.15)),
                    (size.width * 0.7 + cos(phase * 1.2) * 40, size.height * 0.6 + sin(phase) * 30, 100, Color.orange.opacity(0.12)),
                    (size.width * 0.5 + sin(phase * 0.9) * 35, size.height * 0.8 + cos(phase * 1.1) * 25, 90, Color.purple.opacity(0.1)),
                ]

                for orb in orbs {
                    let rect = CGRect(x: orb.x - orb.radius, y: orb.y - orb.radius, width: orb.radius * 2, height: orb.radius * 2)
                    context.fill(Ellipse().path(in: rect), with: .color(orb.color))
                }
            }
            .blur(radius: 80)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Shimmer Line

struct ShimmerLine: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.3), location: phase - 0.1),
                            .init(color: .white.opacity(0.6), location: phase),
                            .init(color: .white.opacity(0.3), location: phase + 0.1),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .frame(height: 1)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LiquidGlassMessagesView(
        conversationTitle: "Prayer Warriors",
        conversationSubtitle: "(Prayer Thread)"
    )
}
