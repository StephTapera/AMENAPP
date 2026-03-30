# Firebase Fixes Deployment Guide

## Critical Issues Fixed & Deployment Steps

This guide covers all the Firebase-related fixes needed to resolve the permission errors and missing indexes identified in the March 28, 2026 logs.

---

## ✅ Completed Code Fixes

### 1. Firestore Indexes JSON Syntax Error - FIXED ✓
- **File**: `AMENAPP/firestore.indexes.json`
- **Issue**: Duplicate trailing commas causing JSON parse errors
- **Status**: Fixed locally, needs deployment

### 2. Apple Sign In Button Constraints - FIXED ✓
- **File**: `AMENAPP/AMENAuthLandingView.swift`
- **Issue**: AutoLayout constraint conflicts causing warnings
- **Fix**: Added `.frame(maxWidth: .infinity)` to prevent width conflicts
- **Status**: Fixed in code

### 3. Haptic Feedback Error Handling - FIXED ✓
- **File**: `AMENAPP/HapticManager.swift`
- **Issue**: CoreHaptics crashes when engine not ready
- **Fix**: Added do-catch blocks around all haptic calls
- **Status**: Fixed in code

---

## 🔴 P0 - Critical Firebase Deployments Required

### Issue 1: Firestore Permission Errors for Saved Posts

**Error Log**:
```
Listen for query at posts/{postId} failed: Missing or insufficient permissions.
```

**Root Cause**: Users cannot read posts they've saved because the Firestore rules don't allow reading posts when the user isn't the author or follower.

**Fix Required**: Update Firestore Rules

**File to Update**: `/AMENAPP/firestore 18.rules` (most recent)

**Location**: Around line 500, the `callerCanReadPost()` helper function needs to check if the post is in the user's saved posts.

**Add this helper function** (find a good spot near other helper functions, around line 60-70):

```javascript
// Check if user has saved this post
function isPostSavedByUser() {
  return exists(/databases/$(database)/documents/users/$(request.auth.uid)/savedPosts/$(postId));
}
```

**Then update the read rule** (around line 500):

Change from:
```javascript
allow get: if isAuthenticated() && callerCanReadPost();
```

To:
```javascript
allow get: if isAuthenticated() && (callerCanReadPost() || isPostSavedByUser());
```

**Deployment Command**:
```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:rules
```

---

### Issue 2: Realtime Database Permission Errors

**Error Logs**:
```
Listener at /posts/recent failed: permission_denied
Listener at /userInteractions/{userId} failed: permission_denied
Listener at /user_saved_posts/{userId} failed: permission_denied
```

**Root Cause**: Realtime Database rules are too restrictive for authenticated users.

**Fix Required**: Update Realtime Database Rules

**File to Update**: `/AMENAPP/database.rules.json` or `/database.rules.json`

**Required Rules**:

```json
{
  "rules": {
    "posts": {
      "recent": {
        ".read": "auth != null",
        ".write": false
      }
    },
    "userInteractions": {
      "$userId": {
        ".read": "auth != null && auth.uid == $userId",
        ".write": "auth != null && auth.uid == $userId",
        "amens": {
          ".read": "auth != null && auth.uid == $userId",
          ".write": "auth != null && auth.uid == $userId"
        },
        "lightbulbs": {
          ".read": "auth != null && auth.uid == $userId",
          ".write": "auth != null && auth.uid == $userId"
        },
        "reposts": {
          ".read": "auth != null && auth.uid == $userId",
          ".write": "auth != null && auth.uid == $userId"
        }
      }
    },
    "user_saved_posts": {
      "$userId": {
        ".read": "auth != null && auth.uid == $userId",
        ".write": "auth != null && auth.uid == $userId"
      }
    }
  }
}
```

**Deployment Command**:
```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only database
```

---

## 🟡 P1 - Missing Composite Indexes (Already in indexes.json)

### Good News: Indexes Already Defined!

The missing composite indexes are already in `firestore.indexes.json`:

**Lines 593-608**:
- `posts`: `authorId` + `lastEchoAt` + `__name__`
- `posts`: `authorId` + `lastCommentAt` + `__name__`

**Deployment Command**:
```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:indexes
```

**Alternative**: Click the URLs provided in error logs to create indexes via Firebase Console:
```
https://console.firebase.google.com/v1/r/project/amen-5e359/firestore/indexes?create_composite=...
```

---

## 🔧 Complete Deployment Workflow

### Step 1: Deploy All Firebase Changes

```bash
# Navigate to project root
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"

# Deploy Firestore rules (after fixing callerCanReadPost)
firebase deploy --only firestore:rules

# Deploy Firestore indexes
firebase deploy --only firestore:indexes

# Deploy Realtime Database rules
firebase deploy --only database

# Or deploy all at once
firebase deploy --only firestore,database
```

### Step 2: Verify Deployment

After deployment, check:

1. **Firestore Rules**: Go to Firebase Console → Firestore Database → Rules
2. **Indexes**: Go to Firebase Console → Firestore Database → Indexes
   - Wait for indexes to finish building (can take 5-30 minutes)
3. **Realtime Database Rules**: Go to Firebase Console → Realtime Database → Rules

### Step 3: Test in App

1. Build and run the app
2. Navigate to Profile → Saved Posts
3. Verify no permission errors in logs
4. Check that user interactions (amens, lightbulbs) work

---

## 📋 Deployment Checklist

- [ ] Update Firestore rules to allow reading saved posts
- [ ] Update Realtime Database rules for userInteractions
- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`
- [ ] Deploy Firestore indexes: `firebase deploy --only firestore:indexes`
- [ ] Deploy Realtime Database rules: `firebase deploy --only database`
- [ ] Wait for indexes to build (check Firebase Console)
- [ ] Test saved posts feature
- [ ] Test user interactions (amen, lightbulb, repost)
- [ ] Verify no permission errors in Xcode logs

---

## 🐛 Other Non-Critical Issues

### CoreHaptics Warnings (P2)
- **Status**: Fixed in code with error handling
- **Action**: Already completed, will be resolved in next build

### Apple Sign In Button Constraints (P2)
- **Status**: Fixed in code
- **Action**: Already completed, will be resolved in next build

### Empty dSYM Warning (P3)
- **Fix**: Xcode Build Settings → `DEBUG_INFORMATION_FORMAT` → Set to `DWARF with dSYM File` for Release
- **Impact**: Crash symbolication for production builds
- **Priority**: Low (only affects crash reporting)

---

## 🚨 Important Notes

1. **Backup First**: Firebase rules are backed up in `/AMENAPP/firestore-rules-backups/`
2. **Test in Emulator**: If you have Firebase Emulator Suite, test rules locally first
3. **Monitor Logs**: After deployment, monitor Xcode console for any remaining errors
4. **Index Build Time**: Composite indexes can take 5-30 minutes to build
5. **Rules Rollback**: If something breaks, you can rollback rules in Firebase Console → Rules History

---

## 📞 Support

If you encounter issues during deployment:
- Check Firebase Console → Usage tab for any quota issues
- Review Firebase Console → Logs for deployment errors
- Ensure you have Owner/Editor permissions in Firebase project

---

**Last Updated**: March 28, 2026
**Project**: AMEN App (amen-5e359)
**Firebase Project ID**: amen-5e359
