# Comment System - Quick Reference Guide

## For Developers: How to Add Comments to Any New View

### Step 1: Import CommentService
```swift
@StateObject private var commentService = CommentService.shared
```

### Step 2: Set Up State Variables
```swift
@State private var comments: [Comment] = []
@State private var commentText = ""
@State private var isLoading = false
@FocusState private var isCommentFocused: Bool
```

### Step 3: Load Comments on View Appear
```swift
.task {
    await loadComments()
}

private func loadComments() async {
    isLoading = true
    
    do {
        let fetchedComments = try await commentService.fetchComments(
            for: post.id.uuidString
        )
        
        await MainActor.run {
            // Only top-level comments (not replies)
            self.comments = fetchedComments.filter { $0.parentCommentId == nil }
            isLoading = false
        }
    } catch {
        print("❌ Failed to load comments: \(error)")
        await MainActor.run {
            isLoading = false
        }
    }
}
```

### Step 4: Add Real-Time Listeners
```swift
.onAppear {
    commentService.startListening(to: post.id.uuidString)
}
.onDisappear {
    commentService.stopListening()
}
```

### Step 5: Post a Comment
```swift
private func postComment() async {
    guard !commentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    
    do {
        let newComment = try await commentService.addComment(
            postId: post.id.uuidString,
            content: commentText
        )
        
        await MainActor.run {
            comments.insert(newComment, at: 0)
            commentText = ""
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    } catch {
        print("❌ Failed to post comment: \(error)")
    }
}
```

### Step 6: Display Comments
```swift
VStack(spacing: 12) {
    ForEach(comments) { comment in
        CommentRow(comment: comment)
    }
}
```

### Step 7: Create Comment Row View
```swift
struct CommentRow: View {
    let comment: Comment
    @State private var hasAmened = false
    @State private var amenCount: Int
    @StateObject private var commentService = CommentService.shared
    
    init(comment: Comment) {
        self.comment = comment
        _amenCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(comment.authorInitials)
                        .font(.custom("OpenSans-Bold", size: 13))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Author and timestamp
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-Bold", size: 13))
                    
                    Text(comment.createdAt.timeAgoDisplay())
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
                
                // Content
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: 13))
                
                // Actions
                HStack(spacing: 16) {
                    // Amen button
                    Button {
                        Task {
                            guard let commentId = comment.id else { return }
                            try await commentService.toggleAmen(commentId: commentId)
                            
                            await MainActor.run {
                                withAnimation {
                                    hasAmened.toggle()
                                    amenCount += hasAmened ? 1 : -1
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                                .font(.system(size: 11, weight: .semibold))
                            if amenCount > 0 {
                                Text("\(amenCount)")
                                    .font(.custom("OpenSans-SemiBold", size: 10))
                            }
                        }
                    }
                    
                    // Reply button
                    Button("Reply") {
                        // Handle reply
                    }
                    .font(.custom("OpenSans-SemiBold", size: 11))
                }
            }
        }
    }
}
```

---

## Common Patterns

### Pattern 1: Inline Comment Preview
Show first comment with "View all" button:

```swift
if showComments {
    CommentSection(
        post: post,
        commentCount: $commentCount,
        showPreviewOnly: true,
        onExpandComments: {
            showFullCommentSheet = true
        }
    )
}
```

### Pattern 2: Full Comment Sheet
Full-screen comment view with input:

```swift
.sheet(isPresented: $showFullCommentSheet) {
    CommentsView(post: post, commentCount: $commentCount)
}
```

### Pattern 3: Quick Response Chips
Pre-written responses for faster engagement:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        ForEach(["Amen! 🙏", "Praying for you", "God is faithful"], id: \.self) { response in
            Button {
                commentText = response
                isCommentFocused = true
            } label: {
                Text(response)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.gray.opacity(0.1)))
            }
        }
    }
}
```

---

## API Reference

### CommentService Methods

#### Fetch Comments
```swift
func fetchComments(for postId: String) async throws -> [Comment]
```
Returns all top-level comments for a post (excludes replies).

#### Add Comment
```swift
func addComment(
    postId: String,
    content: String,
    mentionedUserIds: [String]? = nil
) async throws -> Comment
```
Creates a new comment. Returns the created comment with ID.

#### Add Reply
```swift
func addReply(
    postId: String,
    parentCommentId: String,
    content: String,
    mentionedUserIds: [String]? = nil
) async throws -> Comment
```
Creates a reply to an existing comment.

#### Toggle Amen
```swift
func toggleAmen(commentId: String) async throws
```
Adds or removes the current user's "Amen" on a comment.

#### Delete Comment
```swift
func deleteComment(commentId: String) async throws
```
Deletes a comment and all its replies. Only the author can delete.

#### Edit Comment
```swift
func editComment(commentId: String, newContent: String) async throws
```
Updates comment content. Only the author can edit.

#### Start Listening
```swift
func startListening(to postId: String)
```
Starts real-time listener for comments on a post.

#### Stop Listening
```swift
func stopListening()
```
Removes all active listeners. Call in `.onDisappear`.

---

## Comment Model

```swift
struct Comment: Identifiable, Codable {
    var id: String?
    let postId: String
    let authorId: String
    let authorName: String
    let authorUsername: String
    let authorInitials: String
    var authorProfileImageURL: String?
    let content: String
    var parentCommentId: String?
    var amenCount: Int
    var amenUserIds: [String]
    var lightbulbCount: Int
    var replyCount: Int
    var mentionedUserIds: [String]?
    let createdAt: Date
    var updatedAt: Date
    
    // Computed property for time ago display
    var timeAgo: String {
        createdAt.timeAgoDisplay()
    }
}
```

---

## Best Practices

### ✅ DO:
- Always use `@StateObject` for `CommentService`
- Always call `startListening()` in `.onAppear`
- Always call `stopListening()` in `.onDisappear`
- Filter top-level comments: `filter { $0.parentCommentId == nil }`
- Use `Task {}` wrapper for async comment operations
- Show loading states while fetching
- Provide haptic feedback on user actions
- Update local state optimistically for instant feedback

### ❌ DON'T:
- Don't use `@ObservedObject` - use `@StateObject`
- Don't forget to stop listeners on dismiss
- Don't fetch comments synchronously
- Don't skip error handling
- Don't forget to check for empty/nil comment IDs

---

## Error Handling

```swift
do {
    let comment = try await commentService.addComment(
        postId: post.id.uuidString,
        content: commentText
    )
    // Success - update UI
} catch FirebaseError.unauthorized {
    print("User not authenticated")
    // Show login prompt
} catch FirebaseError.documentNotFound {
    print("Post or user not found")
    // Show error message
} catch {
    print("❌ Failed to add comment: \(error)")
    // Show generic error message
}
```

---

## Firestore Security Rules (Recommended)

```javascript
match /comments/{commentId} {
  // Anyone can read comments
  allow read: if true;
  
  // Only authenticated users can create comments
  allow create: if request.auth != null 
    && request.resource.data.authorId == request.auth.uid;
  
  // Only comment author can update/delete
  allow update, delete: if request.auth != null 
    && resource.data.authorId == request.auth.uid;
}
```

---

## Testing Your Implementation

### Manual Testing Checklist:
- [ ] Comments load on view appear
- [ ] Loading indicator shows while fetching
- [ ] New comments appear instantly after posting
- [ ] Comment count updates correctly
- [ ] Amen button toggles correctly
- [ ] Amen count increments/decrements
- [ ] Real-time updates work (test with 2 devices)
- [ ] Deleting comments works
- [ ] Comments persist after app restart
- [ ] Profile images display correctly
- [ ] Timestamps show correct "time ago" format

### Unit Testing:
```swift
import Testing

@Test("Load comments for post")
func testLoadComments() async throws {
    let service = CommentService.shared
    let postId = "test-post-123"
    
    let comments = try await service.fetchComments(for: postId)
    
    #expect(comments.count > 0)
    #expect(comments.allSatisfy { $0.postId == postId })
}
```

---

## Performance Tips

1. **Pagination** (for posts with many comments):
```swift
func fetchComments(for postId: String, limit: Int = 50) async throws -> [Comment]
```

2. **Cache Management**:
```swift
// CommentService maintains local cache
// Access via: commentService.comments[postId]
```

3. **Optimistic Updates**:
```swift
// Update UI immediately
comments.insert(newComment, at: 0)

// Then sync to backend
Task {
    await syncToBackend()
}
```

---

## Need Help?

Common issues and solutions:

**Issue**: Comments not appearing
- Check Firebase connection
- Verify `postId` is correct
- Check Firestore security rules

**Issue**: Real-time updates not working
- Ensure `startListening()` is called
- Check listener isn't being stopped prematurely
- Verify network connection

**Issue**: Comment count not updating
- Check if `commentCount` binding is passed correctly
- Verify post document exists in Firestore
- Check for errors in console

---

## Examples in Codebase

Reference implementations:
- **Testimonies**: `TestimoniesView.swift` → `TestimonyCommentSection`
- **Prayers**: `PrayerView.swift` → `PrayerCommentSection`
- **OpenTable**: `PostCard.swift` → `PostCommentsView`

All three use the same patterns and `CommentService` backend!
