# Algolia Sync Setup Guide

## 🎯 What You Have Now

You now have a **complete Algolia search and sync system** for your AMEN app! Here's what's been created:

### Files Created/Updated:
1. ✅ `AlgoliaConfig.swift` - API key configuration
2. ✅ `AlgoliaSearchService.swift` - Search functionality (reads from Algolia)
3. ✅ `AlgoliaSyncService.swift` - Sync service (writes to Algolia)
4. ✅ `AlgoliaSyncDebugView.swift` - Admin UI for testing sync

---

## 🚀 Quick Setup (5 Steps)

### Step 1: Add Your Write API Key

Open `AlgoliaConfig.swift` and replace the placeholder:

```swift
enum AlgoliaConfig {
    static let applicationID = "182SCN7O9S"  // ✅ Already set
    static let searchAPIKey = "8727f5af5779e9795b12b565bba20dc3"  // ✅ Already set
    static let writeAPIKey = "YOUR_WRITE_API_KEY"  // ⚠️ REPLACE THIS
}
```

**Where to get your Write API Key:**
1. Go to [Algolia Dashboard](https://dashboard.algolia.com)
2. Click on **Settings** → **API Keys**
3. Look for **"Admin API Key"** or create a new **Write API Key**
4. Copy it and paste it in `AlgoliaConfig.swift`

**Security Note:** In production, the Write API Key should be server-side (Firebase Functions). For development/testing, it's okay to include it in the app temporarily.

---

### Step 2: Create Algolia Indexes

In your Algolia Dashboard:
1. Click **"Indices"** in the left sidebar
2. Click **"Create Index"**
3. Create two indexes:
   - `users`
   - `posts`

These index names must match what's in the code (`usersIndexName` and `postsIndexName`).

---

### Step 3: Add Debug View to Your App

Open your settings view or create a debug menu, and add:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            Form {
                // ... your existing settings ...
                
                // Add this section
                Section("Admin Tools") {
                    NavigationLink("Algolia Sync") {
                        AlgoliaSyncDebugView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

---

### Step 4: Run Initial Sync

1. Build and run your app
2. Navigate to Settings → Algolia Sync
3. Tap **"Sync All Data"**
4. Wait for the success message

This will copy all your existing Firestore users and posts to Algolia.

**What happens:**
- Fetches up to 1000 users from Firestore
- Fetches up to 1000 posts from Firestore
- Sends them to Algolia in batches
- Creates searchable records

---

### Step 5: Test Search

In the debug view, tap **"Test Search"** to verify everything works.

Or test in code:

```swift
Task {
    // Search users
    let users = try await AlgoliaSearchService.shared.searchUsers(query: "john")
    print("Found \(users.count) users")
    
    // Search posts
    let posts = try await AlgoliaSearchService.shared.searchPosts(query: "faith")
    print("Found \(posts.count) posts")
}
```

---

## 🔄 Ongoing Sync (Important!)

After the initial bulk sync, you need to sync individual records when they're created/updated.

### Sync When Creating a User

```swift
// In your user creation/registration code
func createUser(userId: String, displayName: String, username: String) async throws {
    // 1. Prepare user data
    let userData: [String: Any] = [
        "displayName": displayName,
        "username": username,
        "usernameLowercase": username.lowercased(),
        "bio": "",
        "followersCount": 0,
        "followingCount": 0,
        "profileImageURL": "",
        "isVerified": false,
        "createdAt": Date().timeIntervalSince1970
    ]
    
    // 2. Save to Firestore
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .setData(userData)
    
    // 3. Sync to Algolia (NEW!)
    try await AlgoliaSyncService.shared.syncUser(
        userId: userId,
        userData: userData
    )
    
    print("✅ User created and synced to Algolia")
}
```

### Sync When Updating a User

```swift
// In your profile update code
func updateProfile(userId: String, displayName: String, bio: String) async throws {
    let updates: [String: Any] = [
        "displayName": displayName,
        "bio": bio
    ]
    
    // 1. Update Firestore
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .updateData(updates)
    
    // 2. Get full user data for Algolia
    let userDoc = try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .getDocument()
    
    guard let userData = userDoc.data() else { return }
    
    // 3. Sync to Algolia
    try await AlgoliaSyncService.shared.syncUser(
        userId: userId,
        userData: userData
    )
    
    print("✅ Profile updated and synced")
}
```

### Sync When Creating a Post

```swift
// In your post creation code
func createPost(content: String, category: String, authorName: String) async throws {
    let postId = UUID().uuidString
    
    let postData: [String: Any] = [
        "content": content,
        "authorId": FirebaseManager.shared.currentUserId ?? "",
        "authorName": authorName,
        "category": category,
        "amenCount": 0,
        "commentCount": 0,
        "shareCount": 0,
        "createdAt": Date().timeIntervalSince1970,
        "isPublic": true
    ]
    
    // 1. Save to Firestore
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .setData(postData)
    
    // 2. Sync to Algolia (NEW!)
    try await AlgoliaSyncService.shared.syncPost(
        postId: postId,
        postData: postData
    )
    
    print("✅ Post created and synced")
}
```

### Sync When Deleting

```swift
// When deleting a user
func deleteUser(userId: String) async throws {
    // 1. Delete from Firestore
    try await Firestore.firestore()
        .collection("users")
        .document(userId)
        .delete()
    
    // 2. Delete from Algolia
    try await AlgoliaSyncService.shared.deleteUser(userId: userId)
}

// When deleting a post
func deletePost(postId: String) async throws {
    // 1. Delete from Firestore
    try await Firestore.firestore()
        .collection("posts")
        .document(postId)
        .delete()
    
    // 2. Delete from Algolia
    try await AlgoliaSyncService.shared.deletePost(postId: postId)
}
```

---

## 🔍 Using Search in Your UI

### Option 1: Replace Existing SearchService

If you already have a `SearchService`, update it to use Algolia:

```swift
// In SearchService.swift - Update searchPeople method
func searchPeople(query: String) async throws -> [AppSearchResult] {
    // NEW: Use Algolia instead of Firestore
    let users = try await AlgoliaSearchService.shared.searchUsers(query: query)
    
    return users.map { user in
        user.toSearchResult()  // Convenience method already provided
    }
}

// Update searchPosts method
func searchPosts(query: String) async throws -> [AppSearchResult] {
    let posts = try await AlgoliaSearchService.shared.searchPosts(query: query)
    
    return posts.map { post in
        post.toSearchResult()
    }
}
```

### Option 2: Direct Usage in Views

```swift
import SwiftUI

struct UserSearchView: View {
    @StateObject private var searchService = AlgoliaSearchService.shared
    @State private var searchText = ""
    @State private var results: [AlgoliaUser] = []
    
    var body: some View {
        List(results, id: \.objectID) { user in
            HStack {
                // Profile image
                AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                
                // User info
                VStack(alignment: .leading) {
                    Text(user.displayName)
                        .font(.headline)
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .searchable(text: $searchText)
        .onChange(of: searchText) { newValue in
            searchUsers(query: newValue)
        }
        .overlay {
            if searchService.isSearching {
                ProgressView()
            }
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        
        Task {
            do {
                results = try await searchService.searchUsers(query: query)
            } catch {
                print("Search error: \(error)")
            }
        }
    }
}
```

---

## 🎯 Where to Add Sync Calls

Search your codebase for these patterns and add sync calls:

### 1. User Registration/Creation
```swift
// Search for: "collection("users").document"
// Search for: "setData" or "addDocument"
// Add: AlgoliaSyncService.shared.syncUser()
```

### 2. Profile Updates
```swift
// Search for: "updateData"
// Search for: "collection("users")"
// Add: AlgoliaSyncService.shared.syncUser()
```

### 3. Post Creation
```swift
// Search for: "collection("posts").document"
// Search for: "setData"
// Add: AlgoliaSyncService.shared.syncPost()
```

### 4. Post Updates (if editable)
```swift
// Search for: "collection("posts")"
// Search for: "updateData"
// Add: AlgoliaSyncService.shared.syncPost()
```

### 5. Deletions
```swift
// Search for: ".delete()"
// Add: AlgoliaSyncService.shared.deleteUser() or deletePost()
```

---

## 🧪 Testing Checklist

After setup, verify these work:

- [ ] Initial bulk sync completes successfully
- [ ] Test user sync creates a searchable user
- [ ] Test post sync creates a searchable post
- [ ] Test search finds the test records
- [ ] Search with typos works (try "Jhon" to find "John")
- [ ] Create a real user → verify it appears in search
- [ ] Create a real post → verify it appears in search
- [ ] Update a user → verify changes appear in search
- [ ] Delete a user → verify it disappears from search

---

## 🚨 Common Issues

### Issue: "Algolia not configured" error
**Solution:** Make sure you've set `writeAPIKey` in `AlgoliaConfig.swift`

### Issue: "Index does not exist" error
**Solution:** Create the `users` and `posts` indexes in Algolia Dashboard

### Issue: Search returns no results
**Solution:** 
1. Make sure you ran "Sync All Data"
2. Wait 1-2 seconds after syncing (Algolia is eventually consistent)
3. Check Algolia Dashboard → Indices to see if data is there

### Issue: Sync fails with 403 error
**Solution:** Make sure you're using the Write API Key or Admin API Key, not the Search-Only key

### Issue: New users/posts don't appear in search
**Solution:** You forgot to add sync calls! Review the "Ongoing Sync" section above

---

## 🏭 Production Considerations

Before launching to production:

### 1. Move Write API Key to Server
The Write API Key should NOT be in your iOS app in production. Instead:

**Option A: Firebase Functions (Recommended)**
```javascript
// functions/index.js
const functions = require('firebase-functions');
const algoliasearch = require('algoliasearch');

const client = algoliasearch('YOUR_APP_ID', 'YOUR_ADMIN_KEY');
const usersIndex = client.initIndex('users');

exports.syncUserToAlgolia = functions.firestore
    .document('users/{userId}')
    .onWrite(async (change, context) => {
        const userId = context.params.userId;
        
        if (!change.after.exists) {
            await usersIndex.deleteObject(userId);
            return;
        }
        
        const userData = change.after.data();
        await usersIndex.saveObject({
            objectID: userId,
            ...userData
        });
    });
```

**Option B: Firebase Extension**
Install the official "Search with Algolia" extension from Firebase Console.

### 2. Remove Debug View
Remove or hide `AlgoliaSyncDebugView` from production builds:

```swift
#if DEBUG
NavigationLink("Algolia Sync") {
    AlgoliaSyncDebugView()
}
#endif
```

### 3. Add Error Handling
Make sync errors non-blocking:

```swift
// Don't throw, just log
do {
    try await AlgoliaSyncService.shared.syncUser(userId: userId, userData: userData)
} catch {
    print("⚠️ Algolia sync failed (non-critical): \(error)")
    // Continue execution - don't block user from using the app
}
```

### 4. Monitor Costs
Keep an eye on your Algolia usage:
- Free tier: 10,000 searches/month
- Growth: $1/month for 100K searches
- Set up alerts in Algolia Dashboard

---

## 📊 Checking Algolia Dashboard

After sync, check your Algolia Dashboard:

1. Go to [dashboard.algolia.com](https://dashboard.algolia.com)
2. Click **Indices**
3. Click on `users` or `posts`
4. You should see your records listed
5. Try searching in the dashboard's search box

---

## 🎉 You're Done!

Your app now has:
- ✅ Instant, typo-tolerant search
- ✅ Automatic syncing from Firestore → Algolia
- ✅ Debug tools for testing
- ✅ Production-ready architecture

Next steps:
1. Add your Write API Key
2. Create Algolia indexes
3. Run initial sync
4. Add sync calls to your user/post creation code
5. Test it!

Questions? Check the code comments in:
- `AlgoliaSyncService.swift` (usage examples at bottom)
- `AlgoliaSyncDebugView.swift` (testing instructions)
