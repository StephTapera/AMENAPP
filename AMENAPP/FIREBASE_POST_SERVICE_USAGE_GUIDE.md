# Firebase Post Service - Complete Usage Guide

## 🎉 Your Firebase Post Service is Complete!

You have a **fully functional, production-ready** Firebase Post Service with all core features and advanced enhancements.

---

## 📦 What's Included

### **Core Service (Already Implemented)**
✅ `FirebasePostService.swift` - Complete CRUD operations, interactions, notifications

### **Enhancements (New)**
✅ `FirebasePostServiceEnhancements.swift` - Advanced features like image upload, analytics, drafts, scheduling

---

## 🚀 Quick Start

### 1. **Import the Service**
```swift
import SwiftUI

// Use the shared instance
let postService = FirebasePostService.shared
```

### 2. **Create a Simple Post**
```swift
Button("Post") {
    Task {
        do {
            try await postService.createPost(
                content: "My testimony about God's grace today!",
                category: .testimonies,
                topicTag: "grace",
                visibility: .everyone,
                allowComments: true
            )
            print("✅ Post created!")
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
```

### 3. **Create Post with Images**
```swift
Button("Post with Photos") {
    Task {
        do {
            let images = [image1, image2, image3] // UIImage array
            
            try await postService.createPostWithImages(
                content: "Check out these beautiful moments!",
                category: .openTable,
                images: images,
                topicTag: "community",
                visibility: .everyone
            )
            print("✅ Post with images created!")
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
```

---

## 📋 Complete Feature List

### **Core Post Operations**

#### **Create Post**
```swift
try await postService.createPost(
    content: String,
    category: Post.PostCategory,
    topicTag: String? = nil,
    visibility: Post.PostVisibility = .everyone,
    allowComments: Bool = true,
    imageURLs: [String]? = nil,
    linkURL: String? = nil
)
```

#### **Create Post with Images**
```swift
try await postService.createPostWithImages(
    content: String,
    category: Post.PostCategory,
    images: [UIImage],
    topicTag: String? = nil,
    visibility: Post.PostVisibility = .everyone,
    allowComments: Bool = true,
    linkURL: String? = nil
)
```

#### **Edit Post**
```swift
try await postService.editPost(
    postId: String,
    newContent: String
)
```

#### **Delete Post**
```swift
try await postService.deletePost(postId: String)
```

---

### **Fetch Posts**

#### **Fetch All Posts**
```swift
try await postService.fetchAllPosts(limit: 50)
// Access via: postService.posts
```

#### **Fetch by Category with Filters**
```swift
let posts = try await postService.fetchPosts(
    for: .openTable,
    filter: "popular",  // "all", "recent", "popular", "following"
    topicTag: "prayer",
    limit: 50
)
```

#### **Fetch User Posts**
```swift
let userPosts = try await postService.fetchUserPosts(
    userId: "user123",
    limit: 50
)
```

#### **Fetch User's Original Posts (Excluding Reposts)**
```swift
let originalPosts = try await postService.fetchUserOriginalPosts(userId: "user123")
```

#### **Fetch User's Reposts**
```swift
let reposts = try await postService.fetchUserReposts(userId: "user123")
```

#### **Fetch Saved Posts**
```swift
let savedPosts = try await postService.fetchUserSavedPosts(userId: "user123")
```

---

### **Interactions**

#### **Toggle Amen (Like)**
```swift
try await postService.toggleAmen(postId: post.id.uuidString)

// Check if user has amened
let hasAmened = await postService.hasUserAmened(postId: post.id.uuidString)
```

#### **Toggle Lightbulb (Insight)**
```swift
try await postService.toggleLightbulb(postId: post.id.uuidString)

// Check if user has lit lightbulb
let hasLit = await postService.hasUserLitLightbulb(postId: post.id.uuidString)
```

#### **Increment Comment Count**
```swift
try await postService.incrementCommentCount(
    postId: post.id.uuidString,
    commentText: "Great testimony!"
)
```

#### **Repost to Profile**
```swift
try await postService.repostToProfile(originalPostId: post.id.uuidString)
```

---

### **Bookmarking (Save/Unsave)**

#### **Save Post**
```swift
try await postService.savePost(postId: post.id.uuidString)
```

#### **Unsave Post**
```swift
try await postService.unsavePost(postId: post.id.uuidString)
```

#### **Check if Post is Saved**
```swift
let isSaved = try await postService.isPostSaved(postId: post.id.uuidString)
```

---

### **Analytics**

#### **Track Post View**
```swift
try await postService.trackPostView(postId: post.id.uuidString)
```

#### **Get Post Analytics**
```swift
let analytics = try await postService.getPostAnalytics(postId: post.id.uuidString)

print("Views: \(analytics.viewCount)")
print("Engagement Rate: \(analytics.formattedEngagementRate)")
print("Total Engagements: \(analytics.totalEngagements)")
```

---

### **Reporting**

#### **Report Post**
```swift
try await postService.reportPost(
    postId: post.id.uuidString,
    reason: .spam,
    additionalDetails: "This is clearly spam content"
)
```

#### **Available Report Reasons**
- `.spam`
- `.harassment`
- `.hateSpeech`
- `.violence`
- `.sexualContent`
- `.misinformation`
- `.other`

---

### **Pinning**

#### **Pin Post to Profile**
```swift
try await postService.pinPost(postId: post.id.uuidString)
```

#### **Unpin Post**
```swift
try await postService.unpinPost(postId: post.id.uuidString)
```

---

### **Drafts**

#### **Save Draft**
```swift
let draftId = try await postService.saveDraft(
    content: "Draft content here...",
    category: .openTable,
    images: [image1, image2],
    topicTag: "community"
)
```

#### **Load All Drafts**
```swift
let drafts = try await postService.loadDrafts()

// Access draft properties
for draft in drafts {
    print(draft.content)
    print(draft.category)
    print(draft.createdAt)
}
```

#### **Publish Draft**
```swift
try await postService.publishDraft(draftId: draftId)
```

#### **Delete Draft**
```swift
try await postService.deleteDraft(draftId: draftId)
```

---

### **Scheduled Posts**

#### **Schedule Post for Future**
```swift
let scheduledDate = Calendar.current.date(
    byAdding: .hour,
    value: 2,
    to: Date()
)!

let scheduledId = try await postService.schedulePost(
    content: "This will post in 2 hours",
    category: .openTable,
    scheduledFor: scheduledDate,
    images: [image1],
    topicTag: "announcement"
)
```

#### **Cancel Scheduled Post**
```swift
try await postService.cancelScheduledPost(scheduledPostId: scheduledId)
```

> **Note**: Scheduled posts require a Cloud Function to automatically publish them at the scheduled time. See Cloud Functions section below.

---

### **Hide Posts**

#### **Hide Post from Feed**
```swift
try await postService.hidePost(postId: post.id.uuidString)
```

#### **Check if Post is Hidden**
```swift
let isHidden = try await postService.isPostHidden(postId: post.id.uuidString)
```

---

### **Real-time Listeners**

#### **Start Listening to All Posts**
```swift
postService.startListening()

// Posts automatically update in:
// - postService.posts
// - postService.openTablePosts
// - postService.testimoniesPosts
// - postService.prayerPosts
```

#### **Start Listening to Specific Category**
```swift
postService.startListening(category: .testimonies)
```

#### **Stop Listening**
```swift
postService.stopListening()
```

---

## 🎨 SwiftUI Integration Examples

### **Post Feed View**
```swift
struct PostsFeedView: View {
    @StateObject private var postService = FirebasePostService.shared
    @State private var selectedFilter = "all"
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(postService.posts) { post in
                    PostCardView(post: post)
                }
            }
            .padding()
        }
        .task {
            // Fetch initial posts
            try? await postService.fetchAllPosts()
            
            // Start real-time listening
            postService.startListening()
        }
        .onDisappear {
            // Clean up listeners
            postService.stopListening()
        }
        .refreshable {
            try? await postService.fetchAllPosts()
        }
    }
}
```

### **Category Feed View**
```swift
struct CategoryFeedView: View {
    @StateObject private var postService = FirebasePostService.shared
    let category: Post.PostCategory
    @State private var filter = "all"
    @State private var selectedTopicTag: String?
    
    var posts: [Post] {
        switch category {
        case .openTable: return postService.openTablePosts
        case .testimonies: return postService.testimoniesPosts
        case .prayer: return postService.prayerPosts
        }
    }
    
    var body: some View {
        VStack {
            // Filter picker
            Picker("Filter", selection: $filter) {
                Text("All").tag("all")
                Text("Recent").tag("recent")
                Text("Popular").tag("popular")
                Text("Following").tag("following")
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Posts list
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        PostCardView(post: post)
                    }
                }
                .padding()
            }
        }
        .task {
            try? await loadPosts()
        }
        .onChange(of: filter) { _, _ in
            Task {
                try? await loadPosts()
            }
        }
    }
    
    private func loadPosts() async throws {
        let fetchedPosts = try await postService.fetchPosts(
            for: category,
            filter: filter,
            topicTag: selectedTopicTag,
            limit: 50
        )
        
        // Update appropriate array
        await MainActor.run {
            switch category {
            case .openTable:
                postService.openTablePosts = fetchedPosts
            case .testimonies:
                postService.testimoniesPosts = fetchedPosts
            case .prayer:
                postService.prayerPosts = fetchedPosts
            }
        }
    }
}
```

### **Post Card with Interactions**
```swift
struct PostCardView: View {
    @StateObject private var postService = FirebasePostService.shared
    let post: Post
    
    @State private var hasAmened = false
    @State private var hasLitLightbulb = false
    @State private var isSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post header
            HStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(post.authorInitials)
                            .font(.custom("OpenSans-Bold", size: 14))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.custom("OpenSans-Bold", size: 15))
                    
                    Text(post.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button {
                        Task {
                            try? await postService.savePost(postId: post.id.uuidString)
                            isSaved = true
                        }
                    } label: {
                        Label(isSaved ? "Unsave" : "Save", systemImage: "bookmark")
                    }
                    
                    Button {
                        Task {
                            try? await postService.hidePost(postId: post.id.uuidString)
                        }
                    } label: {
                        Label("Hide Post", systemImage: "eye.slash")
                    }
                    
                    Button(role: .destructive) {
                        // Show report sheet
                    } label: {
                        Label("Report", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Post content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 15))
            
            // Post images (if any)
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(imageURLs, id: \.self) { urlString in
                            AsyncImage(url: URL(string: urlString)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 200, height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } placeholder: {
                                ProgressView()
                                    .frame(width: 200, height: 200)
                            }
                        }
                    }
                }
            }
            
            // Interaction buttons
            HStack(spacing: 24) {
                // Amen
                Button {
                    Task {
                        try? await postService.toggleAmen(postId: post.id.uuidString)
                        hasAmened.toggle()
                    }
                } label: {
                    Label("\(post.amenCount)", systemImage: hasAmened ? "hands.clap.fill" : "hands.clap")
                        .foregroundStyle(hasAmened ? .blue : .primary)
                }
                
                // Lightbulb
                Button {
                    Task {
                        try? await postService.toggleLightbulb(postId: post.id.uuidString)
                        hasLitLightbulb.toggle()
                    }
                } label: {
                    Label("\(post.lightbulbCount)", systemImage: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
                        .foregroundStyle(hasLitLightbulb ? .yellow : .primary)
                }
                
                // Comment
                Button {
                    // Show comment sheet
                } label: {
                    Label("\(post.commentCount)", systemImage: "bubble.left")
                }
                
                Spacer()
                
                // Repost
                Button {
                    Task {
                        try? await postService.repostToProfile(originalPostId: post.id.uuidString)
                    }
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                }
                
                // Save
                Button {
                    Task {
                        if isSaved {
                            try? await postService.unsavePost(postId: post.id.uuidString)
                        } else {
                            try? await postService.savePost(postId: post.id.uuidString)
                        }
                        isSaved.toggle()
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
            .font(.custom("OpenSans-Regular", size: 14))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .task {
            // Check initial states
            hasAmened = await postService.hasUserAmened(postId: post.id.uuidString)
            hasLitLightbulb = await postService.hasUserLitLightbulb(postId: post.id.uuidString)
            isSaved = (try? await postService.isPostSaved(postId: post.id.uuidString)) ?? false
        }
        .onAppear {
            // Track view
            Task {
                try? await postService.trackPostView(postId: post.id.uuidString)
            }
        }
    }
}
```

### **Create Post View**
```swift
struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var postService = FirebasePostService.shared
    
    @State private var content = ""
    @State private var selectedCategory: Post.PostCategory = .openTable
    @State private var selectedImages: [UIImage] = []
    @State private var topicTag: String?
    @State private var isPosting = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                }
                
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Open Table").tag(Post.PostCategory.openTable)
                        Text("Testimonies").tag(Post.PostCategory.testimonies)
                        Text("Prayer").tag(Post.PostCategory.prayer)
                    }
                }
                
                Section("Images") {
                    // Photo picker
                    PhotosPicker(selection: $selectedImages, maxSelectionCount: 10) {
                        Label("Add Photos", systemImage: "photo")
                    }
                    
                    if !selectedImages.isEmpty {
                        Text("\(selectedImages.count) photo(s) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        postContent()
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Post")
                                .bold()
                        }
                    }
                    .disabled(content.isEmpty || isPosting)
                }
            }
        }
    }
    
    private func postContent() {
        isPosting = true
        
        Task {
            do {
                if selectedImages.isEmpty {
                    try await postService.createPost(
                        content: content,
                        category: selectedCategory,
                        topicTag: topicTag,
                        visibility: .everyone,
                        allowComments: true
                    )
                } else {
                    try await postService.createPostWithImages(
                        content: content,
                        category: selectedCategory,
                        images: selectedImages,
                        topicTag: topicTag,
                        visibility: .everyone,
                        allowComments: true
                    )
                }
                
                await MainActor.run {
                    isPosting = false
                    dismiss()
                }
            } catch {
                print("Error posting: \(error)")
                await MainActor.run {
                    isPosting = false
                }
            }
        }
    }
}
```

---

## 🔥 Cloud Functions (Optional)

For scheduled posts to work automatically, create a Cloud Function:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Run every minute to check for scheduled posts
exports.publishScheduledPosts = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    
    // Find posts scheduled for now or earlier
    const scheduledPosts = await admin.firestore()
      .collection('scheduledPosts')
      .where('status', '==', 'scheduled')
      .where('scheduledFor', '<=', now.toDate())
      .get();
    
    const promises = [];
    
    scheduledPosts.forEach(doc => {
      const post = doc.data();
      
      // Create the actual post
      const postPromise = admin.firestore().collection('posts').add({
        authorId: post.userId,
        content: post.content,
        category: post.category,
        topicTag: post.topicTag || null,
        imageURLs: post.imageURLs || [],
        createdAt: now.toDate(),
        updatedAt: now.toDate(),
        amenCount: 0,
        lightbulbCount: 0,
        commentCount: 0,
        repostCount: 0,
        amenUserIds: [],
        lightbulbUserIds: []
      });
      
      // Update scheduled post status
      const updatePromise = doc.ref.update({
        status: 'published',
        publishedAt: now.toDate()
      });
      
      promises.push(postPromise, updatePromise);
    });
    
    await Promise.all(promises);
    
    console.log(`Published ${scheduledPosts.size} scheduled posts`);
  });
```

Deploy with:
```bash
firebase deploy --only functions
```

---

## ✅ Summary

You now have **everything you need** for a complete post management system:

### **Core Features** ✅
- Create, read, update, delete posts
- Real-time updates
- Image uploads
- Interactions (Amen, Lightbulb, Comments, Reposts)

### **Advanced Features** ✅
- Post analytics
- Bookmarking
- Reporting
- Pinning
- Drafts
- Scheduled posts
- Hiding posts

### **Notifications** ✅
- Amen notifications
- Comment notifications
- Mention notifications

### **User Experience** ✅
- Haptic feedback
- Loading states
- Error handling
- Optimistic updates

---

## 🎉 You're All Set!

Your Firebase Post Service is **production-ready** and includes all the features you need for a modern social faith app. Start building your UI and let the service handle all the backend logic!

---

**Happy coding!** 🚀
