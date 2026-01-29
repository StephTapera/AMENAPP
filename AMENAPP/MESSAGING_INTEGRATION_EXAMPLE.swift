//
//  MESSAGING_INTEGRATION_EXAMPLE.swift
//  
//  Example showing how to integrate the new messaging components
//  into ModernConversationDetailView in MessagesView.swift
//

/*

// MARK: - Updated Modern Conversation Detail View
// Replace the existing ScrollView in ModernConversationDetailView with this:

ScrollViewReader { proxy in
    ScrollView(showsIndicators: false) {
        LazyVStack(spacing: 0) {
            // Iterate through messages with index for context
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                let previousMessage = index > 0 ? messages[index - 1] : nil
                let nextMessage = index < messages.count - 1 ? messages[index + 1] : nil
                
                // Show timestamp separator if needed (every 15 minutes by default)
                if message.shouldShowTimestamp(after: previousMessage) {
                    HStack {
                        Text(message.timestamp.messageTimestamp())
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                
                // Display message with intelligent grouping
                ModernMessageBubble(
                    message: message,
                    showAvatar: message.shouldShowAvatar(before: nextMessage),
                    showTimestamp: false, // We show it as separator above
                    showSenderName: message.shouldShowSenderName(after: previousMessage),
                    onReply: {
                        replyingTo = message
                        isInputFocused = true
                    },
                    onReact: { emoji in
                        addReaction(to: message, emoji: emoji)
                    }
                )
                .id(message.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
            
            // Typing indicator
            if isTyping {
                ModernTypingIndicator()
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .padding()
        .padding(.bottom, 80)
    }
    .onAppear {
        scrollProxy = proxy
        // Scroll to bottom on appear
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
    .onChange(of: messages.count) { _, _ in
        // Scroll to bottom when new message arrives
        withAnimation {
            if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Alternative: Using Message Grouping

// If you prefer to use the grouping helper:

ScrollViewReader { proxy in
    ScrollView(showsIndicators: false) {
        LazyVStack(spacing: 0) {
            let groups = messages.groupedMessages(timeThreshold: 300) // 5 minutes
            
            ForEach(groups) { group in
                // Show timestamp for first message in group
                if let firstMessage = group.messages.first,
                   firstMessage.id == messages.first?.id || 
                   firstMessage.shouldShowTimestamp(after: nil) {
                    HStack {
                        Text(firstMessage.timestamp.messageTimestamp())
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                
                // Messages in group
                ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, message in
                    let isLastInGroup = index == group.messages.count - 1
                    let isFirstInGroup = index == 0
                    
                    ModernMessageBubble(
                        message: message,
                        showAvatar: isLastInGroup,
                        showTimestamp: false,
                        showSenderName: isFirstInGroup && group.showSenderName,
                        onReply: {
                            replyingTo = message
                            isInputFocused = true
                        },
                        onReact: { emoji in
                            addReaction(to: message, emoji: emoji)
                        }
                    )
                    .id(message.id)
                }
            }
            
            if isTyping {
                ModernTypingIndicator()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .padding(.bottom, 80)
    }
    .onAppear {
        scrollProxy = proxy
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
    .onChange(of: messages.count) { _, _ in
        withAnimation {
            if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Example with Unread Separator

// Add this state variable:
@State private var firstUnreadMessageId: String?

// And add this in the message loop:
if message.id == firstUnreadMessageId {
    HStack {
        VStack { Divider().background(Color.blue) }
        Text("NEW")
            .font(.custom("OpenSans-Bold", size: 11))
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.2))
            )
        VStack { Divider().background(Color.blue) }
    }
    .padding(.vertical, 12)
}

// MARK: - Testing the Components

// 1. Test with system message:
let systemMessage = AppMessage(
    text: "Sarah joined the group",
    isFromCurrentUser: false,
    timestamp: Date(),
    senderId: "system",
    senderName: "System"
)

// 2. Test with deleted message:
var deletedMessage = AppMessage(
    text: "This was a secret",
    isFromCurrentUser: true,
    timestamp: Date()
)
deletedMessage.isDeleted = true

// 3. Test with edited message:
var editedMessage = AppMessage(
    text: "Fixed typo!",
    isFromCurrentUser: true,
    timestamp: Date()
)
editedMessage.editedAt = Date().addingTimeInterval(-60)

// 4. Test with reply:
let originalMessage = AppMessage(
    text: "What time is the meeting?",
    isFromCurrentUser: false,
    timestamp: Date()
)

let replyMessage = AppMessage(
    text: "3 PM tomorrow",
    isFromCurrentUser: true,
    timestamp: Date(),
    replyTo: originalMessage
)

// 5. Test with reactions:
var reactedMessage = AppMessage(
    text: "Great idea!",
    isFromCurrentUser: false,
    timestamp: Date()
)
reactedMessage.reactions = [
    MessageReaction(emoji: "👍", userId: "1", username: "Sarah"),
    MessageReaction(emoji: "❤️", userId: "2", username: "Mike"),
    MessageReaction(emoji: "👍", userId: "3", username: "Emily")
]

*/
