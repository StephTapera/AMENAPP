# Messaging System - Quick Reference Guide

## For Developers

### Starting a New Conversation

```swift
// In your view
let messagingService = FirebaseMessagingService.shared

Task {
    do {
        let conversationId = try await messagingService.getOrCreateDirectConversation(
            withUserId: "user123",
            userName: "John Doe"
        )
        
        // Open chat view with conversationId
        print("Conversation ID: \(conversationId)")
    } catch {
        print("Error: \(error)")
    }
}
```

### Creating a Group

```swift
Task {
    do {
        let conversationId = try await messagingService.createGroupConversation(
            participantIds: ["user1", "user2", "user3"],
            participantNames: [
                "user1": "Alice",
                "user2": "Bob",
                "user3": "Charlie"
            ],
            groupName: "Bible Study Group"
        )
        
        print("Group created: \(conversationId)")
    } catch {
        print("Error: \(error)")
    }
}
```

### Sending a Message

```swift
Task {
    do {
        try await messagingService.sendMessage(
            conversationId: "conv123",
            text: "Hello, world!",
            replyToMessageId: nil // Optional
        )
    } catch {
        print("Error: \(error)")
    }
}
```

### Sending a Message with Photos

```swift
let images: [UIImage] = [image1, image2]

Task {
    do {
        try await messagingService.sendMessageWithPhotos(
            conversationId: "conv123",
            text: "Check out these photos!",
            images: images
        )
    } catch {
        print("Error: \(error)")
    }
}
```

### Searching for Users

```swift
Task {
    do {
        let users = try await messagingService.searchUsers(query: "john")
        
        // users is [ContactUser]
        for user in users {
            print("\(user.displayName) (@\(user.username))")
        }
    } catch {
        print("Error: \(error)")
    }
}
```

### Managing Conversations

```swift
// Mute
try await messagingService.muteConversation(conversationId: "conv123", muted: true)

// Pin
try await messagingService.pinConversation(conversationId: "conv123", pinned: true)

// Archive
try await messagingService.archiveConversation(conversationId: "conv123")

// Delete (soft delete for current user)
try await messagingService.deleteConversation(conversationId: "conv123")
```

### Handling Message Requests

```swift
// Fetch requests
let requests = try await messagingService.fetchMessageRequests(userId: currentUserId)

// Listen to requests in real-time
let cleanup = messagingService.startListeningToMessageRequests(userId: currentUserId) { requests in
    print("Requests updated: \(requests.count)")
}

// Clean up when done
cleanup()

// Accept request
try await messagingService.acceptMessageRequest(requestId: "req123")

// Decline request
try await messagingService.declineMessageRequest(requestId: "req123")
```

### Real-Time Listeners

```swift
// Listen to conversations
messagingService.startListeningToConversations()

// Stop listening
messagingService.stopListeningToConversations()

// Listen to messages in a conversation
messagingService.startListeningToMessages(conversationId: "conv123") { messages in
    print("Messages updated: \(messages.count)")
}

// Stop listening to messages
messagingService.stopListeningToMessages(conversationId: "conv123")
```

### Message Actions

```swift
// Add reaction
try await messagingService.addReaction(
    conversationId: "conv123",
    messageId: "msg456",
    emoji: "👍"
)

// Edit message
try await messagingService.editMessage(
    conversationId: "conv123",
    messageId: "msg456",
    newText: "Updated message"
)

// Delete message
try await messagingService.deleteMessage(
    conversationId: "conv123",
    messageId: "msg456"
)

// Pin message
try await messagingService.pinMessage(
    conversationId: "conv123",
    messageId: "msg456"
)

// Star message
try await messagingService.starMessage(
    conversationId: "conv123",
    messageId: "msg456"
)
```

### Group Management

```swift
// Add participants to group
try await messagingService.addParticipantsToGroup(
    conversationId: "conv123",
    participantIds: ["user4", "user5"],
    participantNames: [
        "user4": "Dave",
        "user5": "Eve"
    ]
)

// Remove participant
try await messagingService.removeParticipantFromGroup(
    conversationId: "conv123",
    participantId: "user4"
)

// Leave group
try await messagingService.leaveGroup(conversationId: "conv123")

// Update group name
try await messagingService.updateGroupName(
    conversationId: "conv123",
    newName: "New Group Name"
)

// Update group avatar
try await messagingService.updateGroupAvatar(
    conversationId: "conv123",
    image: avatarImage
)

// Get participants
let participants = try await messagingService.getGroupParticipants(
    conversationId: "conv123"
)
// Returns [String: String] - [userId: userName]
```

## UI Components

### MessagingUserSearchView

Shows a search interface for finding users to message:

```swift
.sheet(isPresented: $showSearch) {
    MessagingUserSearchView { user in
        // Handle user selection
        print("Selected: \(user.displayName)")
    }
}
```

### CreateGroupView

Shows interface for creating a new group:

```swift
.sheet(isPresented: $showCreateGroup) {
    CreateGroupView()
}
```

### MessageRequestRow

Shows a message request with action buttons:

```swift
MessageRequestRow(request: request) { action in
    switch action {
    case .accept:
        // Handle accept
    case .decline:
        // Handle decline
    case .block:
        // Handle block
    case .report:
        // Handle report
    }
}
```

## Models

### ContactUser

User model from Firestore:

```swift
struct ContactUser: Codable, Identifiable {
    var id: String?
    let displayName: String
    let username: String
    let email: String
    let profileImageURL: String?
    let showActivityStatus: Bool
}
```

### MessageRequest

Message request model:

```swift
struct MessageRequest: Identifiable {
    let id: String
    let conversationId: String
    let fromUserId: String
    let fromUserName: String
    var isRead: Bool
}
```

### AppMessage

Message model for UI:

```swift
struct AppMessage: Identifiable {
    let id: String
    let text: String
    let isFromCurrentUser: Bool
    let timestamp: Date
    let attachments: [MessageAttachment]
    let replyTo: AppMessage?
    let reactions: [MessageReaction]
    var isRead: Bool
    var isPinned: Bool
    var isStarred: Bool
    var isDeleted: Bool
}
```

### ChatConversation

Conversation model for UI:

```swift
struct ChatConversation: Identifiable {
    let id: String
    let name: String
    let lastMessage: String
    let timestamp: String
    let isGroup: Bool
    let unreadCount: Int
    let avatarColor: Color
}
```

## Error Handling

All async functions can throw `FirebaseMessagingError`:

```swift
enum FirebaseMessagingError: LocalizedError {
    case notAuthenticated
    case invalidUserId
    case conversationNotFound
    case messageNotFound
    case uploadFailed(String)
    case networkError(Error)
    case permissionDenied
    case selfConversation
    case invalidInput(String)
    case userBlocked
    case followRequired
    case messagesNotAllowed
}
```

Example error handling:

```swift
Task {
    do {
        try await messagingService.sendMessage(...)
    } catch FirebaseMessagingError.notAuthenticated {
        print("User must log in")
    } catch FirebaseMessagingError.userBlocked {
        print("This user is blocked")
    } catch {
        print("Unknown error: \(error)")
    }
}
```

## Common Patterns

### Open Conversation from Notification

```swift
// In your notification handler
func openConversation(conversationId: String) {
    // Set coordinator state
    MessagingCoordinator.shared.conversationToOpen = conversationId
    
    // Switch to messages tab
    // Your tab selection logic here
}
```

### Check Follow Status Before Messaging

```swift
let followStatus = try await checkFollowStatus(userId1: currentUser, userId2: otherUser)

if followStatus.user1FollowsUser2 && followStatus.user2FollowsUser1 {
    // Mutual follow - message will be accepted
} else {
    // Message will be a request
}
```

### Show Typing Indicator

```swift
// Start typing
try await messagingService.updateTypingStatus(
    conversationId: "conv123",
    isTyping: true
)

// Stop typing
try await messagingService.updateTypingStatus(
    conversationId: "conv123",
    isTyping: false
)

// Listen to typing
messagingService.startListeningToTyping(conversationId: "conv123") { typingUsers in
    if !typingUsers.isEmpty {
        print("\(typingUsers.joined(separator: ", ")) is typing...")
    }
}
```

## Best Practices

1. **Always clean up listeners**:
   ```swift
   .onDisappear {
       messagingService.stopListeningToMessages(conversationId: id)
   }
   ```

2. **Handle offline mode**:
   - Firestore automatically caches data
   - Show loading states appropriately
   - Handle errors gracefully

3. **Optimize image uploads**:
   - Compress images before sending
   - Show upload progress if possible
   - Handle failed uploads

4. **Privacy**:
   - Always check block status
   - Respect privacy settings
   - Show appropriate error messages

5. **Performance**:
   - Use pagination for message history
   - Limit number of conversations loaded
   - Debounce search queries

6. **UX**:
   - Show loading states
   - Provide haptic feedback
   - Animate state changes
   - Show error messages clearly

## Troubleshooting

### Messages not appearing
- Check that listener is started: `startListeningToMessages`
- Verify conversationId is correct
- Check Firestore security rules
- Look for errors in console

### Search not working
- Ensure lowercase fields exist in Firestore
- Check network connection
- Verify user is authenticated
- Try client-side fallback

### Can't create conversation
- Check if user is blocked
- Verify privacy settings
- Ensure not trying to message self
- Check follow status

### Group creation fails
- Need at least 1 member (besides creator)
- Group name can't be empty
- All participant IDs must be valid
- Check Firestore write permissions

## Support

For issues or questions:
1. Check the error message and type
2. Look at console logs (use emoji filters: ✅ 🔍 ❌ 📬)
3. Verify Firestore data structure matches expected format
4. Check that all required files are included in the project
