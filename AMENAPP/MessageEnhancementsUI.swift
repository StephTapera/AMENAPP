//
//  MessageEnhancementsUI.swift
//  AMENAPP
//
//  Message reactions and unread indicators with minimalist black & white design
//

import SwiftUI

// MARK: - Unread Message Divider

struct UnreadMessageDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
            
            Text("Unread Messages")
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .overlay(
                            Capsule()
                                .stroke(Color.black, lineWidth: 1)
                        )
                )
            
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Jump to Unread Button

struct JumpToUnreadButton: View {
    let unreadCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("\(unreadCount) new message\(unreadCount == 1 ? "" : "s")")
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Message Reaction Bar (Black & White)

struct MessageReactionBar: View {
    let onReactionTap: (String) -> Void
    
    // Black and white emoji set
    private let reactions = ["👍", "❤️", "😊", "🙏", "✝️", "👏"]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(reactions, id: \.self) { emoji in
                Button {
                    onReactionTap(emoji)
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Reaction Display (Below Message)

struct MessageReactionsDisplay: View {
    let reactions: [MessageReaction]
    let onReactionTap: (MessageReaction) -> Void
    
    private var groupedReactions: [(emoji: String, count: Int, users: [String])] {
        var groups: [String: (count: Int, users: [String])] = [:]
        
        for reaction in reactions {
            if var existing = groups[reaction.emoji] {
                existing.count += 1
                existing.users.append(reaction.username)
                groups[reaction.emoji] = existing
            } else {
                groups[reaction.emoji] = (count: 1, users: [reaction.username])
            }
        }
        
        return groups.map { (emoji: $0.key, count: $0.value.count, users: $0.value.users) }
            .sorted { $0.count > $1.count }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(groupedReactions, id: \.emoji) { group in
                Button {
                    // Find first reaction with this emoji and tap it
                    if let reaction = reactions.first(where: { $0.emoji == group.emoji }) {
                        onReactionTap(reaction)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(group.emoji)
                            .font(.system(size: 14))
                        
                        if group.count > 1 {
                            Text("\(group.count)")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(.black)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(
                                Capsule()
                                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Enhanced Message Bubble with Reactions

struct EnhancedMessageBubble: View {
    let message: AppMessage
    let showSenderName: Bool
    let onReact: (String) -> Void
    let onReactionTap: (MessageReaction) -> Void
    
    @State private var showReactionBar = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
            // Sender name (for group chats)
            if showSenderName && !message.isFromCurrentUser {
                Text(message.senderName ?? "Unknown")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(.leading, 12)
            }
            
            HStack(alignment: .bottom, spacing: 8) {
                if message.isFromCurrentUser {
                    Spacer()
                }
                
                VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                    // Message bubble
                    messageBubble
                    
                    // Reactions display
                    if !message.reactions.isEmpty {
                        MessageReactionsDisplay(
                            reactions: message.reactions,
                            onReactionTap: onReactionTap
                        )
                        .padding(.horizontal, 8)
                    }
                    
                    // Timestamp
                    Text(message.formattedTimestamp)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.horizontal, 12)
                }
                
                if !message.isFromCurrentUser {
                    Spacer()
                }
            }
            
            // Reaction bar (appears on long press)
            if showReactionBar {
                HStack {
                    if message.isFromCurrentUser {
                        Spacer()
                    }
                    
                    MessageReactionBar(onReactionTap: { emoji in
                        onReact(emoji)
                        withAnimation(.easeOut(duration: 0.2)) {
                            showReactionBar = false
                        }
                    })
                    .transition(.scale.combined(with: .opacity))
                    
                    if !message.isFromCurrentUser {
                        Spacer()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.3) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showReactionBar.toggle()
            }
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
    
    private var messageBubble: some View {
        Text(message.text)
            .font(.custom("OpenSans-Regular", size: 15))
            .foregroundStyle(message.isFromCurrentUser ? .white : .black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(message.isFromCurrentUser ? Color.black : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                message.isFromCurrentUser ? Color.clear : Color.black.opacity(0.15),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Messages Scroll View with Unread Tracking

struct MessagesScrollViewWithUnread: View {
    let messages: [AppMessage]
    let firstUnreadMessageId: String?
    @Binding var showJumpToUnread: Bool
    let onReact: (AppMessage, String) -> Void
    let onReactionTap: (AppMessage, MessageReaction) -> Void
    
    @State private var scrollPosition: String?
    @State private var isAtBottom = true
    
    private var unreadCount: Int {
        guard let firstUnreadId = firstUnreadMessageId,
              let firstUnreadIndex = messages.firstIndex(where: { $0.id == firstUnreadId }) else {
            return 0
        }
        return messages.count - firstUnreadIndex
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            VStack(spacing: 0) {
                                // Show unread divider before first unread message
                                if message.id == firstUnreadMessageId {
                                    UnreadMessageDivider()
                                        .id("unread_divider")
                                }
                                
                                EnhancedMessageBubble(
                                    message: message,
                                    showSenderName: shouldShowSenderName(for: message),
                                    onReact: { emoji in
                                        onReact(message, emoji)
                                    },
                                    onReactionTap: { reaction in
                                        onReactionTap(message, reaction)
                                    }
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
                .onChange(of: messages.count) { oldValue, newValue in
                    // Auto-scroll to bottom when new messages arrive
                    if newValue > oldValue, isAtBottom, let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to first unread or bottom
                    if let firstUnreadId = firstUnreadMessageId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(firstUnreadId, anchor: .top)
                            }
                        }
                    } else if let lastMessage = messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture().onChanged { value in
                        // Detect scrolling direction
                        if value.translation.height > 10 {
                            // Scrolling up - show jump to unread if applicable
                            if firstUnreadMessageId != nil {
                                showJumpToUnread = true
                            }
                        } else if value.translation.height < -10 {
                            // Scrolling down
                            showJumpToUnread = false
                        }
                    }
                )
                .background(
                    // Invisible geometry reader to track scroll position
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    // Update isAtBottom based on scroll position
                    isAtBottom = value > -50
                }
                .onChange(of: showJumpToUnread) { _, shouldShow in
                    if shouldShow, let firstUnreadId = firstUnreadMessageId {
                        // Store the scroll action
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(firstUnreadId, anchor: .top)
                            }
                        }
                    }
                }
            }
            
            // Jump to unread button
            if showJumpToUnread && firstUnreadMessageId != nil && unreadCount > 0 {
                VStack {
                    Spacer()
                    
                    JumpToUnreadButton(unreadCount: unreadCount) {
                        withAnimation {
                            showJumpToUnread = false
                            // The onChange will handle scrolling
                        }
                    }
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func shouldShowSenderName(for message: AppMessage) -> Bool {
        // Show sender name if previous message is from different sender
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return false
        }
        
        if index == 0 {
            return !message.isFromCurrentUser
        }
        
        let previousMessage = messages[index - 1]
        return previousMessage.senderId != message.senderId && !message.isFromCurrentUser
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview("Enhanced Message Bubble") {
    VStack(spacing: 20) {
        EnhancedMessageBubble(
            message: AppMessage(
                text: "Hey! How are you doing today?",
                isFromCurrentUser: false,
                timestamp: Date(),
                reactions: [
                    MessageReaction(emoji: "👍", userId: "1", username: "John"),
                    MessageReaction(emoji: "❤️", userId: "2", username: "Jane")
                ]
            ),
            showSenderName: true,
            onReact: { _ in },
            onReactionTap: { _ in }
        )
        
        EnhancedMessageBubble(
            message: AppMessage(
                text: "I'm great! Just working on some cool features.",
                isFromCurrentUser: true,
                timestamp: Date(),
                reactions: [
                    MessageReaction(emoji: "🙏", userId: "3", username: "Mike")
                ]
            ),
            showSenderName: false,
            onReact: { _ in },
            onReactionTap: { _ in }
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Jump to Unread") {
    VStack {
        Spacer()
        JumpToUnreadButton(unreadCount: 5) {}
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Unread Divider") {
    UnreadMessageDivider()
        .background(Color(.systemGroupedBackground))
}
