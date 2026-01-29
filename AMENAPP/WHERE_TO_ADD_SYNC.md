# Where to Add Algolia Sync - Specific Code Locations

This file shows **exactly** where to add Algolia sync calls in your existing code.

---

## 🎯 FirebaseManager.swift - User Creation

### Location: Line ~137 (in `signUp` method)

**Find this code:**
```swift
do {
    try await firestore.collection(CollectionPath.users)
        .document(user.uid)
        .setData(userData)
    
    print("✅ FirebaseManager: User profile created successfully!")
    print("🎉 Complete user setup finished for: \(displayName)")
    
} catch {
    print("❌ FirebaseManager: Failed to create user profile: \(error)")
    // Delete the auth user if profile creation fails
    try? await user.delete()
    throw error
}
```

**Change to:**
```swift
do {
    try await firestore.collection(CollectionPath.users)
        .document(user.uid)
        .setData(userData)
    
    print("✅ FirebaseManager: User profile created successfully!")
    
    // ⭐️ NEW: Sync to Algolia for instant search
    do {
        try await AlgoliaSyncService.shared.syncUser(userId: user.uid, userData: userData)
        print("✅ FirebaseManager: User synced to Algolia")
    } catch {
        print("⚠️ FirebaseManager: Algolia sync failed (non-critical): \(error)")
        // Don't throw - user creation succeeded, search sync is optional
    }
    
    print("🎉 Complete user setup finished for: \(displayName)")
    
} catch {
    print("❌ FirebaseManager: Failed to create user profile: \(error)")
    // Delete the auth user if profile creation fails
    try? await user.delete()
    throw error
}
```

---

## 🔍 Where to Find Other Locations

### Search for User Update Code

**Pattern to search:** `collection("users").document`

Files likely to contain user updates:
- `FirebaseManager.swift`
- Any file with "Profile" in the name
- Any file with "Settings" in the name
- Any file with "Edit" in the name

**Example pattern:**
```swift
// Find code like this:
try await firestore.collection("users")
    .document(userId)
    .updateData(updates)

// Add after it:
// Sync to Algolia
let doc = try await firestore.collection("users").document(userId).getDocument()
if let userData = doc.data() {
    try? await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
}
```

### Search for Post Creation Code

**Pattern to search:** `collection("posts").document`

Files likely to contain post creation:
- Any file with "Post" in the name
- Any file with "Create" in the name
- Any file with "Feed" in the name
- `FirebaseManager.swift`

**Example pattern:**
```swift
// Find code like this:
let postRef = firestore.collection("posts").document(postId)
try await postRef.setData(postData)

// Add after it:
try? await AlgoliaSyncService.shared.syncPost(postId: postId, postData: postData)
```

### Search for Deletion Code

**Pattern to search:** `.delete()`

**Example pattern:**
```swift
// Find code like this:
try await firestore.collection("users").document(userId).delete()

// Add after it:
try? await AlgoliaSyncService.shared.deleteUser(userId: userId)

// Or for posts:
try await firestore.collection("posts").document(postId).delete()
try? await AlgoliaSyncService.shared.deletePost(postId: postId)
```

---

## 📝 Step-by-Step Integration Guide

### Step 1: Update User Creation (FirebaseManager.swift)

1. Open `FirebaseManager.swift`
2. Find the `signUp` method (around line 78)
3. Find where `setData(userData)` is called (around line 137)
4. Add the Algolia sync code shown above

**Result:** New users will automatically be searchable!

---

### Step 2: Find Profile Update Code

Run these searches in Xcode:

**Search 1:** `func updateProfile`
- Look for methods that update user profiles
- Add Algolia sync after the Firestore update

**Search 2:** `updateData`
- Filter results to user-related files
- Look for code that updates user documents
- Add Algolia sync

**Example locations:**
- `ProfileView.swift` / `EditProfileView.swift`
- `SettingsView.swift` / `ProfileSettingsView.swift`
- Any ViewModel with "Profile" in the name

**Code to add:**
```swift
// After any code that updates user data:
do {
    let userDoc = try await FirebaseManager.shared.firestore
        .collection("users")
        .document(userId)
        .getDocument()
    
    if let userData = userDoc.data() {
        try await AlgoliaSyncService.shared.syncUser(
            userId: userId,
            userData: userData
        )
    }
} catch {
    print("⚠️ Algolia sync failed: \(error)")
}
```

---

### Step 3: Find Post Creation Code

Run these searches in Xcode:

**Search 1:** `func createPost`
**Search 2:** `func submitPost`
**Search 3:** `collection("posts")`

**Example locations:**
- `CreatePostView.swift` / `NewPostView.swift`
- `PostViewModel.swift` / `FeedViewModel.swift`
- Any service with "Post" in the name

**Code to add:**
```swift
// After saving post to Firestore:
do {
    try await AlgoliaSyncService.shared.syncPost(
        postId: postId,
        postData: postData
    )
} catch {
    print("⚠️ Post sync to Algolia failed: \(error)")
}
```

---

### Step 4: Find Deletion Code

Run these searches in Xcode:

**Search 1:** `func deleteUser`
**Search 2:** `func deletePost`
**Search 3:** `.delete()`

**Code to add:**
```swift
// After deleting user from Firestore:
try? await AlgoliaSyncService.shared.deleteUser(userId: userId)

// After deleting post from Firestore:
try? await AlgoliaSyncService.shared.deletePost(postId: postId)
```

---

### Step 5: Update Search Code

Find your existing search implementation:

**Search 1:** `SearchService.swift`
**Search 2:** `func search`
**Search 3:** `.whereField`

**Replace this:**
```swift
// Old Firestore search
let snapshot = try await db.collection("users")
    .whereField("usernameLowercase", isGreaterThanOrEqualTo: query)
    .whereField("usernameLowercase", isLessThan: query + "\u{f8ff}")
    .getDocuments()
```

**With this:**
```swift
// New Algolia search
let users = try await AlgoliaSearchService.shared.searchUsers(query: query)
return users.map { $0.toSearchResult() }
```

---

## 🧪 Testing Each Integration

After adding sync to each location, test it:

### Test User Creation
1. Create a new user account
2. Check console logs for: `✅ FirebaseManager: User synced to Algolia`
3. Open `AlgoliaSyncDebugView`
4. Tap "Test Search"
5. Verify the new user appears

### Test Profile Updates
1. Update a user's profile (name, bio, etc.)
2. Check console logs for sync confirmation
3. Search for the user
4. Verify changes appear in search results

### Test Post Creation
1. Create a new post
2. Check console logs for sync confirmation
3. Search for content from the post
4. Verify it appears in search results

### Test Deletions
1. Delete a user or post
2. Check console logs
3. Search for deleted item
4. Verify it no longer appears

---

## 📋 Integration Checklist

Track your progress:

### Core Integration
- [ ] Added sync to `FirebaseManager.swift` → `signUp` method
- [ ] Tested: New users appear in search

### Profile Updates (Find and update each)
- [ ] Profile edit view
- [ ] Settings view
- [ ] Display name update
- [ ] Bio update
- [ ] Username update (if allowed)
- [ ] Tested: Updates appear in search

### Post Management (Find and update each)
- [ ] Create post
- [ ] Edit post (if supported)
- [ ] Delete post
- [ ] Tested: Posts appear/disappear from search

### User Management (Find and update each)
- [ ] Delete user/account
- [ ] Deactivate account
- [ ] Tested: Deleted users disappear from search

### Search Replacement
- [ ] Replaced user search with Algolia
- [ ] Replaced post search with Algolia
- [ ] Tested: Search with typos works
- [ ] Tested: Instant search works

---

## 🎯 Priority Order

Do these in order for fastest results:

### Priority 1: Get Search Working (15 minutes)
1. ✅ Add Write API Key to `AlgoliaConfig.swift`
2. ✅ Add debug view to settings
3. ✅ Run "Sync All Data"
4. ✅ Replace search implementation
5. ✅ Test search

**Result:** Search now works with existing data!

### Priority 2: Future Data (30 minutes)
6. Add sync to user creation (FirebaseManager.swift)
7. Add sync to post creation (wherever that is)
8. Test by creating new user/post

**Result:** New data automatically searchable!

### Priority 3: Updates & Deletes (30 minutes)
9. Find and update profile edit code
10. Find and update deletion code
11. Test updates and deletes

**Result:** Full sync implementation complete!

---

## 🔍 How to Search Your Codebase

### In Xcode:
1. Press `Cmd + Shift + F` (Find in Project)
2. Enter search term
3. Look through results
4. Add sync code where appropriate

### Key Search Terms:
- `collection("users")`
- `collection("posts")`
- `.setData(`
- `.updateData(`
- `.delete()`
- `func createPost`
- `func createUser`
- `func updateProfile`
- `func deleteUser`
- `func deletePost`

### Files to Check:
- `FirebaseManager.swift` ⭐️ (Start here!)
- Anything with "Create" in the name
- Anything with "Edit" in the name
- Anything with "Profile" in the name
- Anything with "Post" in the name
- Anything with "Delete" in the name
- Anything with "Search" in the name

---

## 💡 Pro Tips

### 1. Make Sync Non-Blocking
Always use try/catch for Algolia sync so it doesn't break your app:

```swift
// Good ✅
try await firestore.collection("users").document(userId).setData(userData)
try? await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)

// Bad ❌ (if Algolia fails, the whole operation fails)
try await firestore.collection("users").document(userId).setData(userData)
try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
```

### 2. Log Everything
Add print statements so you can debug:

```swift
do {
    try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
    print("✅ User \(userId) synced to Algolia")
} catch {
    print("⚠️ Algolia sync failed for user \(userId): \(error)")
}
```

### 3. Test Incrementally
Don't add sync everywhere at once. Add it one place at a time and test:
1. Add to user creation → test
2. Add to post creation → test
3. Add to updates → test
4. Add to deletes → test

### 4. Use the Debug View
The `AlgoliaSyncDebugView` is your friend for testing!

---

## 🆘 Troubleshooting

### "I can't find where posts are created"
Search for:
- `"posts"`
- `addDocument`
- `setData`
- Files with "Post" or "Create" in the name

### "I added sync but it's not working"
Check:
1. Is the Write API Key set in `AlgoliaConfig.swift`?
2. Do the Algolia indexes exist? (Check dashboard)
3. Are there any console errors?
4. Did you run the initial "Sync All Data"?
5. Wait 1-2 seconds (Algolia is eventually consistent)

### "Search returns old data"
Algolia caches can take 1-2 seconds to update. Also check:
1. Did the sync actually run? (Check console logs)
2. Did it error? (Check for ❌ in logs)
3. Check Algolia Dashboard → Indices → See if data is current

---

## ✅ You're Done When...

You can:
- [x] Create a new user → immediately search and find them
- [x] Update a profile → changes appear in search
- [x] Create a post → immediately search and find it
- [x] Delete a user/post → it disappears from search
- [x] Search with typos → still find results
- [x] Search is instant (< 100ms)

---

## 📚 Reference

- Main Guide: `ALGOLIA_SYNC_SETUP_GUIDE.md`
- Quick Reference: `ALGOLIA_QUICK_REFERENCE.md`
- Code: `AlgoliaSyncService.swift`
- Testing: `AlgoliaSyncDebugView.swift`
- Config: `AlgoliaConfig.swift`
