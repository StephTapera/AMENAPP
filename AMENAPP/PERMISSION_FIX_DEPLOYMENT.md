# 🔧 Permission Errors Fix - Deploy Now!

## Issues Fixed

### 1. ✅ Realtime Database - Amen Permission Denied
**Error**: `setValue: at /postInteractions/.../amens/91JpG4q... failed: permission_denied`

**Problem**: Rules used `$amenId` but code writes with `$userId` directly.

**Fix**: Changed amens structure from:
```json
"amens": {
  "$amenId": { ... }
}
```

To:
```json
"amens": {
  "$userId": {
    ".write": "auth != null && auth.uid == $userId"
  }
}
```

### 2. ✅ Firestore - Saved Posts Permission Denied
**Error**: `Listen for query at savedPosts|f:userId==... failed: Missing or insufficient permissions`

**Problem**: Code queries top-level `savedPosts` collection, but rules only had subcollection under `users/{userId}/savedPosts`.

**Fix**: Added top-level `savedPosts` collection to Firestore rules:
```javascript
match /savedPosts/{saveId} {
  allow read: if isAuthenticated() 
    && resource.data.userId == request.auth.uid;
  allow create: if isAuthenticated()
    && request.resource.data.userId == request.auth.uid;
  allow delete: if isAuthenticated()
    && resource.data.userId == request.auth.uid;
}
```

## 🚀 DEPLOY THESE RULES NOW!

### Step 1: Deploy Realtime Database Rules

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your **AMEN** project
3. Click **Realtime Database** (left sidebar)
4. Click **Rules** tab
5. Copy **ALL** content from `/repo/database.rules.json`
6. Paste into the Firebase rules editor
7. Click **Publish** ✅

### Step 2: Deploy Firestore Rules

1. Stay in Firebase Console
2. Click **Firestore Database** (left sidebar)
3. Click **Rules** tab
4. Copy **ALL** content from `/repo/firestore 18.rules`
5. Paste into the Firebase rules editor
6. Click **Publish** ✅

### Step 3: Test Your App

1. **Force quit** your app completely
2. **Reopen** the app
3. **Test amen button** - should work now ✅
4. **Test bookmark/save** - should work now ✅

## ⚠️ About the Font Warning

The warning:
```
Unable to update Font Descriptor's weight to Weight(value: 0.3)
```

**This is harmless!** It's a known SwiftUI bug when using custom fonts (OpenSans) with certain modifiers. It doesn't affect your app functionality. You can safely ignore it.

If you want to suppress it (optional):
- Remove any `.fontWeight()` modifiers on Text views that already use custom fonts
- Or switch to system fonts with weights: `.font(.system(size: 12, weight: .semibold))`

## ✅ After Deployment

Your errors should be gone:
- ✅ Amens will save properly
- ✅ Bookmarks will save properly
- ✅ No more permission denied errors

## 📊 What Changed

### database.rules.json
- Changed `amens/$amenId` → `amens/$userId`
- Now matches how your `PostInteractionsService` writes data

### firestore 18.rules
- Added top-level `savedPosts` collection
- Users can read/write their own saved posts by userId

## 🎯 Data Structure Now Supported

### Realtime Database
```
/postInteractions/{postId}/
  ├── amens/{userId}/          ← FIXED: Now uses userId
  │   ├── userId: "..."
  │   ├── userName: "..."
  │   └── timestamp: 123456
  ├── lightbulbs/{userId}/
  ├── comments/{commentId}/
  └── reposts/{userId}/
```

### Firestore
```
/savedPosts/{saveId}           ← NEW: Top-level collection
  ├── userId: "91JpG4q..."     ← Can query by this
  ├── postId: "..."
  └── savedAt: timestamp

/users/{userId}/savedPosts     ← OLD: Still works for subcollections
```

## 🔥 Deploy Now!

Both rules files are ready. Just copy-paste them to Firebase Console and publish!

---

**Files Updated**:
- ✅ `/repo/database.rules.json` - Realtime Database Rules
- ✅ `/repo/firestore 18.rules` - Firestore Rules

**Next**: Deploy to Firebase Console → Test app → Errors gone! 🎉
