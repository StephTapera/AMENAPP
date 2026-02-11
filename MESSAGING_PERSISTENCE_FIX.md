# 🔧 Messaging Persistence & Real-Time Fix

**Date**: February 10, 2026  
**Status**: 🔍 **INVESTIGATING**

---

## 🐛 Reported Issues

1. **Messages don't persist**: When user sends a message and goes back/exits app, the message is gone
2. **Messages don't update in real-time**: Changes aren't reflected instantly

---

## 🔍 Investigation Summary

### **What's Working:**
✅ Conversation creation (status="pending" for new chats)  
✅ Real-time listener setup (`startListeningToMessages`)  
✅ Message sending to Firebase (`messagingService.sendMessage`)  
✅ Optimistic UI updates (messages appear immediately)  
✅ Firestore cache enabled (should persist offline)

### **Potential Issues:**

#### **Issue 1: Conversation ID Mismatch**
When creating a conversation through different flows, the conversation ID might be different:
- `MessageService.findOrCreateConversation` - creates one ID
- `FirebaseMessagingService.createConversation` - creates another ID
- Messages sent to conversation A, but user later opens conversation B

#### **Issue 2: Listener Not Reconnecting**
- Real-time listener starts in `UnifiedChatView.onAppear`
- If view is recreated, listener might not reconnect properly
- Pending messages dict is cleared when view dismissed

#### **Issue 3: Message Requests Flow**
- New conversations have `status = "pending"`
- Messages ARE being saved to Firebase
- But if conversation isn't in the main Messages tab (filtered out), user can't find it
- Need to ensure pending conversations show for the REQUESTER

---

## 🎯 Root Cause Analysis

Based on code review, the most likely issue is:

### **Conversation ID Consistency**

When user starts a new message:
1. `ProductionMessagingUserSearchView` calls `startConversation(with: selectedUser)`
2. This might create a NEW conversation each time
3. Messages sent to conversation_v1
4. User exits and comes back
5. Opens conversation_v2 (different ID!)
6. Messages don't appear because they're in conversation_v1

### **Evidence:**
- `FirebaseMessagingService.createConversation` always creates new doc: `.document()`
- No check for existing conversation before creating

---

## ✅ Solution: Implement `getOrCreateConversation`

Add a helper function that checks for existing conversations before creating new ones:

```swift
// In FirebaseMessagingService.swift

func getOrCreateConversation(
    with userId: String,
    participantName: String
) async throws -> String {
    guard isAuthenticated else {
        throw FirebaseMessagingError.notAuthenticated
    }
    
    // ✅ STEP 1: Check if conversation already exists
    let conversationsRef = db.collection("conversations")
    
    // Query for existing 1-on-1 conversation with this user
    let snapshot = try await conversationsRef
        .whereField("participantIds", arrayContains: currentUserId)
        .whereField("isGroup", isEqualTo: false)
        .getDocuments()
    
    // Find matching conversation (1-on-1 with both users)
    for doc in snapshot.documents {
        if let conversation = try? doc.data(as: FirebaseConversation.self),
           conversation.participantIds.contains(userId),
           conversation.participantIds.count == 2 {
            print("✅ Found existing conversation: \(doc.documentID)")
            return doc.documentID
        }
    }
    
    // ✅ STEP 2: No existing conversation - create new one
    print("📝 Creating new conversation with \(userId)")
    return try await createConversation(
        participantIds: [userId],
        participantNames: [
            currentUserId: currentUserName,
            userId: participantName
        ],
        isGroup: false,
        conversationStatus: "pending"  // Will auto-set to pending for 1-on-1
    )
}
```

---

## 🔧 Required Changes

### **1. Add `getOrCreateConversation` to FirebaseMessagingService** ✅

Location: `AMENAPP/FirebaseMessagingService.swift`

### **2. Update `startConversation` in MessagesView** ✅

Change from:
```swift
let conversationId = try await messagingService.createConversation(...)
```

To:
```swift
let conversationId = try await messagingService.getOrCreateConversation(
    with: user.id,
    participantName: user.name
)
```

### **3. Verify Real-Time Listener Persistence**

Ensure listener reconnects when:
- User navigates back to conversation
- App resumes from background
- Network reconnects

---

## 📊 Testing Checklist

After implementing fix:

- [ ] **New conversation**: Send first message to user B
  - [ ] Message appears immediately
  - [ ] Exit and come back - message still there
  
- [ ] **Existing conversation**: Send another message
  - [ ] Both messages visible
  - [ ] Real-time updates work
  
- [ ] **App background**: Send message, background app, resume
  - [ ] Message persists
  
- [ ] **Network offline**: Send message while offline
  - [ ] Shows pending state
  - [ ] Syncs when back online
  
- [ ] **Multiple devices**: Send from device A, receive on device B
  - [ ] Real-time sync works

---

## 🚀 Implementation Plan

1. Add `getOrCreateConversation` function to FirebaseMessagingService
2. Update all places that create conversations to use this function
3. Test conversation persistence
4. Verify real-time updates work
5. Test offline/online scenarios

---

**Status**: Ready to implement fix
