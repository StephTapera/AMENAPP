# Complete Post Interactions Implementation Checklist

## 🚨 **URGENT: Fix Duplicate Repost Error First**

### Step 1: Find the Duplicate
1. Open Xcode
2. Press **⌘ + Shift + F** (Find in Project)
3. Search for: **`struct Repost`**
4. You should see results from at least 2 files
5. Identify which file is NOT `PostInteractionModels.swift`
6. Delete that duplicate struct definition

**Common places duplicates hide:**
- Inside `Models.swift` or `SocialModels.swift`
- Old backup files (check for files with "copy" or dates in names)
- Inside service files (though unlikely based on my search)

---

## ✅ What's Already Implemented

### Models
- ✅ `Comment` (PostInteractionModels.swift)
- ✅ `SavedPost` (PostInteractionModels.swift)
- ✅ `Repost` (PostInteractionModels.swift) - **has duplicate somewhere**
- ✅ `PostMention` (PostInteractionModels.swift)
- ✅ `CommentWithReplies` (PostInteractionModels.swift)

### Services
- ✅ `CommentService.swift` - Full CRUD for comments/replies
- ✅ `SavedPostsService.swift` - Save/unsave posts
- ✅ `RepostService.swift` - Repost/unrepost with quotes

### View Models
- ✅ `PostInteractionsViewModel.swift` - Unified interface

### Helpers
- ✅ `Post+Extensions.swift` - UUID↔String conversion, time ago

---

## 🔧 Integration Tasks

### Task 1: Update Post Model
**File:** `PostsManager.swift`

Add these properties to the `Post` struct:

```swift
struct Post: Identifiable, Codable, Equatable {
    // ... existing properties ...
    
    // ADD THESE:
    var amenUserIds: [String] = []  // Users who said amen
    var lightbulbUserIds: [String] = []  // Users who lit lightbulb
    
    // ... rest of struct ...
}
```

This allows tracking which users have interacted with posts.

---

### Task 2: Update PostCard Integration
**File:** `PostCard.swift`

#### A. Add View Model

```swift
struct PostCard: View {
    // ... existing properties ...
    
    // ADD:
    @StateObject private var interactionsVM = PostInteractionsViewModel()
    
    // ... rest of code ...
}
```

#### B. Update Save Button (around line 440)

Replace:
```swift
// Save/Bookmark Button
Button {
    // Save functionality
    let haptic = UIImpactFeedbackGenerator(style: .medium)
    haptic.impactOccurred()
} label: {
    // ... label code ...
}
```

With:
```swift
// Save/Bookmark Button
Button {
    Task {
        guard let postId = post?.id else { return }
        await interactionsVM.toggleSavePost(postId.uuidString)
    }
} label: {
    Image(systemName: (post?.id.map { interactionsVM.isPostSaved($0.uuidString) } ?? false) ? "bookmark.fill" : "bookmark")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle((post?.id.map { interactionsVM.isPostSaved($0.uuidString) } ?? false) ? .black : .black.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
}
```

#### C. Update Repost Button (around line 425)

Replace:
```swift
// Repost Button
Button {
    repostToProfile()
} label: {
    // ... existing label ...
}
```

With:
```swift
// Repost Button  
Button {
    Task {
        guard let postId = post?.id else { return }
        await interactionsVM.toggleRepost(postId.uuidString)
    }
} label: {
    HStack(spacing: 4) {
        let hasReposted = post?.id.map { interactionsVM.hasReposted($0.uuidString) } ?? false
        Image(systemName: hasReposted ? "arrow.2.squarepath.fill" : "arrow.2.squarepath")
            .font(.system(size: 12, weight: .semibold))
        if let post = post, post.repostCount > 0 {
            Text("\(post.repostCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
                .contentTransition(.numericText())
        }
    }
    .foregroundStyle((post?.id.map { interactionsVM.hasReposted($0.uuidString) } ?? false) ? .black : .black.opacity(0.5))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
        Capsule()
            .fill(Color.black.opacity(0.05))
    )
    .overlay(
        Capsule()
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
    )
}
```

#### D. Add Lifecycle Management

Add at the end of the `body` var (before the closing brace):

```swift
.onAppear {
    // Start listeners
    interactionsVM.startListeningToSavedPosts()
    interactionsVM.startListeningToReposts()
}
.onDisappear {
    // Clean up
    interactionsVM.cleanup()
}
```

---

### Task 3: Update PostCommentsView
**File:** `PostCard.swift` (PostCommentsView is defined here)

#### A. Replace Mock Comment Struct

Remove the local `Comment` struct (around line 670):
```swift
struct Comment: Identifiable {
    // DELETE THIS ENTIRE STRUCT
}
```

Import the real one at top of file:
```swift
import SwiftUI
// No need to import, it's in the same module
```

#### B. Update PostCommentsView Properties

Replace:
```swift
struct PostCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var postsManager = PostsManager.shared
    
    let post: Post
    @State private var commentText = ""
    @State private var comments: [Comment] = []
    // ... etc
}
```

With:
```swift
struct PostCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var interactionsVM = PostInteractionsViewModel()
    
    let post: Post
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @FocusState private var isCommentFocused: Bool
}
```

#### C. Update Comments Display

Replace the comments list (around line 755):
```swift
if comments.isEmpty {
    // ... empty state ...
} else {
    LazyVStack(spacing: 12) {
        ForEach(comments) { comment in
            CommentCardView(comment: comment, onReply: { replyingTo = comment })
        }
    }
    .padding(.horizontal, 16)
}
```

With:
```swift
if interactionsVM.isLoadingComments {
    ProgressView()
        .padding(.vertical, 60)
} else if interactionsVM.comments.isEmpty {
    VStack(spacing: 16) {
        Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
        
        Text("No comments yet")
            .font(.custom("OpenSans-Bold", size: 18))
            .foregroundStyle(.primary)
        
        Text("Be the first to share your thoughts!")
            .font(.custom("OpenSans-Regular", size: 14))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
} else {
    LazyVStack(spacing: 12) {
        ForEach(interactionsVM.comments) { commentWithReplies in
            FirestoreCommentCardView(
                commentWithReplies: commentWithReplies,
                interactionsVM: interactionsVM,
                postId: post.id.uuidString,
                onReply: { replyingTo = commentWithReplies.comment }
            )
        }
    }
    .padding(.horizontal, 16)
}
```

#### D. Update submitComment

Replace:
```swift
private func submitComment() {
    guard !commentText.isEmpty else { return }
    
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
        let newComment = Comment(
            // ... mock comment creation ...
        )
        
        comments.insert(newComment, at: 0)
        commentText = ""
        replyingTo = nil
        isCommentFocused = false
        
        // Update comment count in post
        postsManager.updateCommentCount(postId: post.id, increment: true)
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}
```

With:
```swift
private func submitComment() {
    guard !commentText.isEmpty else { return }
    
    Task {
        if let replyingTo = replyingTo, let parentCommentId = replyingTo.id {
            // This is a reply
            await interactionsVM.addReply(
                to: parentCommentId,
                in: post.id.uuidString,
                content: commentText,
                mentionedUserIds: nil
            )
        } else {
            // This is a top-level comment
            await interactionsVM.addComment(
                to: post.id.uuidString,
                content: commentText,
                mentionedUserIds: nil
            )
        }
        
        commentText = ""
        replyingTo = nil
        isCommentFocused = false
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}
```

#### E. Add Lifecycle

Add before the closing brace of `body`:
```swift
.onAppear {
    Task {
        await interactionsVM.fetchComments(for: post.id.uuidString)
        interactionsVM.startListeningToComments(for: post.id.uuidString)
    }
}
.onDisappear {
    interactionsVM.stopListeningToComments()
}
```

---

### Task 4: Create FirestoreCommentCardView
**File:** `PostCard.swift` (add at the end before final preview)

Add this new view to display comments from Firestore:

```swift
// MARK: - Firestore Comment Card View

private struct FirestoreCommentCardView: View {
    let commentWithReplies: CommentWithReplies
    @ObservedObject var interactionsVM: PostInteractionsViewModel
    let postId: String
    let onReply: () -> Void
    
    @State private var hasAmened = false
    @State private var showReplyField = false
    @State private var replyText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main Comment
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(commentWithReplies.comment.authorInitials)
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 6) {
                        Text(commentWithReplies.comment.authorName)
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.primary)
                        
                        Text("•")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        Text(commentWithReplies.comment.timeAgo)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Content
                    Text(commentWithReplies.comment.content)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                    
                    // Actions
                    HStack(spacing: 16) {
                        // Amen button
                        Button {
                            Task {
                                guard let commentId = commentWithReplies.comment.id else { return }
                                await interactionsVM.toggleCommentAmen(commentId)
                                hasAmened.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                                    .font(.system(size: 11, weight: .semibold))
                                
                                if commentWithReplies.comment.amenCount > 0 {
                                    Text("\(commentWithReplies.comment.amenCount)")
                                        .font(.custom("OpenSans-SemiBold", size: 12))
                                }
                            }
                            .foregroundStyle(hasAmened ? .black : .secondary)
                        }
                        
                        // Reply button
                        Button {
                            showReplyField.toggle()
                            onReply()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 11))
                                Text("Reply")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        // Reply count if has replies
                        if commentWithReplies.comment.replyCount > 0 {
                            Text("\(commentWithReplies.comment.replyCount) replies")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            
            // Nested Replies
            if !commentWithReplies.replies.isEmpty {
                VStack(spacing: 8) {
                    ForEach(commentWithReplies.replies) { reply in
                        FirestoreReplyView(reply: reply, interactionsVM: interactionsVM)
                    }
                }
                .padding(.leading, 52)  // Indent replies
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}

// MARK: - Firestore Reply View

private struct FirestoreReplyView: View {
    let reply: Comment
    @ObservedObject var interactionsVM: PostInteractionsViewModel
    @State private var hasAmened = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Small avatar
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(reply.authorInitials)
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .foregroundStyle(.green)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reply.authorName)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.primary)
                    
                    Text("•")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text(reply.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Text(reply.content)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                
                // Reply amen button
                Button {
                    Task {
                        guard let replyId = reply.id else { return }
                        await interactionsVM.toggleCommentAmen(replyId)
                        hasAmened.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                            .font(.system(size: 10, weight: .semibold))
                        
                        if reply.amenCount > 0 {
                            Text("\(reply.amenCount)")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                        }
                    }
                    .foregroundStyle(hasAmened ? .black : .secondary)
                }
                .padding(.top, 2)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}
```

---

### Task 5: Update FirebasePostService
**File:** `FirebasePostService.swift`

The `FirestorePost` model needs to include the interaction user IDs. Check if these properties exist:

```swift
struct FirestorePost: Codable, Identifiable {
    // ... existing properties ...
    
    // Make sure these exist:
    var amenUserIds: [String]
    var lightbulbUserIds: [String]
}
```

If they're missing, add them to the struct and to the `init` method.

---

## 🧪 Testing Checklist

Once all tasks are complete:

### Comments
- [ ] Open a post and add a comment
- [ ] Reply to a comment
- [ ] Toggle amen on a comment
- [ ] See nested replies display correctly
- [ ] Verify real-time updates (test with 2 devices/simulators)

### Saved Posts
- [ ] Tap bookmark icon on a post
- [ ] Icon fills in to show it's saved
- [ ] Tap again to unsave
- [ ] Check saved posts list in profile (if implemented)

### Reposts
- [ ] Tap repost button
- [ ] Post appears in your feed as a repost
- [ ] Original post's repost count increases
- [ ] Tap repost again to unrepost
- [ ] Count decreases

### Real-time Sync
- [ ] Open same post on two devices
- [ ] Comment on one device
- [ ] See it appear on other device
- [ ] Same test for saves and reposts

---

## 🔥 Firebase Console Setup

### 1. Firestore Indexes

Go to Firebase Console → Firestore → Indexes and create:

**Comments by Post:**
- Collection: `comments`
- Fields: `postId` (Ascending), `createdAt` (Descending)

**Comments by Parent:**
- Collection: `comments`
- Fields: `parentCommentId` (Ascending), `createdAt` (Descending)

**Saved Posts by User:**
- Collection: `savedPosts`
- Fields: `userId` (Ascending), `savedAt` (Descending)

**Reposts by User:**
- Collection: `reposts`
- Fields: `userId` (Ascending), `repostedAt` (Descending)

### 2. Security Rules

Firebase Console → Firestore → Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Comments
    match /comments/{commentId} {
      allow read: if true;
      allow create: if request.auth != null && 
                    request.resource.data.authorId == request.auth.uid;
      allow update, delete: if request.auth != null && 
                             resource.data.authorId == request.auth.uid;
    }
    
    // Saved Posts
    match /savedPosts/{saveId} {
      allow read, write: if request.auth != null && 
                         request.resource.data.userId == request.auth.uid;
    }
    
    // Reposts
    match /reposts/{repostId} {
      allow read: if true;
      allow create: if request.auth != null && 
                    request.resource.data.userId == request.auth.uid;
      allow delete: if request.auth != null && 
                    resource.data.userId == request.auth.uid;
    }
  }
}
```

---

## ��� Common Errors & Solutions

### Error: "Invalid redeclaration of 'Repost'"
**Solution:** See Step 1 at top of this document

### Error: "Type 'Post' has no member 'amenUserIds'"
**Solution:** Add the properties to Post struct (see Task 1)

### Error: Comments not appearing
**Solution:** 
1. Check Firestore Console - are comments being created?
2. Check security rules allow reading
3. Verify listener is started in `onAppear`

### Error: "Value of type 'PostInteractionsViewModel' has no member..."
**Solution:** Make sure you created `PostInteractionsViewModel.swift`

### Error: Crashes when opening comments
**Solution:** Make sure you removed the local mock `Comment` struct

---

## 📝 Final Notes

- All services use Firebase's real-time listeners for instant updates
- Haptic feedback is included for better UX
- Error handling is built-in with console logging
- All operations are async/await for clean code
- Optimistic updates provide instant feedback

---

**Ready to Build!** 🚀

Once you complete all tasks, your post interactions will be fully functional with:
- Real-time comments and replies
- Persistent saved posts
- Repost tracking
- Cloud sync across all devices

---

**Last Updated:** January 20, 2026  
**Status:** Ready for implementation  
**Estimated Time:** 1-2 hours
