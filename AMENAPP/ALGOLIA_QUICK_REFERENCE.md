# Algolia Integration Quick Reference

## ⚡️ Copy-Paste Code Snippets

### 1. Add to User Creation Code

```swift
// After saving to Firestore, add this:
try await AlgoliaSyncService.shared.syncUser(
    userId: userId,
    userData: userData
)
```

### 2. Add to User Update Code

```swift
// After updating Firestore, add this:
let userDoc = try await Firestore.firestore()
    .collection("users")
    .document(userId)
    .getDocument()

if let userData = userDoc.data() {
    try await AlgoliaSyncService.shared.syncUser(
        userId: userId,
        userData: userData
    )
}
```

### 3. Add to Post Creation Code

```swift
// After saving to Firestore, add this:
try await AlgoliaSyncService.shared.syncPost(
    postId: postId,
    postData: postData
)
```

### 4. Add to Delete User Code

```swift
// After deleting from Firestore, add this:
try await AlgoliaSyncService.shared.deleteUser(userId: userId)
```

### 5. Add to Delete Post Code

```swift
// After deleting from Firestore, add this:
try await AlgoliaSyncService.shared.deletePost(postId: postId)
```

### 6. Use Search in Views

```swift
// Replace Firestore search with Algolia:
let users = try await AlgoliaSearchService.shared.searchUsers(query: searchText)
let posts = try await AlgoliaSearchService.shared.searchPosts(query: searchText)

// Or with category filter:
let posts = try await AlgoliaSearchService.shared.searchPosts(
    query: searchText,
    category: "testimonies"
)
```

---

## 🎯 Files to Search and Update

| File Pattern | What to Search For | What to Add |
|--------------|-------------------|-------------|
| User registration/signup | `collection("users").document().setData()` | `AlgoliaSyncService.shared.syncUser()` |
| Profile editing | `collection("users").document().updateData()` | `AlgoliaSyncService.shared.syncUser()` |
| Post creation | `collection("posts").document().setData()` | `AlgoliaSyncService.shared.syncPost()` |
| User deletion | `collection("users").document().delete()` | `AlgoliaSyncService.shared.deleteUser()` |
| Post deletion | `collection("posts").document().delete()` | `AlgoliaSyncService.shared.deletePost()` |
| Search users | Firestore queries with `whereField` | `AlgoliaSearchService.shared.searchUsers()` |
| Search posts | Firestore queries for posts | `AlgoliaSearchService.shared.searchPosts()` |

---

## 🚀 Setup Steps (Checklist)

### Setup (One-Time)
- [ ] Add Write API Key to `AlgoliaConfig.swift`
- [ ] Create `users` index in Algolia Dashboard
- [ ] Create `posts` index in Algolia Dashboard
- [ ] Add `AlgoliaSyncDebugView` to your settings
- [ ] Run app and tap "Sync All Data" in debug view
- [ ] Verify data appears in Algolia Dashboard

### Integration (Add to Code)
- [ ] Find all user creation code → add sync
- [ ] Find all user update code → add sync
- [ ] Find all post creation code → add sync
- [ ] Find all post update code → add sync
- [ ] Find all deletion code → add sync
- [ ] Replace Firestore search with Algolia search

### Testing
- [ ] Create new user → verify in search
- [ ] Update user profile → verify changes
- [ ] Create new post → verify in search
- [ ] Delete user → verify disappears
- [ ] Test typo tolerance ("Jhon" finds "John")
- [ ] Test instant search (results appear as you type)

---

## 🔧 Common Code Locations

### User Creation (Likely Files)
- `AuthenticationManager.swift`
- `SignUpView.swift`
- `RegistrationService.swift`
- `UserManager.swift`
- `OnboardingView.swift`

### Profile Updates (Likely Files)
- `ProfileView.swift`
- `EditProfileView.swift`
- `SettingsView.swift`
- `UserProfileManager.swift`

### Post Creation (Likely Files)
- `CreatePostView.swift`
- `PostService.swift`
- `FeedViewModel.swift`
- `NewPostView.swift`

### Search (Likely Files)
- `SearchView.swift`
- `SearchService.swift`
- `ExploreView.swift`
- `DiscoverView.swift`

---

## 💡 Example: Complete User Creation Flow

```swift
// Before (just Firestore)
func createUser(userId: String, name: String, username: String) async throws {
    let userData: [String: Any] = [
        "displayName": name,
        "username": username,
        "usernameLowercase": username.lowercased(),
        "createdAt": Date().timeIntervalSince1970
    ]
    
    try await db.collection("users")
        .document(userId)
        .setData(userData)
}

// After (Firestore + Algolia)
func createUser(userId: String, name: String, username: String) async throws {
    let userData: [String: Any] = [
        "displayName": name,
        "username": username,
        "usernameLowercase": username.lowercased(),
        "createdAt": Date().timeIntervalSince1970
    ]
    
    // 1. Save to Firestore (primary database)
    try await db.collection("users")
        .document(userId)
        .setData(userData)
    
    // 2. Sync to Algolia (search index) - ONLY THIS LINE ADDED!
    try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
}
```

---

## 🎯 Error Handling Pattern

### Non-Critical Sync (Recommended)
Don't let Algolia sync errors break your app:

```swift
// Save to Firestore (critical - must succeed)
try await db.collection("users").document(userId).setData(userData)

// Sync to Algolia (non-critical - log if fails)
do {
    try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
} catch {
    print("⚠️ Algolia sync failed (non-critical): \(error)")
    // Don't throw - continue execution
}
```

### Critical Sync (Alternative)
If search is mission-critical, let errors propagate:

```swift
// Both must succeed
try await db.collection("users").document(userId).setData(userData)
try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
// If either fails, the error is thrown
```

---

## 🔍 Search Examples

### Basic Search
```swift
let users = try await AlgoliaSearchService.shared.searchUsers(query: "john")
```

### Search with Typos
```swift
// All these will find "John Smith":
let r1 = try await AlgoliaSearchService.shared.searchUsers(query: "john")  // exact
let r2 = try await AlgoliaSearchService.shared.searchUsers(query: "jhon")  // typo
let r3 = try await AlgoliaSearchService.shared.searchUsers(query: "jon")   // typo
let r4 = try await AlgoliaSearchService.shared.searchUsers(query: "smith") // lastname
```

### Search Posts by Category
```swift
let faithPosts = try await AlgoliaSearchService.shared.searchPosts(
    query: "prayer",
    category: "prayer"
)

let allPosts = try await AlgoliaSearchService.shared.searchPosts(
    query: "prayer"
    // no category = search all categories
)
```

### Convert to Existing Models
```swift
// Algolia users → App search results
let users = try await AlgoliaSearchService.shared.searchUsers(query: "john")
let searchResults = users.map { $0.toSearchResult() }

// Algolia users → Firebase user models
let firebaseUsers = users.map { $0.toFirebaseSearchUser() }
```

---

## 📱 Add Debug View to Settings

```swift
// In your SettingsView.swift or similar
Section("Developer Tools") {
    #if DEBUG
    NavigationLink {
        AlgoliaSyncDebugView()
    } label: {
        Label("Algolia Sync", systemImage: "cloud.fill")
    }
    #endif
}
```

---

## ⏱️ Time Estimates

| Task | Time |
|------|------|
| Add Write API Key | 2 min |
| Create indexes in Algolia | 2 min |
| Add debug view to settings | 3 min |
| Run initial sync | 1 min |
| Find and update 1 create/update call | 2 min |
| Find and update all calls | 20-30 min |
| Replace search implementation | 10 min |
| Test everything | 10 min |
| **Total** | **~1 hour** |

---

## 🎉 Benefits After Integration

| Before (Firestore) | After (Algolia) |
|-------------------|-----------------|
| Search only by prefix | ✅ Search anywhere in text |
| No typo tolerance | ✅ Typo-tolerant search |
| Case-sensitive | ✅ Case-insensitive |
| Single field only | ✅ Multi-field search |
| Manual relevance | ✅ Smart ranking |
| Slow on large datasets | ✅ Always instant |
| "john" finds "john..." | ✅ "jhon" finds "John Smith" |

---

## 🔗 Important Links

- [Algolia Dashboard](https://dashboard.algolia.com)
- [Setup Guide](./ALGOLIA_SYNC_SETUP_GUIDE.md) (detailed documentation)
- [AlgoliaConfig.swift](./AlgoliaConfig.swift) (add Write API Key here)
- [AlgoliaSyncService.swift](./AlgoliaSyncService.swift) (sync service implementation)
- [AlgoliaSearchService.swift](./AlgoliaSearchService.swift) (search service)

---

## 🆘 Need Help?

Check these in order:
1. Read `ALGOLIA_SYNC_SETUP_GUIDE.md` for detailed instructions
2. Check console logs (look for ✅, ❌, ⚠️ emoji)
3. Verify API keys in `AlgoliaConfig.swift`
4. Check Algolia Dashboard → Indices → See if data is there
5. Use `AlgoliaSyncDebugView` to test sync
6. Check Algolia status page (status.algolia.com)

---

**Remember:** Sync is important but not critical. If Algolia is down, your app should still work. Treat sync as a "nice to have" enhancement, not a requirement for core functionality.
