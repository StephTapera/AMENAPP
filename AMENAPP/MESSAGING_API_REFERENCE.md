# FirebaseMessagingService - Quick API Reference

## 📖 Table of Contents
- [Initialization](#initialization)
- [Conversations](#conversations)
- [Messages](#messages)
- [Group Management](#group-management)
- [Message Actions](#message-actions)
- [Reactions & Interactions](#reactions--interactions)
- [Error Handling](#error-handling)

---

## Initialization

```swift
let messagingService = FirebaseMessagingService.shared
```

### Properties
```swift
messagingService.conversations: [ChatConversation]  // Published
messagingService.isLoading: Bool                    // Published
messagingService.lastError: MessagingError?         // Published
messagingService.currentUserId: String              // Read-only
messagingService.currentUserName: String            // Read-only
messagingService.isAuthenticated: Bool              // Read-only
```

---

## Conversations

### Start Listening
```swift
messagingService.startListeningToConversations()
// Auto-updates messagingService.conversations
```

### Stop Listening
```swift
messagingService.stopListeningToConversations()
```

### Create Direct Conversation
```swift
let conversationId = try await messagingService.getOrCreateDirectConversation(
    withUserId: "user123",
    userName: "John Doe"
)
```

### Create Group Conversation
```swift
let groupId = try await messagingService.createGroupConversation(
    participantIds: ["user1", "user2"],
    participantNames: ["user1": "Alice", "user2": "Bob"],
    groupName: "Team Chat",
    groupAvatarUrl: nil
)
```

---

## Messages

### Start Listening to Messages
```swift
// Default (50 messages)
messagingService.startListeningToMessages(
    conversationId: conversationId
) { messages in
    self.messages = messages
}

// Custom limit
messagingService.startListeningToMessages(
    conversationId: conversationId,
    limit: 20
) { messages in
    self.messages = messages
}
```

### Stop Listening
```swift
messagingService.stopListeningToMessages(conversationId: conversationId)
```

### Load More Messages (Pagination)
```swift
try await messagingService.loadMoreMessages(
    conversationId: conversationId,
    limit: 50
) { olderMessages in
    // Insert at beginning
    self.messages.insert(contentsOf: olderMessages, at: 0)
}
```

### Check for More Messages
```swift
if messagingService.canLoadMoreMessages(conversationId: conversationId) {
    // Show "Load More" button
}
```

### Send Text Message
```swift
try await messagingService.sendMessage(
    conversationId: conversationId,
    text: "Hello!",
    replyToMessageId: nil
)
```

### Send Message with Reply
```swift
try await messagingService.sendMessage(
    conversationId: conversationId,
    text: "That's great!",
    replyToMessageId: originalMessageId
)
```

### Send Photo Message
```swift
try await messagingService.sendMessageWithPhotos(
    conversationId: conversationId,
    text: "Check this out!",
    images: [image1, image2]
)
```

### Mark as Read
```swift
try await messagingService.markMessagesAsRead(
    conversationId: conversationId,
    messageIds: unreadMessageIds
)
```

---

## Group Management

### Add Participants
```swift
try await messagingService.addParticipantsToGroup(
    conversationId: groupId,
    participantIds: ["user3", "user4"],
    participantNames: ["user3": "Charlie", "user4": "Diana"]
)
```

### Remove Participant
```swift
try await messagingService.removeParticipantFromGroup(
    conversationId: groupId,
    participantId: "user2"
)
```

### Leave Group
```swift
try await messagingService.leaveGroup(conversationId: groupId)
```

### Update Group Name
```swift
try await messagingService.updateGroupName(
    conversationId: groupId,
    newName: "Updated Team Name"
)
```

### Update Group Avatar
```swift
try await messagingService.updateGroupAvatar(
    conversationId: groupId,
    image: avatarImage
)
```

### Get Participants
```swift
let participants = try await messagingService.getGroupParticipants(
    conversationId: groupId
)
// Returns: [String: String] (userId: displayName)
```

---

## Message Actions

### Pin Message
```swift
try await messagingService.pinMessage(
    conversationId: conversationId,
    messageId: messageId
)
```

### Unpin Message
```swift
try await messagingService.unpinMessage(
    conversationId: conversationId,
    messageId: messageId
)
```

### Star Message
```swift
try await messagingService.starMessage(
    conversationId: conversationId,
    messageId: messageId
)
```

### Unstar Message
```swift
try await messagingService.unstarMessage(
    conversationId: conversationId,
    messageId: messageId
)
```

### Edit Message
```swift
try await messagingService.editMessage(
    conversationId: conversationId,
    messageId: messageId,
    newText: "Updated text"
)
```

### Delete Message (Soft Delete)
```swift
try await messagingService.deleteMessage(
    conversationId: conversationId,
    messageId: messageId
)
// Message shows as "This message was deleted"
```

### Delete Message Permanently
```swift
try await messagingService.deleteMessagePermanently(
    conversationId: conversationId,
    messageId: messageId
)
// Message is completely removed
```

### Forward Message
```swift
try await messagingService.forwardMessage(
    messageId: messageId,
    fromConversation: sourceConversationId,
    toConversation: destinationConversationId
)
```

### Fetch Pinned Messages
```swift
let pinnedMessages = try await messagingService.fetchPinnedMessages(
    conversationId: conversationId
)
```

### Fetch Starred Messages
```swift
let starredMessages = try await messagingService.fetchStarredMessages(
    conversationId: conversationId
)
```

---

## Reactions & Interactions

### Add Reaction
```swift
try await messagingService.addReaction(
    conversationId: conversationId,
    messageId: messageId,
    emoji: "👍"
)
```

### Remove Reaction
```swift
try await messagingService.removeReaction(
    conversationId: conversationId,
    messageId: messageId,
    reactionId: reactionId
)
```

### Update Typing Status
```swift
// Start typing
try await messagingService.updateTypingStatus(
    conversationId: conversationId,
    isTyping: true
)

// Stop typing
try await messagingService.updateTypingStatus(
    conversationId: conversationId,
    isTyping: false
)
```

### Listen to Typing Indicators
```swift
messagingService.startListeningToTyping(
    conversationId: conversationId
) { typingUsernames in
    if !typingUsernames.isEmpty {
        let names = typingUsernames.joined(separator: ", ")
        self.typingIndicator = "\(names) is typing..."
    } else {
        self.typingIndicator = ""
    }
}
```

---

## Error Handling

### Error Types
```swift
enum MessagingError: LocalizedError {
    case notAuthenticated
    case invalidUserId
    case conversationNotFound
    case messageNotFound
    case uploadFailed(String)
    case networkError(Error)
    case permissionDenied
    case selfConversation
    case invalidInput(String)
}
```

### Handling Errors
```swift
do {
    try await messagingService.sendMessage(
        conversationId: id,
        text: text
    )
} catch MessagingError.notAuthenticated {
    // User needs to log in
    showLoginScreen()
} catch MessagingError.networkError(let error) {
    // Network issue
    showAlert("Network error: \(error.localizedDescription)")
} catch MessagingError.invalidInput(let reason) {
    // Invalid data
    showAlert("Invalid input: \(reason)")
} catch {
    // Other errors
    showAlert("Error: \(error.localizedDescription)")
}
```

### Observing Errors
```swift
.onChange(of: messagingService.lastError) { error in
    if let error = error {
        showErrorBanner(error.localizedDescription)
    }
}
```

---

## User Management

### Update Current User Name
```swift
messagingService.updateCurrentUserName("New Display Name")
```

### Fetch and Cache User Name
```swift
await messagingService.fetchAndCacheCurrentUserName()
```

### Search Users
```swift
let users = try await messagingService.searchUsers(query: "john")
// Returns: [ContactUser]
```

---

## Quick Examples

### Complete Message View
```swift
struct ConversationView: View {
    let conversationId: String
    @StateObject private var service = FirebaseMessagingService.shared
    @State private var messages: [AppMessage] = []
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
            }
            
            HStack {
                TextField("Message", text: $messageText)
                Button("Send") {
                    Task {
                        try? await service.sendMessage(
                            conversationId: conversationId,
                            text: messageText
                        )
                        messageText = ""
                    }
                }
            }
        }
        .onAppear {
            service.startListeningToMessages(conversationId: conversationId) { loadedMessages in
                messages = loadedMessages
            }
        }
        .onDisappear {
            service.stopListeningToMessages(conversationId: conversationId)
        }
    }
}
```

### Create Group
```swift
Button("Create Group") {
    Task {
        do {
            let groupId = try await messagingService.createGroupConversation(
                participantIds: selectedUserIds,
                participantNames: selectedUserNames,
                groupName: groupNameText
            )
            // Navigate to group
        } catch {
            showError(error.localizedDescription)
        }
    }
}
```

### Pagination Example
```swift
ScrollView {
    LazyVStack {
        // Load more at top
        if service.canLoadMoreMessages(conversationId: conversationId) {
            Button("Load Earlier Messages") {
                Task {
                    try? await service.loadMoreMessages(conversationId: conversationId) { older in
                        messages.insert(contentsOf: older, at: 0)
                    }
                }
            }
        }
        
        ForEach(messages) { message in
            MessageRow(message: message)
        }
    }
}
```

---

## Best Practices

1. **Always handle errors** with try-catch
2. **Stop listeners** when views disappear
3. **Use pagination** for long conversations
4. **Cache user names** to avoid repeated lookups
5. **Validate input** before sending messages
6. **Monitor lastError** for user feedback
7. **Clean up state** when switching conversations

---

## Performance Tips

- Use `.limit()` for initial message load (default: 50)
- Load more messages only when needed
- Stop listeners when not in view
- Compress images before upload (0.7-0.8 quality)
- Use batch operations for multiple updates
- Cache frequently accessed data

---

## Common Patterns

### Send Message with Error Handling
```swift
func sendMessage() {
    guard !text.isEmpty else { return }
    
    Task {
        do {
            try await service.sendMessage(
                conversationId: id,
                text: text
            )
            text = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### Scroll to Bottom on New Message
```swift
ScrollViewReader { proxy in
    ScrollView {
        ForEach(messages) { message in
            MessageRow(message: message)
                .id(message.id)
        }
    }
    .onChange(of: messages.count) { _ in
        if let last = messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
```

### Typing Indicator with Timer
```swift
@State private var typingTimer: Timer?

TextField("Message", text: $messageText)
    .onChange(of: messageText) { _ in
        typingTimer?.invalidate()
        
        Task {
            try? await service.updateTypingStatus(
                conversationId: id,
                isTyping: true
            )
        }
        
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            Task {
                try? await service.updateTypingStatus(
                    conversationId: id,
                    isTyping: false
                )
            }
        }
    }
```

---

**Version**: 2.0.0  
**Last Updated**: January 2026  
**Status**: Production Ready ✅
