# 🎯 Quick Developer Guide: Implementing Reaction Buttons

## Overview
This guide shows you how to implement Firebase-synced reaction buttons in any view.

---

## ✅ Step 1: Import Required Services

```swift
import SwiftUI
import FirebaseAuth
import FirebaseDatabase
```

---

## ✅ Step 2: Add State Variables

```swift
struct YourPostCard: View {
    let post: Post
    
    @StateObject private var interactionsService = PostInteractionsService.shared
    @State private var hasAmened = false
    @State private var hasReposted = false
    @State private var hasSaved = false
    @State private var amenCount: Int
    @State private var commentCount: Int
    @State private var repostCount: Int
    
    init(post: Post) {
        self.post = post
        // Initialize with post's current counts
        _amenCount = State(initialValue: post.amenCount)
        _commentCount = State(initialValue: post.commentCount)
        _repostCount = State(initialValue: post.repostCount)
    }
    
    // ... rest of view
}
```

---

## ✅ Step 3: Create Reaction Button UI

```swift
private var amenButton: some View {
    Button {
        Task {
            await toggleAmen()
        }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                .font(.system(size: 12, weight: .semibold))
            Text("\(amenCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(hasAmened ? Color.black : Color.black.opacity(0.5))
        .contentTransition(.numericText())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(hasAmened ? Color.white : Color.black.opacity(0.05))
                .shadow(color: hasAmened ? Color.black.opacity(0.15) : Color.clear, radius: 8, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(hasAmened ? Color.black.opacity(0.2) : Color.black.opacity(0.1), 
                       lineWidth: hasAmened ? 1.5 : 1)
        )
    }
}
```

---

## ✅ Step 4: Implement Toggle Function with Optimistic Update

```swift
private func toggleAmen() async {
    // STEP 1: Optimistic UI update (instant feedback)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
        hasAmened.toggle()
        amenCount = hasAmened ? amenCount + 1 : amenCount - 1
    }
    
    // STEP 2: Haptic feedback
    let haptic = UIImpactFeedbackGenerator(style: hasAmened ? .medium : .light)
    haptic.impactOccurred()
    
    // STEP 3: Background sync to Firebase
    let postId = post.id.uuidString
    let currentAmenState = hasAmened
    
    Task.detached(priority: .userInitiated) {
        do {
            let interactionsService = await PostInteractionsService.shared
            try await interactionsService.toggleAmen(postId: postId)
            print("✅ Amen synced to Firebase")
        } catch {
            print("❌ Failed to sync amen: \(error)")
            
            // STEP 4: Revert on error
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasAmened = !currentAmenState
                    amenCount += currentAmenState ? -1 : 1
                }
            }
        }
    }
}
```

---

## ✅ Step 5: Load Initial States When View Appears

```swift
var body: some View {
    VStack {
        // Your content here
    }
    .task {
        await loadInteractionStates()
    }
}

private func loadInteractionStates() async {
    let postId = post.id.uuidString
    let interactionsService = PostInteractionsService.shared
    
    // Check if user has already interacted
    hasAmened = await interactionsService.hasAmened(postId: postId)
    hasReposted = await interactionsService.hasReposted(postId: postId)
    
    // Load current counts from Firebase
    let counts = await interactionsService.getInteractionCounts(postId: postId)
    amenCount = counts.amenCount
    commentCount = counts.commentCount
    repostCount = counts.repostCount
}
```

---

## ✅ Step 6: (Optional) Add Real-time Listener

For live updates when other users interact:

```swift
.task {
    await loadInteractionStates()
    startRealtimeListener()
}
.onDisappear {
    stopRealtimeListener()
}

private func startRealtimeListener() {
    let postId = post.id.uuidString
    let ref = Database.database().reference()
    
    ref.child("postInteractions").child(postId).observe(.value) { snapshot in
        guard let data = snapshot.value as? [String: Any] else { return }
        
        Task { @MainActor in
            if let amenData = data["amens"] as? [String: Any] {
                self.amenCount = amenData.count
            }
            if let comments = data["comments"] as? [String: Any] {
                self.commentCount = comments.count
            }
            if let reposts = data["reposts"] as? [String: Any] {
                self.repostCount = reposts.count
            }
        }
    }
}

private func stopRealtimeListener() {
    let postId = post.id.uuidString
    let ref = Database.database().reference()
    ref.child("postInteractions").child(postId).removeAllObservers()
}
```

---

## 🎨 UI Variations

### Minimal Button (Icon + Count Only)
```swift
HStack(spacing: 4) {
    Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
        .font(.system(size: 14))
    Text("\(amenCount)")
        .font(.caption)
}
.foregroundStyle(hasAmened ? .blue : .secondary)
```

### With Animation on Tap
```swift
.scaleEffect(isPressed ? 0.9 : 1.0)
.animation(.spring(response: 0.3), value: isPressed)
```

### With Bounce Effect
```swift
.symbolEffect(.bounce, value: hasAmened)
```

---

## 📱 Comment Button Example

```swift
private var commentButton: some View {
    Button {
        showCommentsSheet = true
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("\(commentCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.gray.opacity(0.1)))
    }
}
.sheet(isPresented: $showCommentsSheet) {
    CommentsView(post: post)
}
```

---

## 🔄 Repost Button Example

```swift
private var repostButton: some View {
    Button {
        Task {
            await toggleRepost()
        }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: hasReposted ? "arrow.2.squarepath.circle.fill" : "arrow.2.squarepath")
                .font(.system(size: 12, weight: .semibold))
            Text("\(repostCount)")
                .font(.custom("OpenSans-SemiBold", size: 11))
        }
        .foregroundStyle(hasReposted ? .green : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(hasReposted ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
}

private func toggleRepost() async {
    withAnimation {
        hasReposted.toggle()
        repostCount += hasReposted ? 1 : -1
    }
    
    let postId = post.id.uuidString
    Task.detached {
        do {
            _ = try await PostInteractionsService.shared.toggleRepost(postId: postId)
        } catch {
            await MainActor.run {
                withAnimation {
                    hasReposted.toggle()
                    repostCount += hasReposted ? -1 : 1
                }
            }
        }
    }
}
```

---

## 🎯 Best Practices

### ✅ DO:
- Use optimistic updates for instant feedback
- Provide haptic feedback on interactions
- Revert changes if Firebase sync fails
- Load interaction states in `.task` modifier
- Use `Task.detached` for background Firebase operations
- Show visual feedback (animations, color changes)

### ❌ DON'T:
- Block UI thread waiting for Firebase response
- Forget to handle errors
- Skip haptic feedback
- Use `await` directly in button actions (use Task wrapper)
- Forget to initialize counts in `init()`

---

## 🐛 Debugging Tips

### Check if Firebase is connected:
```swift
print("🔥 Firebase URL: \(Database.database().reference().url)")
```

### Log interaction attempts:
```swift
print("👆 User tapped Amen. Current state: \(hasAmened)")
print("📊 Current count: \(amenCount)")
```

### Monitor Firebase sync:
```swift
do {
    try await interactionsService.toggleAmen(postId: postId)
    print("✅ Successfully synced to Firebase")
} catch {
    print("❌ Firebase sync failed: \(error.localizedDescription)")
}
```

### Check user auth:
```swift
guard let userId = Auth.auth().currentUser?.uid else {
    print("❌ User not authenticated")
    return
}
print("✅ User authenticated: \(userId)")
```

---

## 📚 Related Files

- `PostInteractionsService.swift` - Main service for interactions
- `PrayerView.swift` - Example implementation in prayers
- `TestimoniesView.swift` - Example implementation in testimonies
- `PRODUCTION_FIREBASE_RULES.md` - Firebase security rules
- `PRAYER_TESTIMONY_REACTIONS_FIX.md` - Detailed fix documentation

---

## 🚀 Quick Copy-Paste Template

```swift
struct MyPostCard: View {
    let post: Post
    @StateObject private var interactionsService = PostInteractionsService.shared
    @State private var hasAmened = false
    @State private var amenCount: Int
    
    init(post: Post) {
        self.post = post
        _amenCount = State(initialValue: post.amenCount)
    }
    
    var body: some View {
        VStack {
            // Your content
            
            Button {
                Task { await toggleAmen() }
            } label: {
                HStack {
                    Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                    Text("\(amenCount)")
                }
            }
        }
        .task {
            await loadInteractionStates()
        }
    }
    
    private func toggleAmen() async {
        withAnimation {
            hasAmened.toggle()
            amenCount += hasAmened ? 1 : -1
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        let postId = post.id.uuidString
        let currentState = hasAmened
        
        Task.detached {
            do {
                try await PostInteractionsService.shared.toggleAmen(postId: postId)
            } catch {
                await MainActor.run {
                    withAnimation {
                        hasAmened = !currentState
                        amenCount += currentState ? -1 : 1
                    }
                }
            }
        }
    }
    
    private func loadInteractionStates() async {
        let postId = post.id.uuidString
        hasAmened = await interactionsService.hasAmened(postId: postId)
        amenCount = await interactionsService.getAmenCount(postId: postId)
    }
}
```

---

**Ready to implement!** Just copy the template and customize for your needs. 🎉
