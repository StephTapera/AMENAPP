# 🔥 Firebase: Realtime Database vs Firestore

## 🤔 **Which Rules File Do You Need?**

You have **TWO** separate Firebase databases, each with **different** security rules:

---

## 📊 **Comparison**

| Feature | Realtime Database | Firestore |
|---------|-------------------|-----------|
| **File** | `firebase-realtime-database.rules.json` | `firestore.rules` |
| **Format** | JSON | Custom rules language |
| **Deploy Command** | `firebase deploy --only database` | `firebase deploy --only firestore:rules` |
| **Console URL** | [Realtime DB Rules](https://console.firebase.google.com/project/amen-5e359/database/rules) | [Firestore Rules](https://console.firebase.google.com/project/amen-5e359/firestore/rules) |
| **Data Structure** | JSON tree | Collections & Documents |
| **Best For** | Real-time features | Complex queries |

---

## 🗂️ **What's Stored Where?**

### **Realtime Database** 💨 (Real-time features)
```
realtime-database/
├── test/
├── user_posts/
├── postInteractions/
├── online_status/          ← User presence
├── typing/                 ← Typing indicators
├── live_reactions/         ← Real-time reactions
├── counters/               ← Live counts
├── connections/            ← Followers/following
└── user_saved_posts/
```

**Use for:**
- ✅ Online/offline status
- ✅ Typing indicators
- ✅ Live counters
- ✅ Real-time reactions
- ✅ Presence system

---

### **Firestore** 📚 (Main data storage)
```
firestore/
├── users/                  ← User profiles
│   ├── blockedUsers/       ← Who you blocked
│   ├── following/          ← Who you follow
│   └── followers/          ← Your followers
├── posts/                  ← All posts
├── conversations/          ← Direct messages
│   └── messages/           ← Message history
├── comments/               ← Post comments
├── notifications/          ← User notifications
├── saved_posts/            ← Saved content
├── message_requests/       ← Pending messages
└── blocks/                 ← Block relationships
```

**Use for:**
- ✅ User profiles
- ✅ Posts & comments
- ✅ Conversations & messages
- ✅ Notifications
- ✅ Complex queries
- ✅ Blocking system

---

## 🚨 **Your Current Error**

```
Listen for query at users/xtLSijkHggaBAjFM2aYKqPZ1uJw1/blockedUsers/... failed
Error: Missing or insufficient permissions
```

### ❌ **Wrong Database**
This is a **Firestore** error (path is `users/blockedUsers`)

### ✅ **Solution**
You need to deploy **Firestore rules**, not Realtime Database rules!

---

## 📝 **Files You Need to Deploy**

### 1. **Realtime Database Rules** ✅ (Already done)
**File:** `firebase-realtime-database.rules.json`

```bash
firebase deploy --only database
```

Or in [Console](https://console.firebase.google.com/project/amen-5e359/database/rules)

---

### 2. **Firestore Rules** ⚠️ (NEEDS TO BE DEPLOYED)
**File:** `firestore.rules`

```bash
firebase deploy --only firestore:rules
```

Or in [Console](https://console.firebase.google.com/project/amen-5e359/firestore/rules)

---

## 🚀 **Quick Deploy Both**

### **Copy Firestore Rules** 📋

Here's the content for your Firestore rules (copy this to Firebase Console):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    match /users/{userId} {
      allow read: if isAuthenticated();
      allow write: if isOwner(userId);
      
      match /blockedUsers/{blockedUserId} {
        allow read: if isOwner(userId);
        allow write: if isOwner(userId);
      }
      
      match /following/{followingId} {
        allow read: if isAuthenticated();
        allow write: if isOwner(userId);
      }
      
      match /followers/{followerId} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() && request.auth.uid == followerId;
      }
    }
    
    match /posts/{postId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.authorId;
      allow update, delete: if isAuthenticated() && request.auth.uid == resource.data.authorId;
    }
    
    match /conversations/{conversationId} {
      allow read: if isAuthenticated() && request.auth.uid in resource.data.participantIds;
      allow update: if isAuthenticated() && request.auth.uid in resource.data.participantIds;
      allow create: if isAuthenticated() && request.auth.uid in request.resource.data.participantIds;
      
      match /messages/{messageId} {
        allow read: if isAuthenticated() && 
          request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
        allow create: if isAuthenticated() && 
          request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds &&
          request.auth.uid == request.resource.data.senderId;
        allow update, delete: if isAuthenticated() && request.auth.uid == resource.data.senderId;
      }
    }
    
    match /comments/{commentId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.authorId;
      allow update, delete: if isAuthenticated() && request.auth.uid == resource.data.authorId;
    }
    
    match /notifications/{notificationId} {
      allow read: if isAuthenticated() && request.auth.uid == resource.data.userId;
      allow create: if isAuthenticated();
      allow update: if isAuthenticated() && request.auth.uid == resource.data.userId;
      allow delete: if isAuthenticated() && request.auth.uid == resource.data.userId;
    }
    
    match /saved_posts/{saveId} {
      allow read: if isAuthenticated() && request.auth.uid == resource.data.userId;
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.userId;
      allow delete: if isAuthenticated() && request.auth.uid == resource.data.userId;
    }
    
    match /message_requests/{requestId} {
      allow read: if isAuthenticated() && request.auth.uid == resource.data.recipientId;
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.senderId;
      allow update: if isAuthenticated() && request.auth.uid == resource.data.recipientId;
      allow delete: if isAuthenticated() && (
        request.auth.uid == resource.data.senderId ||
        request.auth.uid == resource.data.recipientId
      );
    }
    
    match /blocks/{blockId} {
      allow read: if isAuthenticated() && request.auth.uid == resource.data.blockerId;
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.blockerId;
      allow delete: if isAuthenticated() && request.auth.uid == resource.data.blockerId;
    }
    
    match /communities/{communityId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.creatorId;
      allow update: if isAuthenticated() && (
        request.auth.uid == resource.data.creatorId ||
        request.auth.uid in resource.data.adminIds
      );
      allow delete: if isAuthenticated() && request.auth.uid == resource.data.creatorId;
      
      match /members/{memberId} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() && (
          request.auth.uid == memberId ||
          request.auth.uid in get(/databases/$(database)/documents/communities/$(communityId)).data.adminIds
        );
      }
    }
    
    match /reports/{reportId} {
      allow read: if isAuthenticated() && request.auth.uid == resource.data.reporterId;
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.reporterId;
      allow update, delete: if false;
    }
    
    match /prayer_requests/{requestId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.authorId;
      allow update, delete: if isAuthenticated() && request.auth.uid == resource.data.authorId;
    }
    
    match /bible_study_groups/{groupId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && request.auth.uid == request.resource.data.creatorId;
      allow update, delete: if isAuthenticated() && request.auth.uid == resource.data.creatorId;
    }
  }
}
```

---

## ✅ **Deployment Steps**

### **Step 1: Deploy Firestore Rules** (Fixes your error)
1. Go to https://console.firebase.google.com/project/amen-5e359/firestore/rules
2. Copy the **entire Firestore rules** above
3. Paste into the editor
4. Click **Publish**

### **Step 2: Deploy Realtime Database Rules** (Already done, but here for reference)
1. Go to https://console.firebase.google.com/project/amen-5e359/database/rules
2. Your rules are already deployed (with test, user_saved_posts, etc.)
3. No action needed unless you want to update

---

## 🧪 **Test After Deployment**

### Firestore Test ✅
```swift
// This should now work without errors
let blockedUsers = try await db.collection("users")
    .document(currentUserId)
    .collection("blockedUsers")
    .getDocuments()

print("✅ Blocked users loaded: \(blockedUsers.count)")
```

### Realtime Database Test ✅
```swift
// This should already work
let ref = Database.database().reference()
    .child("user_saved_posts")
    .child(currentUserId)

let snapshot = try await ref.getData()
print("✅ Saved posts loaded")
```

---

## 🎯 **Summary**

| Issue | Database | File to Deploy | URL |
|-------|----------|----------------|-----|
| ❌ blockedUsers error | Firestore | `firestore.rules` | [Deploy Here](https://console.firebase.google.com/project/amen-5e359/firestore/rules) |
| ✅ user_saved_posts | Realtime DB | Already deployed | [View Here](https://console.firebase.google.com/project/amen-5e359/database/rules) |

---

## 🚀 **Deploy Firestore Rules NOW!**

Copy the Firestore rules above and deploy them to fix your permission errors! 🎉
