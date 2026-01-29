# Firebase Realtime Database Integration Guide

## Overview

This guide explains how Firebase Realtime Database is integrated into AMENAPP for real-time messaging and post updates.

## Architecture

### Hybrid Approach
We use **both Firestore and Realtime Database** for optimal performance:

- **Firestore**: Permanent storage, complex queries, user profiles, post content
- **Realtime Database**: Real-time updates, typing indicators, presence, live messaging

## Features Implemented

### 1. Real-Time Messaging

#### Message Flow
```
User sends message → Realtime Database (instant delivery) → Firestore (permanent storage)
```

#### Features:
- ✅ Instant message delivery (sub-second latency)
- ✅ Typing indicators
- ✅ Read receipts
- ✅ Online/offline presence
- ✅ Message reactions
- ✅ Reply to messages

#### Usage Example:
```swift
let rtService = RealtimeDatabaseService.shared

// Send a message
try await rtService.sendRealtimeMessage(
    conversationId: "conv123",
    text: "Hello world!"
)

// Observe messages
rtService.observeMessages(conversationId: "conv123")

// Access messages
let messages = rtService.realtimeMessages["conv123"]
```

### 2. Typing Indicators

Real-time typing indicators show when users are composing messages.

```swift
// Set typing indicator
try await rtService.setTypingIndicator(
    conversationId: "conv123",
    isTyping: true
)

// Observe typing
rtService.observeTypingIndicators(conversationId: "conv123")

// Check who's typing
if let typingUsers = rtService.typingUsers["conv123"] {
    print("\(typingUsers.count) users are typing...")
}
```

### 3. Online Presence

Automatically tracks which users are online.

```swift
// Online users are automatically tracked
let onlineUsers = rtService.onlineUsers

// Check if specific user is online
let isUserOnline = rtService.onlineUsers.contains(userId)
```

### 4. Real-Time Post Feed

Posts appear instantly in the feed using Realtime Database for notification, then load full data from Firestore.

```swift
// Publish post to realtime feed
try await rtService.publishRealtimePost(
    postId: postId,
    authorId: userId,
    category: "testimonies",
    timestamp: Date()
)

// Observe recent posts
rtService.observeRecentPosts(limit: 50) { postIds in
    // postIds updated in real-time
    // Fetch full post data from Firestore
}
```

## Database Structure

### Realtime Database Schema

```
/
├── conversations/
│   ├── {conversationId}/
│   │   ├── metadata/
│   │   │   ├── participantIds: []
│   │   │   ├── participantNames: {}
│   │   │   ├── lastMessageText: ""
│   │   │   ├── lastMessageTimestamp: 0
│   │   │   └── isGroup: false
│   │   ├── messages/
│   │   │   └── {messageId}/
│   │   │       ├── id: ""
│   │   │       ├── senderId: ""
│   │   │       ├── senderName: ""
│   │   │       ├── text: ""
│   │   │       ├── timestamp: 0
│   │   │       └── readBy: {}
│   │   └── typing/
│   │       └── {userId}/
│   │           ├── userId: ""
│   │           ├── userName: ""
│   │           └── timestamp: 0
├── userConversations/
│   └── {userId}/
│       └── {conversationId}: true
├── presence/
│   └── {userId}/
│       ├── online: true/false
│       └── lastSeen: timestamp
└── posts/
    ├── recent/
    │   └── {postId}/
    │       ├── postId: ""
    │       ├── authorId: ""
    │       ├── category: ""
    │       ├── timestamp: 0
    │       ├── likes: 0
    │       └── comments: 0
    └── byCategory/
        └── {category}/
            └── {postId}: {...}
```

## Integration Steps

### Step 1: Initialize Service

The service is automatically initialized as a singleton and starts presence monitoring.

```swift
let rtService = RealtimeDatabaseService.shared
```

### Step 2: Observe Conversations

```swift
// In MessagesView or similar
rtService.observeConversations()

// Access conversations
ForEach(rtService.realtimeConversations) { conversation in
    ConversationRow(conversation: conversation)
}
```

### Step 3: Implement Chat View

```swift
struct ChatView: View {
    let conversationId: String
    @StateObject private var rtService = RealtimeDatabaseService.shared
    
    var body: some View {
        VStack {
            // Display messages
            ScrollView {
                ForEach(rtService.realtimeMessages[conversationId] ?? []) { message in
                    MessageBubble(message: message)
                }
            }
            
            // Input with typing indicator
            MessageInput { text in
                Task {
                    try await rtService.sendRealtimeMessage(
                        conversationId: conversationId,
                        text: text
                    )
                }
            }
            .onChange(of: inputText) { oldValue, newValue in
                Task {
                    try await rtService.setTypingIndicator(
                        conversationId: conversationId,
                        isTyping: !newValue.isEmpty
                    )
                }
            }
        }
        .onAppear {
            rtService.observeMessages(conversationId: conversationId)
            rtService.observeTypingIndicators(conversationId: conversationId)
        }
        .onDisappear {
            rtService.stopObservingMessages(conversationId: conversationId)
            rtService.stopObservingTypingIndicators(conversationId: conversationId)
        }
    }
}
```

### Step 4: Post Creation with Real-Time Updates

```swift
// When creating a post
Task {
    // 1. Save to Firestore (permanent storage)
    try await FirebasePostService.shared.createPost(
        content: content,
        category: category
    )
    
    // 2. Publish to Realtime Database (instant notification)
    try await RealtimeDatabaseService.shared.publishRealtimePost(
        postId: postId,
        authorId: userId,
        category: category.rawValue,
        timestamp: Date()
    )
}
```

## Security Rules

### Realtime Database Rules

Add these rules to your Firebase Console → Realtime Database → Rules:

```json
{
  "rules": {
    "conversations": {
      "$conversationId": {
        ".read": "auth != null && data.child('metadata/participantIds').val().contains(auth.uid)",
        ".write": "auth != null && data.child('metadata/participantIds').val().contains(auth.uid)",
        "messages": {
          "$messageId": {
            ".write": "auth != null && newData.child('senderId').val() === auth.uid"
          }
        },
        "typing": {
          "$userId": {
            ".write": "auth != null && $userId === auth.uid"
          }
        }
      }
    },
    "userConversations": {
      "$userId": {
        ".read": "auth != null && $userId === auth.uid",
        ".write": "auth != null && $userId === auth.uid"
      }
    },
    "presence": {
      "$userId": {
        ".read": true,
        ".write": "auth != null && $userId === auth.uid"
      }
    },
    "posts": {
      "recent": {
        ".read": true,
        "$postId": {
          ".write": "auth != null && newData.child('authorId').val() === auth.uid"
        }
      },
      "byCategory": {
        "$category": {
          ".read": true,
          "$postId": {
            ".write": "auth != null && newData.child('authorId').val() === auth.uid"
          }
        }
      }
    }
  }
}
```

## Performance Optimization

### Best Practices

1. **Use Queries Wisely**
   - Limit recent messages: `queryLimited(toLast: 50)`
   - Only observe active conversations

2. **Clean Up Observers**
   - Always remove observers in `onDisappear`
   - Use `cleanup()` when user logs out

3. **Offline Persistence**
   - Enable offline persistence:
   ```swift
   Database.database().isPersistenceEnabled = true
   ```

4. **Combine with Firestore**
   - Realtime DB for live updates
   - Firestore for search, complex queries, and permanent storage

## Monitoring & Debugging

### Enable Logging

```swift
// In AppDelegate
Database.database().setLoggingEnabled(true)
```

### Check Connection Status

```swift
let connectedRef = Database.database().reference(withPath: ".info/connected")
connectedRef.observe(.value) { snapshot in
    if let connected = snapshot.value as? Bool, connected {
        print("✅ Connected to Realtime Database")
    } else {
        print("❌ Disconnected from Realtime Database")
    }
}
```

## Migration from Firestore Only

If you have existing data in Firestore:

1. Keep Firestore as primary storage
2. Add Realtime Database for real-time features
3. Sync initial data on app launch
4. Use both services in parallel (hybrid approach)

## Troubleshooting

### Messages not appearing?
- Check security rules
- Verify user is authenticated
- Check conversationId is correct
- Look for errors in console

### Typing indicators not working?
- Ensure observer is set up correctly
- Check 5-second timeout
- Verify user permissions

### Presence not updating?
- Check internet connection
- Verify `.info/connected` observer
- Check onDisconnect hooks

## Resources

- [Firebase Realtime Database Docs](https://firebase.google.com/docs/database)
- [Security Rules Guide](https://firebase.google.com/docs/database/security)
- [Best Practices](https://firebase.google.com/docs/database/usage/best-practices)
