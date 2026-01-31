# Firestore Security Rules Fix

## Problem
You're seeing this error:
```
❌ Firestore listener error: Missing or insufficient permissions.
   Error code: 7, domain: FIRFirestoreErrorDomain
```

This means your **Firestore Security Rules** are blocking read access to the `posts` collection.

## Solution

### Step 1: Open Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project (AMENAPP)
3. Click on **Firestore Database** in the left sidebar
4. Click on the **Rules** tab

### Step 2: Update Your Security Rules

Replace your current rules with one of the following options:

#### Option A: Production-Ready Rules (Recommended)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to check if user owns the document
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    // Users collection
    match /users/{userId} {
      // Anyone can read public user data (for profiles, posts, etc.)
      allow read: if true;
      // Only the user can write their own data
      allow write: if isOwner(userId);
      
      // Subcollections
      match /posts/{postId} {
        allow read: if true;
        allow write: if isOwner(userId);
      }
      
      match /savedPosts/{savedPostId} {
        allow read, write: if isOwner(userId);
      }
    }
    
    // Posts collection - PUBLIC FEED
    match /posts/{postId} {
      // ✅ Anyone authenticated can read posts
      allow read: if isAuthenticated();
      
      // ✅ Only authenticated users can create posts with their own authorId
      allow create: if isAuthenticated() 
                    && request.resource.data.authorId == request.auth.uid;
      
      // ✅ Only the post author can update/delete their posts
      allow update, delete: if isAuthenticated() 
                            && resource.data.authorId == request.auth.uid;
    }
    
    // Comments collection
    match /comments/{commentId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() 
                    && request.resource.data.authorId == request.auth.uid;
      allow update, delete: if isAuthenticated() 
                            && resource.data.authorId == request.auth.uid;
      
      // Nested replies
      match /replies/{replyId} {
        allow read: if isAuthenticated();
        allow create: if isAuthenticated() 
                      && request.resource.data.authorId == request.auth.uid;
        allow update, delete: if isAuthenticated() 
                              && resource.data.authorId == request.auth.uid;
      }
    }
    
    // Follows collection
    match /follows/{followId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() 
                    && request.resource.data.followerId == request.auth.uid;
      allow delete: if isAuthenticated() 
                    && resource.data.followerId == request.auth.uid;
    }
    
    // Notifications
    match /notifications/{notificationId} {
      allow read: if isAuthenticated() 
                  && resource.data.userId == request.auth.uid;
      allow write: if isAuthenticated();
    }
    
    // Messages
    match /conversations/{conversationId} {
      allow read: if isAuthenticated() 
                  && request.auth.uid in resource.data.participantIds;
      allow create: if isAuthenticated() 
                    && request.auth.uid in request.resource.data.participantIds;
      
      match /messages/{messageId} {
        allow read: if isAuthenticated();
        allow create: if isAuthenticated();
      }
    }
    
    // Saved posts
    match /savedPosts/{userId}/posts/{postId} {
      allow read, write: if isOwner(userId);
    }
    
    // Reposts tracking
    match /reposts/{repostId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() 
                    && request.resource.data.userId == request.auth.uid;
      allow delete: if isAuthenticated() 
                    && resource.data.userId == request.auth.uid;
    }
    
    // Moderation
    match /muted/{muteId} {
      allow read, write: if isAuthenticated() 
                         && resource.data.userId == request.auth.uid;
    }
    
    match /blocked/{blockId} {
      allow read, write: if isAuthenticated() 
                         && resource.data.userId == request.auth.uid;
    }
    
    match /reports/{reportId} {
      allow create: if isAuthenticated() 
                    && request.resource.data.reporterId == request.auth.uid;
      allow read: if false; // Only admins (via Cloud Functions)
    }
    
    // Default deny all for security
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

#### Option B: Development/Testing Rules (Simpler, Less Secure)

**⚠️ Use this ONLY during development. Replace with Option A before launching.**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to read and write everything
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

#### Option C: Wide Open (NEVER USE IN PRODUCTION)

**🚨 EXTREMELY INSECURE - Only for initial testing**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

### Step 3: Publish the Rules

1. After pasting your chosen rules, click **Publish**
2. Wait a few seconds for the rules to propagate
3. Restart your app and try again

---

## Code Changes Made

I've also updated your `FirebasePostService.swift` to:

1. ✅ **Check authentication before setting up listeners**
   - Prevents the listener from running if user isn't signed in
   
2. ✅ **Better error messages**
   - Detects permission errors (code 7) and shows helpful message
   - Prints clearer debugging information

### Testing

After updating your Firestore rules:

1. Make sure you're signed in to the app
2. Check the Xcode console for these messages:
   - ✅ `User authenticated, setting up listener...`
   - ✅ `Real-time update: X posts`

If you still see errors:
- Check that your Firebase project is the correct one
- Verify the rules were published successfully
- Try signing out and signing back in
- Check the Firestore Rules Playground in Firebase Console to test your rules

---

## Additional Security Recommendations

### 1. Add Firestore Indexes

For better query performance, create these indexes in Firebase Console:

**Posts Collection:**
- `category` (Ascending) + `createdAt` (Descending)
- `authorId` (Ascending) + `createdAt` (Descending)
- `visibility` (Ascending) + `createdAt` (Descending)

**Comments Collection:**
- `postId` (Ascending) + `createdAt` (Ascending)

**Follows Collection:**
- `followerId` (Ascending) + `createdAt` (Descending)
- `followingId` (Ascending) + `createdAt` (Descending)

### 2. Set Up Firebase Realtime Database Rules

Since you're also using Firebase Realtime Database (for interactions), update those rules too:

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null",
    
    "postInteractions": {
      "$postId": {
        ".read": "auth != null",
        "lightbulbs": {
          "$userId": {
            ".write": "auth != null && auth.uid === $userId"
          }
        },
        "amens": {
          "$userId": {
            ".write": "auth != null && auth.uid === $userId"
          }
        }
      }
    },
    
    "users": {
      "$userId": {
        ".read": "auth != null",
        ".write": "auth != null && auth.uid === $userId"
      }
    }
  }
}
```

---

## Troubleshooting

### Still getting permission errors?

1. **Check you're using the correct Firebase project:**
   ```swift
   print("Firebase Project ID: \(FirebaseApp.app()?.options.projectID ?? "Unknown")")
   ```

2. **Verify authentication state:**
   ```swift
   print("Current User: \(Auth.auth().currentUser?.uid ?? "Not signed in")")
   ```

3. **Test rules in Firebase Console:**
   - Go to Firestore > Rules > Rules Playground
   - Select "posts" collection
   - Test with your user's UID

4. **Clear app data and sign in again:**
   - Delete the app from simulator/device
   - Reinstall and sign in fresh

---

## Summary

✅ **Updated `FirebasePostService.swift`** to check authentication before listeners
✅ **Improved error messages** to help diagnose permission issues
✅ **Provided production-ready Firestore security rules**

**Next Steps:**
1. Update your Firestore rules in Firebase Console
2. Publish the rules
3. Restart your app
4. Check console for success messages
