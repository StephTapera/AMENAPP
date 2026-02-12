# UserProfileView Production-Ready Fix

## Issues Identified

### 1. **Comment Button Not Working**
- **Problem**: `handleReply(postId: String)` tries to fetch Post by String ID, but Post model uses UUID
- **Symptom**: Comments sheet doesn't open when tapping comment button
- **Root Cause**: Type mismatch between ProfilePost.id (String) and Post.id (UUID)

### 2. **Swipe Gestures Not Implemented**
- **Problem**: SwipeDirection enum exists but swipe gesture handler not connected
- **Symptom**: Cannot swipe to comment or like posts
- **Root Cause**: No `.gesture()` modifier attached to card

### 3. **Post ID Conversion Issues**  
- **Problem**: ProfilePost uses String IDs from Firestore, Post model uses UUID
- **Symptom**: Errors when trying to convert between types
- **Root Cause**: Inconsistent ID types across data models

## Solution

### Fix 1: Update ProfilePost to Store UUID String

**File**: `UserProfileView.swift` (Line 14-52)

```swift
struct ProfilePost: Identifiable {
    let id: String  // Keep as String (Firestore document ID)
    let firestoreId: String  // Actual Firestore ID
    let content: String
    let timestamp: String
    var likes: Int
    var replies: Int
    let postType: PostType?
    let createdAt: Date
    let authorId: String  // ✅ ADD: For fetching full post
    let authorName: String  // ✅ ADD: For display
    
    // ... rest of struct
}
```

### Fix 2: Update handleReply to Use Firestore ID

**File**: `UserProfileView.swift` (handleReply function)

**REPLACE:**
```swift
private func handleReply(postId: String) {
    let haptic = UIImpactFeedbackGenerator(style: .light)
    haptic.impactOccurred()
    
    // Fetch full post and show comments
    Task {
        do {
            let firebasePostService = FirebasePostService.shared
            // Fetch the full post object by ID
            if let post = try await firebasePostService.fetchPostById(postId: postId) {
                await MainActor.run {
                    selectedPostForComments = post
                    showCommentsSheet = true
                }
            } else {
                print("⚠️ Post not found: \(postId)")
            }
        } catch {
            print("❌ Failed to fetch post for comments: \(error)")
        }
    }
}
```

**WITH:**
```swift
private func handleReply(postId: String) {
    let haptic = UIImpactFeedbackGenerator(style: .light)
    haptic.impactOccurred()
    
    print("💬 Opening comments for post: \(postId)")
    
    // Fetch full post and show comments
    Task {
        do {
            let db = Firestore.firestore()
            
            // Fetch post document from Firestore
            let postDoc = try await db.collection("posts").document(postId).getDocument()
            
            guard postDoc.exists, let data = postDoc.data() else {
                print("⚠️ Post not found: \(postId)")
                await MainActor.run {
                    inlineErrorMessage = "Post not found"
                    showInlineError = true
                }
                return
            }
            
            // Convert to Post object
            guard let uuidString = data["id"] as? String,
                  let postUUID = UUID(uuidString: uuidString) else {
                print("❌ Invalid post UUID")
                return
            }
            
            let post = Post(
                id: postUUID,
                authorId: data["authorId"] as? String ?? data["userId"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "Unknown",
                authorUsername: data["authorUsername"] as? String ?? "unknown",
                authorInitials: data["authorInitials"] as? String ?? "??",
                content: data["content"] as? String ?? "",
                category: PostCategory(rawValue: data["category"] as? String ?? "openTable") ?? .openTable,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                amenCount: data["amenCount"] as? Int ?? 0,
                lightbulbCount: data["lightbulbCount"] as? Int ?? 0,
                repostCount: data["repostCount"] as? Int ?? 0,
                commentCount: data["commentCount"] as? Int ?? 0,
                imageURL: data["imageURL"] as? String,
                linkURL: data["linkURL"] as? String,
                topicTag: data["topicTag"] as? String,
                visibility: PostVisibility(rawValue: data["visibility"] as? String ?? "public") ?? .public,
                isPinned: data["isPinned"] as? Bool ?? false,
                profileImageURL: data["profileImageURL"] as? String
            )
            
            await MainActor.run {
                selectedPostForComments = post
                showCommentsSheet = true
                print("✅ Comments sheet opened for post: \(postId)")
            }
            
        } catch {
            print("❌ Failed to fetch post for comments: \(error)")
            await MainActor.run {
                inlineErrorMessage = "Failed to load comments"
                showInlineError = true
            }
        }
    }
}
```

### Fix 3: Add Swipe Gesture to ReadOnlyProfilePostCard

**File**: `UserProfileView.swift` (ReadOnlyProfilePostCard)

**ADD after the card's main VStack:**

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        // ... existing content ...
    }
    .background(Color.white)
    .cornerRadius(12)
    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
    )
    .offset(x: swipeOffset)  // ✅ ADD: Swipe animation
    .gesture(
        DragGesture()
            .onChanged { value in
                // Only allow horizontal swipe
                let horizontalAmount = value.translation.width
                
                // Limit swipe distance
                if abs(horizontalAmount) > 5 {
                    withAnimation(.interactiveSpring()) {
                        swipeOffset = min(max(horizontalAmount, -80), 80)
                    }
                }
                
                // Determine direction
                if horizontalAmount > 40 {
                    swipeDirection = .right  // Amen/Like
                } else if horizontalAmount < -40 {
                    swipeDirection = .left  // Comment
                } else {
                    swipeDirection = nil
                }
            }
            .onEnded { value in
                let horizontalAmount = value.translation.width
                
                // Trigger action if swiped far enough
                if horizontalAmount > 60 {
                    // Swipe right = Like/Amen
                    onLike()
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                } else if horizontalAmount < -60 {
                    // Swipe left = Comment
                    onReply()
                    
                    // Success haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
                
                // Reset swipe
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    swipeOffset = 0
                    swipeDirection = nil
                }
            }
    )
    .overlay(
        // Swipe hint icons
        Group {
            if let direction = swipeDirection {
                ZStack {
                    if direction == .right {
                        // Amen icon (right side)
                        HStack {
                            Spacer()
                            Image(systemName: "hands.clap.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                                .padding(16)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.8))
                                )
                                .padding(.trailing, 16)
                        }
                    } else {
                        // Comment icon (left side)
                        HStack {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                                .padding(16)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.8))
                                )
                                .padding(.leading, 16)
                            Spacer()
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    )
}
```

### Fix 4: Update Post Loading to Include All Required Fields

**File**: `UserProfileView.swift` (loadProfileData or wherever posts are fetched)

**When converting Firestore data to ProfilePost, ensure:**

```swift
// Example transformation
let profilePost = ProfilePost(
    id: doc.documentID,  // Use Firestore document ID
    firestoreId: doc.documentID,
    content: data["content"] as? String ?? "",
    timestamp: formatTimestamp(data["createdAt"] as? Timestamp),
    likes: data["amenCount"] as? Int ?? 0,
    replies: data["commentCount"] as? Int ?? 0,
    postType: determinePostType(data["category"] as? String),
    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
    authorId: data["authorId"] as? String ?? data["userId"] as? String ?? "",  // ✅ ADD
    authorName: data["authorName"] as? String ?? "Unknown"  // ✅ ADD
)
```

## Testing Checklist

After applying fixes:

- [ ] **Comment Button**: Tap comment button → Comments sheet opens
- [ ] **Swipe Right**: Swipe post card right → Amen/Like triggers
- [ ] **Swipe Left**: Swipe post card left → Comments sheet opens
- [ ] **Swipe Animation**: Swipe shows visual feedback (icons appear)
- [ ] **Error Handling**: Invalid post shows error message
- [ ] **No Console Errors**: Check for "Post not found" or UUID conversion errors

## Performance Considerations

1. **Lazy Loading**: Posts use `LazyVStack` ✅ Already implemented
2. **Smart Prefetch**: Loads more posts before reaching end ✅ Already implemented  
3. **Haptic Feedback**: All interactions have appropriate haptics ✅ Add to swipes
4. **Error Recovery**: Inline error banners instead of blocking alerts ✅ Implemented

## Additional Improvements (Optional)

### 1. Add Loading State for Comments
```swift
@State private var isLoadingComments = false

// In handleReply:
isLoadingComments = true
defer { isLoadingComments = false }
```

### 2. Cache Fetched Posts
```swift
private var postCache: [String: Post] = [:]

// Check cache before fetching
if let cachedPost = postCache[postId] {
    selectedPostForComments = cachedPost
    showCommentsSheet = true
    return
}
```

### 3. Add Swipe Tutorial Hint
```swift
@AppStorage("hasSeenSwipeTutorial") private var hasSeenSwipeTutorial = false

// Show on first visit
if !hasSeenSwipeTutorial {
    // Show tutorial overlay
}
```

## Summary

**Files to Modify:**
1. `UserProfileView.swift` - Main fixes for comment handling and swipe gestures

**Key Changes:**
- ✅ Fix handleReply to properly fetch Post from Firestore
- ✅ Add swipe gesture handling to ReadOnlyProfilePostCard
- ✅ Add visual feedback for swipe actions
- ✅ Proper error handling with inline messages

**Result:**
- Fully functional comment button
- Swipe-to-interact functionality
- Production-ready error handling
- Smooth animations and haptics

---
**Date Created**: 2026-02-11  
**Priority**: High - Blocks user engagement features  
**Estimated Implementation Time**: 30-45 minutes
