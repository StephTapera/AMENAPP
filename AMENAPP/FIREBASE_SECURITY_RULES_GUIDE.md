# Firebase Security Rules Setup Guide

## ⚠️ CRITICAL SECURITY ISSUE

Your current Firebase security rules allow **any authenticated user** to read and write to your **entire database**. This is a serious security vulnerability that must be fixed immediately.

### What's Wrong?

The current rules likely look like this:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

This means:
- ❌ Any logged-in user can read ALL users' private data
- ❌ Any logged-in user can modify or delete ANY post
- ❌ Any logged-in user can impersonate other users
- ❌ No data validation is enforced
- ❌ Users can manually manipulate counts (likes, followers, etc.)

## 🔒 Solution: Proper Security Rules

I've created two security rule files for you:

1. **`firestore.rules`** - Database security rules
2. **`storage.rules`** - File storage security rules

## 📋 How to Deploy These Rules

### Option 1: Firebase Console (Recommended for Quick Fix)

1. **Go to Firebase Console**
   - Visit: https://console.firebase.google.com
   - Select your AMENAPP project

2. **Deploy Firestore Rules**
   - Click on **Firestore Database** in the left sidebar
   - Click on the **Rules** tab at the top
   - Copy the entire contents of `firestore.rules`
   - Paste it into the rules editor
   - Click **Publish**

3. **Deploy Storage Rules**
   - Click on **Storage** in the left sidebar
   - Click on the **Rules** tab
   - Copy the entire contents of `storage.rules`
   - Paste it into the rules editor
   - Click **Publish**

### Option 2: Firebase CLI (Recommended for Production)

1. **Install Firebase CLI** (if not already installed)
   ```bash
   npm install -g firebase-tools
   ```

2. **Login to Firebase**
   ```bash
   firebase login
   ```

3. **Initialize Firebase in your project** (if not already done)
   ```bash
   cd /path/to/your/project
   firebase init
   ```
   - Select **Firestore** and **Storage**
   - Choose your AMENAPP project
   - Accept default file names

4. **Copy the rules files**
   - Copy `firestore.rules` to your project root
   - Copy `storage.rules` to your project root

5. **Deploy the rules**
   ```bash
   firebase deploy --only firestore:rules
   firebase deploy --only storage:rules
   ```

## 🔍 What the New Rules Do

### Firestore Rules

#### Users Collection
- ✅ Anyone authenticated can **read** public profiles
- ✅ Users can only **create/update/delete** their own profile
- ✅ Email cannot be changed after creation
- ✅ Follower/following/post counts can only be changed by Cloud Functions
- ✅ Users can only access their own saved posts

#### Posts Collection
- ✅ Anyone authenticated can **read** posts
- ✅ Users can only **create** posts with their own authorId
- ✅ Post content limited to 500 characters
- ✅ Only valid categories allowed: 'openTable', 'testimonies', 'prayer'
- ✅ Like/comment/repost counts protected from manual manipulation
- ✅ Only post author can **update/delete** their posts
- ✅ Comments have similar protections

#### Messages Collection
- ✅ Users can only read messages they're part of
- ✅ Users can only send messages as themselves
- ✅ Message content limited to 1000 characters
- ✅ Only sender can edit/delete their messages

#### Notifications Collection
- ✅ Users can only read their own notifications
- ✅ Users can mark their notifications as read
- ✅ Users can delete their own notifications

#### Communities Collection
- ✅ Anyone can read community info
- ✅ Only creator or admins can update community
- ✅ Only creator can delete community
- ✅ Members can join/leave freely

#### Follows/Reposts/SavedPosts
- ✅ Users can only create follows/reposts/saves for themselves
- ✅ Users can only delete their own follows/reposts/saves

### Storage Rules

#### Profile Images
- ✅ Anyone can **read** profile images (public)
- ✅ Only owner can **upload/update/delete** their profile image
- ✅ Images limited to 10MB
- ✅ Only image file types allowed

#### Post/Testimony/Prayer Images
- ✅ Authenticated users can read
- ✅ Authenticated users can upload (must be images, max 10MB)
- ✅ Only authenticated users can delete

#### Message Images
- ✅ Only authenticated users can access
- ✅ Images limited to 10MB

## ⚡️ Testing Your Rules

After deploying, test these scenarios:

### Test 1: User Can Only Edit Own Profile
```swift
// This should work
FirebaseManager.shared.updateDocument([
    "bio": "New bio"
], at: "users/\(currentUserId)")

// This should FAIL with permission denied
FirebaseManager.shared.updateDocument([
    "bio": "Hacked!"
], at: "users/someOtherUserId")
```

### Test 2: User Cannot Manipulate Counts
```swift
// This should FAIL
FirebaseManager.shared.updateDocument([
    "followersCount": 1000000
], at: "users/\(currentUserId)")
```

### Test 3: User Can Only Delete Own Posts
```swift
// This should work (if user is post author)
FirebaseManager.shared.deleteDocument(at: "posts/\(myPostId)")

// This should FAIL (if user is not post author)
FirebaseManager.shared.deleteDocument(at: "posts/\(someoneElsesPostId)")
```

## 🚨 Important Notes

### 1. Cloud Functions Needed for Counts
Since users can't manually update counts, you'll need Cloud Functions to handle:
- Incrementing/decrementing follower counts
- Updating post counts
- Updating like/comment counts
- Updating community member counts

Example Cloud Function:
```javascript
exports.onFollowCreated = functions.firestore
  .document('follows/{followId}')
  .onCreate(async (snap, context) => {
    const follow = snap.data();
    const batch = admin.firestore().batch();
    
    // Increment follower count
    const followingRef = admin.firestore()
      .collection('users')
      .doc(follow.followingId);
    batch.update(followingRef, {
      followersCount: admin.firestore.FieldValue.increment(1)
    });
    
    // Increment following count
    const followerRef = admin.firestore()
      .collection('users')
      .doc(follow.followerId);
    batch.update(followerRef, {
      followingCount: admin.firestore.FieldValue.increment(1)
    });
    
    await batch.commit();
  });
```

### 2. Existing Data
These rules don't affect existing data structure, only access permissions. However, you should audit your existing data to ensure it follows the validation rules.

### 3. Testing in Development
While testing, you can temporarily relax rules by setting:
```javascript
// WARNING: Only use in development!
allow read, write: if request.auth != null && request.auth.token.email.matches('.*@yourdomain.com');
```

### 4. Rate Limiting
Consider implementing rate limiting in your app to prevent abuse:
- Limit post creation to X per hour
- Limit message sending
- Limit follow/unfollow actions

This should be done in your Swift code or Cloud Functions.

## 📚 Additional Resources

- [Firebase Security Rules Documentation](https://firebase.google.com/docs/firestore/security/get-started)
- [Security Rules Testing](https://firebase.google.com/docs/firestore/security/test-rules-emulator)
- [Cloud Functions for Firebase](https://firebase.google.com/docs/functions)

## ✅ Deployment Checklist

- [ ] Backup current rules (if any)
- [ ] Copy `firestore.rules` to project
- [ ] Copy `storage.rules` to project
- [ ] Deploy Firestore rules via Console or CLI
- [ ] Deploy Storage rules via Console or CLI
- [ ] Test user authentication flows
- [ ] Test that users can't edit others' data
- [ ] Test that counts can't be manually changed
- [ ] Verify images upload correctly
- [ ] Monitor Firebase Console for rule violations

## 🆘 If Something Breaks

If you deploy these rules and your app stops working:

1. **Check the Firebase Console logs** for specific rule violations
2. **Temporarily revert** to open rules (only if necessary):
   ```javascript
   allow read, write: if request.auth != null;
   ```
3. **Fix the specific issue** based on the error message
4. **Redeploy the secure rules**

The most common issues will be:
- Trying to update fields that are protected (like counts)
- Trying to update documents without proper authorization
- Missing required fields when creating documents

## 🎯 Next Steps

1. **Deploy these rules immediately** to fix the security vulnerability
2. **Set up Cloud Functions** to handle count updates
3. **Test thoroughly** in development before deploying to production
4. **Monitor Firebase usage** for any unauthorized access attempts
5. **Implement rate limiting** in your app code
6. **Consider adding Cloud Functions** for additional business logic validation

---

**Remember:** Security rules are your first line of defense. Even with proper client-side validation, malicious users can bypass your app and directly access Firebase APIs. These server-side rules ensure your data is always protected.
