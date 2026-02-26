# P0 Cloud Functions Deployment Guide

## ✅ iOS P0 Fixes (Already Deployed)
The iOS app is ready to handle server-side idempotency keys and improved notification logic. All client-side P0 fixes are complete.

---

## 🚀 Server-Side P0 Fixes Required

### **P0-2b: Implement Deterministic Notification IDs in Cloud Functions**

**Location:** `functions/pushNotifications.js`

**Problem:** Notifications can be duplicated if Cloud Functions retry or network failures occur.

**Solution:** Add deterministic `idempotencyKey` to all notifications before creating them.

#### Implementation Pattern

For **ALL notification creation** in your Cloud Functions, add the `idempotencyKey` field:

```javascript
// ✅ PATTERN: Deterministic idempotency key
const idempotencyKey = `${notificationType}_${actorUserId}_${targetUserId}_${targetResourceId || ''}`;

// Example 1: Follow notification
const idempotencyKey = `follow_${followerId}_${followedUserId}`;

// Example 2: Comment notification
const idempotencyKey = `comment_${commenterId}_${postOwnerId}_${postId}`;

// Example 3: Amen notification
const idempotencyKey = `amen_${amenerId}_${postOwnerId}_${postId}`;
```

#### Specific Functions to Update

**1. `onUserFollow` (Line ~150-200)**
```javascript
// BEFORE
await admin.firestore().collection("users")
  .doc(followedUserId)
  .collection("notifications")
  .add({
    userId: followedUserId,
    type: "follow",
    actorId: followerId,
    // ... other fields
  });

// AFTER (with P0-2b fix)
const idempotencyKey = `follow_${followerId}_${followedUserId}`;

// Check if notification already exists
const existingNotif = await admin.firestore()
  .collection("users")
  .doc(followedUserId)
  .collection("notifications")
  .where("idempotencyKey", "==", idempotencyKey)
  .limit(1)
  .get();

if (!existingNotif.empty) {
  console.log(`⏭️ Skipping duplicate follow notification: ${idempotencyKey}`);
  return null;
}

await admin.firestore().collection("users")
  .doc(followedUserId)
  .collection("notifications")
  .add({
    userId: followedUserId,
    type: "follow",
    actorId: followerId,
    idempotencyKey: idempotencyKey,  // ✅ Added
    // ... other fields
  });
```

**2. `onFollowRequestAccepted` (Line ~795-820)**
```javascript
// ✅ P0-9: Check for existing notification before creating
const idempotencyKey = `follow_request_accepted_${toUserId}_${fromUserId}`;

const existingNotif = await admin.firestore()
  .collection("users")
  .doc(fromUserId)
  .collection("notifications")
  .where("idempotencyKey", "==", idempotencyKey)
  .limit(1)
  .get();

if (!existingNotif.empty) {
  console.log(`⏭️ Skipping duplicate follow request accepted notification: ${idempotencyKey}`);
  return null;
}

await admin.firestore().collection("users")
  .doc(fromUserId)
  .collection("notifications")
  .add({
    userId: fromUserId,
    type: "followRequestAccepted",
    actorId: toUserId,
    idempotencyKey: idempotencyKey,  // ✅ Added
    // ... other fields
  });
```

**3. `onCommentCreate` (Line ~250-300)**
```javascript
const idempotencyKey = `comment_${commenterId}_${postOwnerId}_${postId}`;

// Check for existing notification
const existingNotif = await admin.firestore()
  .collection("users")
  .doc(postOwnerId)
  .collection("notifications")
  .where("idempotencyKey", "==", idempotencyKey)
  .limit(1)
  .get();

if (!existingNotif.empty) {
  console.log(`⏭️ Skipping duplicate comment notification: ${idempotencyKey}`);
  return null;
}

await admin.firestore().collection("users")
  .doc(postOwnerId)
  .collection("notifications")
  .add({
    userId: postOwnerId,
    type: "comment",
    actorId: commenterId,
    postId: postId,
    commentText: commentText,
    idempotencyKey: idempotencyKey,  // ✅ Added
    // ... other fields
  });
```

**4. `onAmenCreate` (Line ~400-450)**
```javascript
const idempotencyKey = `amen_${amenerId}_${postOwnerId}_${postId}`;

// Check for existing notification
const existingNotif = await admin.firestore()
  .collection("users")
  .doc(postOwnerId)
  .collection("notifications")
  .where("idempotencyKey", "==", idempotencyKey)
  .limit(1)
  .get();

if (!existingNotif.empty) {
  console.log(`⏭️ Skipping duplicate amen notification: ${idempotencyKey}`);
  return null;
}

await admin.firestore().collection("users")
  .doc(postOwnerId)
  .collection("notifications")
  .add({
    userId: postOwnerId,
    type: "amen",
    actorId: amenerId,
    postId: postId,
    idempotencyKey: idempotencyKey,  // ✅ Added
    // ... other fields
  });
```

**5. `onRepostCreate` (Similar pattern)**
```javascript
const idempotencyKey = `repost_${reposterId}_${originalPostOwnerId}_${postId}`;
```

**6. `onMessageRequestAccepted` (Similar pattern)**
```javascript
const idempotencyKey = `message_request_accepted_${fromUserId}_${toUserId}`;
```

---

## 📝 Deployment Steps

### 1. Install Firebase CLI (if not already installed)
```bash
npm install -g firebase-tools
```

### 2. Navigate to functions directory
```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions"
```

### 3. Login to Firebase
```bash
firebase login
```

### 4. Check current project
```bash
firebase projects:list
firebase use <your-project-id>
```

### 5. Test locally (optional but recommended)
```bash
# Install dependencies
npm install

# Run emulator
firebase emulators:start --only functions
```

### 6. Deploy to production
```bash
# Deploy all functions
firebase deploy --only functions

# Or deploy specific functions
firebase deploy --only functions:onUserFollow,functions:onFollowRequestAccepted
```

### 7. Monitor deployment
```bash
# View logs
firebase functions:log

# View specific function logs
firebase functions:log --only onUserFollow
```

---

## 🔍 Testing After Deployment

### Test P0-2b (Idempotency)
1. Create a follow action from User A to User B
2. Check Firestore: `users/{userB}/notifications`
3. Verify notification has `idempotencyKey` field
4. Trigger same action again (simulate retry)
5. Verify only ONE notification exists with that idempotencyKey

### Test P0-9 (No Duplicate Follow Request Accepted)
1. User A sends follow request to User B (private account)
2. User B accepts request
3. Check User A's notifications
4. Should see only ONE "follow request accepted" notification
5. Simulate multiple accept triggers (edge case)
6. Verify no duplicates

---

## 📊 Firestore Index Requirements

After adding `idempotencyKey` queries, you may need to create composite indexes:

**Index 1: Notifications by idempotencyKey**
```
Collection: users/{userId}/notifications
Fields:
  - idempotencyKey (Ascending)
  - createdAt (Descending)
```

Firebase will prompt you to create these automatically when you first run queries.

---

## 🚨 Rollback Plan

If issues occur after deployment:

```bash
# View function versions
firebase functions:list

# Rollback to previous version (if needed)
firebase functions:delete <function-name>
# Then redeploy previous code
```

---

## ✅ Verification Checklist

After deployment, verify:

- [ ] All notifications have `idempotencyKey` field
- [ ] No duplicate follow notifications
- [ ] No duplicate follow request accepted notifications
- [ ] No duplicate comment/amen/repost notifications
- [ ] Cloud Function logs show "⏭️ Skipping duplicate" messages for retries
- [ ] Badge counts are accurate
- [ ] No performance degradation

---

## 📞 Support

If you encounter deployment issues:
1. Check Firebase Console > Functions for error logs
2. Check Firestore Rules (ensure notifications can be created)
3. Verify IAM permissions for Cloud Functions
4. Check function quotas and limits

---

## 🎯 Expected Impact

**Before P0-2b & P0-9:**
- Users see duplicate notifications
- Badge counts are inflated
- Confusing UX

**After P0-2b & P0-9:**
- ✅ Each action creates exactly ONE notification
- ✅ Retries are safely idempotent
- ✅ Badge counts are accurate
- ✅ Clean, professional notification experience

---

## 📚 Additional Resources

- [Firebase Functions Documentation](https://firebase.google.com/docs/functions)
- [Firestore Triggers](https://firebase.google.com/docs/functions/firestore-events)
- [Function Deployment Best Practices](https://firebase.google.com/docs/functions/manage-functions)
