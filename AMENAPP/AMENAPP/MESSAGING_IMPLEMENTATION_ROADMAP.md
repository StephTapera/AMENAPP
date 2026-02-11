# 🗺️ Messaging System - Implementation Roadmap

**Date**: February 10, 2026
**Status**: Partial implementation complete, backend integration needed

---

## ✅ What's Complete

### **1. Core Messaging Functionality**
- ✅ Send and receive messages
- ✅ Real-time message updates
- ✅ Message persistence
- ✅ Conversation creation (1-on-1 and group)
- ✅ Message requests system (pending/accepted flow)
- ✅ Read receipts and delivery status
- ✅ Typing indicators
- ✅ Last message preview
- ✅ Unread count badges
- ✅ Archive conversations
- ✅ Delete conversations
- ✅ Search conversations

### **2. UI Enhancements (Just Added!)**
- ✅ Profile photos on message cards
- ✅ Compact design (15% smaller cards)
- ✅ Pin indicator UI (📌 badge)
- ✅ Mute indicator UI (🔕 icon)
- ✅ Smart message previews (📷 🎤 📎 ❤️)
- ✅ Message status checkmarks
- ✅ Enhanced animations
- ✅ Glassmorphic design maintained

### **3. Data Model**
- ✅ ChatConversation model with new fields:
  - `profilePhotoURL: String?`
  - `isPinned: Bool`
  - `isMuted: Bool`
- ✅ Backward compatible defaults
- ✅ FirebaseConversation model complete
- ✅ Message model complete

### **4. Critical Bug Fixes**
- ✅ @DocumentID fallback fix (sender now sees messages!)
- ✅ Conversation filtering logic
- ✅ RequesterId tracking
- ✅ Status management (pending/accepted)

---

## 🚧 What Needs Implementation

### **1. Backend Functions (High Priority)**

#### **Pin/Unpin Conversations**
**Location**: `AMENAPP/FirebaseMessagingService.swift`
**Status**: ❌ Not implemented (TODO at line ~975)

**What's Needed**:
```swift
func pinConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    // Add current user to pinnedBy array
    try await convRef.updateData([
        "pinnedBy": FieldValue.arrayUnion([currentUserId])
    ])

    // Update local state
    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
        var updated = conversations[index]
        updated.isPinned = true
        conversations[index] = updated
    }
}

func unpinConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    // Remove current user from pinnedBy array
    try await convRef.updateData([
        "pinnedBy": FieldValue.arrayRemove([currentUserId])
    ])

    // Update local state
    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
        var updated = conversations[index]
        updated.isPinned = false
        conversations[index] = updated
    }
}
```

**Firestore Changes**:
- Add `pinnedBy: [String]` array field to conversations collection
- Update listener to check if currentUserId is in pinnedBy array
- Sort pinned conversations to top of list

---

#### **Mute/Unmute Conversations**
**Location**: `AMENAPP/FirebaseMessagingService.swift`
**Status**: ❌ Not implemented (TODO at line ~960)

**What's Needed**:
```swift
func muteConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    // Add current user to mutedBy array
    try await convRef.updateData([
        "mutedBy": FieldValue.arrayUnion([currentUserId])
    ])

    // Update local state
    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
        var updated = conversations[index]
        updated.isMuted = true
        conversations[index] = updated
    }
}

func unmuteConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    // Remove current user from mutedBy array
    try await convRef.updateData([
        "mutedBy": FieldValue.arrayRemove([currentUserId])
    ])

    // Update local state
    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
        var updated = conversations[index]
        updated.isMuted = false
        conversations[index] = updated
    }
}
```

**Firestore Changes**:
- Add `mutedBy: [String]` array field to conversations collection
- Update listener to check if currentUserId is in mutedBy array
- Suppress notifications for muted conversations

---

#### **Report Spam Functionality**
**Location**: `AMENAPP/FirebaseMessagingService.swift`
**Status**: ❌ Not implemented (TODO at line ~1045)

**What's Needed**:
```swift
func reportSpam(_ conversationId: String, reason: String) async throws {
    let db = Firestore.firestore()

    // Create report document
    let reportData: [String: Any] = [
        "conversationId": conversationId,
        "reportedBy": currentUserId,
        "reason": reason,
        "timestamp": FieldValue.serverTimestamp(),
        "status": "pending"
    ]

    try await db.collection("spamReports").addDocument(data: reportData)

    // Optionally block the conversation
    try await blockConversation(conversationId)
}
```

**Firestore Changes**:
- Create `spamReports` collection
- Add moderation workflow for reviewing reports
- Auto-block after multiple reports (optional)

---

#### **Profile Photo URL Population**
**Location**: `AMENAPP/FirebaseMessagingService.swift` (conversation listener)
**Status**: ❌ Not implemented

**What's Needed**:
```swift
// In conversation listener, after decoding FirebaseConversation:
// Fetch profile photo for the other participant
let otherParticipant = firebaseConv.participantIds.first { $0 != currentUserId }

if let userId = otherParticipant {
    // Fetch user's profile photo URL
    let userDoc = try? await db.collection("users").document(userId).getDocument()
    if let photoURL = userDoc?.data()?["profilePhotoURL"] as? String {
        profilePhotoURL = photoURL
    }
}

// Update ChatConversation init:
ChatConversation(
    // ... other fields ...
    profilePhotoURL: profilePhotoURL  // ✅ Now populated
)
```

**Alternative**: Pre-cache profile photo URLs in conversations collection when conversation is created.

---

### **2. UI Interactions (Medium Priority)**

#### **Long-Press Context Menu**
**Location**: `AMENAPP/MessagesView.swift` (SmartConversationRow)
**Status**: ❌ Not implemented

**What's Needed**:
```swift
.contextMenu {
    // Pin/Unpin
    Button {
        if conversation.isPinned {
            Task { try? await messagingService.unpinConversation(conversation.id) }
        } else {
            Task { try? await messagingService.pinConversation(conversation.id) }
        }
    } label: {
        Label(
            conversation.isPinned ? "Unpin" : "Pin",
            systemImage: conversation.isPinned ? "pin.slash" : "pin"
        )
    }

    // Mute/Unmute
    Button {
        if conversation.isMuted {
            Task { try? await messagingService.unmuteConversation(conversation.id) }
        } else {
            Task { try? await messagingService.muteConversation(conversation.id) }
        }
    } label: {
        Label(
            conversation.isMuted ? "Unmute" : "Mute",
            systemImage: conversation.isMuted ? "speaker.wave.2" : "speaker.slash"
        )
    }

    Divider()

    // Archive
    Button(role: .destructive) {
        Task { try? await messagingService.archiveConversation(conversation.id) }
    } label: {
        Label("Archive", systemImage: "archivebox")
    }

    // Delete
    Button(role: .destructive) {
        showDeleteAlert = true
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

---

#### **Swipe Actions**
**Location**: `AMENAPP/MessagesView.swift` (conversation list)
**Status**: ❌ Not implemented

**What's Needed**:
```swift
// In ForEach for conversations:
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    // Delete
    Button(role: .destructive) {
        conversationToDelete = conversation
        showDeleteAlert = true
    } label: {
        Label("Delete", systemImage: "trash")
    }

    // Archive
    Button {
        Task {
            try? await messagingService.archiveConversation(conversation.id)
        }
    } label: {
        Label("Archive", systemImage: "archivebox")
    }
    .tint(.orange)
}
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    // Pin/Unpin
    Button {
        Task {
            if conversation.isPinned {
                try? await messagingService.unpinConversation(conversation.id)
            } else {
                try? await messagingService.pinConversation(conversation.id)
            }
        }
    } label: {
        Label(
            conversation.isPinned ? "Unpin" : "Pin",
            systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill"
        )
    }
    .tint(.yellow)

    // Mute/Unmute
    Button {
        Task {
            if conversation.isMuted {
                try? await messagingService.unmuteConversation(conversation.id)
            } else {
                try? await messagingService.muteConversation(conversation.id)
            }
        }
    } label: {
        Label(
            conversation.isMuted ? "Unmute" : "Mute",
            systemImage: conversation.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
        )
    }
    .tint(.purple)
}
```

---

#### **Error Alert Dialogs**
**Location**: `AMENAPP/MessagesView.swift`
**Status**: ❌ Missing user-facing error alerts (TODOs at lines 995, 1015, 1070)

**What's Needed**:
```swift
@State private var errorMessage: String?
@State private var showErrorAlert = false

// Replace print statements with:
.alert("Error", isPresented: $showErrorAlert) {
    Button("OK", role: .cancel) {}
} message: {
    if let error = errorMessage {
        Text(error)
    }
}

// Usage:
do {
    try await messagingService.deleteConversation(conversation.id)
} catch {
    errorMessage = "Failed to delete conversation: \(error.localizedDescription)"
    showErrorAlert = true
}
```

---

### **3. Data Migration (Low Priority)**

#### **Add New Fields to Existing Conversations**

**What's Needed**: Run a one-time migration script to add new fields to existing conversations in Firestore.

**Migration Script** (run in Firebase Console or Cloud Functions):
```javascript
const admin = require('firebase-admin');
const db = admin.firestore();

async function migrateConversations() {
  const conversations = await db.collection('conversations').get();

  const batch = db.batch();
  let count = 0;

  conversations.forEach(doc => {
    const ref = db.collection('conversations').doc(doc.id);
    batch.update(ref, {
      pinnedBy: [],  // Empty array for pinned users
      mutedBy: []    // Empty array for muted users
    });
    count++;

    // Firestore batch limit is 500
    if (count % 500 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  });

  await batch.commit();
  console.log(`Migrated ${count} conversations`);
}
```

**Alternative**: Add fields on-the-fly when conversations are first accessed (lazy migration).

---

#### **Populate Profile Photo URLs**

**Option 1**: Store in conversations collection (duplicates data but faster reads)
```swift
// When creating conversation:
let otherUserId = participantIds.first { $0 != currentUserId }
let userDoc = try? await db.collection("users").document(otherUserId).getDocument()
let profilePhotoURL = userDoc?.data()?["profilePhotoURL"] as? String

conversationData["profilePhotoURL"] = profilePhotoURL
```

**Option 2**: Fetch on-demand (saves storage but slower)
```swift
// In conversation listener, make parallel requests for all participant photos
let photoTasks = conversations.map { conv in
    fetchProfilePhoto(for: conv.otherParticipantId)
}
let photos = await withTaskGroup(of: String?.self) { group in
    // Fetch all photos in parallel
}
```

---

### **4. Firestore Rules & Indexes**

#### **Security Rules for New Fields**

Update `firestore.rules` to allow pin/mute operations:
```javascript
match /conversations/{conversationId} {
  allow update: if request.auth.uid in resource.data.participantIds
    && (
      // Allow updating pinnedBy
      request.resource.data.diff(resource.data).affectedKeys().hasOnly(['pinnedBy'])
      // Allow updating mutedBy
      || request.resource.data.diff(resource.data).affectedKeys().hasOnly(['mutedBy'])
    );
}
```

#### **Firestore Indexes**

From `MESSAGING_FIRESTORE_INDEXES_NEEDED.md`, these are still needed:

**Already Created**:
- ✅ `participantIds` (Ascending) + `updatedAt` (Descending)

**Still Needed** (will create when errors appear):
1. `participantIds` (Ascending) + `conversationStatus` (Ascending) + `updatedAt` (Descending)
2. `participantIds` (Ascending) + `conversationType` (Ascending) + `updatedAt` (Descending)
3. `conversationId` (Ascending) + `timestamp` (Descending) - for messages
4. `conversationId` (Ascending) + `senderId` (Ascending) + `timestamp` (Descending)
5. Several others for advanced queries

**Recommendation**: Create indexes on-demand when Firestore throws index errors (more efficient).

---

### **5. Notification Integration**

#### **Respect Muted Conversations**

**Location**: `AMENAPP/PushNotificationManager.swift` or Cloud Functions
**Status**: ❌ Not implemented

**What's Needed**:
```swift
// Before sending push notification, check if conversation is muted
func shouldSendNotification(conversationId: String, recipientId: String) async -> Bool {
    let db = Firestore.firestore()
    let doc = try? await db.collection("conversations").document(conversationId).getDocument()

    let mutedBy = doc?.data()?["mutedBy"] as? [String] ?? []

    // Don't send notification if recipient has muted this conversation
    return !mutedBy.contains(recipientId)
}
```

**Better**: Handle in Cloud Functions (server-side) to prevent unnecessary notification sends.

---

### **6. Settings & Management UI**

#### **Pinned Messages Section**

Create a new view to manage all pinned conversations:
```swift
struct PinnedMessagesView: View {
    @ObservedObject var messagingService: FirebaseMessagingService

    var pinnedConversations: [ChatConversation] {
        messagingService.conversations.filter { $0.isPinned }
    }

    var body: some View {
        List {
            ForEach(pinnedConversations) { conversation in
                // Conversation row
            }
        }
        .navigationTitle("Pinned Messages")
    }
}
```

#### **Muted Messages Section**

Similar to pinned, show all muted conversations with quick unmute option.

---

## 📋 Implementation Priority

### **Phase 1: Core Backend (Do First)**
1. ✅ Implement `pinConversation` / `unpinConversation`
2. ✅ Implement `muteConversation` / `unmuteConversation`
3. ✅ Add Firestore fields: `pinnedBy`, `mutedBy`
4. ✅ Update conversation listener to populate `isPinned`, `isMuted`
5. ✅ Implement profile photo URL population

### **Phase 2: UI Interactions**
1. ✅ Add long-press context menu
2. ✅ Add swipe actions
3. ✅ Add error alert dialogs
4. ✅ Sort pinned conversations to top of list

### **Phase 3: Advanced Features**
1. ✅ Respect muted conversations in notifications
2. ✅ Create settings pages for pinned/muted management
3. ✅ Implement report spam functionality
4. ✅ Add spam moderation workflow

### **Phase 4: Migration & Cleanup**
1. ✅ Migrate existing conversations (add new fields)
2. ✅ Populate profile photo URLs for all conversations
3. ✅ Create remaining Firestore indexes as needed
4. ✅ Remove debug logging (optional, keep for production monitoring)

---

## 🧪 Testing Checklist

### **What to Test Now** (Already Implemented):
- ✅ Send message and verify it appears in sender's Messages tab
- ✅ Receive message and verify real-time update
- ✅ Profile photos display correctly (or fallback to initials)
- ✅ Compact design looks good on all screen sizes
- ✅ Unread badges show correct count
- ✅ Message previews show correct icons

### **What to Test After Phase 1**:
- ❌ Pin a conversation and verify it stays at top
- ❌ Mute a conversation and verify no notifications
- ❌ Unpin/unmute and verify behavior returns to normal
- ❌ Profile photo updates reflect in real-time
- ❌ Pinned conversations survive app restart

### **What to Test After Phase 2**:
- ❌ Long-press context menu works on all conversations
- ❌ Swipe actions work smoothly
- ❌ Error alerts show when operations fail
- ❌ Haptic feedback feels natural

---

## 📝 Quick Start: Implement Pin/Mute

If you want to implement pin/mute functionality right now, here's what to do:

### **Step 1: Update FirebaseMessagingService.swift**

Add these functions after line ~460 (after `createConversation`):

```swift
// MARK: - Pin/Unpin Conversations

func pinConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    try await convRef.updateData([
        "pinnedBy": FieldValue.arrayUnion([currentUserId])
    ])

    await MainActor.run {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            var updated = conversations[index]
            updated.isPinned = true
            conversations[index] = updated

            // Re-sort to move pinned to top
            conversations.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned  // Pinned first
                }
                return lhs.timestamp > rhs.timestamp
            }
        }
    }
}

func unpinConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    try await convRef.updateData([
        "pinnedBy": FieldValue.arrayRemove([currentUserId])
    ])

    await MainActor.run {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            var updated = conversations[index]
            updated.isPinned = false
            conversations[index] = updated

            // Re-sort
            conversations.sort { $0.timestamp > $1.timestamp }
        }
    }
}

// MARK: - Mute/Unmute Conversations

func muteConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    try await convRef.updateData([
        "mutedBy": FieldValue.arrayUnion([currentUserId])
    ])

    await MainActor.run {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            var updated = conversations[index]
            updated.isMuted = true
            conversations[index] = updated
        }
    }
}

func unmuteConversation(_ conversationId: String) async throws {
    let db = Firestore.firestore()
    let convRef = db.collection("conversations").document(conversationId)

    try await convRef.updateData([
        "mutedBy": FieldValue.arrayRemove([currentUserId])
    ])

    await MainActor.run {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            var updated = conversations[index]
            updated.isMuted = false
            conversations[index] = updated
        }
    }
}
```

### **Step 2: Update Conversation Listener**

In `startListeningToConversations` function (around line 240-270), add:

```swift
// After decoding firebaseConv, check pin/mute status:
let pinnedBy = firebaseConv.pinnedBy ?? []
let mutedBy = firebaseConv.mutedBy ?? []
let isPinned = pinnedBy.contains(currentUserId)
let isMuted = mutedBy.contains(currentUserId)

// When creating ChatConversation:
let conversation = ChatConversation(
    // ... existing fields ...
    isPinned: isPinned,
    isMuted: isMuted
)
```

### **Step 3: Update FirebaseConversation Model**

Around line ~1800, add new fields:

```swift
struct FirebaseConversation: Codable {
    // ... existing fields ...

    var pinnedBy: [String]?
    var mutedBy: [String]?
}
```

### **Step 4: Add Context Menu to MessagesView**

Around line 3200 (after SmartConversationRow), add:

```swift
.contextMenu {
    Button {
        Task {
            try? await messagingService.pinConversation(conversation.id)
        }
    } label: {
        Label("Pin", systemImage: "pin")
    }

    Button {
        Task {
            try? await messagingService.muteConversation(conversation.id)
        }
    } label: {
        Label("Mute", systemImage: "speaker.slash")
    }
}
```

---

## 🎯 Summary

**Completed**: Core messaging, UI enhancements, bug fixes
**In Progress**: None currently
**Next Up**: Backend integration for pin/mute/spam features
**Blocked By**: Nothing - ready to implement!

The messaging system is **functionally complete** for basic use, but needs **backend integration** to make the new UI features (pin/mute indicators) actually functional.
