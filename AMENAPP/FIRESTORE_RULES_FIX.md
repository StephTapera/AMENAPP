# Firestore Security Rules Fix

## Issue: "Missing or insufficient permissions" on Username Login

### Problem
When trying to sign in with a username, the app needs to look up the username in Firestore to find the associated email address. However, Firestore security rules are blocking this read operation.

### Solution
Update your Firestore Security Rules to allow username lookups during login.

## Updated Firestore Rules

Go to [Firebase Console](https://console.firebase.google.com/) → Firestore Database → Rules

Replace your current rules with this:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isSignedIn() {
      return request.auth != null;
    }
    
    // Helper function to check if accessing own data
    function isOwner(userId) {
      return request.auth.uid == userId;
    }
    
    // USERS COLLECTION
    match /users/{userId} {
      // Allow read access to all authenticated users (for profiles, search, etc.)
      allow read: if isSignedIn();
      
      // Allow reading user profiles for username lookup BEFORE authentication
      // This is needed for username-based login
      allow read: if true;
      
      // Allow users to create their own profile during sign-up
      allow create: if request.auth.uid == userId;
      
      // Allow users to update their own profile
      allow update: if isOwner(userId);
      
      // Only allow users to delete their own profile
      allow delete: if isOwner(userId);
    }
    
    // POSTS COLLECTION
    match /posts/{postId} {
      // Anyone authenticated can read posts
      allow read: if isSignedIn();
      
      // Only authenticated users can create posts
      allow create: if isSignedIn() 
                   && request.auth.uid == request.resource.data.authorId;
      
      // Only post author can update their post
      allow update: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
      
      // Only post author can delete their post
      allow delete: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
    }
    
    // TESTIMONIES COLLECTION
    match /testimonies/{testimonyId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() 
                   && request.auth.uid == request.resource.data.authorId;
      allow update: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
      allow delete: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
    }
    
    // PRAYERS COLLECTION
    match /prayers/{prayerId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn() 
                   && request.auth.uid == request.resource.data.authorId;
      allow update: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
      allow delete: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
    }
    
    // COMMENTS COLLECTION
    match /comments/{commentId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow update: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
      allow delete: if isSignedIn() 
                   && request.auth.uid == resource.data.authorId;
    }
    
    // CONVERSATIONS COLLECTION
    match /conversations/{conversationId} {
      // Helper to check if user is participant
      function isParticipant() {
        return request.auth.uid in resource.data.participantIds;
      }
      
      allow read: if isSignedIn() && isParticipant();
      allow create: if isSignedIn() 
                   && request.auth.uid in request.resource.data.participantIds;
      allow update: if isSignedIn() && isParticipant();
      allow delete: if isSignedIn() && isParticipant();
      
      // Messages subcollection
      match /messages/{messageId} {
        allow read: if isSignedIn() && isParticipant();
        allow create: if isSignedIn() && isParticipant();
        allow update, delete: if isSignedIn() 
                             && request.auth.uid == resource.data.senderId;
      }
    }
    
    // SAVED POSTS
    match /savedPosts/{userId} {
      allow read, write: if isOwner(userId);
    }
    
    // FOLLOWS
    match /follows/{followId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow delete: if isSignedIn() 
                   && request.auth.uid == resource.data.followerId;
    }
    
    // NOTIFICATIONS
    match /notifications/{notificationId} {
      allow read: if isSignedIn() 
                 && request.auth.uid == resource.data.recipientId;
      allow create: if isSignedIn();
      allow update, delete: if isSignedIn() 
                           && request.auth.uid == resource.data.recipientId;
    }
    
    // COMMUNITIES/GROUPS
    match /communities/{communityId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow update: if isSignedIn(); // Adjust based on admin logic
      allow delete: if isSignedIn(); // Adjust based on admin logic
    }
    
    // REPOSTS
    match /reposts/{repostId} {
      allow read: if isSignedIn();
      allow create: if isSignedIn();
      allow delete: if isSignedIn() 
                   && request.auth.uid == resource.data.userId;
    }
  }
}
```

### Key Changes

1. **Users collection**: Now allows `read: if true` which means anyone (even unauthenticated users) can read user profiles. This is necessary for username lookup during login.

2. **Duplicate read rule**: The first `allow read: if isSignedIn()` handles reads by authenticated users, and the second `allow read: if true` handles reads during login (when user isn't authenticated yet).

### Alternative: More Secure Approach

If you want to keep user profiles private but still allow username lookup, you can create a separate `usernames` collection:

```javascript
// Add this to your rules
match /usernames/{username} {
  // Anyone can look up username to email mapping (for login only)
  allow read: if true;
  
  // Only system can write (use Cloud Functions)
  allow write: if false;
}
```

Then in your Cloud Functions, create a trigger to maintain this collection:

```javascript
// Cloud Function to sync usernames
exports.onUserCreate = functions.firestore
  .document('users/{userId}')
  .onCreate(async (snap, context) => {
    const userData = snap.data();
    const username = userData.username;
    const email = userData.email;
    
    // Create username lookup entry
    await admin.firestore()
      .collection('usernames')
      .doc(username.toLowerCase())
      .set({
        email: email,
        userId: context.params.userId
      });
  });
```

### How to Apply Rules

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click **Firestore Database** in the left menu
4. Click the **Rules** tab
5. Copy and paste the rules above
6. Click **Publish**

### Testing

After updating rules, try:
1. Sign out of your app
2. Try logging in with username
3. Should work now without permission errors

### Important Note

Making user profiles readable without authentication (`allow read: if true`) means anyone can query your users collection. This is generally acceptable for public profile data but consider:

- Don't store sensitive data in user documents
- Use subcollections for private data
- Implement rate limiting in Firebase
- Consider using the separate `usernames` collection approach for better security

---

## Summary

✅ **Root Cause**: Firestore rules blocked unauthenticated reads  
✅ **Fix**: Allow reading users collection for username lookup  
✅ **Alternative**: Create separate usernames collection  
✅ **Security**: Consider implications of public user profiles  

Your username login should now work! 🎉
