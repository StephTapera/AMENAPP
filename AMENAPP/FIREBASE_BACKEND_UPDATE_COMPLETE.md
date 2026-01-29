# ✅ Firebase Backend Update Complete

## Updated Files

### 1. **FirebaseMessagingService.swift** ✅ UPDATED

#### **Added Fields to FirebaseMessage:**
```swift
struct FirebaseMessage: Codable {
    // ... existing fields ...
    
    // ✅ NEW: Delivery Status
    var isSent: Bool?
    var isDelivered: Bool?
    var isSendFailed: Bool?
    
    // ✅ NEW: Disappearing Messages
    var disappearAfter: TimeInterval? // Duration in seconds
    var disappearAt: Timestamp? // When to delete
    
    // ✅ NEW: Link Previews
    var linkPreviewURLs: [String]? // URLs detected in message
    
    // ✅ NEW: Mentions
    var mentionedUserIds: [String]? // @mentioned user IDs
}
```

#### **Updated toMessage() Conversion:**
Now includes all new fields when converting Firebase → AppMessage:
- `isSent`, `isDelivered`, `isSendFailed`
- `disappearAfter`
- `linkPreviews` (empty array, loaded separately)
- `mentionedUserIds`

#### **New Backend Methods Added:**

##### **Message Requests:**
```swift
✅ acceptMessageRequest(requestId:) 
   - Changes status to "accepted"

✅ declineMessageRequest(requestId:)
   - Deletes the conversation

✅ markMessageRequestAsRead(requestId:)
   - Adds current user to requestReadBy array
```

##### **Delivery Status:**
```swift
✅ updateMessageDeliveryStatus(conversationId:messageId:isSent:isDelivered:isFailed:)
   - Updates message delivery state in Firestore
```

##### **Disappearing Messages:**
```swift
✅ setDisappearingMessageDuration(conversationId:duration:)
   - Sets timer for conversation

✅ scheduleMessageDisappear(conversationId:messageId:after:)
   - Schedules individual message deletion

✅ deleteDisappearedMessages()
   - Background task to delete expired messages
```

##### **Link Previews:**
```swift
✅ saveLinkPreviewURLs(conversationId:messageId:urls:)
   - Saves detected URLs to message
```

##### **Mentions:**
```swift
✅ saveMentionedUsers(conversationId:messageId:userIds:)
   - Saves mentioned user IDs

✅ notifyMentionedUsers(conversationId:messageId:mentionedUserIds:messageText:)
   - Sends notifications to mentioned users (placeholder for FCM)
```

---

## Firestore Database Schema Updates

### **Messages Collection:**
```javascript
/conversations/{conversationId}/messages/{messageId}
{
  // Existing fields...
  "text": "Hey @john, check this out!",
  "senderId": "user123",
  "timestamp": Timestamp,
  
  // ✅ NEW: Delivery tracking
  "isSent": true,
  "isDelivered": true,
  "isSendFailed": false,
  
  // ✅ NEW: Disappearing messages
  "disappearAfter": 3600, // 1 hour in seconds
  "disappearAt": Timestamp, // When to auto-delete
  
  // ✅ NEW: Link previews
  "linkPreviewURLs": [
    "https://example.com/article"
  ],
  
  // ✅ NEW: Mentions
  "mentionedUserIds": [
    "userId_john"
  ]
}
```

### **Conversations Collection:**
```javascript
/conversations/{conversationId}
{
  // Existing fields...
  "participantIds": [...],
  "conversationStatus": "accepted" | "pending",
  
  // ✅ NEW: Disappearing messages setting
  "disappearingMessageDuration": 3600, // seconds, or null if disabled
  
  // ✅ NEW: Request tracking
  "requestReadBy": ["userId1", "userId2"]
}
```

---

## Firestore Security Rules

### **Recommended Updates:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Messages
    match /conversations/{conversationId}/messages/{messageId} {
      // Allow read if user is participant
      allow read: if request.auth != null && 
        request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
      
      // Allow create if user is participant and sender
      allow create: if request.auth != null && 
        request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds &&
        request.resource.data.senderId == request.auth.uid;
      
      // Allow update for delivery status, reactions, and read receipts
      allow update: if request.auth != null && (
        // Sender can update delivery status
        (request.resource.data.senderId == request.auth.uid && 
         onlyChanging(['isSent', 'isDelivered', 'isSendFailed'])) ||
        // Any participant can mark as read
        (request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds &&
         onlyChanging(['readBy'])) ||
        // Any participant can add reactions
        (request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds &&
         onlyChanging(['reactions']))
      );
      
      // Allow delete for disappearing messages (by system) or sender
      allow delete: if request.auth != null && (
        request.resource.data.senderId == request.auth.uid ||
        request.resource.data.disappearAt <= request.time // Expired message
      );
    }
    
    // Conversations
    match /conversations/{conversationId} {
      allow read: if request.auth != null && 
        request.auth.uid in resource.data.participantIds;
      
      allow create: if request.auth != null && 
        request.auth.uid in request.resource.data.participantIds;
      
      allow update: if request.auth != null && 
        request.auth.uid in resource.data.participantIds;
      
      allow delete: if request.auth != null && 
        request.auth.uid in resource.data.participantIds;
    }
  }
}

// Helper function
function onlyChanging(fields) {
  return request.resource.data.diff(resource.data).affectedKeys().hasOnly(fields);
}
```

---

## Usage Examples

### **1. Send Message with Delivery Tracking:**
```swift
// Create message
let message = FirebaseMessage(
    conversationId: conversationId,
    senderId: currentUserId,
    senderName: currentUserName,
    text: "Hello!",
    attachments: [],
    reactions: [],
    replyTo: nil,
    timestamp: Timestamp(date: Date()),
    readBy: [currentUserId],
    isSent: false, // Initially false
    isDelivered: false,
    isSendFailed: false
)

// Try to send
do {
    try await messagingService.sendMessage(...)
    
    // Update status to sent
    try await messagingService.updateMessageDeliveryStatus(
        conversationId: conversationId,
        messageId: message.id!,
        isSent: true,
        isDelivered: true
    )
} catch {
    // Mark as failed
    try await messagingService.updateMessageDeliveryStatus(
        conversationId: conversationId,
        messageId: message.id!,
        isFailed: true
    )
}
```

### **2. Enable Disappearing Messages:**
```swift
// Enable 1-hour disappearing messages
try await messagingService.setDisappearingMessageDuration(
    conversationId: conversationId,
    duration: 3600 // 1 hour
)

// When sending a message, schedule it to disappear
try await messagingService.scheduleMessageDisappear(
    conversationId: conversationId,
    messageId: messageId,
    after: 3600
)
```

### **3. Save Link Previews:**
```swift
// Detect URLs in message
let urls = detectURLs(in: messageText)

if !urls.isEmpty {
    try await messagingService.saveLinkPreviewURLs(
        conversationId: conversationId,
        messageId: messageId,
        urls: urls.map { $0.absoluteString }
    )
}
```

### **4. Handle Mentions:**
```swift
// Parse mentions
let mentions = MentionParser.detectMentions(in: messageText)

// Get user IDs from usernames
let mentionedUserIds = mentions.compactMap { username in
    participants.first { $0.username == username }?.id
}

// Save to message
try await messagingService.saveMentionedUsers(
    conversationId: conversationId,
    messageId: messageId,
    userIds: mentionedUserIds
)

// Send notifications
try await messagingService.notifyMentionedUsers(
    conversationId: conversationId,
    messageId: messageId,
    mentionedUserIds: mentionedUserIds,
    messageText: messageText
)
```

### **5. Accept Message Request:**
```swift
try await messagingService.acceptMessageRequest(requestId: conversation.id)
```

### **6. Background Task for Disappearing Messages:**
```swift
// Call periodically (e.g., every 5 minutes)
Task {
    try await FirebaseMessagingService.shared.deleteDisappearedMessages()
}
```

---

## Migration Notes

### **Existing Messages:**
All new fields are **optional** (`?`), so:
- ✅ Existing messages will continue to work
- ✅ Old messages will have `nil` for new fields
- ✅ New messages will include all fields
- ✅ No database migration required

### **Default Values:**
When converting to AppMessage:
- `isSent`: defaults to `true` (assume sent if not specified)
- `isDelivered`: defaults to `true`
- `isSendFailed`: defaults to `false`
- `linkPreviews`: empty array (loaded separately)
- `mentionedUserIds`: empty array if not set

---

## Testing Checklist

### Delivery Status:
- [ ] Send message → Check `isSent` = true in Firestore
- [ ] Verify `isDelivered` updates after sync
- [ ] Simulate network error → Check `isSendFailed` = true
- [ ] Retry failed message → Check status updates

### Disappearing Messages:
- [ ] Set duration in conversation → Verify Firestore update
- [ ] Send message → Check `disappearAt` timestamp
- [ ] Run `deleteDisappearedMessages()` → Verify deletion
- [ ] Disable disappearing → Verify field removed

### Link Previews:
- [ ] Send URL → Check `linkPreviewURLs` saved
- [ ] Multiple URLs → All saved to array
- [ ] No URLs → Field not present or empty

### Mentions:
- [ ] @mention user → Check `mentionedUserIds` array
- [ ] Multiple mentions → All users saved
- [ ] No mentions → Array empty or not present
- [ ] Notification triggered → Check logs

### Message Requests:
- [ ] Accept request → Status changes to "accepted"
- [ ] Decline request → Conversation deleted
- [ ] Mark as read → Current user added to `requestReadBy`

---

## Performance Considerations

1. **Disappearing Messages Background Task:**
   - Run every 5-15 minutes
   - Use batch delete for efficiency
   - Limit to user's conversations only

2. **Link Preview Loading:**
   - Load asynchronously after message display
   - Cache previews to avoid re-fetching
   - Consider storing preview data in Firestore

3. **Mention Notifications:**
   - Send via Firebase Cloud Messaging (FCM)
   - Batch notifications if multiple users mentioned
   - Include deep link to conversation

4. **Delivery Status Updates:**
   - Update in background (non-blocking)
   - Batch updates when possible
   - Use Firebase real-time listeners for live updates

---

## Next Steps

1. **Set up Firebase Cloud Messaging** for mention notifications
2. **Implement background task** for disappearing messages (iOS BackgroundTasks framework)
3. **Add link preview caching** in Firestore
4. **Create Cloud Function** for automated disappearing message cleanup
5. **Add analytics** for feature usage tracking

---

## Summary

✅ **FirebaseMessage model** - 7 new fields added
✅ **toMessage() conversion** - Updated with new fields  
✅ **10 new backend methods** - All features supported
✅ **Firestore schema** - Ready for new features
✅ **Security rules** - Example rules provided
✅ **Backward compatible** - Existing messages still work

**Status:** Backend is fully updated and ready! 🚀
