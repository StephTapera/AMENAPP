# Comment System Quick Reference

## 🎯 Quick Start

### Add a Comment
```swift
let comment = try await commentService.addComment(
    postId: "post123",
    content: "Great post!"
)
```

### Add a Reply
```swift
let reply = try await commentService.addReply(
    postId: "post123",
    parentCommentId: "comment456",
    content: "I agree!"
)
```

### Edit a Comment
```swift
try await commentService.editComment(
    commentId: "comment789",
    postId: "post123",
    newContent: "Updated content"
)
```

### Delete a Comment
```swift
try await commentService.deleteComment(
    commentId: "comment789",
    postId: "post123"
)
```

### Like/Unlike a Comment
```swift
try await commentService.toggleAmen(commentId: "comment789")
```

---

## 📡 Real-Time Listening

### Start Listening
```swift
commentService.startListening(to: postId)
```

### Stop Listening
```swift
commentService.stopListening()
```

### Access Real-Time Data
```swift
// In your view:
private var comments: [Comment] {
    commentService.comments[post.id.uuidString] ?? []
}

private var replies: [Comment] {
    commentService.commentReplies[comment.id ?? ""] ?? []
}
```

---

## 🎨 UI Components

### Display Comments
```swift
ForEach(comments) { comment in
    RealCommentCardView(
        comment: comment,
        postCategory: post.category,
        onReply: { 
            replyingTo = comment 
        }
    )
}
```

### Edit Comment Sheet
```swift
.sheet(isPresented: $showEditSheet) {
    EditCommentSheet(comment: comment)
}
```

---

## 🔐 Permission Checks

### Check Ownership
```swift
private var isUserComment: Bool {
    guard let currentUserId = Auth.auth().currentUser?.uid else { 
        return false 
    }
    return comment.authorId == currentUserId
}
```

### Show Menu Only for Own Comments
```swift
if isUserComment {
    Menu {
        Button("Edit") { showEditSheet = true }
        Button("Delete", role: .destructive) { showDeleteAlert = true }
    } label: {
        Image(systemName: "ellipsis")
    }
}
```

---

## 📊 Data Model

### Comment Structure
```swift
struct Comment {
    var id: String?
    var postId: String
    var authorId: String
    var authorName: String
    var authorUsername: String
    var authorInitials: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isEdited: Bool          // NEW: Shows if edited
    var amenCount: Int
    var lightbulbCount: Int
    var replyCount: Int
    var amenUserIds: [String]
    var parentCommentId: String?  // nil = top-level, set = reply
}
```

---

## 🎭 Interaction States

### Track Like State
```swift
@State private var hasLiked = false
@State private var likeCount = 0

// On appear:
hasLiked = await commentService.hasUserAmened(commentId: commentId)

// On toggle:
try await commentService.toggleAmen(commentId: commentId)
withAnimation {
    hasLiked.toggle()
    likeCount += hasLiked ? 1 : -1
}
```

### Track Reply Expansion
```swift
@State private var showReplies = false

// Button:
Button {
    withAnimation {
        showReplies.toggle()
    }
} label: {
    HStack {
        Image(systemName: showReplies ? "chevron.down" : "chevron.right")
        Text("\(replies.count) replies")
    }
}

// Content:
if showReplies {
    ForEach(replies) { reply in
        RealCommentCardView(comment: reply, ...)
            .padding(.leading, 40)  // Indent
    }
}
```

---

## 🔥 Common Patterns

### Submit Comment with Reply Support
```swift
private func submitComment() async {
    if let replyingTo = replyingTo {
        // Submit as reply
        _ = try await commentService.addReply(
            postId: post.id.uuidString,
            parentCommentId: replyingTo.id ?? "",
            content: commentText
        )
    } else {
        // Submit as top-level comment
        _ = try await commentService.addComment(
            postId: post.id.uuidString,
            content: commentText
        )
    }
    
    // Clear state
    commentText = ""
    replyingTo = nil
}
```

### Optimistic UI Updates
```swift
// Update UI immediately
withAnimation {
    hasLiked.toggle()
    likeCount += hasLiked ? 1 : -1
}

// Then sync with server
Task {
    do {
        try await commentService.toggleAmen(commentId: commentId)
        // Success - already updated
    } catch {
        // Revert on error
        withAnimation {
            hasLiked.toggle()
            likeCount -= hasLiked ? 1 : -1
        }
    }
}
```

---

## 🎯 Visual Indicators

### Edited Badge
```swift
if comment.isEdited {
    Text("• edited")
        .font(.custom("OpenSans-Regular", size: 12))
        .foregroundStyle(.secondary.opacity(0.7))
}
```

### Active Reaction Glow
```swift
if hasLiked {
    Image(systemName: "lightbulb.fill")
        .foregroundStyle(.yellow)
        .blur(radius: 6)
        .opacity(0.6)
}

Image(systemName: hasLiked ? "lightbulb.fill" : "lightbulb")
    .foregroundStyle(hasLiked ? 
        LinearGradient(colors: [.yellow, .orange], ...) :
        LinearGradient(colors: [.secondary, .secondary], ...)
    )
```

---

## ⚡ Performance Tips

1. **Use computed properties** for real-time data (not @State)
2. **Stop listeners** when view disappears
3. **Use LazyVStack** for long comment lists
4. **Implement pagination** for 100+ comments
5. **Cache user profiles** to avoid repeated fetches

---

## 🐛 Debugging

### Check Listener Status
```swift
print("Active listeners: \(commentService.listenerPaths.count)")
```

### Verify Data Structure
```swift
print("Comments for post: \(commentService.comments[postId]?.count ?? 0)")
print("Replies for comment: \(commentService.commentReplies[commentId]?.count ?? 0)")
```

### Test Permissions
```swift
// Should fail if not comment author:
try await commentService.deleteComment(commentId: "someone_elses_comment", postId: "post123")
// Error: "You can only delete your own comments"
```

---

## 📱 Complete Flow Example

```swift
struct CommentsView: View {
    @StateObject private var commentService = CommentService.shared
    let post: Post
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    
    private var comments: [Comment] {
        commentService.comments[post.id.uuidString] ?? []
    }
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(comments) { comment in
                    RealCommentCardView(
                        comment: comment,
                        postCategory: post.category,
                        onReply: { replyingTo = comment }
                    )
                }
            }
            
            // Input field
            TextField("Comment...", text: $commentText)
            Button("Send") { submitComment() }
        }
        .onAppear {
            commentService.startListening(to: post.id.uuidString)
        }
        .onDisappear {
            commentService.stopListening()
        }
    }
    
    private func submitComment() {
        Task {
            if let replyingTo = replyingTo {
                _ = try await commentService.addReply(
                    postId: post.id.uuidString,
                    parentCommentId: replyingTo.id ?? "",
                    content: commentText
                )
            } else {
                _ = try await commentService.addComment(
                    postId: post.id.uuidString,
                    content: commentText
                )
            }
            commentText = ""
            replyingTo = nil
        }
    }
}
```

---

## ✅ Feature Checklist

- [x] Add top-level comments
- [x] Add nested replies
- [x] Like/unlike comments (lightbulb/amen)
- [x] Real-time count updates
- [x] View nested replies (collapsible)
- [x] Edit own comments
- [x] Delete own comments
- [x] Edited badge display
- [x] Permission validation
- [x] Optimistic UI updates
- [x] Error handling
- [x] Clean up listeners

---

## 🎊 You're All Set!

Your comment system now has:
✅ Full CRUD operations  
✅ Real-time synchronization  
✅ Nested replies  
✅ Like/reaction support  
✅ Edit/delete with validation  
✅ Beautiful UI with animations  

Happy coding! 🚀
