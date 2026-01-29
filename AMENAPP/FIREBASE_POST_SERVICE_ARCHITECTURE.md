# Firebase Post Service - Architecture Overview

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AMENAPP SwiftUI Views                       │
│  (FeedView, PostDetailView, CreatePostView, ProfileView, etc.)  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               FirebasePostService (Singleton)                    │
│  - @Published properties (posts, loading, error)                │
│  - CRUD operations                                               │
│  - Real-time listeners                                           │
│  - Interaction management                                        │
└───────┬────────────┬────────────┬────────────┬──────────────────┘
        │            │            │            │
        ▼            ▼            ▼            ▼
┌─────────────┐ ┌─────────┐ ┌─────────┐ ┌──────────────┐
│  Firestore  │ │ Realtime│ │ Storage │ │Notifications │
│   (Posts)   │ │   DB    │ │(Images) │ │  (System)    │
└─────────────┘ └─────────┘ └─────────┘ └──────────────┘
```

---

## 📦 Service Components

### **FirebasePostService.swift**
```
┌──────────────────────────────────────┐
│     Core Post Service (Main)         │
├──────────────────────────────────────┤
│  ✓ Create Post                       │
│  ✓ Edit Post                         │
│  ✓ Delete Post                       │
│  ✓ Fetch Posts (All, Category, User) │
│  ✓ Toggle Amen                       │
│  ✓ Toggle Lightbulb                  │
│  ✓ Increment Comment Count           │
│  ✓ Repost to Profile                 │
│  ✓ Real-time Listeners               │
│  ✓ Notification Creation             │
└──────────────────────────────────────┘
```

### **FirebasePostServiceEnhancements.swift**
```
┌──────────────────────────────────────┐
│    Enhanced Features (Extensions)    │
├──────────────────────────────────────┤
│  ✓ Upload Images                     │
│  ✓ Create Post with Images           │
│  ✓ Track Post Views                  │
│  ✓ Get Post Analytics                │
│  ✓ Save/Unsave Posts                 │
│  ✓ Report Posts                      │
│  ✓ Pin/Unpin Posts                   │
│  ✓ Manage Drafts                     │
│  ✓ Schedule Posts                    │
│  ✓ Hide Posts                        │
└──────────────────────────────────────┘
```

---

## 🔄 Data Flow Diagram

### **Creating a Post**
```
User Types Content
      │
      ▼
SwiftUI View
      │
      ▼
createPost() / createPostWithImages()
      │
      ├─────────────────┐
      ▼                 ▼
Upload Images    Fetch User Data
  (Storage)        (Firestore)
      │                 │
      └────────┬────────┘
               ▼
      Create Post Document
         (Firestore)
               │
               ├──────────────────┐
               ▼                  ▼
    Update User Stats    Publish to Feed
      (Firestore)      (Realtime DB)
               │                  │
               ├──────────────────┤
               ▼
      Create Notifications
       (Mentions, etc.)
               │
               ▼
       Haptic Feedback
               │
               ▼
        Success! 🎉
```

### **Fetching Posts**
```
View Appears
      │
      ▼
fetchAllPosts() / fetchPosts()
      │
      ▼
Query Firestore
  - Filter by category
  - Filter by user
  - Apply topic tags
  - Apply visibility
      │
      ▼
Get Documents
      │
      ▼
Convert FirestorePost → Post
      │
      ▼
Update @Published posts Array
      │
      ▼
SwiftUI View Auto-Updates
      │
      ▼
Display Posts 📱
```

### **Real-time Updates**
```
startListening()
      │
      ▼
Firestore .addSnapshotListener()
      │
      ├─────────────────────┐
      │                     │
      ▼                     ▼
  New Post Added    Post Updated/Deleted
      │                     │
      └──────────┬──────────┘
                 ▼
     Update @Published Array
                 │
                 ▼
    SwiftUI View Auto-Updates
                 │
                 ▼
        Live Updates! ⚡
```

### **Toggling Amen**
```
User Taps Amen Button
      │
      ▼
toggleAmen(postId)
      │
      ▼
Fetch Post Document
      │
      ▼
Check amenUserIds Array
      │
      ├──────────────────┐
      ▼                  ▼
Has Amened?        Not Amened?
      │                  │
      ▼                  ▼
Remove UserId      Add UserId
Decrement Count    Increment Count
      │                  │
      ├──────────┬───────┘
      │          │
      │          ▼
      │    Create Notification
      │      (If not self)
      │          │
      └──────────┼───────┐
                 ▼       │
          Update Local   │
             Cache       │
                 │       ▼
                 └─► Haptic
                       Feedback
                         │
                         ▼
                    Success! 🙏
```

---

## 💾 Firestore Data Structure

### **Posts Collection**
```
posts (collection)
  └─ {postId} (document)
       ├─ authorId: "user123"
       ├─ authorName: "John Doe"
       ├─ authorUsername: "johndoe"
       ├─ authorInitials: "JD"
       ├─ authorProfileImageURL: "https://..."
       ├─ content: "Post content here"
       ├─ category: "openTable"
       ├─ topicTag: "prayer"
       ├─ visibility: "everyone"
       ├─ allowComments: true
       ├─ imageURLs: ["url1", "url2"]
       ├─ linkURL: "https://..."
       ├─ createdAt: Timestamp
       ├─ updatedAt: Timestamp
       ├─ amenCount: 42
       ├─ lightbulbCount: 15
       ├─ commentCount: 8
       ├─ repostCount: 3
       ├─ viewCount: 150
       ├─ isRepost: false
       ├─ originalPostId: null
       ├─ amenUserIds: ["user1", "user2", ...]
       ├─ lightbulbUserIds: ["user3", "user4", ...]
       ├─ isPinned: false
       └─ pinnedAt: null
```

### **Saved Posts Collection**
```
savedPosts (collection)
  └─ {userId}_{postId} (document)
       ├─ userId: "user123"
       ├─ postId: "post456"
       └─ savedAt: Timestamp
```

### **Post Drafts Collection**
```
postDrafts (collection)
  └─ {draftId} (document)
       ├─ userId: "user123"
       ├─ content: "Draft content"
       ├─ category: "testimonies"
       ├─ topicTag: "faith"
       ├─ imageURLs: ["url1"]
       ├─ createdAt: Timestamp
       └─ updatedAt: Timestamp
```

### **Scheduled Posts Collection**
```
scheduledPosts (collection)
  └─ {scheduledId} (document)
       ├─ userId: "user123"
       ├─ content: "Scheduled content"
       ├─ category: "prayer"
       ├─ scheduledFor: Timestamp
       ├─ status: "scheduled"
       ├─ createdAt: Timestamp
       └─ imageURLs: ["url1"]
```

### **Hidden Posts Collection**
```
hiddenPosts (collection)
  └─ {userId}_{postId} (document)
       ├─ userId: "user123"
       ├─ postId: "post789"
       └─ hiddenAt: Timestamp
```

### **Post Reports Collection**
```
postReports (collection)
  └─ {reportId} (document)
       ├─ postId: "post123"
       ├─ reportedBy: "user456"
       ├─ reason: "spam"
       ├─ additionalDetails: "..."
       ├─ reportedAt: Timestamp
       └─ status: "pending"
```

### **Notifications Collection**
```
notifications (collection)
  └─ {notificationId} (document)
       ├─ userId: "user123" (recipient)
       ├─ type: "amen" | "comment" | "mention"
       ├─ fromUserId: "user456"
       ├─ fromUserName: "Jane Doe"
       ├─ fromUserUsername: "janedoe"
       ├─ postId: "post789"
       ├─ message: "Jane Doe said Amen to your post"
       ├─ postPreview: "First 50 chars..."
       ├─ commentPreview: "..."
       ├─ createdAt: Timestamp
       └─ read: false
```

---

## 🎯 Key Methods Reference

### **Post Creation**
```swift
// Basic post
createPost(content:category:topicTag:visibility:allowComments:imageURLs:linkURL:)

// Post with images
createPostWithImages(content:category:images:topicTag:visibility:allowComments:linkURL:)

// From draft
publishDraft(draftId:)
```

### **Post Management**
```swift
editPost(postId:newContent:)
deletePost(postId:)
pinPost(postId:)
unpinPost(postId:)
```

### **Fetching**
```swift
fetchAllPosts(limit:)
fetchPosts(for:filter:topicTag:limit:)
fetchUserPosts(userId:limit:)
fetchUserOriginalPosts(userId:)
fetchUserReposts(userId:)
fetchUserSavedPosts(userId:)
```

### **Interactions**
```swift
toggleAmen(postId:)
toggleLightbulb(postId:)
incrementCommentCount(postId:commentText:)
repostToProfile(originalPostId:)
```

### **Status Checks**
```swift
hasUserAmened(postId:) -> Bool
hasUserLitLightbulb(postId:) -> Bool
isPostSaved(postId:) -> Bool
isPostHidden(postId:) -> Bool
```

### **Bookmarking**
```swift
savePost(postId:)
unsavePost(postId:)
```

### **Moderation**
```swift
reportPost(postId:reason:additionalDetails:)
hidePost(postId:)
```

### **Analytics**
```swift
trackPostView(postId:)
getPostAnalytics(postId:) -> PostAnalytics
```

### **Drafts**
```swift
saveDraft(content:category:images:topicTag:) -> String
loadDrafts() -> [PostDraft]
deleteDraft(draftId:)
publishDraft(draftId:)
```

### **Scheduling**
```swift
schedulePost(content:category:scheduledFor:images:topicTag:) -> String
cancelScheduledPost(scheduledPostId:)
```

### **Real-time**
```swift
startListening(category:)
stopListening()
```

---

## 🔐 Security Rules Example

### **Firestore Security Rules**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Posts
    match /posts/{postId} {
      // Anyone can read
      allow read: if true;
      
      // Only authenticated users can create
      allow create: if request.auth != null 
                    && request.resource.data.authorId == request.auth.uid;
      
      // Only author can update/delete
      allow update, delete: if request.auth != null 
                            && resource.data.authorId == request.auth.uid;
    }
    
    // Saved Posts
    match /savedPosts/{docId} {
      allow read, write: if request.auth != null 
                         && docId.split('_')[0] == request.auth.uid;
    }
    
    // Drafts
    match /postDrafts/{draftId} {
      allow read, write: if request.auth != null 
                         && resource.data.userId == request.auth.uid;
    }
    
    // Scheduled Posts
    match /scheduledPosts/{scheduledId} {
      allow read, write: if request.auth != null 
                         && resource.data.userId == request.auth.uid;
    }
    
    // Hidden Posts
    match /hiddenPosts/{docId} {
      allow read, write: if request.auth != null 
                         && docId.split('_')[0] == request.auth.uid;
    }
    
    // Reports (anyone can create, only admins can read)
    match /postReports/{reportId} {
      allow create: if request.auth != null;
      allow read: if request.auth != null 
                  && get(/databases/$(database)/documents/users/$(request.auth.uid))
                     .data.isAdmin == true;
    }
  }
}
```

---

## 📱 SwiftUI View Hierarchy

```
ContentView
  │
  ├─ TabView
  │   │
  │   ├─ FeedView
  │   │   └─ ForEach(postService.posts)
  │   │       └─ PostCardView
  │   │           ├─ Amen Button → toggleAmen()
  │   │           ├─ Lightbulb Button → toggleLightbulb()
  │   │           ├─ Comment Button → Show CommentSheet
  │   │           └─ More Menu
  │   │               ├─ Save → savePost()
  │   │               ├─ Hide → hidePost()
  │   │               └─ Report → reportPost()
  │   │
  │   ├─ OpenTableView
  │   │   └─ ForEach(postService.openTablePosts)
  │   │
  │   ├─ TestimoniesView
  │   │   └─ ForEach(postService.testimoniesPosts)
  │   │
  │   ├─ PrayerView
  │   │   └─ ForEach(postService.prayerPosts)
  │   │
  │   └─ ProfileView
  │       ├─ User Posts Tab
  │       │   └─ ForEach(userPosts)
  │       ├─ Saved Posts Tab
  │       │   └─ ForEach(savedPosts)
  │       └─ Drafts Tab
  │           └─ ForEach(drafts)
  │
  ├─ CreatePostView (Sheet)
  │   └─ Create Button → createPost() / createPostWithImages()
  │
  └─ PostDetailView (Navigation)
      └─ Comments, Full Content, etc.
```

---

## 🎨 Published Properties Flow

```swift
@MainActor
class FirebasePostService: ObservableObject {
    
    // These properties trigger SwiftUI view updates
    @Published var posts: [Post] = []
    @Published var openTablePosts: [Post] = []
    @Published var testimoniesPosts: [Post] = []
    @Published var prayerPosts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // When these change:
    // 1. SwiftUI views observing this service auto-update
    // 2. No manual view refresh needed
    // 3. Smooth animations handled by SwiftUI
}
```

**In Your Views:**
```swift
struct FeedView: View {
    @StateObject private var postService = FirebasePostService.shared
    
    var body: some View {
        // This automatically updates when postService.posts changes
        List(postService.posts) { post in
            PostRow(post: post)
        }
    }
}
```

---

## ✅ Complete Implementation Checklist

### **Core Features**
- [x] Create posts
- [x] Edit posts
- [x] Delete posts
- [x] Fetch posts (all, category, user)
- [x] Real-time listeners
- [x] Toggle Amen
- [x] Toggle Lightbulb
- [x] Comment count tracking
- [x] Repost functionality

### **Advanced Features**
- [x] Image upload to Storage
- [x] Create post with images
- [x] Post analytics
- [x] Save/bookmark posts
- [x] Report posts
- [x] Pin posts
- [x] Draft management
- [x] Schedule posts
- [x] Hide posts

### **Data Management**
- [x] Firestore integration
- [x] Realtime Database integration
- [x] Firebase Storage integration
- [x] Published properties
- [x] Local cache updates

### **User Experience**
- [x] Haptic feedback
- [x] Loading states
- [x] Error handling
- [x] Optimistic updates
- [x] Smooth animations

### **Security**
- [x] Authentication checks
- [x] Authorization checks
- [x] Input validation
- [x] Proper error handling

### **Notifications**
- [x] Amen notifications
- [x] Comment notifications
- [x] Mention notifications
- [x] Prevent self-notifications

---

## 🚀 You're Ready!

Everything is implemented, tested, and documented. Start building your UI and enjoy the seamless backend! 🎉

**Happy coding!** 🙏✨
