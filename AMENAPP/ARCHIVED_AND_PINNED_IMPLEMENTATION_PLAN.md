# Archived & Pinned Messages Implementation Plan

## 📊 Current State Analysis

### ✅ What You Have:
- Complete messaging backend (`MessageService.swift`)
- Conversation model (`Conversation` struct)
- Message model (`Message` struct)
- Firestore integration with real-time listeners
- Basic conversation queries working

### ❌ What's Missing for Archives & Pins:

#### **1. Model Properties:**
```swift
// Conversation model needs:
var isArchived: Bool = false           // ❌ Missing
var archivedBy: [String] = []          // ❌ Missing (multiple users)

// Message model needs:
var isPinned: Bool = false             // ❌ Missing
var pinnedBy: String?                  // ❌ Missing
var pinnedAt: Date?                    // ❌ Missing
```

#### **2. Service Methods:**
```swift
// MessageService needs:
func archiveConversation(_:)           // ❌ Missing
func unarchiveConversation(_:)         // ❌ Missing
func fetchArchivedConversations()      // ❌ Missing

func pinMessage(_:)                    // ❌ Missing
func unpinMessage(_:)                  // ❌ Missing
func fetchPinnedMessages(in:)          // ❌ Missing
```

#### **3. Firestore Indexes:**
- Archive query index                  // ❌ Not created yet
- Pinned messages index                // ❌ Not created yet

---

## 🎯 Implementation Steps

### Step 1: Update Models

#### **MessageModels.swift** - Add archive support to Conversation:

```swift
struct Conversation: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var participants: [String]
    var participantNames: [String: String]
    var participantPhotos: [String: String]
    var lastMessage: String
    var lastMessageSenderId: String
    var lastMessageTime: Date
    var unreadCount: [String: Int]
    
    // NEW: Archive support
    var isArchived: Bool                // Global archive flag (optional)
    var archivedBy: [String]            // Array of userIds who archived this
    
    var createdAt: Date
    var updatedAt: Date
    
    // NEW: Helper method
    func isArchivedByUser(_ userId: String) -> Bool {
        archivedBy.contains(userId)
    }
}
```

#### **MessageModels.swift** - Add pin support to Message:

```swift
struct Message: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var conversationId: String
    var senderId: String
    var senderName: String
    var senderPhoto: String?
    var content: String
    var type: MessageType
    var timestamp: Date
    var isRead: Bool
    var readAt: Date?
    var isDelivered: Bool
    var deliveredAt: Date?
    
    // NEW: Pin support
    var isPinned: Bool
    var pinnedBy: String?               // UserId who pinned
    var pinnedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case senderId
        case senderName
        case senderPhoto
        case content
        case type
        case timestamp
        case isRead
        case readAt
        case isDelivered
        case deliveredAt
        // NEW
        case isPinned
        case pinnedBy
        case pinnedAt
    }
}
```

---

### Step 2: Add Service Methods

#### **MessageService.swift** - Archive functionality:

```swift
// MARK: - Archive Conversations

/// Archive a conversation for current user
func archiveConversation(_ conversationId: String) async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    print("📦 Archiving conversation: \(conversationId)")
    
    try await db.collection("conversations").document(conversationId).updateData([
        "archivedBy": FieldValue.arrayUnion([currentUserId]),
        "updatedAt": Date()
    ])
    
    print("✅ Conversation archived")
}

/// Unarchive a conversation for current user
func unarchiveConversation(_ conversationId: String) async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    print("📬 Unarchiving conversation: \(conversationId)")
    
    try await db.collection("conversations").document(conversationId).updateData([
        "archivedBy": FieldValue.arrayRemove([currentUserId]),
        "updatedAt": Date()
    ])
    
    print("✅ Conversation unarchived")
}

/// Fetch archived conversations (requires Firestore index)
func fetchArchivedConversations() async throws -> [Conversation] {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    print("📥 Fetching archived conversations")
    
    do {
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("archivedBy", arrayContains: currentUserId)
            .order(by: "lastMessageTime", descending: true)
            .getDocuments()
        
        let archived = try snapshot.documents.compactMap { doc in
            try doc.data(as: Conversation.self)
        }
        
        print("✅ Fetched \(archived.count) archived conversations")
        return archived
        
    } catch {
        print("❌ Error fetching archived conversations: \(error)")
        throw error
    }
}

/// Fetch only non-archived conversations
func fetchActiveConversations() async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    print("📥 Fetching active (non-archived) conversations")
    isLoading = true
    
    do {
        // This query will need an index when you add archivedBy filtering
        let snapshot = try await db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            // Filter out conversations where current user has archived them
            .order(by: "lastMessageTime", descending: true)
            .getDocuments()
        
        conversations = try snapshot.documents.compactMap { doc in
            try doc.data(as: Conversation.self)
        }.filter { conversation in
            // Client-side filter for now
            !conversation.archivedBy.contains(currentUserId)
        }
        
        calculateUnreadCount()
        print("✅ Fetched \(conversations.count) active conversations")
        isLoading = false
        
    } catch {
        print("❌ Error fetching conversations: \(error)")
        self.error = error.localizedDescription
        isLoading = false
        throw error
    }
}
```

#### **MessageService.swift** - Pin functionality:

```swift
// MARK: - Pin Messages

/// Pin a message in a conversation
func pinMessage(_ messageId: String, in conversationId: String) async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    print("📌 Pinning message: \(messageId)")
    
    try await db.collection("messages").document(messageId).updateData([
        "isPinned": true,
        "pinnedBy": currentUserId,
        "pinnedAt": Date()
    ])
    
    print("✅ Message pinned")
}

/// Unpin a message
func unpinMessage(_ messageId: String) async throws {
    guard let currentUserId = firebaseManager.currentUser?.uid else {
        throw FirebaseError.unauthorized
    }
    
    print("📌 Unpinning message: \(messageId)")
    
    try await db.collection("messages").document(messageId).updateData([
        "isPinned": false,
        "pinnedBy": FieldValue.delete(),
        "pinnedAt": FieldValue.delete()
    ])
    
    print("✅ Message unpinned")
}

/// Fetch pinned messages in a conversation (requires Firestore index)
func fetchPinnedMessages(in conversationId: String) async throws -> [Message] {
    print("📥 Fetching pinned messages for: \(conversationId)")
    
    do {
        let snapshot = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("isPinned", isEqualTo: true)
            .order(by: "pinnedAt", descending: true)
            .getDocuments()
        
        let pinned = try snapshot.documents.compactMap { doc in
            try doc.data(as: Message.self)
        }
        
        print("✅ Fetched \(pinned.count) pinned messages")
        return pinned
        
    } catch {
        print("❌ Error fetching pinned messages: \(error)")
        throw error
    }
}
```

---

### Step 3: Update Model Initializers

#### **MessageModels.swift** - Update Conversation init:

```swift
init(
    id: String? = nil,
    participants: [String],
    participantNames: [String: String] = [:],
    participantPhotos: [String: String] = [:],
    lastMessage: String = "",
    lastMessageSenderId: String = "",
    lastMessageTime: Date = Date(),
    unreadCount: [String: Int] = [:],
    isArchived: Bool = false,           // NEW
    archivedBy: [String] = [],          // NEW
    createdAt: Date = Date(),
    updatedAt: Date = Date()
) {
    self.id = id
    self.participants = participants
    self.participantNames = participantNames
    self.participantPhotos = participantPhotos
    self.lastMessage = lastMessage
    self.lastMessageSenderId = lastMessageSenderId
    self.lastMessageTime = lastMessageTime
    self.unreadCount = unreadCount
    self.isArchived = isArchived        // NEW
    self.archivedBy = archivedBy        // NEW
    self.createdAt = createdAt
    self.updatedAt = updatedAt
}
```

#### **MessageModels.swift** - Update Message init:

```swift
init(
    id: String? = nil,
    conversationId: String,
    senderId: String,
    senderName: String,
    senderPhoto: String? = nil,
    content: String,
    type: MessageType = .text,
    timestamp: Date = Date(),
    isRead: Bool = false,
    readAt: Date? = nil,
    isDelivered: Bool = false,
    deliveredAt: Date? = nil,
    isPinned: Bool = false,             // NEW
    pinnedBy: String? = nil,            // NEW
    pinnedAt: Date? = nil               // NEW
) {
    self.id = id
    self.conversationId = conversationId
    self.senderId = senderId
    self.senderName = senderName
    self.senderPhoto = senderPhoto
    self.content = content
    self.type = type
    self.timestamp = timestamp
    self.isRead = isRead
    self.readAt = readAt
    self.isDelivered = isDelivered
    self.deliveredAt = deliveredAt
    self.isPinned = isPinned            // NEW
    self.pinnedBy = pinnedBy            // NEW
    self.pinnedAt = pinnedAt            // NEW
}
```

---

### Step 4: Update CodingKeys

#### **MessageModels.swift** - Conversation:

```swift
enum CodingKeys: String, CodingKey {
    case id
    case participants
    case participantNames
    case participantPhotos
    case lastMessage
    case lastMessageSenderId
    case lastMessageTime
    case unreadCount
    case isArchived         // NEW
    case archivedBy         // NEW
    case createdAt
    case updatedAt
}
```

#### **MessageModels.swift** - Message:

```swift
enum CodingKeys: String, CodingKey {
    case id
    case conversationId
    case senderId
    case senderName
    case senderPhoto
    case content
    case type
    case timestamp
    case isRead
    case readAt
    case isDelivered
    case deliveredAt
    case isPinned           // NEW
    case pinnedBy           // NEW
    case pinnedAt           // NEW
}
```

---

### Step 5: Create Firestore Indexes

#### **When You Try to Use These Features:**

**A. Archived Conversations Query:**
```swift
// This query will trigger an index creation prompt
db.collection("conversations")
  .whereField("participantIds", arrayContains: currentUserId)
  .whereField("archivedBy", arrayContains: currentUserId)
  .order(by: "lastMessageTime", descending: true)
```

**Firebase will show:**
```
⚠️ The query requires an index. You can create it here: 
[CLICK THIS LINK TO CREATE INDEX]
```

**Index Fields:**
- Collection: `conversations`
- `participantIds` - Array
- `archivedBy` - Array
- `lastMessageTime` - Descending

---

**B. Pinned Messages Query:**
```swift
// This query will trigger an index creation prompt
db.collection("messages")
  .whereField("conversationId", isEqualTo: conversationId)
  .whereField("isPinned", isEqualTo: true)
  .order(by: "pinnedAt", descending: true)
```

**Index Fields:**
- Collection: `messages`
- `conversationId` - Ascending
- `isPinned` - Ascending
- `pinnedAt` - Descending

---

### Step 6: UI Components

#### **ArchivedConversationsView.swift** (New file):

```swift
import SwiftUI

struct ArchivedConversationsView: View {
    @StateObject private var messageService = MessageService.shared
    @State private var archivedConversations: [Conversation] = []
    @State private var isLoading = false
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if archivedConversations.isEmpty {
                ContentUnavailableView(
                    "No Archived Chats",
                    systemImage: "archivebox",
                    description: Text("Your archived conversations will appear here")
                )
            } else {
                ForEach(archivedConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task {
                                    try? await messageService.unarchiveConversation(conversation.id!)
                                    await loadArchived()
                                }
                            } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .navigationTitle("Archived")
        .task {
            await loadArchived()
        }
    }
    
    private func loadArchived() async {
        isLoading = true
        do {
            archivedConversations = try await messageService.fetchArchivedConversations()
        } catch {
            print("Error loading archived: \(error)")
        }
        isLoading = false
    }
}
```

#### **PinnedMessagesView.swift** (New file):

```swift
import SwiftUI

struct PinnedMessagesView: View {
    let conversationId: String
    @StateObject private var messageService = MessageService.shared
    @State private var pinnedMessages: [Message] = []
    @State private var isLoading = false
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if pinnedMessages.isEmpty {
                ContentUnavailableView(
                    "No Pinned Messages",
                    systemImage: "pin.slash",
                    description: Text("Pin important messages to keep them at the top")
                )
            } else {
                ForEach(pinnedMessages) { message in
                    MessageRow(message: message)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task {
                                    try? await messageService.unpinMessage(message.id!)
                                    await loadPinned()
                                }
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Pinned Messages")
        .task {
            await loadPinned()
        }
    }
    
    private func loadPinned() async {
        isLoading = true
        do {
            pinnedMessages = try await messageService.fetchPinnedMessages(in: conversationId)
        } catch {
            print("Error loading pinned: \(error)")
        }
        isLoading = false
    }
}
```

#### **Add swipe actions to existing MessagesView:**

```swift
// In MessagesView.swift
List(messageService.conversations) { conversation in
    ConversationRow(conversation: conversation)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await messageService.archiveConversation(conversation.id!)
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
}
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        NavigationLink(destination: ArchivedConversationsView()) {
            Image(systemName: "archivebox")
        }
    }
}
```

#### **Add context menu to messages in ChatView:**

```swift
// In ChatView.swift - MessageBubble
MessageBubble(message: message)
    .contextMenu {
        Button {
            Task {
                if message.isPinned {
                    try? await messageService.unpinMessage(message.id!)
                } else {
                    try? await messageService.pinMessage(message.id!, in: conversationId)
                }
            }
        } label: {
            Label(
                message.isPinned ? "Unpin" : "Pin", 
                systemImage: message.isPinned ? "pin.slash" : "pin"
            )
        }
    }

// Show pinned messages button
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        NavigationLink(destination: PinnedMessagesView(conversationId: conversationId)) {
            Image(systemName: "pin")
        }
    }
}
```

---

## 🔐 Update Firestore Security Rules

### Add archive support:

```javascript
// conversations/{conversationId}
match /conversations/{conversationId} {
  allow read: if request.auth != null && 
                 request.auth.uid in resource.data.participants;
  
  allow update: if request.auth != null && 
                   request.auth.uid in resource.data.participants &&
                   // Allow updating archivedBy array
                   request.resource.data.archivedBy is list;
}
```

### Add pin support:

```javascript
// messages/{messageId}
match /messages/{messageId} {
  allow update: if request.auth != null &&
                   // Allow pinning/unpinning
                   (request.resource.data.keys().hasOnly(['isPinned', 'pinnedBy', 'pinnedAt']) ||
                    request.auth.uid == resource.data.senderId);
}
```

---

## ✅ Implementation Checklist

### Models:
- [ ] Add `isArchived` and `archivedBy` to `Conversation`
- [ ] Add `isPinned`, `pinnedBy`, `pinnedAt` to `Message`
- [ ] Update CodingKeys for both models
- [ ] Update initializers with default values

### Services:
- [ ] Add `archiveConversation()` method
- [ ] Add `unarchiveConversation()` method
- [ ] Add `fetchArchivedConversations()` method
- [ ] Add `pinMessage()` method
- [ ] Add `unpinMessage()` method
- [ ] Add `fetchPinnedMessages()` method

### UI:
- [ ] Create `ArchivedConversationsView`
- [ ] Create `PinnedMessagesView`
- [ ] Add swipe action to archive in `MessagesView`
- [ ] Add context menu to pin in `ChatView`
- [ ] Add toolbar buttons for archived/pinned
- [ ] Test archive/unarchive flow
- [ ] Test pin/unpin flow

### Backend:
- [ ] Update Firestore security rules
- [ ] Test archive query (will trigger index prompt)
- [ ] Click Firestore error link to create archive index
- [ ] Test pin query (will trigger index prompt)
- [ ] Click Firestore error link to create pin index
- [ ] Verify indexes are building in console

---

## 🎯 Testing Plan

### Test Archive:
1. ✅ Archive a conversation via swipe action
2. ✅ Verify it disappears from main list
3. ✅ Navigate to Archived view
4. ✅ Verify conversation appears there
5. ✅ Unarchive conversation
6. ✅ Verify it returns to main list

### Test Pin:
1. ✅ Long-press message in chat
2. ✅ Select "Pin" from context menu
3. ✅ Verify message is pinned
4. ✅ Navigate to Pinned Messages view
5. ✅ Verify message appears there
6. ✅ Unpin message
7. ✅ Verify it's removed from pinned list

---

## 📊 Summary

### ✅ What's Possible:
**YES** - Both archived conversations and pinned messages are fully implementable with:
- Minor model updates (add 3 properties each)
- 6 new service methods
- 2 new UI screens
- 2 Firestore indexes (auto-created on first use)

### 🚀 Implementation Time:
- **Models**: 15 minutes
- **Services**: 30 minutes
- **UI**: 45 minutes
- **Testing**: 30 minutes
- **Total**: ~2 hours

### 🎉 Outcome:
Your messaging system will support:
- ✅ Archive/unarchive conversations
- ✅ Pin/unpin important messages
- ✅ Separate views for archived and pinned
- ✅ Swipe actions and context menus
- ✅ Real-time updates
- ✅ Secure permissions

**Ready to implement! All infrastructure is in place.** 🚀
