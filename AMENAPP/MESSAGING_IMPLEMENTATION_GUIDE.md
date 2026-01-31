# Messaging System Implementation Guide

## Overview

Your Firestore rules now implement a sophisticated messaging permission system:

1. **Mutual Followers**: Users who follow each other can exchange unlimited messages
2. **Allow Anyone**: Users can set their privacy to allow messages from anyone (unlimited)
3. **Message Requests**: Users can send ONE message to someone they don't mutually follow (unless they allow anyone)
4. **Blocking**: Blocked users cannot send messages

## Data Structure Requirements

### User Document Structure

```swift
struct User {
    let id: String
    let username: String
    let bio: String?
    let createdAt: Date
    let updatedAt: Date
    
    // NEW: Message privacy setting
    let messagePrivacy: MessagePrivacy // "anyone" or "followers"
    
    let followersCount: Int
    let followingCount: Int
}

enum MessagePrivacy: String, Codable {
    case anyone = "anyone"        // Allow messages from anyone
    case followers = "followers"  // Only mutual followers (default)
}
```

### Follow Document Structure

```swift
// Document ID format: "{followerId}_{followingId}"
struct Follow {
    let followerId: String     // or followerUserId
    let followingId: String    // or followingUserId
    let createdAt: Date
}
```

### Conversation Document Structure

```swift
struct Conversation {
    let id: String
    let participantIds: [String]  // Array of 2 user IDs
    let createdAt: Date
    let updatedAt: Date
    
    // NEW: Track message counts per user (for message request limit)
    let messageCounts: [String: Int]  // { "userId1": 5, "userId2": 3 }
    
    // Optional metadata
    let lastMessage: String?
    let lastMessageAt: Date?
    let lastMessageSenderId: String?
}
```

### Message Document Structure

```swift
struct Message {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date
    
    // Optional fields
    let imageUrl: String?
    let isRead: Bool
}
```

## Implementation Steps

### 1. Update User Profile to Include Message Privacy

```swift
// When creating a new user
func createUserProfile(userId: String, username: String) async throws {
    let userData: [String: Any] = [
        "username": username,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "messagePrivacy": "followers",  // Default to followers only
        "followersCount": 0,
        "followingCount": 0
    ]
    
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .setData(userData)
}

// Allow users to update their message privacy
func updateMessagePrivacy(to privacy: MessagePrivacy) async throws {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .updateData([
            "messagePrivacy": privacy.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
}
```

### 2. Create Follow System

```swift
// Follow a user
func followUser(targetUserId: String) async throws {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }
    
    let db = Firestore.firestore()
    let batch = db.batch()
    
    // Create follow document
    let followId = "\(currentUserId)_\(targetUserId)"
    let followRef = db.collection("follows").document(followId)
    batch.setData([
        "followerId": currentUserId,
        "followerUserId": currentUserId,  // Backward compatibility
        "followingId": targetUserId,
        "followingUserId": targetUserId,   // Backward compatibility
        "createdAt": FieldValue.serverTimestamp()
    ], forDocument: followRef)
    
    // Update follower counts
    let targetUserRef = db.collection("users").document(targetUserId)
    batch.updateData([
        "followersCount": FieldValue.increment(Int64(1)),
        "updatedAt": FieldValue.serverTimestamp()
    ], forDocument: targetUserRef)
    
    let currentUserRef = db.collection("users").document(currentUserId)
    batch.updateData([
        "followingCount": FieldValue.increment(Int64(1)),
        "updatedAt": FieldValue.serverTimestamp()
    ], forDocument: currentUserRef)
    
    try await batch.commit()
}

// Unfollow a user
func unfollowUser(targetUserId: String) async throws {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }
    
    let db = Firestore.firestore()
    let batch = db.batch()
    
    // Delete follow document
    let followId = "\(currentUserId)_\(targetUserId)"
    let followRef = db.collection("follows").document(followId)
    batch.deleteDocument(followRef)
    
    // Update follower counts
    let targetUserRef = db.collection("users").document(targetUserId)
    batch.updateData([
        "followersCount": FieldValue.increment(Int64(-1)),
        "updatedAt": FieldValue.serverTimestamp()
    ], forDocument: targetUserRef)
    
    let currentUserRef = db.collection("users").document(currentUserId)
    batch.updateData([
        "followingCount": FieldValue.increment(Int64(-1)),
        "updatedAt": FieldValue.serverTimestamp()
    ], forDocument: currentUserRef)
    
    try await batch.commit()
}

// Check if two users follow each other
func areFollowingEachOther(userId1: String, userId2: String) async throws -> Bool {
    let db = Firestore.firestore()
    
    let follow1 = try await db.collection("follows")
        .document("\(userId1)_\(userId2)")
        .getDocument()
    
    let follow2 = try await db.collection("follows")
        .document("\(userId2)_\(userId1)")
        .getDocument()
    
    return follow1.exists && follow2.exists
}
```

### 3. Messaging System with Permission Checks

```swift
// Check if current user can message another user
func canMessageUser(_ targetUserId: String) async throws -> (canMessage: Bool, isLimited: Bool) {
    guard let currentUserId = Auth.auth().currentUser?.uid else {
        return (false, false)
    }
    
    let db = Firestore.firestore()
    
    // Get target user's privacy settings
    let targetUser = try await db.collection("users")
        .document(targetUserId)
        .getDocument()
    
    let messagePrivacy = targetUser.data()?["messagePrivacy"] as? String ?? "followers"
    
    // If they allow messages from anyone, no limit
    if messagePrivacy == "anyone" {
        return (true, false)  // Can message, unlimited
    }
    
    // Check if mutual followers
    let areMutual = try await areFollowingEachOther(userId1: currentUserId, userId2: targetUserId)
    
    if areMutual {
        return (true, false)  // Can message, unlimited
    }
    
    // Otherwise, it's a message request (limited to 1 message)
    return (true, true)  // Can message, but limited to 1
}

// Find or create conversation
func findOrCreateConversation(with otherUserId: String) async throws -> String {
    guard let currentUserId = Auth.auth().currentUser?.uid else {
        throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
    }
    
    let db = Firestore.firestore()
    
    // Check if conversation already exists
    let existingConversations = try await db.collection("conversations")
        .whereField("participantIds", arrayContains: currentUserId)
        .getDocuments()
    
    for doc in existingConversations.documents {
        let participantIds = doc.data()["participantIds"] as? [String] ?? []
        if participantIds.contains(otherUserId) && participantIds.count == 2 {
            return doc.documentID
        }
    }
    
    // Create new conversation
    let conversationData: [String: Any] = [
        "participantIds": [currentUserId, otherUserId].sorted(),  // Sort for consistency
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "messageCounts": [
            currentUserId: 0,
            otherUserId: 0
        ]
    ]
    
    let conversationRef = try await db.collection("conversations").addDocument(data: conversationData)
    return conversationRef.documentID
}

// Send a message
func sendMessage(to conversationId: String, text: String) async throws {
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }
    
    let db = Firestore.firestore()
    
    // Get conversation to check message count
    let conversation = try await db.collection("conversations")
        .document(conversationId)
        .getDocument()
    
    guard let conversationData = conversation.data() else {
        throw NSError(domain: "Firestore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
    }
    
    let participantIds = conversationData["participantIds"] as? [String] ?? []
    let otherUserId = participantIds.first { $0 != currentUserId } ?? ""
    
    // Check permissions
    let (canMessage, isLimited) = try await canMessageUser(otherUserId)
    
    guard canMessage else {
        throw NSError(domain: "Permission", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot message this user"])
    }
    
    if isLimited {
        // Check message count
        let messageCounts = conversationData["messageCounts"] as? [String: Int] ?? [:]
        let currentCount = messageCounts[currentUserId] ?? 0
        
        if currentCount >= 1 {
            throw NSError(domain: "Permission", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Message request already sent. Wait for them to follow you back."])
        }
    }
    
    // Create message and update conversation in a batch
    let batch = db.batch()
    
    // Add message
    let messageRef = db.collection("conversations")
        .document(conversationId)
        .collection("messages")
        .document()
    
    batch.setData([
        "senderId": currentUserId,
        "text": text,
        "createdAt": FieldValue.serverTimestamp(),
        "isRead": false
    ], forDocument: messageRef)
    
    // Update conversation metadata and increment message count
    let conversationRef = db.collection("conversations").document(conversationId)
    var updateData: [String: Any] = [
        "lastMessage": text,
        "lastMessageAt": FieldValue.serverTimestamp(),
        "lastMessageSenderId": currentUserId,
        "updatedAt": FieldValue.serverTimestamp(),
        "messageCounts.\(currentUserId)": FieldValue.increment(Int64(1))
    ]
    
    batch.updateData(updateData, forDocument: conversationRef)
    
    try await batch.commit()
}
```

### 4. UI Indicators

```swift
// Show message request UI
func getMessageStatus(for userId: String) async -> MessageStatus {
    guard let (canMessage, isLimited) = try? await canMessageUser(userId) else {
        return .blocked
    }
    
    if !canMessage {
        return .blocked
    }
    
    if isLimited {
        // Check if they've already sent a message request
        // You'll need to check the conversation
        return .messageRequest
    }
    
    return .unlimited
}

enum MessageStatus {
    case unlimited       // Mutual followers or they allow anyone
    case messageRequest  // Can send 1 message only
    case blocked        // Cannot message
}
```

## Important Notes

1. **Follow Document IDs**: Use format `{followerId}_{followingId}` for consistent lookups
2. **Message Counts**: Track in conversation document to enforce 1-message limit
3. **Privacy Default**: Default to "followers" for new users
4. **Blocking**: If users block each other, they cannot message at all
5. **Accepting Message Requests**: When the recipient follows back, they get unlimited messaging

## Testing Checklist

- [ ] Users with `messagePrivacy: "anyone"` receive unlimited messages from everyone
- [ ] Users with `messagePrivacy: "followers"` only get unlimited messages from mutual followers
- [ ] Non-mutual followers can send exactly 1 message (message request)
- [ ] After sending 1 message, they cannot send more until recipient follows back
- [ ] Blocked users cannot send any messages
- [ ] When recipient follows back, message count resets and both can send unlimited messages
- [ ] Follow/unfollow updates follower counts correctly
- [ ] Conversation queries work correctly

## Security Notes

✅ **Production Ready Features:**
- Message count enforcement in security rules
- Permission checks before conversation creation
- Blocking enforcement
- Follow relationship verification
- Field validation and length limits

⚠️ **Consider Adding:**
- Rate limiting (via Cloud Functions)
- Spam detection
- Report system integration
- Message deletion/editing time limits
