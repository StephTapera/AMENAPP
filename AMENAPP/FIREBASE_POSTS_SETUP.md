# Firebase Posts Quick Setup Guide

## Step 1: Firebase Console Setup

### 1.1 Create Firestore Database
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your AMENAPP project
3. Navigate to **Firestore Database**
4. Click **Create Database**
5. Choose **Start in test mode** (we'll add security rules later)
6. Select a location closest to your users (e.g., `us-central1`)

### 1.2 Add Security Rules
1. In Firestore Database, go to the **Rules** tab
2. Replace the default rules with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Posts collection
    match /posts/{postId} {
      // Anyone can read posts
      allow read: if true;
      
      // Only authenticated users can create posts
      allow create: if request.auth != null
                    && request.resource.data.authorId == request.auth.uid;
      
      // Only post author can update or delete
      allow update, delete: if request.auth != null
                           && resource.data.authorId == request.auth.uid;
    }
    
    // Users collection
    match /users/{userId} {
      // Anyone can read user profiles
      allow read: if true;
      
      // Only the user can update their own profile
      allow create, update: if request.auth != null
                           && request.auth.uid == userId;
      
      // Users cannot delete their profiles
      allow delete: if false;
    }
  }
}
```

3. Click **Publish**

### 1.3 Create Indexes (Important!)
Firestore will suggest indexes automatically when you first run queries. When you see errors like:

```
Error: The query requires an index
```

Click the provided link in the console to auto-create the index. Common indexes needed:

**Index 1: Posts by Category**
- Collection: `posts`
- Fields: `category` (Ascending), `createdAt` (Descending)

**Index 2: Posts by Author**
- Collection: `posts`
- Fields: `authorId` (Ascending), `createdAt` (Descending)

You can also create these manually in Firebase Console → Firestore → Indexes.

## Step 2: Xcode Project Setup

### 2.1 Verify Firebase SDK
Ensure your Xcode project has Firebase packages added:

**Package Dependencies (in Xcode):**
- `FirebaseAuth`
- `FirebaseFirestore`
- `FirebaseStorage`

**In your app's main file (AMENAPPApp.swift):**
```swift
import SwiftUI
import FirebaseCore

@main
struct AMENAPPApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2.2 Enable Offline Persistence (Optional but Recommended)
Add this to your app initialization:

```swift
import FirebaseFirestore

init() {
    FirebaseApp.configure()
    
    // Enable offline persistence
    let settings = FirestoreSettings()
    settings.isPersistenceEnabled = true
    Firestore.firestore().settings = settings
}
```

## Step 3: Seed Initial Data

### Option A: Using the Debug View (Recommended for Development)

1. Add this to your app's main view during development:

```swift
// In your main ContentView or debug menu
#if DEBUG
Button("Open Firebase Seeder") {
    // Present the seeder view
}
.sheet(isPresented: $showSeeder) {
    FirebaseSeederDebugView()
}
#endif
```

2. Run the app, tap the button
3. Tap "Seed Everything" to create:
   - 16 sample user profiles
   - 16 sample posts (across all categories)

### Option B: Programmatically

```swift
Task {
    do {
        // Seed sample users first
        try await FirebaseDataSeeder.shared.seedSampleUsers()
        print("✅ Users seeded")
        
        // Then seed posts
        try await FirebaseDataSeeder.shared.seedSamplePosts()
        print("✅ Posts seeded")
    } catch {
        print("❌ Seeding failed: \(error)")
    }
}
```

### Option C: Manual Creation in Firebase Console

1. Go to Firestore Database
2. Click **Start Collection**
3. Collection ID: `posts`
4. Add first document with auto-ID
5. Add fields manually:
   - `authorId` (string): "your-user-id"
   - `authorName` (string): "Your Name"
   - `authorUsername` (string): "yourname"
   - `authorInitials` (string): "YN"
   - `content` (string): "Test post content"
   - `category` (string): "openTable" | "testimonies" | "prayer"
   - `visibility` (string): "everyone"
   - `allowComments` (boolean): true
   - `createdAt` (timestamp): (current time)
   - `updatedAt` (timestamp): (current time)
   - `amenCount` (number): 0
   - `lightbulbCount` (number): 0
   - `commentCount` (number): 0
   - `repostCount` (number): 0
   - `isRepost` (boolean): false
   - `amenUserIds` (array): []
   - `lightbulbUserIds` (array): []

## Step 4: Update Your Views

### 4.1 Load Posts on App Launch

In your main feed view:

```swift
struct FeedView: View {
    @StateObject private var postsManager = PostsManager.shared
    
    var body: some View {
        ScrollView {
            ForEach(postsManager.allPosts) { post in
                PostCard(post: post, /* ... */)
            }
        }
        .task {
            // Load posts when view appears
            await postsManager.loadPostsFromFirebase()
        }
        .onAppear {
            // Start real-time listener
            FirebasePostService.shared.startListening()
        }
        .onDisappear {
            // Stop listener to save resources
            FirebasePostService.shared.stopListening()
        }
    }
}
```

### 4.2 Create Posts

In your CreatePostView:

```swift
Button("Post") {
    PostsManager.shared.createPost(
        content: postText,
        category: selectedCategory,
        topicTag: selectedTopicTag,
        visibility: postVisibility,
        allowComments: allowComments
    )
    
    dismiss()
}
```

That's it! The FirebasePostService handles all the Firestore operations.

## Step 5: Testing

### Test Create
1. Sign in to the app
2. Create a new post
3. Check Firebase Console → Firestore → `posts` collection
4. Verify the post appears with correct data

### Test Read
1. Clear app cache (delete and reinstall)
2. Sign in
3. Navigate to feed
4. Verify posts load from Firestore

### Test Real-time Updates
1. Open app on two devices/simulators
2. Create a post on Device 1
3. Verify it appears on Device 2 instantly

### Test Interactions
1. Tap "Amen" or "Lightbulb" on a post
2. Check Firebase Console to see count incremented
3. Check `amenUserIds` or `lightbulbUserIds` array

### Test Edit
1. Tap "..." menu on your own post
2. Select "Edit"
3. Update content
4. Verify changes in Firebase Console

### Test Delete
1. Tap "..." menu on your own post
2. Select "Delete"
3. Verify post removed from Firestore

## Step 6: Production Considerations

### 6.1 Update Security Rules
Replace test mode rules with production rules (see FIRESTORE_POSTS_IMPLEMENTATION.md)

### 6.2 Add Error Handling
```swift
PostsManager.shared.createPost(...)

// Listen for errors
postsManager.$error
    .compactMap { $0 }
    .sink { errorMessage in
        // Show alert to user
        showAlert(message: errorMessage)
    }
```

### 6.3 Add Loading States
```swift
if postsManager.isLoading {
    ProgressView("Loading posts...")
} else {
    // Show posts
}
```

### 6.4 Implement Pagination
For large datasets, implement pagination:

```swift
// Coming soon in FirebasePostService
func fetchMorePosts(after lastPostId: String) async throws {
    // Use Firestore's startAfter
}
```

### 6.5 Add Analytics
```swift
import FirebaseAnalytics

// Log post creation
Analytics.logEvent("post_created", parameters: [
    "category": category.rawValue,
    "has_image": imageURLs != nil
])
```

## Troubleshooting

### "Permission Denied" Errors
- Check Firestore security rules
- Verify user is authenticated
- Ensure `authorId` matches current user ID

### Posts Not Appearing
- Check Firebase Console to verify data exists
- Verify indexes are created
- Check console logs for errors
- Ensure real-time listener is started

### Slow Performance
- Create composite indexes
- Limit query size (`.limit(to: 50)`)
- Enable offline persistence

### Duplicate Posts
- Stop duplicate listeners
- Check you're not calling `fetchAllPosts()` multiple times
- Verify `startListening()` is called once

## Next Steps

1. **Add Comments:** Create `posts/{postId}/comments` subcollection
2. **Add Reactions:** Extend interaction types beyond amen/lightbulb
3. **Add Notifications:** Use Cloud Functions to notify on interactions
4. **Add Search:** Implement Algolia or Firestore queries for search
5. **Add Media Upload:** Use Firebase Storage for images/videos
6. **Add Moderation:** Flag inappropriate content

## Resources

- [Firebase Firestore Docs](https://firebase.google.com/docs/firestore)
- [Swift Firebase Guide](https://firebase.google.com/docs/firestore/solutions/ios)
- [Security Rules Reference](https://firebase.google.com/docs/firestore/security/rules-structure)

---

**Setup Complete!** 🎉

Your posts are now fully integrated with Firebase Firestore. All create, read, update, delete, and interaction operations are persisted to the cloud and synced in real-time.
