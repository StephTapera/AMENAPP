# Unread Message Badge - Code Snippets

## Quick Copy-Paste Reference

### 1. UnreadBadge Component (Add to ContentView.swift)

```swift
// MARK: - Unread Badge Component

struct UnreadBadge: View {
    let count: Int
    let pulse: Bool
    
    var body: some View {
        ZStack {
            // Pulse circle background (appears when new message arrives)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            // Main badge
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: count > 9 ? 20 : 16, height: 16)
                .shadow(color: .red.opacity(0.5), radius: 4, x: 0, y: 2)
            
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: count > 9 ? 9 : 10, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
        .scaleEffect(pulse ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulse)
        .transition(.scale.combined(with: .opacity))
    }
}
```

### 2. CompactTabBar State Variables (Add to CompactTabBar struct)

```swift
struct CompactTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatePost: Bool
    @StateObject private var messagingService = FirebaseMessagingService.shared
    
    // ADD THESE TWO LINES ↓
    @State private var previousUnreadCount: Int = 0
    @State private var badgePulse: Bool = false
    
    // ... rest of the struct
}
```

### 3. Unread Count Computed Property (Add to CompactTabBar)

```swift
// Computed property for total unread count
private var totalUnreadCount: Int {
    messagingService.conversations.reduce(0) { $0 + $1.unreadCount }
}
```

### 4. Badge Display in Tab Button (Replace Messages tab button content)

```swift
ForEach(leftTabs, id: \.tag) { tab in
    Button {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedTab = tab.tag
        }
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    } label: {
        ZStack(alignment: .topTrailing) {
            Image(systemName: tab.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(selectedTab == tab.tag ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .scaleEffect(selectedTab == tab.tag ? 1.05 : 1.0)
            
            // ADD THIS BLOCK ↓
            // 🔴 Unread badge for Messages tab with smooth animation
            if tab.tag == 1 && totalUnreadCount > 0 {
                UnreadBadge(count: totalUnreadCount, pulse: badgePulse)
                    .offset(x: 12, y: 4)
            }
        }
    }
    .buttonStyle(PlainButtonStyle())
}
```

### 5. Change Detection with Animation (Add to CompactTabBar body)

```swift
var body: some View {
    ZStack {
        // ... existing tab bar code
    }
    // ADD THIS MODIFIER ↓
    .onChange(of: totalUnreadCount) { oldValue, newValue in
        // Trigger pulse animation when unread count increases
        if newValue > oldValue {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                badgePulse = true
            }
            
            // Haptic feedback for new message
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            // Reset pulse after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    badgePulse = false
                }
            }
        }
        previousUnreadCount = newValue
    }
    .onAppear {
        previousUnreadCount = totalUnreadCount
    }
}
```

### 6. Update sendMessage() in FirebaseMessagingService.swift

```swift
/// Send a text message
func sendMessage(
    conversationId: String,
    text: String,
    replyToMessageId: String? = nil
) async throws {
    let messageRef = db.collection("conversations")
        .document(conversationId)
        .collection("messages")
        .document()
    
    var replyToMessage: FirebaseMessage.ReplyInfo? = nil
    
    // Fetch reply-to message if specified
    if let replyToId = replyToMessageId {
        let replyDoc = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(replyToId)
            .getDocument()
        
        if let replyData = try? replyDoc.data(as: FirebaseMessage.self),
           let replyMessageId = replyData.id {
            replyToMessage = FirebaseMessage.ReplyInfo(
                messageId: replyMessageId,
                text: replyData.text,
                senderId: replyData.senderId,
                senderName: replyData.senderName
            )
        }
    }
    
    let message = FirebaseMessage(
        id: messageRef.documentID,
        conversationId: conversationId,
        senderId: currentUserId,
        senderName: currentUserName,
        text: text,
        attachments: [],
        reactions: [],
        replyTo: replyToMessage,
        timestamp: Timestamp(date: Date()),
        readBy: [currentUserId]
    )
    
    // ADD THIS BLOCK ↓
    // Fetch conversation to get participants
    let conversationRef = db.collection("conversations").document(conversationId)
    let conversationDoc = try await conversationRef.getDocument()
    let participantIds = conversationDoc.data()?["participantIds"] as? [String] ?? []
    
    // Use batch to update both message and conversation
    let batch = db.batch()
    
    try batch.setData(from: message, forDocument: messageRef)
    
    // MODIFY THIS BLOCK ↓
    // Build unread count updates for other participants
    var updates: [String: Any] = [
        "lastMessageText": text,
        "lastMessageTimestamp": Timestamp(date: Date()),
        "updatedAt": Timestamp(date: Date())
    ]
    
    // Increment unread count for all participants except sender
    for participantId in participantIds where participantId != currentUserId {
        updates["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
    }
    
    batch.updateData(updates, forDocument: conversationRef)
    
    try await batch.commit()
    
    print("✅ Message sent and unread counts updated for other participants")
}
```

### 7. Update sendMessageWithPhotos() in FirebaseMessagingService.swift

```swift
/// Send a message with photo attachments
func sendMessageWithPhotos(
    conversationId: String,
    text: String,
    images: [UIImage]
) async throws {
    // Upload images first
    let attachments = try await uploadImages(images, conversationId: conversationId)
    
    let messageRef = db.collection("conversations")
        .document(conversationId)
        .collection("messages")
        .document()
    
    let message = FirebaseMessage(
        id: messageRef.documentID,
        conversationId: conversationId,
        senderId: currentUserId,
        senderName: currentUserName,
        text: text,
        attachments: attachments,
        reactions: [],
        replyTo: nil,
        timestamp: Timestamp(date: Date()),
        readBy: [currentUserId]
    )
    
    // ADD THIS BLOCK ↓
    // Fetch conversation to get participants
    let conversationRef = db.collection("conversations").document(conversationId)
    let conversationDoc = try await conversationRef.getDocument()
    let participantIds = conversationDoc.data()?["participantIds"] as? [String] ?? []
    
    let batch = db.batch()
    
    try batch.setData(from: message, forDocument: messageRef)
    
    // MODIFY THIS BLOCK ↓
    // Build unread count updates for other participants
    var updates: [String: Any] = [
        "lastMessageText": text.isEmpty ? "📷 Photo" : text,
        "lastMessageTimestamp": Timestamp(date: Date()),
        "updatedAt": Timestamp(date: Date())
    ]
    
    // Increment unread count for all participants except sender
    for participantId in participantIds where participantId != currentUserId {
        updates["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
    }
    
    batch.updateData(updates, forDocument: conversationRef)
    
    try await batch.commit()
    
    print("✅ Photo message sent and unread counts updated for other participants")
}
```

### 8. Update markMessagesAsRead() in FirebaseMessagingService.swift

```swift
/// Mark messages as read
func markMessagesAsRead(conversationId: String, messageIds: [String]) async throws {
    guard !messageIds.isEmpty else { return }
    
    let batch = db.batch()
    
    for messageId in messageIds {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        batch.updateData([
            "readBy": FieldValue.arrayUnion([currentUserId])
        ], forDocument: messageRef)
    }
    
    // ADD THIS BLOCK ↓
    // Reset unread count for current user in conversation
    let conversationRef = db.collection("conversations").document(conversationId)
    batch.updateData([
        "unreadCounts.\(currentUserId)": 0
    ], forDocument: conversationRef)
    
    try await batch.commit()
    
    print("✅ Marked \(messageIds.count) messages as read and cleared unread count")
}
```

## Testing Snippets

### Create Test Conversation with Unread Count

```swift
// In Firebase Console or test script
// conversations/{conversationId}
{
  "participantIds": ["user1", "user2"],
  "participantNames": {
    "user1": "John Doe",
    "user2": "Jane Smith"
  },
  "isGroup": false,
  "lastMessageText": "Test message",
  "lastMessageTimestamp": Timestamp.now(),
  "unreadCounts": {
    "user1": 5,  // John has 5 unread
    "user2": 0   // Jane has read all
  }
}
```

### Debug Print Unread Count

```swift
// Add to CompactTabBar body to debug
.onAppear {
    print("🔍 Total unread count: \(totalUnreadCount)")
    print("🔍 Conversations: \(messagingService.conversations.count)")
    for conversation in messagingService.conversations {
        print("   - \(conversation.name): \(conversation.unreadCount) unread")
    }
}
```

### Force Badge Pulse (for testing)

```swift
// Add a test button somewhere in your UI
Button("Test Pulse") {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
        badgePulse = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        withAnimation {
            badgePulse = false
        }
    }
}
```

### Simulate New Message

```swift
// In MessagesView or a test view
Button("Simulate New Message") {
    Task {
        try? await FirebaseMessagingService.shared.sendMessage(
            conversationId: "test_conversation_id",
            text: "Test message at \(Date())"
        )
    }
}
```

## SwiftUI Preview

```swift
#Preview("Unread Badge") {
    VStack(spacing: 40) {
        // Different states
        UnreadBadge(count: 1, pulse: false)
            .previewDisplayName("1 unread")
        
        UnreadBadge(count: 5, pulse: false)
            .previewDisplayName("5 unread")
        
        UnreadBadge(count: 23, pulse: false)
            .previewDisplayName("23 unread")
        
        UnreadBadge(count: 150, pulse: false)
            .previewDisplayName("99+")
        
        UnreadBadge(count: 3, pulse: true)
            .previewDisplayName("With pulse")
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
```

## Firestore Security Rules

```javascript
// Add to firestore.rules
match /conversations/{conversationId} {
  allow read: if request.auth != null && 
              request.auth.uid in resource.data.participantIds;
  
  allow write: if request.auth != null && 
               request.auth.uid in resource.data.participantIds;
  
  // Allow updating unread counts
  allow update: if request.auth != null && 
                request.auth.uid in resource.data.participantIds &&
                request.resource.data.diff(resource.data).affectedKeys()
                  .hasOnly(['unreadCounts', 'lastMessageText', 
                           'lastMessageTimestamp', 'updatedAt']);
}
```

## Performance Monitoring

```swift
// Add to FirebaseMessagingService
func logUnreadCountPerformance() {
    let startTime = Date()
    let count = conversations.reduce(0) { $0 + $1.unreadCount }
    let duration = Date().timeIntervalSince(startTime)
    
    print("⏱️ Unread count calculation took \(duration * 1000)ms")
    print("   Result: \(count) unread across \(conversations.count) conversations")
    
    if duration > 0.1 {
        print("⚠️ Slow unread count calculation!")
    }
}
```

## Migration Script (if you have existing data)

```swift
// Run this once to initialize unreadCounts for existing conversations
func migrateUnreadCounts() async {
    let db = Firestore.firestore()
    
    do {
        let conversations = try await db.collection("conversations").getDocuments()
        
        for doc in conversations.documents {
            let participantIds = doc.data()["participantIds"] as? [String] ?? []
            
            var unreadCounts: [String: Int] = [:]
            for participantId in participantIds {
                unreadCounts[participantId] = 0
            }
            
            try await doc.reference.updateData([
                "unreadCounts": unreadCounts
            ])
            
            print("✅ Migrated conversation: \(doc.documentID)")
        }
        
        print("✅ Migration complete!")
    } catch {
        print("❌ Migration failed: \(error)")
    }
}
```

---

**Usage**: Copy and paste these snippets directly into your project!  
**Status**: ✅ Production-Ready  
**Last Updated**: January 24, 2026
