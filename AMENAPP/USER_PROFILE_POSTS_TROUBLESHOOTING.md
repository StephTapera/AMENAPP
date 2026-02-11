# User Profile Posts Troubleshooting Guide

## Issue: Posts from OpenTable, Testimonies, and Prayer not showing on UserProfileView

### ✅ What Was Fixed

1. **Enhanced Debugging in `fetchUserPosts`** (UserProfileView.swift)
   - Added detailed logging for post counts and categories
   - Shows warning when no posts are found with possible reasons
   - Logs category breakdown to verify all post types are fetched

2. **Enhanced Debugging in `fetchUserOriginalPosts`** (FirebasePostService.swift)
   - Added comprehensive error handling for Firestore index errors
   - Logs raw Firestore data for first 3 documents
   - Shows category breakdown of fetched posts
   - **AUTOMATIC FALLBACK**: If composite index is missing, automatically retries with a simpler query

3. **Fallback Query Option**
   - If the composite index is not created, the query will automatically fall back to a simpler version
   - The fallback filters `isRepost` in memory instead of at the database level

---

## 🔍 Diagnostic Steps

### Step 1: Run the App and Check Console Logs

When you open a user profile, look for these log messages:

```
📥 Fetching original posts for user: <userId>
📊 Firestore query returned X documents
```

**Expected Outputs:**

✅ **Success (Posts Found)**:
```
✅ Fetched 5 original posts for user
📊 Category breakdown:
   - openTable: 2
   - testimonies: 2
   - prayer: 1
```

⚠️ **No Posts Found**:
```
⚠️ No documents found. Possible reasons:
   1. User hasn't created any posts
   2. All posts by this user are reposts (isRepost=true)
   3. Posts exist but authorId doesn't match '<userId>'
   4. Firestore composite index not created (try useFallback=true)
```

❌ **Index Error**:
```
❌ Error fetching user posts: ...
⚠️ FIRESTORE INDEX REQUIRED!
   Create a composite index for:
   Collection: posts
   Fields: authorId (Ascending), isRepost (Ascending), createdAt (Descending)
   
🔄 Automatically retrying with fallback query...
```

---

### Step 2: Verify Firestore Data

1. Open **Firebase Console** → **Firestore Database**
2. Navigate to the **`posts`** collection
3. Check if posts exist for the user

**What to verify:**
- ✅ `authorId` matches the user's Firebase UID
- ✅ `category` is one of: `"openTable"`, `"testimonies"`, `"prayer"`, or `"general"`
- ✅ `isRepost` is `false` (or missing, which defaults to `false`)
- ✅ `createdAt` is a valid timestamp

**Example of a valid post document:**
```json
{
  "authorId": "abc123xyz",
  "authorName": "John Doe",
  "content": "This is my testimony...",
  "category": "testimonies",
  "isRepost": false,
  "createdAt": "2026-02-05T10:30:00Z",
  "amenCount": 5,
  "commentCount": 2
}
```

---

### Step 3: Create Firestore Composite Index (If Needed)

If you see the index error, you need to create a composite index.

#### Option A: Auto-Create via Console Link
1. When the error occurs, Firestore provides a link in the error message
2. Click the link to auto-create the index
3. Wait 2-5 minutes for the index to build

#### Option B: Manual Creation
1. Go to **Firebase Console** → **Firestore Database** → **Indexes**
2. Click **Create Index**
3. Configure:
   - **Collection**: `posts`
   - **Fields to index**:
     - `authorId` - **Ascending**
     - `isRepost` - **Ascending**
     - `createdAt` - **Descending**
4. Click **Create**
5. Wait for the index to build (shows "Building..." then "Enabled")

#### Option C: Use Fallback (No Index Required)
If you don't want to create the index, the code will automatically use a fallback query that:
- Fetches all posts by `authorId`
- Filters `isRepost` in memory
- Slightly less efficient but works without an index

---

### Step 4: Verify Post Creation

If posts still don't show, check how posts are being created in your app:

1. **Check Post Creation Code**
   - Ensure `isRepost` is explicitly set to `false` for original posts
   - Verify `authorId` is set to the current user's UID
   - Confirm `category` is one of the valid values

2. **Test Creating a New Post**
   - Create a test post in OpenTable, Testimonies, or Prayer
   - Check Firestore to see if it appears with correct fields
   - Refresh the user profile to see if it shows up

---

## 🐛 Common Issues and Solutions

### Issue 1: Posts exist but don't show on profile

**Possible Causes:**
- `authorId` doesn't match the user's Firebase UID
- `isRepost` is `true` (these are filtered out)
- Posts are missing the `category` field

**Solution:**
```swift
// Check the console logs - they will show the exact authorId being queried
📥 Fetching original posts for user: <userId>

// Then verify in Firestore that posts have this exact authorId
```

---

### Issue 2: Only some categories show up

**Possible Cause:**
- Category field has typos or incorrect capitalization

**Valid Categories:**
- `"openTable"` (camelCase)
- `"testimonies"` (lowercase)
- `"prayer"` (lowercase)
- `"general"` (lowercase)

**Solution:**
Check Firestore for typos like:
- ❌ `"OpenTable"` (wrong capitalization)
- ❌ `"testimony"` (singular, should be "testimonies")
- ❌ `"prayers"` (plural, should be "prayer")

---

### Issue 3: Firestore permission error

**Error Message:**
```
Permission denied. This might be a private account...
```

**Solution:**
Your Firestore rules already allow reading posts:
```rules
match /posts/{postId} {
  allow read: if isAuthenticated();
}
```

This should work. If not:
1. Verify the user is signed in
2. Check Firebase Console → Authentication to confirm user exists
3. Try signing out and back in

---

### Issue 4: Query timeout or slow performance

**Solution:**
1. Ensure the composite index is created (see Step 3)
2. Reduce the `limit` in the query if fetching too many posts
3. Consider pagination for users with many posts

---

## 📊 Debugging Checklist

Use this checklist to systematically debug the issue:

- [ ] **User is authenticated** - Firestore rules require authentication
- [ ] **Posts exist in Firestore** - Check Firebase Console
- [ ] **Posts have correct `authorId`** - Must match user's Firebase UID
- [ ] **Posts have `isRepost: false`** - Or field is missing (defaults to false)
- [ ] **Posts have valid `category`** - One of: openTable, testimonies, prayer, general
- [ ] **Composite index is created** - Or using fallback query
- [ ] **Console logs show posts being fetched** - Look for "✅ Fetched X posts"
- [ ] **No Firestore permission errors** - Check for "Permission denied" in console
- [ ] **App has internet connection** - Firestore requires network access

---

## 🚀 Quick Test

To quickly test if the fix works:

1. **Create a test post**:
   - Go to OpenTable tab
   - Create a new post: "Test post from OpenTable"
   
2. **View your profile**:
   - Navigate to your own profile
   - Check the "Posts" tab
   
3. **Check console logs**:
   - Look for: `✅ Fetched X original posts for user`
   - Verify: `- openTable: 1` appears in the category breakdown

If the test post appears, the fix is working! If not, review the diagnostic steps above.

---

## 📝 Summary of Changes

### Modified Files:

1. **`UserProfileView.swift`** - `fetchUserPosts()` function
   - Added detailed logging for debugging
   - Shows category breakdown and warnings

2. **`FirebasePostService.swift`** - `fetchUserOriginalPosts()` function
   - Enhanced error handling
   - Automatic fallback for missing index
   - Detailed Firestore document logging
   - Category breakdown analytics

### New Features:

- **Automatic Index Error Recovery**: Query automatically retries with fallback if index is missing
- **Comprehensive Logging**: Every step of the fetch process is logged for easy debugging
- **Category Analytics**: Shows breakdown of posts by category

---

## ✅ Expected Behavior After Fix

1. **All post types show on profile**: OpenTable, Testimonies, Prayer, and General posts all appear
2. **Real-time updates**: New posts appear immediately after creation
3. **Correct categorization**: Each post shows its category badge (icon + label)
4. **No permission errors**: Authenticated users can view any profile
5. **Graceful error handling**: Clear error messages if something goes wrong

---

## 🆘 Still Having Issues?

If posts still don't show after following this guide:

1. **Share console logs**: Copy the full console output when loading a profile
2. **Share a Firestore screenshot**: Show a sample post document from the Firebase Console
3. **Verify user ID**: Confirm the `userId` being queried matches the `authorId` in posts

The enhanced logging will help identify the exact issue!
