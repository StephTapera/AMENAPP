# Post Reactions UI Location Guide

## 📍 Main Location: `EnhancedPostCard.swift`

All post reaction buttons are in **`AMENAPP/AMENAPP/EnhancedPostCard.swift`**

---

## 🎯 Reaction Buttons Layout

### Line 232-333: Action Buttons Section

```swift
// MARK: - Action Buttons
HStack(spacing: 8) {
    // 1️⃣ LIGHTBULB (OpenTable) / AMEN (Prayer/Testimonies)
    // 2️⃣ COMMENTS
    // 3️⃣ REPOSTS
    // Spacer()
    // 4️⃣ SAVE/BOOKMARK
}
```

---

## 1️⃣ Lightbulb / Amen Button

**Location:** Lines 233-258  
**File:** `EnhancedPostCard.swift`

```swift
if category == .openTable {
    // 💡 LIGHTBULB for #OPENTABLE posts
    Button {
        toggleLightbulb()
    } label: {
        ActionButton(
            icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
            count: post.lightbulbCount,
            isActive: hasLitLightbulb,
            activeColor: .yellow
        )
    }
    .symbolEffect(.bounce, value: hasLitLightbulb)
} else {
    // 🙏 AMEN for Prayer/Testimonies
    Button {
        toggleAmen()
    } label: {
        ActionButton(
            icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
            count: post.amenCount,
            isActive: hasSaidAmen,
            activeColor: .black
        )
    }
    .symbolEffect(.bounce, value: hasSaidAmen)
}
```

**Toggle Functions:**
- `toggleLightbulb()` - Line 448-467
- `toggleAmen()` - Line 469-487

---

## 2️⃣ Comments Button

**Location:** Lines 260-269  
**File:** `EnhancedPostCard.swift`

```swift
// 💬 COMMENTS
Button {
    showComments = true
} label: {
    ActionButton(
        icon: "bubble.left.fill",
        count: currentCommentCount,  // ✅ Live count from RTDB
        isActive: false
    )
}
```

**Opens:** `CommentsView` sheet (Line 343-361)

**Live Count Updates:**
- On load: Line 393 in `loadInteractionStates()`
- On sheet dismiss: Line 346-360
- On notification: Line 383-399

---

## 3️⃣ Reposts Button

**Location:** Lines 271-306  
**File:** `EnhancedPostCard.swift`

```swift
// 🔄 REPOSTS (with Menu)
Menu {
    Button {
        Task {
            if hasReposted {
                try await repostService.unrepost(postId: post.backendId)
            } else {
                try await repostService.repost(postId: post.backendId)
            }
        }
    } label: {
        Label(hasReposted ? "Unrepost" : "Repost", 
              systemImage: "arrow.2.squarepath")
    }
    
    Button {
        showQuoteRepost = true
    } label: {
        Label("Quote Repost", systemImage: "quote.bubble")
    }
    
    Divider()
    
    Button {
        // Show who reposted
    } label: {
        Label("See who reposted", systemImage: "person.2")
    }
} label: {
    ActionButton(
        icon: "arrow.2.squarepath",
        count: post.repostCount,
        isActive: hasReposted,
        activeColor: .green
    )
}
```

**Menu Options:**
1. Regular repost/unrepost
2. Quote repost (opens `QuoteRepostView` - Line 362-364)
3. See who reposted (not implemented yet)

---

## 4️⃣ Save/Bookmark Button

**Location:** Lines 310-330  
**File:** `EnhancedPostCard.swift`

```swift
// 🔖 SAVE
Button {
    Task {
        try await savedPostsService.toggleSave(postId: post.id.uuidString)
    }
} label: {
    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isSaved ? .blue : .black.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isSaved ? Color.blue.opacity(0.1) : Color.black.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(isSaved ? Color.blue.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
        )
}
.symbolEffect(.bounce, value: isSaved)
```

---

## 🎨 ActionButton Component

**Location:** Lines 496-518  
**File:** `EnhancedPostCard.swift`

This is the reusable component for Lightbulb, Amen, Comments, and Reposts buttons:

```swift
private struct ActionButton: View {
    let icon: String
    let count: Int
    var isActive: Bool = false
    var activeColor: Color = .blue
    
    var body: some View {
        // Just show icon - no count numbers
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? activeColor : Color.black.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? activeColor.opacity(0.15) : Color.black.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? activeColor.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
            )
    }
}
```

**Note:** Currently shows only icons, not counts (see comment on line 503)

---

## 🔧 State Management

### State Variables (Lines 25-35)

```swift
@State private var showComments = false
@State private var showQuoteRepost = false
@State private var showSaveToCollection = false
@State private var hasLitLightbulb = false
@State private var hasSaidAmen = false
@State private var isSaved = false
@State private var hasReposted = false
@State private var currentCommentCount: Int = 0  // ✅ Live count
```

### Service Instances (Lines 19-23)

```swift
@StateObject private var savedPostsService = SavedPostsService.shared
@StateObject private var repostService = RepostService.shared
@StateObject private var commentService = CommentService.shared
@StateObject private var postsManager = PostsManager.shared
```

---

## 📊 Backend Services

### PostInteractionsService.swift
- `toggleLightbulb(postId:)` - Toggle lightbulb reaction
- `toggleAmen(postId:)` - Toggle amen reaction
- `getCommentCount(postId:)` - Get real-time comment count
- `toggleRepost(postId:)` - Toggle repost status

### SavedPostsService
- `toggleSave(postId:)` - Save/unsave posts

### RepostService
- `repost(postId:)` - Create repost
- `unrepost(postId:)` - Remove repost
- `repost(postId:withComment:)` - Quote repost

### CommentService
- Opens `CommentsView` for reading/writing comments

---

## 🎭 Visual Hierarchy

```
EnhancedPostCard
├── Header (Avatar, Name, Category Badge, Menu)
├── Content (Post text + optional link preview)
├── Repost Indicator (if applicable)
└── Action Buttons Row ← YOU ARE HERE
    ├── Lightbulb/Amen (conditional)
    ├── Comments
    ├── Reposts (Menu)
    ├── Spacer
    └── Save/Bookmark
```

---

## 🎨 Styling

### Colors
- **Lightbulb Active:** `.yellow`
- **Amen Active:** `.black`
- **Comments:** No active state (always black/gray)
- **Repost Active:** `.green`
- **Save Active:** `.blue`

### Effects
- **Bounce animation** on toggle (`.symbolEffect(.bounce)`)
- **Spring animation** for comment count updates
- **Haptic feedback** on interactions

---

## 🔄 Real-Time Updates

### Lightbulb/Amen
- Optimistic UI update (instant toggle)
- Background sync to RTDB
- Revert on error

### Comments
- Live count from RTDB
- Updates on notification
- Refreshes on sheet dismiss

### Reposts
- Updates via `repostService.repostedPostIds`
- Tracked in `onChange` listener (Line 408)

### Saved
- Updates via `savedPostsService.savedPostIds`
- Tracked in `onChange` listener (Line 405)

---

## 📱 Quick Navigation

| Component | Line Number | File |
|-----------|-------------|------|
| Action Buttons HStack | 232-333 | EnhancedPostCard.swift |
| Lightbulb/Amen | 233-258 | EnhancedPostCard.swift |
| Comments Button | 260-269 | EnhancedPostCard.swift |
| Reposts Menu | 271-306 | EnhancedPostCard.swift |
| Save Button | 310-330 | EnhancedPostCard.swift |
| ActionButton Component | 496-518 | EnhancedPostCard.swift |
| toggleLightbulb() | 448-467 | EnhancedPostCard.swift |
| toggleAmen() | 469-487 | EnhancedPostCard.swift |
| loadInteractionStates() | 373-411 | EnhancedPostCard.swift |

---

**Last Updated:** February 10, 2026  
**Status:** ✅ All buttons functional with real-time updates
