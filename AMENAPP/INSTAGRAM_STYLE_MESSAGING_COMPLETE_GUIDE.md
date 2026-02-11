# 🎯 Instagram/Threads-Style Messaging Implementation

## Current Issues & Requirements

### ❌ Current Problems:
1. **No message limit** for non-mutual follows
2. **No message request tab** for pending conversations
3. **No instant delivery** to "Messages" for mutual follows
4. **No "Accept/Decline"** UI for message requests
5. **Typing disabled check** not implemented in chat view

### ✅ Required Behavior (Instagram/Threads Style):

#### **Scenario 1: Non-Mutual Follow (One Person Follows)**
- ✅ Can send **1 message only** (initial message)
- ❌ **Cannot type** more messages until recipient accepts
- 📬 Message goes to **"Message Requests" tab** for recipient
- ⏳ Conversation status: `"pending"`

#### **Scenario 2: Mutual Follow**
- ✅ Can send **unlimited messages**
- ✅ Messages appear in **"Messages" tab** immediately
- ⏳ Conversation status: `"accepted"`

#### **Scenario 3: No Follow Relationship**
- ✅ Can send **1 message only** (initial message)
- ❌ **Cannot type** more messages until recipient accepts
- 📬 Message goes to **"Message Requests" tab** for recipient
- ⏳ Conversation status: `"pending"`

---

## 🔧 Implementation Steps

### Step 1: Update Firestore Schema

Your `conversationStatus` field already exists! We need to track:

```javascript
{
  conversationStatus: "pending" | "accepted" | "declined" | "blocked",
  requesterId: "uid_who_sent_first_message",
  requestReadBy: ["uid1", "uid2"], // Track who read the request
  messageCount: {
    "user1_id": 0,  // Number of messages sent by user1
    "user2_id": 0   // Number of messages sent by user2
  }
}
```

### Step 2: Message Limit Logic

Before sending a message, check:
1. Is conversation `"pending"`?
2. If yes, has sender sent **1 message already**?
3. If yes, **prevent sending** (disable input)

### Step 3: Accept/Decline Request

When recipient accepts:
1. Update `conversationStatus` to `"accepted"`
2. Move conversation from "Requests" to "Messages"
3. Enable unlimited messaging for both users

### Step 4: Real-Time Updates

Use Firestore listeners to:
1. Listen for `conversationStatus` changes
2. Automatically move conversations between tabs
3. Enable/disable typing based on status

---

## 📝 Code Implementation

### 1. Enhanced FirebaseConversation Model

```swift
// Add to FirebaseMessagingService.swift

internal struct FirebaseConversation: Codable {
    @DocumentID var id: String?
    var participantIds: [String]
    var participantNames: [String: String]
    var isGroup: Bool
    var groupName: String?
    var groupAvatarUrl: String?
    var lastMessage: FirebaseMessage?
    var lastMessageText: String
    var lastMessageTimestamp: Date
    var unreadCounts: [String: Int]
    var createdAt: Date
    var updatedAt: Date
    
    // ✅ NEW: Message Request Fields
    var conversationStatus: String? // "pending", "accepted", "declined", "blocked"
    var requesterId: String? // User who sent the first message
    var requestReadBy: [String]? // Users who have seen the request
    var messageCount: [String: Int]? // Track messages per user
    
    enum CodingKeys: String, CodingKey {
        case id
        case participantIds
        case participantNames
        case isGroup
        case groupName
        case groupAvatarUrl
        case lastMessage
        case lastMessageText
        case lastMessageTimestamp
        case unreadCounts
        case createdAt
        case updatedAt
        case conversationStatus
        case requesterId
        case requestReadBy
        case messageCount
    }
}
```

### 2. Message Limit Check Function

```swift
// Add to FirebaseMessagingService.swift

/// Check if user can send a message in this conversation
func canSendMessage(conversationId: String) async throws -> (canSend: Bool, reason: String?) {
    guard isAuthenticated else {
        return (false, "Not authenticated")
    }
    
    // Fetch conversation
    let conversationRef = db.collection("conversations").document(conversationId)
    let doc = try await conversationRef.getDocument()
    
    guard doc.exists,
          let conversation = try? doc.data(as: FirebaseConversation.self) else {
        return (false, "Conversation not found")
    }
    
    let status = conversation.conversationStatus ?? "accepted"
    
    // ✅ If conversation is accepted, can always send
    if status == "accepted" {
        return (true, nil)
    }
    
    // ✅ If conversation is declined or blocked, cannot send
    if status == "declined" || status == "blocked" {
        return (false, "This conversation is not available")
    }
    
    // ✅ If conversation is pending
    if status == "pending" {
        let messageCount = conversation.messageCount?[currentUserId] ?? 0
        
        // Check if sender is the requester
        let isRequester = conversation.requesterId == currentUserId
        
        if isRequester {
            // Requester can only send 1 message
            if messageCount >= 1 {
                return (false, "Please wait for the recipient to accept your message request")
            } else {
                return (true, nil)
            }
        } else {
            // Recipient can send unlimited messages (accepting by sending a message)
            return (true, nil)
        }
    }
    
    return (true, nil)
}

/// Get message count for current user in conversation
func getMessageCount(conversationId: String) async throws -> Int {
    let conversationRef = db.collection("conversations").document(conversationId)
    let doc = try await conversationRef.getDocument()
    
    guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
        return 0
    }
    
    return conversation.messageCount?[currentUserId] ?? 0
}
```

### 3. Enhanced Send Message with Limit Check

```swift
// Replace existing sendMessage function in FirebaseMessagingService.swift

func sendMessage(
    conversationId: String,
    text: String,
    replyToMessageId: String? = nil,
    clientMessageId: String? = nil
) async throws {
    guard isAuthenticated else {
        throw FirebaseMessagingError.notAuthenticated
    }
    
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw FirebaseMessagingError.invalidInput("Message cannot be empty")
    }
    
    // ✅ NEW: Check if user can send message
    let (canSend, reason) = try await canSendMessage(conversationId: conversationId)
    guard canSend else {
        throw FirebaseMessagingError.invalidInput(reason ?? "Cannot send message")
    }
    
    do {
        let messageId = clientMessageId ?? db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document()
            .documentID
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
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
            id: messageId,
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
        
        // Fetch conversation to get participants and status
        let conversationRef = db.collection("conversations").document(conversationId)
        let conversationDoc = try await conversationRef.getDocument()
        
        guard conversationDoc.exists else {
            throw FirebaseMessagingError.conversationNotFound
        }
        
        guard let conversationData = conversationDoc.data(),
              let conversation = try? conversationDoc.data(as: FirebaseConversation.self) else {
            throw FirebaseMessagingError.conversationNotFound
        }
        
        let participantIds = conversation.participantIds
        let status = conversation.conversationStatus ?? "accepted"
        let requesterId = conversation.requesterId
        
        // Use batch to update both message and conversation
        let batch = db.batch()
        
        try batch.setData(from: message, forDocument: messageRef)
        
        // Build conversation updates
        var updates: [String: Any] = [
            "lastMessageText": text,
            "lastMessageTimestamp": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]
        
        // ✅ NEW: Increment message count for sender
        updates["messageCount.\(currentUserId)"] = FieldValue.increment(Int64(1))
        
        // ✅ NEW: Auto-accept if recipient sends a message
        if status == "pending" && requesterId != currentUserId {
            updates["conversationStatus"] = "accepted"
            print("✅ Conversation auto-accepted (recipient replied)")
        }
        
        // Increment unread count for all participants except sender
        for participantId in participantIds where participantId != currentUserId {
            updates["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
        }
        
        batch.updateData(updates, forDocument: conversationRef)
        
        try await batch.commit()
        
        print("✅ Message sent successfully")
    } catch let error as FirebaseMessagingError {
        print("❌ FirebaseMessagingError: \(error.localizedDescription)")
        throw error
    } catch {
        print("❌ Error sending message: \(error)")
        throw FirebaseMessagingError.networkError(error)
    }
}
```

### 4. Accept/Decline Request Functions

```swift
// Add to FirebaseMessagingService.swift

/// Accept a message request
func acceptMessageRequest(conversationId: String) async throws {
    guard isAuthenticated else {
        throw FirebaseMessagingError.notAuthenticated
    }
    
    let conversationRef = db.collection("conversations").document(conversationId)
    
    try await conversationRef.updateData([
        "conversationStatus": "accepted",
        "updatedAt": Timestamp(date: Date())
    ])
    
    print("✅ Message request accepted")
}

/// Decline a message request
func declineMessageRequest(conversationId: String) async throws {
    guard isAuthenticated else {
        throw FirebaseMessagingError.notAuthenticated
    }
    
    let conversationRef = db.collection("conversations").document(conversationId)
    
    try await conversationRef.updateData([
        "conversationStatus": "declined",
        "updatedAt": Timestamp(date: Date())
    ])
    
    print("✅ Message request declined")
}

/// Delete a message request
func deleteMessageRequest(conversationId: String) async throws {
    guard isAuthenticated else {
        throw FirebaseMessagingError.notAuthenticated
    }
    
    // Just decline it (don't actually delete to preserve data)
    try await declineMessageRequest(conversationId: conversationId)
}
```

---

## 🎨 UI Implementation

### 1. MessagesView with Tabs

Your existing code already has tabs! Update filtering:

```swift
// In MessagesView.swift

private var acceptedConversations: [ChatConversation] {
    messagingService.conversations.filter { conversation in
        let status = conversation.conversationStatus ?? "accepted"
        return status == "accepted"
    }
}

private var pendingConversations: [ChatConversation] {
    messagingService.conversations.filter { conversation in
        let status = conversation.conversationStatus
        let requesterId = conversation.requesterId
        
        // Show in requests if:
        // 1. Status is pending
        // 2. Current user is NOT the requester (they're the recipient)
        return status == "pending" && requesterId != Auth.auth().currentUser?.uid
    }
}

var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("Messages").tag(MessageTab.messages)
                if !pendingConversations.isEmpty {
                    Text("Requests (\(pendingConversations.count))").tag(MessageTab.requests)
                }
                Text("Archived").tag(MessageTab.archived)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content based on selected tab
            if selectedTab == .messages {
                conversationList(acceptedConversations)
            } else if selectedTab == .requests {
                requestsList(pendingConversations)
            } else {
                archivedList()
            }
        }
    }
}
```

### 2. Message Request Card with Accept/Decline

```swift
// Add to MessagesView.swift

private func requestsList(_ requests: [ChatConversation]) -> some View {
    List {
        if requests.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No message requests")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 100)
        } else {
            ForEach(requests) { conversation in
                MessageRequestCard(
                    conversation: conversation,
                    onAccept: {
                        Task {
                            await acceptRequest(conversation)
                        }
                    },
                    onDecline: {
                        Task {
                            await declineRequest(conversation)
                        }
                    },
                    onTap: {
                        // Allow viewing the request
                        activeSheet = .chat(conversation)
                    }
                )
            }
        }
    }
}

private func acceptRequest(_ conversation: ChatConversation) async {
    do {
        try await messagingService.acceptMessageRequest(conversationId: conversation.id)
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("✅ Request accepted")
    } catch {
        print("❌ Error accepting request: \(error)")
    }
}

private func declineRequest(_ conversation: ChatConversation) async {
    do {
        try await messagingService.declineMessageRequest(conversationId: conversation.id)
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        
        print("✅ Request declined")
    } catch {
        print("❌ Error declining request: \(error)")
    }
}
```

### 3. Message Request Card Component

```swift
// Create new file: MessageRequestCard.swift

struct MessageRequestCard: View {
    let conversation: ChatConversation
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(conversation.initials)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
                    
                    Text(conversation.lastMessage)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            
            // Action Buttons
            HStack(spacing: 12) {
                // Decline
                Button {
                    onDecline()
                } label: {
                    Text("Decline")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                }
                
                // Accept
                Button {
                    onAccept()
                } label: {
                    Text("Accept")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue)
                        )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}
```

### 4. Chat View with Typing Restriction

```swift
// Add to UnifiedChatView.swift (or your chat view)

@State private var canSendMessage = true
@State private var sendLimitMessage: String? = nil

var body: some View {
    VStack(spacing: 0) {
        // Messages list...
        
        // Input bar with restriction
        HStack(spacing: 12) {
            TextField("Message", text: $messageText)
                .disabled(!canSendMessage)
                .opacity(canSendMessage ? 1.0 : 0.5)
            
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSendMessage ? .blue : .gray)
            }
            .disabled(!canSendMessage || messageText.isEmpty)
        }
        .padding()
        
        // Restriction banner
        if !canSendMessage, let message = sendLimitMessage {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.systemYellow).opacity(0.1))
            }
        }
    }
    .task {
        await checkMessagePermission()
    }
}

func checkMessagePermission() async {
    do {
        let (canSend, reason) = try await messagingService.canSendMessage(conversationId: conversation.id)
        
        await MainActor.run {
            canSendMessage = canSend
            sendLimitMessage = reason
        }
    } catch {
        print("❌ Error checking message permission: \(error)")
    }
}
```

---

## 🎯 Complete Feature Checklist

### ✅ Backend (Firestore)
- [ ] `conversationStatus` field exists
- [ ] `messageCount` field tracks per-user messages
- [ ] `requesterId` field identifies who started conversation
- [ ] `canSendMessage()` function checks limits
- [ ] `sendMessage()` enforces limits
- [ ] `acceptMessageRequest()` updates status
- [ ] `declineMessageRequest()` updates status

### ✅ UI (SwiftUI)
- [ ] "Messages" tab shows `accepted` conversations
- [ ] "Requests" tab shows `pending` conversations (for recipients)
- [ ] Request cards have "Accept" and "Decline" buttons
- [ ] Chat view disables typing when limit reached
- [ ] Banner shows reason when typing disabled
- [ ] Real-time updates move conversations between tabs

### ✅ User Experience
- [ ] Non-mutual follow: Can send 1 message only
- [ ] Recipient sees message in "Requests" tab
- [ ] Accepting enables unlimited messaging
- [ ] Mutual follow: Messages go straight to "Messages" tab
- [ ] Typing disabled with clear reason shown

---

## 🚀 Testing Checklist

Test these scenarios:

1. **Non-Mutual Follow → Send Request**
   - [ ] User A follows User B (but B doesn't follow A)
   - [ ] User A sends message to User B
   - [ ] Message appears in User B's "Requests" tab
   - [ ] User A cannot send another message (typing disabled)

2. **Accept Request → Enable Messaging**
   - [ ] User B accepts request
   - [ ] Conversation moves to "Messages" tab
   - [ ] Both users can now send unlimited messages

3. **Mutual Follow → Instant Messaging**
   - [ ] User A and User B follow each other
   - [ ] User A sends message
   - [ ] Message appears in User B's "Messages" tab (not "Requests")
   - [ ] Both can send unlimited messages

4. **Decline Request**
   - [ ] User B declines request
   - [ ] Conversation removed from requests
   - [ ] User A notified (optional)

---

**This is the complete Instagram/Threads-style messaging system!** 🎉

