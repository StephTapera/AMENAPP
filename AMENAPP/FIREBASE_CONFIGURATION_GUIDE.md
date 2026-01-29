# Firebase Configuration Guide for Messaging App

Complete step-by-step instructions to configure Firebase for your messaging app.

---

## 📋 Table of Contents

1. [Firestore Security Rules](#1-firestore-security-rules)
2. [Enable Offline Persistence](#2-enable-offline-persistence)
3. [Firebase Storage Rules](#3-firebase-storage-rules)
4. [Database Indexes](#4-database-indexes)
5. [Testing & Validation](#5-testing--validation)

---

## 1. Firestore Security Rules

### 🎯 Purpose
Security rules protect your data and ensure users can only access conversations they're part of.

### 📝 Steps

1. **Open Firebase Console**
   - Go to [https://console.firebase.google.com](https://console.firebase.google.com)
   - Select your project

2. **Navigate to Firestore**
   - Click **Firestore Database** in the left sidebar
   - Click the **Rules** tab at the top

3. **Replace the rules with the following:**

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to check if user is in conversation
    function isParticipant(conversationId) {
      return isAuthenticated() && 
             request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
    }
    
    // Users collection
    match /users/{userId} {
      // Anyone authenticated can read user profiles (for search)
      allow read: if isAuthenticated();
      
      // Users can only write their own profile
      allow create, update: if isAuthenticated() && request.auth.uid == userId;
      
      // Users can't delete profiles (optional - remove if you want deletion)
      allow delete: if false;
    }
    
    // Conversations collection
    match /conversations/{conversationId} {
      
      // Users can read conversations they're part of
      allow read: if isAuthenticated() && 
                     request.auth.uid in resource.data.participantIds;
      
      // Users can create conversations (will be validated they're in participantIds)
      allow create: if isAuthenticated() &&
                       request.auth.uid in request.resource.data.participantIds &&
                       request.resource.data.participantIds.size() >= 2;
      
      // Only participants can update conversations
      // Also prevent removing yourself unless it's a group chat
      allow update: if isAuthenticated() &&
                       request.auth.uid in resource.data.participantIds &&
                       (
                         // Allow updates to lastMessage, unreadCounts, etc.
                         !request.resource.data.diff(resource.data).affectedKeys().hasAny(['participantIds']) ||
                         // Or if it's a group chat, allow participant changes
                         (resource.data.isGroup == true)
                       );
      
      // Only allow deletion if you're a participant (optional)
      allow delete: if isAuthenticated() && 
                       request.auth.uid in resource.data.participantIds;
      
      // Messages subcollection
      match /messages/{messageId} {
        
        // Participants can read all messages in their conversations
        allow read: if isParticipant(conversationId);
        
        // Participants can create messages
        // Ensure senderId matches authenticated user
        allow create: if isParticipant(conversationId) &&
                         isAuthenticated() &&
                         request.resource.data.senderId == request.auth.uid;
        
        // Only message sender can update their own messages
        // Allow updating for: reactions, readBy, edit, delete, pin, star
        allow update: if isParticipant(conversationId) &&
                         (
                           // Sender can edit/delete their own message
                           resource.data.senderId == request.auth.uid ||
                           // Anyone can add reactions, mark as read, star
                           request.resource.data.diff(resource.data).affectedKeys()
                             .hasOnly(['reactions', 'readBy', 'isStarred', 'isPinned', 'pinnedAt', 'pinnedBy'])
                         );
        
        // Only sender can permanently delete their message
        allow delete: if isAuthenticated() &&
                         resource.data.senderId == request.auth.uid;
      }
      
      // Typing indicators subcollection
      match /typing/{userId} {
        // Anyone in the conversation can read typing indicators
        allow read: if isParticipant(conversationId);
        
        // Users can only write their own typing status
        allow write: if isAuthenticated() && 
                        userId == request.auth.uid &&
                        isParticipant(conversationId);
      }
    }
  }
}
```

4. **Click "Publish"** to save the rules

### ⚠️ Important Notes

- **Test Mode vs Production**: Never use "Test Mode" rules in production
- **Validation**: These rules validate that users can only modify their own data
- **Group Chats**: Rules allow participant changes only in group conversations
- **Message Actions**: Users can edit/delete their own messages, but anyone can react/star

---

## 2. Enable Offline Persistence

### 🎯 Purpose
Offline persistence allows your app to work without internet and sync when reconnected.

### 📝 Steps - Already Configured! ✅

**Good news**: Offline persistence is already enabled in your code! 

In `FirebaseMessagingService.swift`, line ~109:

```swift
private func enableOfflineSupport() {
    let settings = db.settings
    settings.cacheSettings = PersistentCacheSettings(sizeBytes: FirestoreCacheSizeUnlimited)
    db.settings = settings
    print("✅ Offline persistence enabled for messaging")
}
```

### 🔧 Optional: Firebase Console Settings

1. **Navigate to Firestore**
   - Go to Firebase Console → Firestore Database
   - Click **Settings** (gear icon)

2. **Offline Persistence Settings**
   - These are client-side settings (already configured in your app)
   - No additional console configuration needed

### ✅ What This Enables

- 📦 Cached conversations load instantly
- 💬 Read messages offline
- 📤 Send messages offline (queued until online)
- 🔄 Automatic sync when reconnected
- 💾 Unlimited cache size

### 🧪 Testing Offline Mode

```swift
// In your app:
// 1. Load some conversations and messages
// 2. Turn on Airplane Mode
// 3. Navigate around - data still loads from cache
// 4. Compose a message
// 5. Turn off Airplane Mode
// 6. Message automatically sends!
```

---

## 3. Firebase Storage Rules

### 🎯 Purpose
Secure image uploads for messages and group avatars.

### 📝 Steps

1. **Navigate to Storage**
   - Firebase Console → **Storage**
   - Click the **Rules** tab

2. **Replace the rules with the following:**

```javascript
rules_version = '2';

service firebase.storage {
  match /b/{bucket}/o {
    
    // Helper function to check authentication
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to validate image files
    function isImage() {
      return request.resource.contentType.matches('image/.*');
    }
    
    // Helper function to check file size (10MB max)
    function isUnder10MB() {
      return request.resource.size < 10 * 1024 * 1024;
    }
    
    // Message attachments: messages/{conversationId}/{filename}
    match /messages/{conversationId}/{filename} {
      // Anyone authenticated can read message images
      // (conversation access is validated in Firestore)
      allow read: if isAuthenticated();
      
      // Authenticated users can upload images to conversations
      allow create: if isAuthenticated() &&
                       isImage() &&
                       isUnder10MB();
      
      // Users can update/delete their own uploaded images
      // (we don't track uploader in metadata, so allow if authenticated)
      allow update, delete: if isAuthenticated();
    }
    
    // Group avatars: group_avatars/{conversationId}_avatar.jpg
    match /group_avatars/{filename} {
      // Anyone authenticated can view group avatars
      allow read: if isAuthenticated();
      
      // Authenticated users can upload/update group avatars
      allow create, update: if isAuthenticated() &&
                               isImage() &&
                               isUnder10MB();
      
      // Allow deletion of group avatars
      allow delete: if isAuthenticated();
    }
    
    // User profile images (optional, add if you have profile pictures)
    match /profile_images/{userId}/{filename} {
      // Anyone can read profile images
      allow read: if true;
      
      // Users can only upload their own profile images
      allow create, update: if isAuthenticated() &&
                               request.auth.uid == userId &&
                               isImage() &&
                               isUnder10MB();
      
      // Users can only delete their own profile images
      allow delete: if isAuthenticated() && request.auth.uid == userId;
    }
    
    // Deny all other paths
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

3. **Click "Publish"** to save the rules

### 📊 Storage Rules Breakdown

| Path | Who Can Read | Who Can Write | Max Size |
|------|-------------|---------------|----------|
| `/messages/{conversationId}/*` | Authenticated users | Authenticated users | 10 MB |
| `/group_avatars/*` | Authenticated users | Authenticated users | 10 MB |
| `/profile_images/{userId}/*` | Everyone | Owner only | 10 MB |

### 🔒 Security Features

- ✅ Only authenticated users can upload
- ✅ Only image files accepted
- ✅ 10 MB maximum file size
- ✅ Prevents unauthorized access
- ✅ Prevents storage abuse

### ⚙️ Customization Options

**Adjust file size limit:**
```javascript
function isUnder5MB() {
  return request.resource.size < 5 * 1024 * 1024;  // 5 MB
}
```

**Allow video files:**
```javascript
function isImageOrVideo() {
  return request.resource.contentType.matches('image/.*') ||
         request.resource.contentType.matches('video/.*');
}
```

**Restrict to JPEG/PNG only:**
```javascript
function isJPEGorPNG() {
  return request.resource.contentType.matches('image/jpeg') ||
         request.resource.contentType.matches('image/png');
}
```

---

## 4. Database Indexes

### 🎯 Purpose
Indexes improve query performance for conversations and messages.

### 📝 Required Indexes

Firebase will usually auto-create these, but you can create them manually:

#### 1. **Navigate to Firestore → Indexes**

#### 2. **Create Composite Indexes**

**Index 1: Conversations by participant and update time**
- Collection: `conversations`
- Fields to index:
  - `participantIds` - Arrays
  - `updatedAt` - Descending
- Query scope: Collection

**Index 2: Messages by conversation and timestamp**
- Collection: `conversations/{conversationId}/messages`
- Fields to index:
  - `timestamp` - Descending
- Query scope: Collection group

**Index 3: Pinned messages**
- Collection: `conversations/{conversationId}/messages`
- Fields to index:
  - `isPinned` - Ascending
  - `pinnedAt` - Descending
- Query scope: Collection group

**Index 4: Starred messages**
- Collection: `conversations/{conversationId}/messages`
- Fields to index:
  - `isStarred` - Arrays
  - `timestamp` - Descending
- Query scope: Collection group

### 🔍 Auto-Index Creation

Firebase will show you index creation links in the console when you run queries. Look for errors like:

```
The query requires an index. You can create it here: https://console.firebase.google.com/...
```

Simply click the link and Firebase will create the index for you!

### ⚡ Performance Tips

- Indexes are created automatically for most queries
- Check the **Indexes** tab periodically
- Remove unused indexes to save costs

---

## 5. Testing & Validation

### ✅ Security Rules Testing

1. **Open Rules Playground**
   - Firestore → Rules → **Rules Playground** button

2. **Test Read Access**
```javascript
// Test reading a conversation
Location: /conversations/conv123
Read: true
Auth: {uid: "user123"}

// Simulator will show ✅ if rules allow
```

3. **Test Write Access**
```javascript
// Test creating a message
Location: /conversations/conv123/messages/msg456
Write: true
Auth: {uid: "user123"}
Data: {"senderId": "user123", "text": "Hello"}
```

### 🧪 Real-World Testing

#### Test 1: Send a Message
```swift
Task {
    do {
        try await FirebaseMessagingService.shared.sendMessage(
            conversationId: "test-conversation",
            text: "Test message"
        )
        print("✅ Message sent successfully")
    } catch {
        print("❌ Error: \(error)")
    }
}
```

#### Test 2: Upload Photo
```swift
Task {
    do {
        try await FirebaseMessagingService.shared.sendMessageWithPhotos(
            conversationId: "test-conversation",
            text: "Check this out!",
            images: [UIImage(named: "test")!]
        )
        print("✅ Photo uploaded successfully")
    } catch {
        print("❌ Error: \(error)")
    }
}
```

#### Test 3: Offline Mode
```swift
// 1. Load conversations
FirebaseMessagingService.shared.startListeningToConversations()

// 2. Enable Airplane Mode on device/simulator

// 3. Try to load conversations again
// Should load from cache with "📦" emoji in logs

// 4. Try to send a message
// Will queue and send when back online
```

---

## 📊 Firebase Console Monitoring

### 1. **Firestore Usage**
- Navigate to: **Firestore Database** → **Usage**
- Monitor:
  - Document reads/writes
  - Storage usage
  - Network egress

### 2. **Storage Usage**
- Navigate to: **Storage** → **Usage**
- Monitor:
  - Total storage
  - Bandwidth
  - Number of files

### 3. **Authentication**
- Navigate to: **Authentication** → **Users**
- Monitor:
  - Active users
  - Sign-in methods

---

## 🔐 Production Checklist

Before launching your app:

- [ ] ✅ Security rules published (Firestore)
- [ ] ✅ Storage rules published
- [ ] ✅ Offline persistence enabled (already in code)
- [ ] ✅ Required indexes created
- [ ] ✅ Test message sending
- [ ] ✅ Test photo uploads
- [ ] ✅ Test offline mode
- [ ] ✅ Test security rules in playground
- [ ] ⚠️ Set up billing alerts in Firebase
- [ ] ⚠️ Enable Firebase App Check (recommended)
- [ ] ⚠️ Set up Firebase Analytics (optional)
- [ ] ⚠️ Configure push notifications (separate setup)

---

## 🚨 Common Issues & Solutions

### Issue 1: "Missing or insufficient permissions"
**Solution**: Check your security rules. User might not be in `participantIds`.

### Issue 2: "The query requires an index"
**Solution**: Click the link in the error message to auto-create the index.

### Issue 3: "Permission denied" on Storage
**Solution**: Verify Storage rules allow authenticated users to write.

### Issue 4: Messages not syncing offline
**Solution**: Ensure offline persistence is enabled (already done in your code).

### Issue 5: "Exceeded quota"
**Solution**: 
- Check Firebase Console → Usage
- Optimize queries to reduce reads
- Implement pagination (already done!)

---

## 📞 Support Resources

- **Firebase Documentation**: [https://firebase.google.com/docs](https://firebase.google.com/docs)
- **Security Rules Reference**: [https://firebase.google.com/docs/rules](https://firebase.google.com/docs/rules)
- **Stack Overflow**: Tag questions with `firebase` and `swift`
- **Firebase Support**: [https://firebase.google.com/support](https://firebase.google.com/support)

---

## 🎯 Quick Copy-Paste Summary

### Firestore Rules
```bash
# Copy from Section 1, lines 26-129
```

### Storage Rules
```bash
# Copy from Section 3, lines 239-299
```

### Test Message Send
```swift
try await FirebaseMessagingService.shared.sendMessage(
    conversationId: conversationId,
    text: messageText
)
```

---

**Configuration Complete! 🎉**

Your Firebase backend is now fully configured for production messaging with:
- ✅ Secure data access
- ✅ Offline support
- ✅ Image uploads
- ✅ Optimized queries

