# Deploy Firestore Rules Fix - Saved Posts Permission Error

## Issue Fixed
The app was getting "Permission denied" errors when trying to fetch saved posts while offline. This happened because Firestore rules weren't explicitly allowing individual post document reads (using `get` operation).

## Changes Made
Updated `AMENAPP/firestore 18.rules` line 213-216:

**Before:**
```javascript
allow read: if isAuthenticated();
```

**After:**
```javascript
// Allow read for all authenticated users (for feeds, saved posts, etc.)
// This includes both get (single document) and list (queries)
allow get: if isAuthenticated();
allow list: if isAuthenticated();
```

## Why This Fixes The Error
- Firebase separates `read` into two operations: `get` (single document) and `list` (queries)
- When fetching saved posts, the app uses `get` to fetch individual post documents by ID
- The previous rule used generic `read` which works online but can fail offline
- Explicitly splitting into `get` and `list` ensures both operations work correctly offline

## Deploy to Firebase

### Option 1: Using Firebase Console (Easiest)
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Firestore Database** → **Rules**
4. Copy the contents of `AMENAPP/firestore 18.rules`
5. Paste into the console editor
6. Click **Publish**

### Option 2: Using Firebase CLI
If you have Firebase CLI installed:

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase deploy --only firestore:rules
```

If Firebase CLI is not installed:
```bash
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules
```

## Verification
After deploying, the error should disappear:
- ❌ **Before**: `⚠️ Failed to fetch saved post F3862F4F-7D4C-45C0-A616-216FDB9C216D: Permission denied`
- ✅ **After**: Saved posts load successfully, even when offline

## Additional Notes
- This fix maintains all existing security rules
- Only the posts collection read permissions were updated
- All other rules remain unchanged and secure
- The app can now properly cache and retrieve saved posts offline
