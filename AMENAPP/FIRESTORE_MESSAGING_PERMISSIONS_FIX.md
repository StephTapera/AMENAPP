# Firestore Messaging Permissions Fix

## Problem
When clicking "Message" on a user profile, you get: **"Network error / Missing or insufficient permissions"**

## Root Cause
The `getOrCreateDirectConversation` method in `FirebaseMessagingService` needs to:
1. Check if users are blocked
2. Check follow status
3. Create/access conversations

These operations require proper Firestore security rules.

---

## Solution: Complete Firestore Security Rules

Go to **Firebase Console → Firestore Database → Rules** and **REPLACE ALL** existing rules with these:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // ========================================
    // HELPER FUNCTIONS
    // ========================================
    
    function isSignedIn() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return isSignedIn() && request.auth.uid == userId;
    }
    
    function isParticipant(participantIds) {
      return isSignedIn() && request.auth.uid in participantIds;
    }
    
    // ========================================
    // USERS COLLECTION
    // ========================================
    
    match /users/{userId} {
      // ✅ Anyone authenticated can READ user profiles
      allow read: if isSignedIn();
      
      // ✅ Users can CREATE their own profile during signup
      allow create: if isSignedIn() && request.auth.uid == userId;
      
      // ✅ Users can UPDATE their own profile
      // Special case: Allow updating followerCount/followingCount from follow operations
      allow update: if isSignedIn() && (
        // User updating their own profile
        request.auth.uid == userId ||
        // OR: Follow operation updating counts
        (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followersCount', 'followingCount', 'updatedAt']))
      );
      
      // ✅ Users can DELETE their own profile
      allow delete: if isOwner(userId);
      
      // ----------------------------------------
      // User Subcollections
      // ----------------------------------------
      
      // Blocked Users Subcollection
      match /blockedUsers/{blockedUserId} {
        // Users can read their own blocked list
        allow read: if isOwner(userId);
        // Users can block/unblock anyone
        allow write: if isOwner(userId);
      }
      
      // Muted Users Subcollection  
      match /mutedUsers/{mutedUserId} {
        // Users can read their own muted list
        allow read: if isOwner(userId);
        // Users can mute/unmute anyone
        allow write: if isOwner(userId);
      }
      
      // Hidden From Subcollection (users you've hidden your profile from)
      match /hiddenFrom/{hiddenUserId} {
        // Users can read their own hidden list
        allow read: if isOwner(userId);
        // Users can hide/unhide their profile from anyone
        allow write: if isOwner(userId);
      }
    }
    
    // ========================================
    // FOLLOWS COLLECTION (NEW - for follow/unfollow)
    // ========================================
    
    match /follows/{followId} {
      // ✅ Anyone can read follow relationships
      allow read: if isSignedIn();
      
      // ✅ Users can create a follow relationship
      // followId format: "followerUserId_followingUserId"
      allow create: if isSignedIn() && 
                       request.resource.data.followerUserId == request.auth.uid;
      
      // ✅ Users can update their own follows (status, timestamps)
      allow update: if isSignedIn() && 
                       resource.data.followerUserId == request.auth.uid;
      
      // ✅ Users can delete their own follows (unfollow)
      allow delete: if isSignedIn() && 
                       resource.data.followerUserId == request.auth.uid;
    }
    
    // ========================================
    // CONVERSATIONS COLLECTION
    // ========================================
    
    match /conversations/{conversationId} {
      // ✅ Users can read conversations they're part of
      allow read: if isSignedIn() && 
                     request.auth.uid in resource.data.participantIds;
      
      // ✅ Users can create new conversations
      allow create: if isSignedIn() && 
                       request.auth.uid in request.resource.data.participantIds;
      
      // ✅ Participants can update conversation metadata
      // (last message, read status, muted/archived flags, etc.)
      allow update: if isSignedIn() && 
                       request.auth.uid in resource.data.participantIds;
      
      // ✅ Participants can soft delete conversations
      allow delete: if isSignedIn() && 
                       request.auth.uid in resource.data.participantIds;
      
      // Messages Subcollection
      match /messages/{messageId} {
        // ✅ Participants can read messages
        allow read: if isSignedIn() && 
                       request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds;
        
        // ✅ Participants can send messages
        allow create: if isSignedIn() && 
                         request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participantIds &&
                         request.auth.uid == request.resource.data.senderId;
        
        // ✅ Sender can update their own messages (edit, mark as read, reactions)
        allow update: if isSignedIn() && 
                         request.auth.uid == resource.data.senderId;
        
        // ✅ Sender can delete their own messages
        allow delete: if isSignedIn() && 
                         request.auth.uid == resource.data.senderId;
      }
    }
    
    // ========================================
    // POSTS COLLECTION
    // ========================================
    
    match /posts/{postId} {
      // ✅ Anyone authenticated can read posts
      allow read: if isSignedIn();
      
      // ✅ Users can create their own posts
      allow create: if isSignedIn() && 
                       request.auth.uid == request.resource.data.userId;
      
      // ✅ Post authors can update their posts
      // Special case: Allow updating amenCount/commentCount/repostCount
      allow update: if isSignedIn() && (
        // Post author updating their own post
        request.auth.uid == resource.data.userId ||
        // OR: Interaction updating counts only
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['amenCount', 'commentCount', 'repostCount', 'updatedAt'])
      );
      
      // ✅ Post authors can delete their posts
      allow delete: if isSignedIn() && 
                       request.auth.uid == resource.data.userId;
      
      // Comments Subcollection
      match /comments/{commentId} {
        // ✅ Anyone can read comments
        allow read: if isSignedIn();
        
        // ✅ Anyone can create comments
        allow create: if isSignedIn();
        
        // ✅ Comment authors can update/delete their comments
        allow update, delete: if isSignedIn() && 
                                 request.auth.uid == resource.data.userId;
      }
      
      // Amens (Likes) Subcollection
      match /amens/{amenId} {
        // ✅ Anyone can read who liked
        allow read: if isSignedIn();
        
        // ✅ Users can like/unlike posts
        allow create, delete: if isSignedIn() && 
                                 request.auth.uid == amenId;
      }
      
      // Reposts Subcollection
      match /reposts/{repostId} {
        // ✅ Anyone can read reposts
        allow read: if isSignedIn();
        
        // ✅ Users can repost/unrepost
        allow create, delete: if isSignedIn() && 
                                 request.auth.uid == repostId;
      }
    }
    
    // ========================================
    // NOTIFICATIONS COLLECTION
    // ========================================
    
    match /notifications/{notificationId} {
      // ✅ Users can read their own notifications
      allow read: if isSignedIn() && 
                     resource.data.recipientId == request.auth.uid;
      
      // ✅ System can create notifications for any user
      allow create: if isSignedIn();
      
      // ✅ Users can mark their notifications as read
      allow update: if isSignedIn() && 
                       resource.data.recipientId == request.auth.uid;
      
      // ✅ Users can delete their own notifications
      allow delete: if isSignedIn() && 
                       resource.data.recipientId == request.auth.uid;
    }
    
    // ========================================
    // REPORTS COLLECTION (Moderation)
    // ========================================
    
    match /reports/{reportId} {
      // ✅ Only admins can read reports (add admin check if needed)
      allow read: if false; // Update with admin check
      
      // ✅ Users can create reports
      allow create: if isSignedIn() && 
                       request.auth.uid == request.resource.data.reporterId;
      
      // ✅ No updates or deletes for reports
      allow update, delete: if false;
    }
    
    // ========================================
    // COMMUNITIES COLLECTION (if you have it)
    // ========================================
    
    match /communities/{communityId} {
      // ✅ Anyone can read public communities
      allow read: if isSignedIn();
      
      // ✅ Anyone can create communities
      allow create: if isSignedIn();
      
      // ✅ Community admins/creators can update
      allow update: if isSignedIn() && 
                       request.auth.uid in resource.data.adminIds;
      
      // ✅ Community creators can delete
      allow delete: if isSignedIn() && 
                       request.auth.uid == resource.data.creatorId;
      
      // Members Subcollection
      match /members/{memberId} {
        allow read: if isSignedIn();
        allow create: if isSignedIn();
        allow delete: if isSignedIn() && request.auth.uid == memberId;
      }
    }
  }
}
```

---

## After Updating Rules

1. **Save and Publish** the rules in Firebase Console
2. **Wait 30 seconds** for the rules to propagate
3. **Test the Message button** again in your app
4. **Check the Xcode console** for detailed logs

---

## How the New Rules Work

### ✅ Following/Unfollowing Users

The rules support a **`follows` collection** at the root level with this structure:

```
follows/
├── {followId}  // Format: "followerUserId_followingUserId"
    ├── followerUserId: "user123"
    ├── followingUserId: "user456"
    ├── createdAt: timestamp
    └── status: "active" (optional)
```

**Key Features:**
- ✅ Anyone can read follow relationships
- ✅ Users can only create follows where they are the follower
- ✅ Users can only delete their own follows (unfollow)
- ✅ The `users` collection allows updating `followersCount` and `followingCount`

### ✅ Messaging

**Conversation Creation:**
- Users can create conversations with others
- Blocked users are checked before creation (via blocking checks)
- Conversation status can be "pending" or "accepted"

**Message Sending:**
- Only conversation participants can send messages
- Messages must have correct senderId
- Users can update/delete their own messages

### ✅ Blocking/Muting/Privacy

**Subcollections under `/users/{userId}/`:**
- `blockedUsers/{blockedUserId}` - Users you've blocked
- `mutedUsers/{mutedUserId}` - Users you've muted
- `hiddenFrom/{hiddenUserId}` - Users you've hidden your profile from

Each user can only read/write their own privacy lists.

### ✅ Posts & Interactions

**Posts:**
- Anyone can read posts
- Users create their own posts
- Post counts (amenCount, commentCount) can be updated by anyone (for likes/comments)

**Comments:**
- Anyone can create comments
- Users can update/delete their own comments

**Amens (Likes) & Reposts:**
- Stored as subcollections under posts
- Users can only create/delete their own amens/reposts

---

## Testing the Follow/Unfollow Feature

### Check Your Data Structure

Your FollowService should write to Firestore like this:

```swift
// Follow document structure in /follows/ collection
{
  "followerUserId": "currentUserId",
  "followingUserId": "targetUserId", 
  "createdAt": Timestamp,
  "status": "active"
}

// Document ID format: "currentUserId_targetUserId"
```

### Test Follow Flow

1. **Follow a user:**
   ```swift
   try await FollowService.shared.toggleFollow(userId: "targetUserId")
   ```

2. **Check Firestore Console:**
   - Navigate to `follows` collection
   - Look for document with ID: `{yourUserId}_{targetUserId}`
   - Verify fields: `followerUserId`, `followingUserId`, `createdAt`

3. **Check User Counts:**
   - Navigate to `users/{yourUserId}`
   - Verify `followingCount` incremented
   - Navigate to `users/{targetUserId}`
   - Verify `followersCount` incremented

### Common Follow/Unfollow Issues

**Issue: "Permission denied" when following**
- **Cause**: Rules don't allow creating follow document
- **Fix**: Ensure the `follows` collection rules are present (see rules above)

**Issue: "Cannot update followersCount"**
- **Cause**: User update rules too restrictive  
- **Fix**: The rules above allow updating counts specifically with this line:
  ```javascript
  request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followersCount', 'followingCount', 'updatedAt'])
  ```

**Issue: Follow created but counts not updated**
- **Cause**: Your FollowService might not be updating counts
- **Check**: Look for code that updates `followersCount`/`followingCount` in Firestore

---

## Testing the Fix

### 1. Check Current User Authentication
```swift
// In Xcode console, look for:
print("Current user ID: \(Auth.auth().currentUser?.uid ?? "not signed in")")
```

### 2. Test Message Flow
1. Open a user profile
2. Tap "Message"
3. Watch console for:
   - ✅ "Getting or creating conversation..."
   - ✅ "Got conversation ID: ..."
   - OR ❌ specific error messages

### 3. Common Issues

**Issue: "permissionDenied" error**
- **Solution**: User has blocked you or vice versa. Check `blockedUsers` subcollection.

**Issue: "followRequired" error**
- **Solution**: User requires mutual follow for messages. Follow them first.

**Issue: Still getting "insufficient permissions"**
- **Solution**: 
  1. Sign out and sign back in
  2. Check Firebase Console → Authentication to verify user exists
  3. Verify Firestore rules were published (check timestamp in Console)

---

## Alternative: Simplified Messaging (For Testing Only)

⚠️ **The blocking checks are NOW ENABLED and should work with the rules above.**

If you still want to temporarily disable blocking checks for debugging:

### Temporary Disable (Not Recommended)

Find this in `FirebaseMessagingService.swift` around line 290-296:

```swift
// CURRENT CODE (blocking checks enabled - this is correct):
let isBlocked = try await checkIfBlocked(userId: userId)
let isBlockedBy = try await checkIfBlockedByUser(userId: userId)

if isBlocked || isBlockedBy {
    throw FirebaseMessagingError.permissionDenied
}
```

To temporarily disable (ONLY for testing):
```swift
// ⚠️ TEMPORARY: Disable blocking check for testing
// let isBlocked = try await checkIfBlocked(userId: userId)
// let isBlockedBy = try await checkIfBlockedByUser(userId: userId)
// 
// if isBlocked || isBlockedBy {
//     throw FirebaseMessagingError.permissionDenied
// }
print("⚠️ Blocking check temporarily disabled for testing")
```

**🚨 IMPORTANT: This must be re-enabled before production! The rules above should allow this to work correctly.**

---

## Debugging Checklist

- [ ] Firestore rules updated and published
- [ ] User is authenticated (check `Auth.auth().currentUser`)
- [ ] `users/{userId}` document exists in Firestore
- [ ] Internet connection is working
- [ ] App has been restarted after rule changes
- [ ] Tried signing out and back in
- [ ] Console shows detailed error messages

---

## Still Not Working?

### Check Firestore Console

1. Go to Firebase Console → Firestore Database
2. Navigate to `conversations` collection
3. Try manually creating a test document
4. If manual creation works, the issue is in the app code
5. If manual creation fails, it's a rules/permissions issue

### Check User Document Structure

Your user document should look like:
```json
{
  "displayName": "John Doe",
  "username": "johndoe",
  "email": "john@example.com",
  "bio": "...",
  "followersCount": 0,
  "followingCount": 0,
  "createdAt": "...",
  "updatedAt": "..."
}
```

### Enable Firestore Debug Logging

Add this to your AppDelegate:

```swift
import FirebaseFirestore

// In application(_:didFinishLaunchingWithOptions:)
FirebaseConfiguration.shared.setLoggerLevel(.debug)
```

This will show detailed Firestore operations in the console.

---

## Production Considerations

Once working, consider:

1. **Rate Limiting**: Prevent spam by limiting conversation creation
2. **Block List Sync**: Ensure blocked users can't message at all
3. **Message Requests**: Implement pending/accepted conversation states
4. **Privacy Settings**: Allow users to control who can message them
5. **Error Recovery**: Show user-friendly error messages

---

**Last Updated**: January 29, 2026
**Status**: Ready to implement
