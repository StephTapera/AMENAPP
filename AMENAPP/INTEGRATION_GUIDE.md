# Post Interactions Integration Guide

## Overview

This guide explains how to integrate the Firestore-backed post interaction features (comments, saves, reposts) into your AMENAPP UI.

---

## ✅ What's Already Done

### Models (`PostInteractionModels.swift`)
- ✅ `Comment` - with support for replies
- ✅ `SavedPost` - with optional collections
- ✅ `Repost` - with optional quote comments
- ✅ `PostMention` - for @mentions
- ✅ `CommentWithReplies` - helper for nested display

### Services (Fully Implemented)
- ✅ `CommentService.swift` - Complete CRUD for comments/replies
- ✅ `SavedPostsService.swift` - Save/unsave posts
- ✅ `RepostService.swift` - Repost/unrepost functionality

### View Model
- ✅ `PostInteractionsViewModel.swift` - Unified interface

---

## 🔧 Integration Steps

### Step 1: Fix the Duplicate `Repost` Error

**IN XCODE:**
1. Press `⌘ + Shift + F` (Find in Project)
2. Search for: **`struct Repost`**
3. You should find at least 2 files defining this struct
4. Keep the one in `PostInteractionModels.swift`
5. Delete the duplicate from any other file

**Common places duplicates might be:**
- Old backup files
- Inside a "Models.swift" or "SocialModels.swift" file
- Inside service files (though I checked and didn't find it there)

---

### Step 2: Update PostCard to Use Firestore Services

The current `PostCard.swift` uses mock data and `PostsManager`. Update it to use the new services:

#### A. Add View Model to PostCard

```swift
struct PostCard: View {
    let post: Post?
    // ... existing properties ...
    
    // ADD THIS:
    @StateObject private var interactionsVM = PostInteractionsViewModel()
    
    // ... rest of the code ...
}
```

#### B. Update the Save/Bookmark Button

Replace the current save button implementation with:

```swift
// Save/Bookmark Button
Button {
    Task {
        if let post = post, let postId = post.id {
            await interactionsVM.toggleSavePost(postId.uuidString)
        }
    }
} label: {
    Image(systemName: interactionsVM.isPostSaved(post?.id.uuidString ?? "") ? "bookmark.fill" : "bookmark")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(interactionsVM.isPostSaved(post?.id.uuidString ?? "") ? .black : .black.opacity(0.5))
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

#### C. Update the Repost Button

Replace the current repost button to check if already reposted:

```swift
// Repost Button
Button {
    Task {
        if let post = post, let postId = post.id {
            await interactionsVM.toggleRepost(postId.uuidString)
        }
    }
} label: {
    HStack(spacing: 4) {
        Image(systemName: interactionsVM.hasReposted(post?.id.uuidString ?? "") ? "arrow.2.squarepath.fill" : "arrow.2.squarepath")
            .font(.system(size: 12, weight: .semibold))
        if let post = post, post.repostCount > 0 {
            Text("\(post.repostCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
                .contentTransition(.numericText())
        }
    }
    .foregroundStyle(interactionsVM.hasReposted(post?.id.uuidString ?? "") ? .black : .black.opacity(0.5))
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

Add these to `PostCard`:

```swift
.onAppear {
    // Start listening to saved posts and reposts
    interactionsVM.startListeningToSavedPosts()
    interactionsVM.startListeningToReposts()
}
.onDisappear {
    // Clean up listeners
    interactionsVM.cleanup()
}
```

---

### Step 3: Update PostCommentsView to Use Real Comments

The current `PostCommentsView` uses mock comments. Update it:

#### A. Add View Model

```swift
struct PostCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var interactionsVM = PostInteractionsViewModel()
    
    let post: Post
    @State private var commentText = ""
    @FocusState private var isCommentFocused: Bool
    
    // Remove the mock Comment struct and use the real one from PostInteractionModels.swift
    
    var body: some View {
        // ... existing UI ...
    }
}
```

#### B. Update to Fetch Real Comments

```swift
.onAppear {
    Task {
        if let postId = post.id {
            // Fetch real comments from Firestore
            await interactionsVM.fetchComments(for: postId.uuidString)
            // Start real-time listener
            interactionsVM.startListeningToComments(for: postId.uuidString)
        }
    }
}
.onDisappear {
    interactionsVM.stopListeningToComments()
}
```

#### C. Update Comment Submission

```swift
private func submitComment() {
    guard !commentText.isEmpty else { return }
    guard let postId = post.id else { return }
    
    Task {
        await interactionsVM.addComment(
            to: postId.uuidString,
            content: commentText,
            mentionedUserIds: nil  // TODO: Parse @mentions from text
        )
        
        commentText = ""
        isCommentFocused = false
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}
```

#### D. Display Real Comments

Update the comments list to use `interactionsVM.comments`:

```swift
if interactionsVM.comments.isEmpty {
    // Empty state
} else {
    LazyVStack(spacing: 12) {
        ForEach(interactionsVM.comments) { commentWithReplies in
            RealCommentCardView(
                commentWithReplies: commentWithReplies,
                interactionsVM: interactionsVM,
                postId: post.id?.uuidString ?? ""
            )
        }
    }
    .padding(.horizontal, 16)
}
```

---

### Step 4: Create Real Comment Card View

Replace the mock `CommentCardView` with one that uses real data:

```swift
struct RealCommentCardView: View {
    let commentWithReplies: CommentWithReplies
    @ObservedObject var interactionsVM: PostInteractionsViewModel
    let postId: String
    
    @State private var showReplyField = false
    @State private var replyText = ""
    @State private var hasAmened = false
    
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
                                if let commentId = commentWithReplies.comment.id {
                                    await interactionsVM.toggleCommentAmen(commentId)
                                }
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
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 11))
                                Text("Reply")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    
                    // Reply field
                    if showReplyField {
                        HStack(spacing: 8) {
                            TextField("Write a reply...", text: $replyText)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemGray6))
                                )
                            
                            Button {
                                Task {
                                    if let commentId = commentWithReplies.comment.id {
                                        await interactionsVM.addReply(
                                            to: commentId,
                                            in: postId,
                                            content: replyText,
                                            mentionedUserIds: nil
                                        )
                                        replyText = ""
                                        showReplyField = false
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.blue)
                            }
                            .disabled(replyText.isEmpty)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Spacer()
            }
            
            // Nested Replies
            if !commentWithReplies.replies.isEmpty {
                VStack(spacing: 8) {
                    ForEach(commentWithReplies.replies) { reply in
                        ReplyCellView(reply: reply, interactionsVM: interactionsVM)
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

struct ReplyCellView: View {
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
                        if let replyId = reply.id {
                            await interactionsVM.toggleCommentAmen(replyId)
                        }
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

## 🎯 Testing Checklist

Once integrated, test these features:

### Comments
- [ ] Add a comment to a post
- [ ] Reply to a comment
- [ ] Toggle amen on a comment
- [ ] View nested replies
- [ ] Real-time updates when others comment

### Saved Posts
- [ ] Save a post
- [ ] Unsave a post
- [ ] View saved posts in profile
- [ ] Save to collections (if implemented)
- [ ] Real-time sync across devices

### Reposts
- [ ] Repost to your profile
- [ ] Unrepost
- [ ] View repost count updates
- [ ] Quote repost (with comment)
- [ ] See original author attribution

---

## 📊 Firestore Structure

Your data is organized as:

```
firestore/
├── posts/
│   └── {postId}/
│       ├── content, author, counts, etc.
│       
├── comments/
│   └── {commentId}/
│       ├── postId
│       ├── parentCommentId (null for top-level)
│       ├── content, author, counts, etc.
│
├── savedPosts/
│   └── {saveId}/
│       ├── userId
│       ├── postId
│       ├── savedAt
│       └── collectionName (optional)
│
└── reposts/
    └── {repostId}/
        ├── userId
        ├── originalPostId
        ├── repostedAt
        └── withComment (optional quote)
```

---

## 🔐 Security Rules

Add these to Firebase Console → Firestore → Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Comments: anyone can read, authenticated users can create
    match /comments/{commentId} {
      allow read: if true;
      allow create: if request.auth != null && request.resource.data.authorId == request.auth.uid;
      allow update, delete: if request.auth != null && resource.data.authorId == request.auth.uid;
    }
    
    // Saved Posts: only owner can read/write
    match /savedPosts/{saveId} {
      allow read, write: if request.auth != null && request.resource.data.userId == request.auth.uid;
    }
    
    // Reposts: anyone can read, owner can create/delete
    match /reposts/{repostId} {
      allow read: if true;
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow delete: if request.auth != null && resource.data.userId == request.auth.uid;
    }
  }
}
```

---

## 🚀 Next Steps

After integration:

1. **Add @mentions parsing**: Extract usernames from comment text
2. **Add notifications**: Notify users when mentioned or replied to
3. **Add comment moderation**: Report/delete inappropriate comments
4. **Add saved collections UI**: Let users organize saved posts
5. **Add quote repost UI**: Show comment with repost
6. **Pagination**: Load comments in batches for performance

---

## 📞 Troubleshooting

### Comments not appearing?
- Check Firestore rules allow reading
- Verify listener is started
- Check console for errors

### Can't save/repost?
- Ensure user is authenticated
- Check Firestore rules
- Verify post IDs are valid strings

### Real-time updates not working?
- Ensure listeners are started in `onAppear`
- Check network connection
- Verify Firestore setup

---

**Last Updated:** January 20, 2026  
**Status:** Ready for integration  
**Dependencies:** FirebaseFirestore, FirebaseAuth
