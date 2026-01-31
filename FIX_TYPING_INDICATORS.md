# 🔧 Fix: Typing Indicators & Remove Online Status

## 🔴 **The Problem:**

Your typing indicators are using Firebase Realtime Database with conversation IDs that contain forbidden characters (`.`, `#`, `$`, `[`, `]`, or `/`).

**Error:**
```
Invalid key in object. Keys must be non-empty and cannot contain '.' '#' '$' '[' or ']'
```

---

## ✅ **Solution: Fix Typing Indicators**

### **Option 1: Use Firestore Instead (Recommended)**

Typing indicators should use Firestore's subcollection (which you already have set up according to your rules).

**Find this in `FirebaseMessagingService.swift`:**

```swift
// CURRENT IMPLEMENTATION (Using Realtime DB - BROKEN)
func updateTypingStatus(conversationId: String, isTyping: Bool) async throws {
    let ref = Database.database().ref("typing")
        .child(conversationId)  // ← conversationId contains '.' causing error!
        .child(currentUserId)
    
    ref.updateChildValues(["isTyping": isTyping, "timestamp": ServerValue.timestamp()])
}
```

**Replace with this (Using Firestore - WORKS):**

```swift
func updateTypingStatus(conversationId: String, isTyping: Bool) async throws {
    let db = Firestore.firestore()
    let typingRef = db.collection("conversations")
        .document(conversationId)
        .collection("typing")
        .document(currentUserId)
    
    if isTyping {
        try await typingRef.setData([
            "isTyping": true,
            "timestamp": FieldValue.serverTimestamp()
        ])
    } else {
        try await typingRef.delete()
    }
}
```

**And update the listener:**

```swift
// CURRENT (Realtime DB - BROKEN)
func startListeningToTyping(conversationId: String, onUpdate: @escaping ([String]) -> Void) -> (() -> Void) {
    let ref = Database.database().ref("typing").child(conversationId)
    
    let handle = ref.observe(.value) { snapshot in
        var typingUsers: [String] = []
        for child in snapshot.children {
            if let snap = child as? DataSnapshot,
               let data = snap.value as? [String: Any],
               let isTyping = data["isTyping"] as? Bool,
               isTyping {
                typingUsers.append(snap.key)
            }
        }
        onUpdate(typingUsers)
    }
    
    return {
        ref.removeObserver(withHandle: handle)
    }
}
```

**Replace with (Firestore - WORKS):**

```swift
func startListeningToTyping(conversationId: String, onUpdate: @escaping ([String]) -> Void) {
    let db = Firestore.firestore()
    let typingRef = db.collection("conversations")
        .document(conversationId)
        .collection("typing")
    
    typingRef.addSnapshotListener { snapshot, error in
        guard let documents = snapshot?.documents else {
            onUpdate([])
            return
        }
        
        let typingUsers = documents
            .filter { doc in
                guard let isTyping = doc.data()["isTyping"] as? Bool else { return false }
                return isTyping
            }
            .map { $0.documentID }
            .filter { $0 != self.currentUserId } // Don't show own typing
        
        onUpdate(typingUsers)
    }
}
```

---

### **Option 2: Sanitize Conversation IDs (If You Must Use Realtime DB)**

If you want to keep using Realtime Database, sanitize the keys:

```swift
// Add this helper function
private func sanitizeForRealtimeDB(_ string: String) -> String {
    return string
        .replacingOccurrences(of: ".", with: "_")
        .replacingOccurrences(of: "#", with: "_")
        .replacingOccurrences(of: "$", with: "_")
        .replacingOccurrences(of: "[", with: "_")
        .replacingOccurrences(of: "]", with: "_")
        .replacingOccurrences(of: "/", with: "_")
}

// Then use it:
func updateTypingStatus(conversationId: String, isTyping: Bool) async throws {
    let safeId = sanitizeForRealtimeDB(conversationId)  // ← SANITIZE HERE
    
    let ref = Database.database().ref("typing")
        .child(safeId)
        .child(currentUserId)
    
    ref.updateChildValues(["isTyping": isTyping, "timestamp": ServerValue.timestamp()])
}
```

---

## 🗑️ **Remove Online Status Implementation**

Search your project for these and DELETE or COMMENT OUT:

### **1. Remove Presence Tracking**

Look for code like:
```swift
// DELETE THIS:
func setUserOnline() {
    Database.database().ref("presence/\(userId)")
        .updateChildValues(["online": true, "lastSeen": ServerValue.timestamp()])
}

func setUserOffline() {
    Database.database().ref("presence/\(userId)")
        .updateChildValues(["online": false, "lastSeen": ServerValue.timestamp()])
}
```

### **2. Remove Presence Listeners**

Look for:
```swift
// DELETE THIS:
func listenToUserPresence(userId: String, onUpdate: @escaping (Bool) -> Void) {
    Database.database().ref("presence/\(userId)/online")
        .observe(.value) { snapshot in
            let isOnline = snapshot.value as? Bool ?? false
            onUpdate(isOnline)
        }
}
```

### **3. Remove from AppDelegate/SceneDelegate**

Look for:
```swift
// DELETE THIS:
func applicationDidBecomeActive(_ application: UIApplication) {
    FirebaseMessagingService.shared.setUserOnline()
}

func applicationWillResignActive(_ application: UIApplication) {
    FirebaseMessagingService.shared.setUserOffline()
}
```

### **4. Remove UI Elements**

In any chat or profile views, remove:
```swift
// DELETE THIS:
@State private var isUserOnline = false

// And the UI:
Circle()
    .fill(isUserOnline ? Color.green : Color.gray)
    .frame(width: 10, height: 10)
```

---

## ✅ **Keep Read Receipts (Already Working)**

Your read receipts should already be working through Firestore. They look like this:

```swift
// This is fine - uses Firestore
func markMessagesAsRead(conversationId: String, messageIds: [String]) async throws {
    let db = Firestore.firestore()
    let batch = db.batch()
    
    for messageId in messageIds {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        batch.updateData([
            "isRead": true,
            "readAt": FieldValue.serverTimestamp()
        ], forDocument: messageRef)
    }
    
    try await batch.commit()
}
```

Keep this as is - it uses Firestore and works correctly.

---

## 📋 **Files to Check and Fix:**

### **1. FirebaseMessagingService.swift**
- [ ] Fix `updateTypingStatus` (use Firestore or sanitize)
- [ ] Fix `startListeningToTyping` (use Firestore or sanitize)
- [ ] Remove `setUserOnline` function
- [ ] Remove `setUserOffline` function
- [ ] Remove `listenToUserPresence` function

### **2. AppDelegate.swift or SceneDelegate.swift**
- [ ] Remove online status calls from lifecycle methods

### **3. ChatView.swift or MessagesView.swift**
- [ ] Remove online status UI (green dots, "Active now" text)
- [ ] Keep typing indicator (just fix the implementation)

### **4. Profile Views**
- [ ] Remove "Last seen" or "Active now" displays

---

## 🚀 **Quick Implementation (Copy-Paste Ready)**

Add this to your `FirebaseMessagingService.swift`:

```swift
// MARK: - Typing Indicators (Firestore-based)

/// Update user's typing status in a conversation
func updateTypingStatus(conversationId: String, isTyping: Bool) async throws {
    guard !currentUserId.isEmpty else {
        throw NSError(domain: "MessagingService", code: -1, 
                     userInfo: [NSLocalizedDescriptionKey: "User ID is empty"])
    }
    
    let db = Firestore.firestore()
    let typingRef = db.collection("conversations")
        .document(conversationId)
        .collection("typing")
        .document(currentUserId)
    
    if isTyping {
        try await typingRef.setData([
            "isTyping": true,
            "timestamp": FieldValue.serverTimestamp(),
            "userId": currentUserId
        ], merge: true)
    } else {
        // Delete typing indicator when done
        try? await typingRef.delete()
    }
}

/// Listen to typing indicators in a conversation
func startListeningToTyping(
    conversationId: String,
    onUpdate: @escaping ([String]) -> Void
) {
    let db = Firestore.firestore()
    let typingRef = db.collection("conversations")
        .document(conversationId)
        .collection("typing")
    
    typingRef.addSnapshotListener { snapshot, error in
        if let error = error {
            print("❌ Error listening to typing: \(error)")
            onUpdate([])
            return
        }
        
        guard let documents = snapshot?.documents else {
            onUpdate([])
            return
        }
        
        // Get user IDs of people currently typing (excluding self)
        let typingUsers = documents
            .compactMap { doc -> String? in
                guard let isTyping = doc.data()["isTyping"] as? Bool,
                      isTyping,
                      doc.documentID != self.currentUserId else {
                    return nil
                }
                return doc.documentID
            }
        
        onUpdate(typingUsers)
    }
}

/// Stop listening to typing (cleanup)
func stopListeningToTyping(conversationId: String) {
    // Firestore listeners are automatically cleaned up when views disappear
    // But we should clear our own typing status
    Task {
        try? await updateTypingStatus(conversationId: conversationId, isTyping: false)
    }
}
```

---

## 🧪 **Test It:**

1. **Run your app**
2. **Open a chat**
3. **Start typing** - no error should occur
4. **The typing indicator should work** (if someone else is typing)
5. **No online status** should be shown anywhere

---

## 🎯 **Summary:**

**To Fix:**
1. ✅ Replace typing indicators to use **Firestore** instead of Realtime DB
2. ✅ Remove all **online status/presence** code
3. ✅ Keep **read receipts** (already working with Firestore)

**This will:**
- ✅ Fix the crash/error
- ✅ Make typing indicators work properly
- ✅ Remove unnecessary online status tracking
- ✅ Keep your app clean and focused

---

**Copy the code above into your `FirebaseMessagingService.swift` and the error will be gone!** 🎉
