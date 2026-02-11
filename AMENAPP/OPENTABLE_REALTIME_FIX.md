# OpenTable Real-Time Updates Fix

## Issues Found

1. ✅ **Metadata Error** - Fixed (changed `if let` to direct access)
2. ⚠️ **Posts not updating in real-time** - Need to verify listener is active
3. ⚠️ **Saved posts permission error** - Offline cache issue
4. ⚠️ **Font descriptor warning** - SwiftUI warning (harmless but annoying)

## Fixes Applied

### 1. Fixed Metadata Error ✅

**Before:**
```swift
if let metadata = snapshot.metadata { // ❌ Error: metadata is not Optional
    // ...
}
```

**After:**
```swift
let metadata = snapshot.metadata // ✅ Correct
if metadata.isFromCache {
    // ...
}
```

### 2. Ensure Real-Time Listener is Active

Your `FirebasePostService` has a `startListening()` method, but you need to make sure it's being called. Add this to your OpenTable view:

```swift
struct OpenTableView: View {
    @StateObject private var postService = FirebasePostService.shared
    
    var body: some View {
        // Your view code
    }
    .onAppear {
        // ✅ Start listening when view appears
        postService.startListening(category: .openTable)
    }
    .onDisappear {
        // ✅ Stop listening when view disappears (optional - saves resources)
        postService.stopListening()
    }
}
```

### 3. Alternative: Use `.task` for Better Lifecycle Management

```swift
struct OpenTableView: View {
    @StateObject private var postService = FirebasePostService.shared
    
    var body: some View {
        // Your view code
    }
    .task {
        // ✅ Automatically starts when view appears and cancels when it disappears
        postService.startListening(category: .openTable)
    }
}
```

### 4. Check if Listener is Already Active

Modify `startListening()` to prevent duplicate listeners:

```swift
// Add to FirebasePostService class
private var isListenerActive = false

func startListening(category: Post.PostCategory? = nil) {
    // Prevent duplicate listeners
    guard !isListenerActive else {
        print("⚠️ Listener already active, skipping...")
        return
    }
    
    print("🔊 Starting real-time listener for posts...")
    isListenerActive = true
    
    // ... rest of your existing code ...
}

func stopListening() {
    print("🔇 Stopping all listeners...")
    listeners.forEach { $0.remove() }
    listeners.removeAll()
    isListenerActive = false // ✅ Reset flag
}
```

### 5. Fix Saved Posts Offline Issue

The error shows Firestore can't access offline cache for saved posts. Update your Firestore settings:

**In your AppDelegate or App initialization:**

```swift
import FirebaseFirestore

// Enable offline persistence
let settings = Firestore.firestore().settings
settings.isPersistenceEnabled = true
settings.cacheSizeBytes = FirestoreCacheSizeUnlimited // or specific size
Firestore.firestore().settings = settings
```

**OR** modify the saved posts query to handle offline gracefully:

```swift
func fetchUserSavedPosts(userId: String) async throws -> [Post] {
    print("📥 Fetching saved posts for user: \(userId)")
    
    do {
        // First, get all saved post IDs
        let savedQuery = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .order(by: "savedAt", descending: true)
            .limit(to: 50)
        
        // ✅ Try server first, fallback to cache
        var savedSnapshot: QuerySnapshot
        do {
            savedSnapshot = try await savedQuery.getDocuments(source: .server)
            print("🌐 Saved posts loaded from server")
        } catch {
            print("⚠️ Server unavailable, trying cache...")
            savedSnapshot = try await savedQuery.getDocuments(source: .cache)
            print("📦 Saved posts loaded from cache")
        }
        
        let savedPostIds = savedSnapshot.documents.compactMap { doc -> String? in
            doc.data()["postId"] as? String
        }
        
        guard !savedPostIds.isEmpty else {
            print("✅ No saved posts found")
            return []
        }
        
        // Fetch the actual posts with offline support
        var allSavedPosts: [Post] = []
        
        for batch in savedPostIds.chunked(into: 10) {
            let postsQuery = db.collection(FirebaseManager.CollectionPath.posts)
                .whereField(FieldPath.documentID(), in: batch)
            
            // ✅ Try server first, fallback to cache
            var postsSnapshot: QuerySnapshot
            do {
                postsSnapshot = try await postsQuery.getDocuments(source: .server)
            } catch {
                print("⚠️ Fetching from cache for batch...")
                postsSnapshot = try await postsQuery.getDocuments(source: .cache)
            }
            
            let batchPosts = try postsSnapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
            allSavedPosts.append(contentsOf: batchPosts.map { $0.toPost() })
        }
        
        print("✅ Fetched \(allSavedPosts.count) saved posts for user")
        return allSavedPosts
        
    } catch {
        print("❌ Error fetching saved posts: \(error)")
        throw error
    }
}
```

### 6. Fix Font Descriptor Warning (Optional)

This warning is harmless but annoying. It's caused by trying to apply weight to a font that already has a weight specified (OpenSans-SemiBold).

**Replace:**
```swift
.font(.custom("OpenSans-SemiBold", size: 12))
.fontWeight(.semibold) // ❌ Causes warning
```

**With:**
```swift
.font(.custom("OpenSans-SemiBold", size: 12))
// ✅ Don't add .fontWeight() - it's already SemiBold
```

Or use:
```swift
.font(.custom("OpenSans", size: 12))
.fontWeight(.semibold) // ✅ This is fine for base font
```

## Testing Real-Time Updates

### Test 1: Verify Listener is Active

Add this debug log to your view:

```swift
.onAppear {
    postService.startListening(category: .openTable)
    print("🔍 DEBUG: Listener started, current posts: \(postService.openTablePosts.count)")
}
```

You should see:
```
🔊 Starting real-time listener for posts...
✅ User authenticated, setting up listener...
✅ Real-time update: X posts
```

### Test 2: Create a Post and Watch for Update

1. Open OpenTable tab
2. Create a new post
3. You should see these logs:

```
📤 Saving post to Firestore (async)...
✅ Post created successfully with ID: [postId]
✅ Real-time update: X+1 posts
```

### Test 3: Check Firestore Console

1. Go to Firebase Console → Firestore
2. Create a test post directly in the console
3. Your app should automatically update within 1-2 seconds

## Common Issues & Solutions

### Issue: "Posts don't appear immediately after creating"

**Cause:** Optimistic update not working or listener not triggered

**Solution:**
```swift
// In createPost(), immediately add to local array
await MainActor.run {
    let optimisticPost = newPost.toPost()
    self.posts.insert(optimisticPost, at: 0) // Add to beginning
    self.updateCategoryArrays()
}
```

### Issue: "Listener stops working after a while"

**Cause:** Listener removed or app goes to background

**Solution:**
```swift
// Re-attach listener when app becomes active
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    if !postService.isLoading {
        postService.startListening(category: .openTable)
    }
}
```

### Issue: "Too many reads from Firestore"

**Cause:** Creating new listener on every view appear

**Solution:** Use the `isListenerActive` flag (shown in Fix #4 above)

## Performance Optimization

### 1. Limit Initial Load

```swift
.limit(to: 50) // ✅ Don't load all posts at once
```

### 2. Use Pagination

```swift
func loadMorePosts(category: Post.PostCategory) async throws {
    guard let lastPost = posts.last else { return }
    
    let query = db.collection("posts")
        .whereField("category", isEqualTo: category.rawValue)
        .order(by: "createdAt", descending: true)
        .start(after: [lastPost.createdAt])
        .limit(to: 20)
    
    // ... fetch and append
}
```

### 3. Debounce Updates

If you're getting too many real-time updates:

```swift
import Combine

private var updateDebouncer = PassthroughSubject<Void, Never>()
private var cancellables = Set<AnyCancellable>()

init() {
    updateDebouncer
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.updateCategoryArrays()
        }
        .store(in: &cancellables)
}
```

## Complete Working Example

```swift
// OpenTableView.swift

struct OpenTableView: View {
    @StateObject private var postService = FirebasePostService.shared
    @State private var showComposer = false
    
    var body: some View {
        NavigationView {
            List(postService.openTablePosts) { post in
                PostRowView(post: post)
            }
            .navigationTitle("Open Table")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showComposer) {
                PostComposerView(category: .openTable)
            }
            .refreshable {
                // Pull to refresh
                try? await postService.fetchPosts(for: .openTable)
            }
            .task {
                // ✅ Start listening when view appears
                postService.startListening(category: .openTable)
            }
            .onDisappear {
                // Optional: Stop when leaving
                // postService.stopListening()
            }
        }
    }
}

// PostComposerView.swift

struct PostComposerView: View {
    @Environment(\.dismiss) var dismiss
    let category: Post.PostCategory
    @State private var content = ""
    @StateObject private var postService = FirebasePostService.shared
    @State private var isPosting = false
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $content)
                    .padding()
            }
            .navigationTitle("New Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            isPosting = true
                            defer { isPosting = false }
                            
                            do {
                                try await postService.createPost(
                                    content: content,
                                    category: category
                                )
                                dismiss()
                            } catch {
                                print("❌ Failed to create post: \(error)")
                            }
                        }
                    }
                    .disabled(content.isEmpty || isPosting)
                }
            }
        }
    }
}
```

## Verification Checklist

- [ ] Metadata error fixed (`if let` → direct access)
- [ ] `startListening()` called in `.task` or `.onAppear`
- [ ] Listener only created once (check `isListenerActive` flag)
- [ ] Offline persistence enabled in Firestore settings
- [ ] Font warnings addressed (remove redundant `.fontWeight()`)
- [ ] Test: Create post → appears immediately
- [ ] Test: Post from another device → appears in ~1-2 seconds
- [ ] Console shows "✅ Real-time update: X posts" logs
- [ ] No permission errors in console

## Next Steps

1. **Add the listener activation code** to your OpenTable view
2. **Test creating a post** and verify it appears immediately
3. **Check console logs** to ensure listener is active
4. **Monitor Firestore usage** in Firebase Console to avoid excessive reads

---

**Last Updated:** February 5, 2026  
**Status:** Ready to implement ✅
