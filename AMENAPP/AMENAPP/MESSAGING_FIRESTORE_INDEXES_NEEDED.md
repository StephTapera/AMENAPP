# 🔥 Messaging Firestore Indexes - Complete List

**Date**: February 9, 2026
**Status**: ⚠️ **INDEXES NEEDED**

---

## 📊 Indexes Required for Messaging

Based on analysis of `MessageService.swift` and `FirebaseMessagingService.swift`, here are **all composite indexes** needed:

---

## 1️⃣ Conversations Collection Indexes

### **Index 1: Regular Conversations**
```
Collection: conversations
Fields:
  - participants (Ascending)
  - lastMessageTime (Descending)
```

**Used by**:
- `MessageService.fetchConversations()` (line ~146)
- `MessageService.startListening()` (line ~225)

**Query**:
```swift
.whereField("participants", arrayContains: currentUserId)
.order(by: "lastMessageTime", descending: true)
```

---

### **Index 2: Archived Conversations**
```
Collection: conversations
Fields:
  - participants (Ascending)
  - lastMessageTime (Descending)
```

**Used by**:
- `MessageService.startArchivedConversationsListener()` (line ~258)
- `MessageService.fetchArchivedConversations()` (line ~748)

**Note**: Same as Index 1 - already covered!

---

### **Index 3: Message Requests**
```
Collection: conversations
Fields:
  - participants (Ascending)
  - lastMessageTime (Descending)
```

**Used by**:
- `MessageService.startMessageRequestsListener()` (line ~647)

**Note**: Same as Index 1 - already covered!

---

### **Index 4: Direct Chat Lookup (New Service)**
```
Collection: conversations
Fields:
  - participantIds (Ascending)
  - isGroup (Ascending)
```

**Used by**:
- `FirebaseMessagingService.getOrCreateConversation()` (line ~327)

**Query**:
```swift
.whereField("participantIds", arrayContains: currentUserId)
.whereField("isGroup", isEqualTo: false)
```

---

### **Index 5: Conversations by Update Time (New Service)**
```
Collection: conversations
Fields:
  - participantIds (Ascending)
  - updatedAt (Descending)
```

**Used by**:
- `FirebaseMessagingService.startListeningToConversations()` (line ~157)
- `FirebaseMessagingService.startListeningToArchivedConversations()` (line ~192)

**Query**:
```swift
.whereField("participantIds", arrayContains: currentUserId)
.order(by: "updatedAt", descending: true)
```

---

### **Index 6: Pending Message Requests (Complex)**
```
Collection: conversations
Fields:
  - participantIds (Ascending)
  - conversationStatus (Ascending)
  - requesterId (Ascending)
  - updatedAt (Descending)
```

**Used by**:
- `FirebaseMessagingService.listenToMessageRequests()` (line ~1372)

**Query**:
```swift
.whereField("participantIds", arrayContains: userId)
.whereField("conversationStatus", isEqualTo: "pending")
.whereField("requesterId", isNotEqualTo: userId)
.order(by: "requesterId")
.order(by: "updatedAt", descending: true)
```

---

## 2️⃣ Messages Subcollection Indexes

### **Index 7: Messages by Conversation**
```
Collection Group: messages (or conversations/{conversationId}/messages)
Fields:
  - conversationId (Ascending)
  - timestamp (Ascending)
```

**Used by**:
- `MessageService.fetchMessages()` (line ~319)
- `MessageService.startMessagesListener()` (line ~350)

**Query**:
```swift
.whereField("conversationId", isEqualTo: conversationId)
.order(by: "timestamp", descending: false)
```

---

### **Index 8: Unread Messages**
```
Collection Group: messages
Fields:
  - conversationId (Ascending)
  - senderId (Ascending)
  - isRead (Ascending)
```

**Used by**:
- `MessageService.markMessagesAsRead()` (line ~438)

**Query**:
```swift
.whereField("conversationId", isEqualTo: conversationId)
.whereField("senderId", isNotEqualTo: currentUserId)
.whereField("isRead", isEqualTo: false)
```

---

### **Index 9: Pinned Messages**
```
Collection Group: messages (or conversations/{conversationId}/messages)
Fields:
  - conversationId (Ascending)
  - isPinned (Ascending)
  - pinnedAt (Descending)
```

**Used by**:
- `MessageService.fetchPinnedMessages()` (line ~721)
- `FirebaseMessagingService.fetchPinnedMessages()` (line ~598)

**Query**:
```swift
.whereField("conversationId", isEqualTo: conversationId)
.whereField("isPinned", isEqualTo: true)
.order(by: "pinnedAt", descending: true)
```

---

### **Index 10: Messages for Subcollection (New Service)**
```
Collection: conversations/{conversationId}/messages
Fields:
  - timestamp (Descending)
```

**Used by**:
- `FirebaseMessagingService.listenToMessages()` (line ~383)
- `FirebaseMessagingService.loadMoreMessages()` (line ~547)

**Query**:
```swift
.order(by: "timestamp", descending: true)
.limit(to: limit)
```

**Note**: This might not need index if querying subcollection directly

---

### **Index 11: Starred Messages**
```
Collection: conversations/{conversationId}/messages
Fields:
  - isStarred (Array)
  - timestamp (Descending)
```

**Used by**:
- `FirebaseMessagingService.fetchStarredMessages()` (line ~673)

**Query**:
```swift
.whereField("isStarred", arrayContains: currentUserId)
.order(by: "timestamp", descending: true)
```

---

## 3️⃣ User Search Indexes

### **Index 12: User Search by Display Name**
```
Collection: users
Fields:
  - displayNameLowercase (Ascending)
```

**Used by**:
- `FirebaseMessagingService.searchUsersForMessaging()` (line ~718)

**Query**:
```swift
.whereField("displayNameLowercase", isGreaterThanOrEqualTo: query)
.whereField("displayNameLowercase", isLessThanOrEqualTo: query + "\u{f8ff}")
.limit(to: 20)
```

---

### **Index 13: User Search by Username**
```
Collection: users
Fields:
  - usernameLowercase (Ascending)
```

**Used by**:
- `FirebaseMessagingService.searchUsersForMessaging()` (line ~736)

**Query**:
```swift
.whereField("usernameLowercase", isGreaterThanOrEqualTo: query)
.whereField("usernameLowercase", isLessThanOrEqualTo: query + "\u{f8ff}")
.limit(to: 20)
```

---

## 4️⃣ Disappearing Messages Index

### **Index 14: Expired Messages Cleanup**
```
Collection: conversations/{conversationId}/messages
Fields:
  - disappearAt (Ascending)
```

**Used by**:
- `FirebaseMessagingService.deleteDisappearedMessages()` (line ~1297)

**Query**:
```swift
.whereField("disappearAt", isLessThanOrEqualTo: now)
```

---

## ⚡ Quick Create Links

Firebase Console will auto-generate these links when you encounter the errors. Or create manually:

### **Manual Creation Steps**:
1. Go to: https://console.firebase.google.com/project/amen-5e359/firestore/indexes
2. Click **"Create Index"**
3. Select collection
4. Add fields with correct sort order
5. Click **"Create"**

---

## 📋 Priority Order

### **High Priority** (Create these first):
1. ✅ Index 5: Conversations by participantIds + updatedAt (most used)
2. ✅ Index 7: Messages by conversationId + timestamp (core messaging)
3. ✅ Index 9: Pinned messages (if using feature)

### **Medium Priority**:
4. ⏸️ Index 4: Direct chat lookup (only if using FirebaseMessagingService)
5. ⏸️ Index 8: Unread messages (mark as read feature)
6. ⏸️ Index 11: Starred messages (if using feature)

### **Low Priority** (Create on demand):
7. ⏸️ Index 6: Message requests with complex filters
8. ⏸️ Index 12-13: User search (if search is slow)
9. ⏸️ Index 14: Disappearing messages (if using feature)

---

## 🎯 What to Do

### **Option 1: Wait for Errors (Recommended)**
Run your app, use messaging features. When you hit an index error:
1. Copy the auto-generated link from error
2. Paste in browser
3. Click "Create Index"
4. Wait 2-5 minutes

### **Option 2: Create Proactively**
Visit Firebase Console and create indexes 1, 5, 7, and 9 now:
https://console.firebase.google.com/project/amen-5e359/firestore/indexes

---

## 🔍 How to Know Which Indexes You Need

Run these features in your app:
- Open Messages tab → Need Index 5
- Open a conversation → Need Index 7
- Pin a message → Need Index 9
- Search for users → Need Index 12-13
- Mark messages as read → Need Index 8

If no error appears, you don't need that index yet!

---

## 📊 Current Known Errors

Based on your logs, you already have one error for **posts** collection. Messaging indexes will appear as you use messaging features.

**Next index error you'll see** (most likely):
```
Collection: conversations
Fields: participantIds (Ascending), updatedAt (Descending)
```

Firebase will provide a click-to-create link when it happens!

---

## ✅ Index Build Times

- **Small collections** (<1000 docs): 2-5 minutes
- **Medium collections** (1000-10000 docs): 5-15 minutes
- **Large collections** (>10000 docs): 15-30 minutes

You can use your app while indexes build. Queries will start working once complete.

---

**Status**: 🟡 **Create indexes as needed** - Start with high priority ones or wait for errors!
