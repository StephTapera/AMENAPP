# Algolia Implementation Checklist for Your App

## ✅ What Firebase Extension Does FOR YOU (Automatic)

When you install the Firebase Extension:
- ✅ Automatically syncs Firestore → Algolia
- ✅ Indexes all existing data
- ✅ Keeps data in sync when you create/update/delete
- ✅ Runs on Firebase servers (no code needed)
- ✅ Handles all the complex stuff

**You don't need to:**
- ❌ Write sync code
- ❌ Manually send data to Algolia
- ❌ Handle updates
- ❌ Worry about Cloud Functions

---

## 🔧 What YOU Need to Do in Your App

### Phase 1: Just Install the Extension (Recommended for Now)

**Current State:**
- Your search works with Firestore (basic but functional)
- Users can find people/posts

**After Extension Install:**
- Data automatically syncs to Algolia
- Your app still uses Firestore search
- **Nothing breaks!**

**Do this:**
1. ✅ Install Firebase Extension
2. ✅ Wait for data to sync
3. ✅ Test in Algolia Dashboard
4. ✅ Keep using your current search
5. ✅ Update to Algolia search later when ready

**Benefit:** Data is ready in Algolia whenever you want to upgrade!

---

### Phase 2: Add Algolia SDK to Your App (Later)

When you're ready for better search, you'll need to:

#### Step 1: Add Algolia SDK

**Using Swift Package Manager:**
1. Xcode → File → Add Package Dependencies
2. Enter: `https://github.com/algolia/algoliasearch-client-swift`
3. Click "Add Package"

**Or add to Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/algolia/algoliasearch-client-swift", from: "8.0.0")
]
```

#### Step 2: Create AlgoliaSearchService.swift

Create a new file: `AlgoliaSearchService.swift`

```swift
//
//  AlgoliaSearchService.swift
//  AMENAPP
//
//  Algolia search service for instant, typo-tolerant search
//

import Foundation
import AlgoliaSearchClient

@MainActor
class AlgoliaSearchService: ObservableObject {
    static let shared = AlgoliaSearchService()
    
    private let client: SearchClient
    private let usersIndex: Index
    private let postsIndex: Index
    
    @Published var isSearching = false
    @Published var error: String?
    
    private init() {
        // ⚠️ IMPORTANT: Use SEARCH-ONLY API Key here (not Admin Key!)
        client = SearchClient(
            appID: "YOUR_APPLICATION_ID",        // Get from Algolia Dashboard
            apiKey: "YOUR_SEARCH_ONLY_API_KEY"   // Get from Algolia Dashboard → API Keys
        )
        
        usersIndex = client.index(withName: "users")
        postsIndex = client.index(withName: "posts")
    }
    
    // MARK: - Search Users
    
    func searchUsers(query: String) async throws -> [AlgoliaUser] {
        guard !query.isEmpty else { return [] }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            let response = try await usersIndex.search(
                query: Query(query: query)
                    .set(\.hitsPerPage, to: 20)
                    .set(\.attributesToRetrieve, to: ["objectID", "displayName", "username", "bio", "followersCount"])
            )
            
            let users: [AlgoliaUser] = try response.hits.map { hit in
                try hit.object()
            }
            
            print("✅ Algolia found \(users.count) users for query: '\(query)'")
            return users
            
        } catch {
            print("❌ Algolia search error: \(error)")
            self.error = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Search Posts
    
    func searchPosts(query: String, category: String? = nil) async throws -> [AlgoliaPost] {
        guard !query.isEmpty else { return [] }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            var queryBuilder = Query(query: query)
                .set(\.hitsPerPage, to: 20)
                .set(\.attributesToRetrieve, to: ["objectID", "content", "authorName", "category", "amenCount", "commentCount", "createdAt"])
            
            // Optional category filter
            if let category = category {
                queryBuilder = queryBuilder.set(\.filters, to: "category:\(category)")
            }
            
            let response = try await postsIndex.search(query: queryBuilder)
            
            let posts: [AlgoliaPost] = try response.hits.map { hit in
                try hit.object()
            }
            
            print("✅ Algolia found \(posts.count) posts for query: '\(query)'")
            return posts
            
        } catch {
            print("❌ Algolia search error: \(error)")
            self.error = error.localizedDescription
            throw error
        }
    }
}

// MARK: - Algolia Models

struct AlgoliaUser: Codable {
    let objectID: String
    let displayName: String
    let username: String
    let bio: String?
    let followersCount: Int?
    
    // Convert to your existing AppSearchResult
    func toSearchResult() -> AppSearchResult {
        AppSearchResult(
            firestoreId: objectID,
            title: displayName,
            subtitle: "@\(username)",
            metadata: "\(followersCount ?? 0) followers" + (bio != nil ? " • \(bio!.prefix(50))" : ""),
            type: .person,
            isVerified: false
        )
    }
}

struct AlgoliaPost: Codable {
    let objectID: String
    let content: String
    let authorName: String
    let category: String
    let amenCount: Int?
    let commentCount: Int?
    let createdAt: TimeInterval?
    
    // Convert to your existing AppSearchResult
    func toSearchResult() -> AppSearchResult {
        let timeAgo = createdAt.map { Date(timeIntervalSince1970: $0) }
            .map { formatTimeAgo(from: $0) } ?? "Recent"
        
        AppSearchResult(
            firestoreId: objectID,
            title: String(content.prefix(80)) + (content.count > 80 ? "..." : ""),
            subtitle: "by \(authorName)",
            metadata: "\(timeAgo) • \(amenCount ?? 0) Amens • \(commentCount ?? 0) comments",
            type: .post,
            isVerified: false
        )
    }
    
    private func formatTimeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds/60))m" }
        if seconds < 86400 { return "\(Int(seconds/3600))h" }
        return "\(Int(seconds/86400))d"
    }
}
```

#### Step 3: Update Your SearchService.swift

Replace the Firestore search with Algolia:

```swift
// In SearchService.swift

func searchPeople(query: String) async throws -> [AppSearchResult] {
    print("🔍 Searching people with Algolia: '\(query)'")
    
    // Use Algolia instead of Firestore
    let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(query: query)
    
    return algoliaUsers.map { $0.toSearchResult() }
}

func searchPosts(query: String) async throws -> [AppSearchResult] {
    print("🔍 Searching posts with Algolia: '\(query)'")
    
    // Use Algolia instead of Firestore
    let algoliaPosts = try await AlgoliaSearchService.shared.searchPosts(query: query)
    
    return algoliaPosts.map { $0.toSearchResult() }
}
```

#### Step 4: Add Your Algolia API Keys

**Get your keys from Algolia Dashboard:**
1. Go to Algolia Dashboard → Settings → API Keys
2. Copy **Application ID**
3. Copy **Search-Only API Key** (NOT Admin Key!)

**Store them securely:**

Create a `Config.swift` file:
```swift
//
//  Config.swift
//  AMENAPP
//

import Foundation

enum AlgoliaConfig {
    // ⚠️ TODO: Replace with your actual keys from Algolia Dashboard
    static let applicationID = "YOUR_APP_ID"
    static let searchAPIKey = "YOUR_SEARCH_ONLY_API_KEY"
}
```

Then update `AlgoliaSearchService.swift`:
```swift
private init() {
    client = SearchClient(
        appID: AlgoliaConfig.applicationID,
        apiKey: AlgoliaConfig.searchAPIKey
    )
    // ...
}
```

---

## 📊 Summary: Do You Need to Do Anything?

### Right Now (Recommended): NO ✅

**Just:**
1. Install Firebase Extension
2. Let it sync your data
3. Keep using your current search
4. Done!

**Why?**
- Your search works fine for launching
- Extension keeps data synced in background
- You can upgrade to Algolia search anytime

---

### Later (When Ready): YES 🔧

**When to upgrade:**
- Users complain search doesn't work
- You have >500 users
- You want professional search quality

**What to do:**
1. Add Algolia SDK (5 minutes)
2. Create AlgoliaSearchService (copy code above)
3. Update SearchService to use Algolia (2 lines)
4. Add API keys (1 minute)
5. Test!

**Total time:** ~15 minutes

---

## 🎯 Recommended Approach

### Phase 1 (Now): Install Extension Only
```
1. Install Firebase Extension ✅
2. Configure with Algolia credentials ✅
3. Let data sync ✅
4. Keep using current search ✅
```
**Benefit:** Data is ready when you need it!

### Phase 2 (After Launch): Add SDK
```
1. Add Algolia SDK
2. Create AlgoliaSearchService
3. Update SearchService
4. Test
5. Ship update
```
**Benefit:** Better search when you're ready!

---

## 🚫 What You DON'T Need

- ❌ Cloud Functions (Extension handles it)
- ❌ Backend code (Extension does sync)
- ❌ Complex setup (just SDK + API keys)
- ❌ Data migration (happens automatically)
- ❌ Duplicate data storage (minimal extra storage)

---

## 📱 Code Changes Summary

### Minimal Changes (Just SDK):
```
Files to create: 1 (AlgoliaSearchService.swift)
Files to modify: 1 (SearchService.swift)
Lines of code: ~150
Time required: 15 minutes
```

### What stays the same:
- ✅ Your UI (SearchView, etc.)
- ✅ Your data models (AppSearchResult)
- ✅ Your Firestore data
- ✅ Everything else in your app

---

## 🧪 Testing Your Implementation

### Test 1: Typo Tolerance
```
Search: "jhon smith"
Expected: Finds "John Smith" ✅
```

### Test 2: Substring Search
```
Search: "smith"
Expected: Finds "John Smith" ✅
```

### Test 3: Multi-word Search
```
Search: "ios developer"
Expected: Finds users with "iOS Developer" in bio ✅
```

### Test 4: Speed
```
Search: Any query
Expected: Results in <100ms ✅
```

---

## 💡 Pro Tip

**Don't update your app code yet!**

1. ✅ Install Extension first
2. ✅ Wait for data to sync
3. ✅ Test in Algolia Dashboard
4. ✅ Verify search works there
5. Then update app code

**Why?** This way you know Algolia is working before changing your app!

---

## 🆘 Need Help?

**After Extension Install:**
- Check Firebase Console → Extensions → Logs
- Look for "Successfully indexed X documents"
- Verify in Algolia Dashboard

**After SDK Install:**
- Check Xcode console for Algolia logs
- Test with simple queries first
- Verify API keys are correct

---

## ✅ Final Answer

**Do you need to do anything NOW?** 

**No!** Just install the extension and you're done. Your current search keeps working.

**Will you need to do something LATER?**

**Yes!** When you want better search, add the SDK (~15 minutes of work).

---

**Bottom line:** Extension = automatic sync. SDK = better search in your app. You can do them at different times! 🚀
