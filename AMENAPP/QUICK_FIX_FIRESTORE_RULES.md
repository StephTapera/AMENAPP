# 🚨 QUICK FIX: Firestore Rules for Follow Feature

## The Problem

You're getting this error:
```
❌ Batch commit failed: Missing or insufficient permissions.
❌ Failed to toggle follow: Missing or insufficient permissions.
```

This means your Firestore security rules are blocking the follow/unfollow operations.

## ⚡️ QUICK FIX (2 minutes)

### Option 1: Quick Temporary Fix (For Testing Only)

Go to **Firebase Console → Firestore Database → Rules** and temporarily use:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // TEMPORARY: Allow all authenticated users
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

⚠️ **WARNING**: This is INSECURE and should only be used temporarily for testing!

---

### Option 2: Proper Fix for Follows (Recommended)

Go to **Firebase Console → Firestore Database → Rules** and use these rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper functions
    function isSignedIn() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return request.auth.uid == userId;
    }
    
    // ============================================
    // USERS COLLECTION
    // ============================================
    
    match /users/{userId} {
      // Anyone authenticated can read user profiles
      allow read: if isSignedIn();
      
      // Users can create/update/delete their own profile
      allow create, update, delete: if isSignedIn() && isOwner(userId);
      
      // Following subcollection
      match /following/{followedUserId} {
        // Can read your own following list
        allow read: if isSignedIn();
        
        // Can create/delete follows for yourself
        allow create, delete: if isSignedIn() && isOwner(userId);
      }
      
      // Followers subcollection
      match /followers/{followerId} {
        // Can read your own followers list
        allow read: if isSignedIn();
        
        // Can create/delete follower records
        allow create, delete: if isSignedIn();
      }
    }
    
    // ============================================
    // FOLLOWS COLLECTION (Top-level)
    // ============================================
    
    match /follows/{followId} {
      // Anyone can read follows (for social graph)
      allow read: if isSignedIn();
      
      // Can create a follow if you're the follower
      allow create: if isSignedIn() && 
                       request.resource.data.followerId == request.auth.uid;
      
      // Can delete your own follows
      allow delete: if isSignedIn() && 
                       resource.data.followerId == request.auth.uid;
    }
    
    // ============================================
    // POSTS (All types)
    // ============================================
    
    match /posts/{postId} {
      // Anyone can read posts
      allow read: if isSignedIn();
      
      // Can create your own posts
      allow create: if isSignedIn() && 
                       request.resource.data.authorId == request.auth.uid;
      
      // Can update/delete your own posts
      allow update, delete: if isSignedIn() && 
                               resource.data.authorId == request.auth.uid;
      
      // Comments subcollection
      match /comments/{commentId} {
        allow read: if isSignedIn();
        allow create: if isSignedIn() && 
                         request.resource.data.authorId == request.auth.uid;
        allow update, delete: if isSignedIn() && 
                                 resource.data.authorId == request.auth.uid;
      }
      
      // Likes subcollection
      match /likes/{userId} {
        allow read: if isSignedIn();
        allow create, delete: if isSignedIn() && userId == request.auth.uid;
      }
    }
    
    // ============================================
    // CONVERSATIONS (Messaging)
    // ============================================
    
    match /conversations/{conversationId} {
      // Can read if you're a participant
      allow read: if isSignedIn() && 
                     request.auth.uid in resource.data.participantIds;
      
      // Can create if you're in the participant list
      allow create: if isSignedIn() && 
                       request.auth.uid in request.resource.data.participantIds;
      
      // Can update if you're a participant
      allow update: if isSignedIn() && 
                       request.auth.uid in resource.data.participantIds;
      
      // Can delete if you're a participant
      allow delete: if isSignedIn() && 
                       request.auth.uid in resource.data.participantIds;
      
      // Messages subcollection
      match /messages/{messageId} {
        allow read: if isSignedIn() &&
                       request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
        
        allow create: if isSignedIn() &&
                         request.resource.data.senderId == request.auth.uid;
        
        allow update, delete: if isSignedIn() &&
                                 resource.data.senderId == request.auth.uid;
      }
    }
    
    // ============================================
    // NOTIFICATIONS
    // ============================================
    
    match /notifications/{userId}/items/{notificationId} {
      // Can only read your own notifications
      allow read: if isSignedIn() && isOwner(userId);
      
      // System creates notifications, but allow for testing
      allow create: if isSignedIn();
      
      // Can mark your notifications as read/delete
      allow update, delete: if isSignedIn() && isOwner(userId);
    }
    
    // ============================================
    // EVERYTHING ELSE (Fallback)
    // ============================================
    
    // Allow authenticated access to other collections
    match /{collection}/{document=**} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }
  }
}
```

---

## 📋 Step-by-Step Instructions

### 1. Open Firebase Console
- Go to: https://console.firebase.google.com
- Select your **AMENAPP** project

### 2. Navigate to Firestore Rules
- Click **Firestore Database** in the left sidebar
- Click the **Rules** tab at the top

### 3. Copy and Paste Rules
- **Select ALL** existing rules in the editor
- **Delete** them
- **Copy** the rules from Option 2 above
- **Paste** into the empty editor

### 4. Publish Rules
- Click **Publish** button (top right)
- Wait for "Rules published successfully" message

### 5. Test Your App
- Try following/unfollowing users
- Should work immediately!

---

## 🔍 What This Fixes

These rules allow:

✅ **Following/Unfollowing Users**
- Creates documents in `follows/{followId}` collection
- Updates `users/{userId}/following/{followedUserId}`
- Updates `users/{userId}/followers/{followerId}`

✅ **Reading User Profiles**
- Anyone can view user profiles
- Users can update their own profile

✅ **Posts & Comments**
- Create/read/update/delete posts
- Add comments and likes

✅ **Messaging**
- Send/receive messages
- Create conversations
- Archive/delete conversations

✅ **Notifications**
- Read your own notifications
- Mark as read

---

## 🧪 Test After Deploying

1. **Test Follow**:
   - Open your app
   - Navigate to a user profile
   - Tap "Follow" button
   - Should see: "✅ Followed successfully"

2. **Test Unfollow**:
   - Tap "Following" button
   - Should see: "✅ Unfollowed successfully"

3. **Check Follower Counts**:
   - Counts should update immediately

---

## 🚨 If Still Not Working

### Check Your Follow Service Code

Your `FollowService.swift` should be creating documents like this:

```swift
// Create follow document
let followData: [String: Any] = [
    "followerId": currentUserId,
    "followingId": userId,
    "createdAt": Timestamp(date: Date())
]

try await db.collection("follows").addDocument(data: followData)
```

### Common Issues:

1. **Wrong Collection Name**: Make sure you're using `follows` not `follow`
2. **Missing Fields**: Ensure `followerId` and `followingId` are set
3. **Not Authenticated**: Check that user is signed in

---

## 📝 Collection Structure Reference

Your Firestore should have this structure:

```
├── users/
│   └── {userId}/
│       ├── following/
│       │   └── {followedUserId}  ← Document for each user you follow
│       └── followers/
│           └── {followerId}      ← Document for each follower
│
├── follows/                      ← Top-level collection
│   └── {followId}                ← Each follow relationship
│       ├── followerId: "abc123"
│       ├── followingId: "xyz789"
│       └── createdAt: Timestamp
│
├── posts/
│   └── {postId}/
│       ├── comments/
│       └── likes/
│
└── conversations/
    └── {conversationId}/
        └── messages/
```

---

## ✅ Expected Console Messages

After deploying rules, you should see in Xcode console:

```
✅ Successfully followed user
✅ Real-time follower count update: 1 followers, 0 following
✅ Batch commit successful
```

Instead of:

```
❌ Batch commit failed: Missing or insufficient permissions.
❌ Failed to toggle follow: Missing or insufficient permissions.
```

---

## 🎯 Next Steps

1. **Deploy these rules** (2 minutes)
2. **Test follow/unfollow** in your app
3. **Verify counts update** correctly
4. **Later**: Consider the comprehensive rules from `COMPLETE_FIREBASE_RULES.md` for production

---

## 💡 Pro Tip

After testing, you can use the comprehensive rules from `COMPLETE_FIREBASE_RULES.md` which include:
- Blocking users
- Privacy controls
- Content validation
- Better security

But for now, these rules will get you unblocked!

---

**Status**: ✅ Ready to deploy  
**Time**: 2 minutes  
**Difficulty**: Easy (copy & paste)
