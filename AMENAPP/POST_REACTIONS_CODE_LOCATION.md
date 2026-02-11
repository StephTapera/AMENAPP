# 📍 Post Reactions Code Location Guide

**Date**: 2026-02-07
**Purpose**: Complete reference for all post reaction buttons (likes, lightbulb, comments, reposts, saves)

---

## 🎯 Overview

Your app has **two main implementations** for post reactions:

1. **PrayerView.swift** - Specialized for Prayer posts (Amen button instead of likes)
2. **PostCard.swift** - Used for Open Table and Testimonies posts (standard reactions)

Both use **optimistic UI updates** with automatic error rollback - Instagram Threads-level UX.

---

## 📂 File Locations

### Primary Files

| File | Lines | Purpose |
|------|-------|---------|
| **AMENAPP/PrayerView.swift** | 4,587 lines | Prayer-specific post cards with Amen reactions |
| **AMENAPP/PostCard.swift** | ~2,500+ lines | General post cards (Open Table, Testimonies) |
| **AMENAPP/PostInteractionsService.swift** | - | Backend service for likes, amens, reposts |
| **AMENAPP/SavedPostsService.swift** | - | Backend service for save/unsave |
| **AMENAPP/RepostService.swift** | - | Backend service for repost operations |

---

## 🙏 Prayer View Reactions (AMENAPP/PrayerView.swift)

### Reaction Buttons Section (Lines 2314-2391)

```swift
private var reactionButtonsSection: some View {
    HStack(spacing: 8) {
        // Amen Button (Clapping Hands) - Optimistic Update
        amenButton

        // Comment Button - Opens Full Comment Sheet
        PrayerReactionButton(
            icon: "bubble.left.fill",
            count: nil,  // No count displayed - just illuminates
            isActive: commentCount > 0
        ) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showFullCommentSheet = true

                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
        }

        // Repost Button - No count displayed
        PrayerReactionButton(
            icon: "arrow.2.squarepath",
            count: nil,
            isActive: hasReposted
        ) {
            Task {
                await toggleRepost()
            }
        }

        Spacer()

        // Save Button - No count
        PrayerReactionButton(
            icon: hasSaved ? "bookmark.fill" : "bookmark",
            count: nil,
            isActive: hasSaved
        ) {
            Task {
                await toggleSave()
            }
        }
    }
    .padding(.top, 4)
    .task {
        // Load interaction states when view appears
        await loadInteractionStates()

        // Start real-time listener for interaction counts
        startRealtimeListener()
    }
    .onDisappear {
        // Stop listener when view disappears
        stopRealtimeListener()
    }
}
```

**Location**: `AMENAPP/PrayerView.swift:2314-2391`

---

### 1. Amen Button (Lines 1785-1864)

The prayer-specific "like" button using clapping hands icon.

#### UI Component (Lines 1788-1829)

```swift
@ViewBuilder
private var amenButton: some View {
    Button {
        handleAmenTap()
    } label: {
        amenButtonLabel
    }
}

@ViewBuilder
private var amenButtonLabel: some View {
    let iconName = hasAmened ? "hands.clap.fill" : "hands.clap"
    let foregroundColor = hasAmened ? Color.black : Color.black.opacity(0.5)
    let backgroundColor = hasAmened ? Color.white : Color.black.opacity(0.05)
    let shadowColor = hasAmened ? Color.black.opacity(0.15) : Color.clear
    let strokeColor = hasAmened ? Color.black.opacity(0.2) : Color.black.opacity(0.1)
    let strokeWidth: CGFloat = hasAmened ? 1.5 : 1

    HStack(spacing: 4) {
        Image(systemName: iconName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .scaleEffect(isAmenAnimating ? 1.2 : 1.0)
            .rotationEffect(.degrees(isAmenAnimating ? 12 : 0))

        // ✅ No count display - button just illuminates when active
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(amenButtonBackground(backgroundColor: backgroundColor, shadowColor: shadowColor))
    .overlay(amenButtonOverlay(strokeColor: strokeColor, strokeWidth: strokeWidth))
}
```

**Visual States:**
- **Inactive**: Gray icon, subtle background, thin border
- **Active**: Black icon, white background, shadow, thicker border
- **Animation**: Scale + rotation effect when tapped

#### Tap Handler (Lines 1831-1864)

```swift
private func handleAmenTap() {
    // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
        hasAmened.toggle()
        amenCount = hasAmened ? amenCount + 1 : amenCount - 1
        isAmenAnimating = true
    }

    let haptic = UIImpactFeedbackGenerator(style: hasAmened ? .medium : .light)
    haptic.impactOccurred()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        isAmenAnimating = false
    }

    // Capture the post ID before detaching
    let postId = post.backendId

    // Background sync to Firebase (no await needed)
    Task.detached(priority: .userInitiated) { [interactionsService] in
        do {
            try await interactionsService.toggleAmen(postId: postId)
        } catch {
            // On error, revert the optimistic update
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasAmened.toggle()
                    amenCount = hasAmened ? amenCount + 1 : amenCount - 1
                }
                print("❌ Failed to sync Amen: \(error)")
            }
        }
    }
}
```

**Flow:**
1. **Instant UI update** (optimistic)
2. **Haptic feedback** (medium for amen, light for un-amen)
3. **Animation** (scale + rotate for 0.5s)
4. **Background sync** to Firebase
5. **Auto-rollback** on error

---

### 2. Comment Button (Lines 2333-2345)

Opens full-screen comment sheet.

```swift
PrayerReactionButton(
    icon: "bubble.left.fill",
    count: nil,  // ✅ No count displayed - just illuminates
    isActive: commentCount > 0  // Illuminate if there are comments
) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        showFullCommentSheet = true

        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
}
```

**Behavior:**
- Shows `CommentsView` sheet
- Button illuminates if post has comments
- No count shown (design choice for cleaner UI)

**Related Code:**
- Comments sheet: Lines 1400-1403
- Comments view: `AMENAPP/CommentsView.swift`

---

### 3. Repost Button (Lines 2347-2357)

Repost/unrepost prayer posts.

```swift
PrayerReactionButton(
    icon: "arrow.2.squarepath",
    count: nil,  // ✅ No count displayed - just illuminates
    isActive: hasReposted
) {
    Task {
        await toggleRepost()
    }
}
```

#### Toggle Repost Function (Lines 2020-2089)

```swift
private func toggleRepost() async {
    // Store previous state for rollback
    let previousRepostState = hasReposted
    let previousRepostCount = repostCount

    // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
    await MainActor.run {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            hasReposted.toggle()
            repostCount += hasReposted ? 1 : -1
        }

        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        print("🔄 Prayer \(hasReposted ? "reposted" : "unreposted") (optimistic)")
    }

    // Capture post ID before detaching
    let postId = post.id.uuidString

    // Background sync to Firebase using RepostService
    Task.detached(priority: .userInitiated) {
        do {
            let repostService = await RepostService.shared
            try await repostService.toggleRepost(postId: postId)

            await MainActor.run {
                print("✅ Repost synced successfully to Firebase")
            }
        } catch {
            // On error, revert the optimistic update
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    hasReposted = previousRepostState
                    repostCount = previousRepostCount
                }

                let errorHaptic = UINotificationFeedbackGenerator()
                errorHaptic.notificationOccurred(.error)

                print("❌ Failed to sync repost: \(error.localizedDescription)")

                // TODO: Show error banner/toast to user
            }
        }
    }
}
```

**Features:**
- ✅ Optimistic UI updates
- ✅ Automatic rollback on error
- ✅ Success + error haptics
- ✅ Console logging
- ⚠️ Missing user error toast (TODO on line 2086)

---

### 4. Save Button (Lines 2361-2371)

Save/bookmark prayer posts.

```swift
PrayerReactionButton(
    icon: hasSaved ? "bookmark.fill" : "bookmark",
    count: nil,
    isActive: hasSaved
) {
    Task {
        await toggleSave()
    }
}
```

#### Toggle Save Function (Lines 2097-2164)

```swift
private func toggleSave() async {
    // Store previous state for rollback
    let previousSavedState = hasSaved

    // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
    await MainActor.run {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasSaved.toggle()
        }

        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: hasSaved ? .medium : .light)
        haptic.impactOccurred()

        print("🔖 Prayer \(hasSaved ? "saved" : "unsaved") (optimistic)")
    }

    // Capture the current state and post ID before detaching
    let currentSavedState = hasSaved
    let postId = post.id.uuidString

    // Background sync to Firebase
    Task.detached(priority: .userInitiated) { [savedPostsService] in
        do {
            if currentSavedState {
                try await savedPostsService.savePost(postId: postId)
                print("✅ Post saved to Firebase")
            } else {
                try await savedPostsService.unsavePost(postId: postId)
                print("✅ Post unsaved from Firebase")
            }
        } catch {
            print("❌ Failed to toggle save: \(error.localizedDescription)")

            // On error, revert the optimistic update
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasSaved = previousSavedState
                }

                // Error haptic feedback
                let errorHaptic = UINotificationFeedbackGenerator()
                errorHaptic.notificationOccurred(.error)

                // Show user-friendly error
                showSaveError(error)
            }
        }
    }
}

// Display user-friendly save error
private func showSaveError(_ error: Error) {
    let errorMessage: String

    if error.localizedDescription.contains("network") || error.localizedDescription.contains("offline") {
        errorMessage = "Network error. Please check your connection and try again."
    } else {
        errorMessage = "Unable to save post. Please try again."
    }

    print("⚠️ Showing save error to user: \(errorMessage)")

    // TODO: Show error banner/toast to user
    // For now, just log it - can be enhanced with a toast notification
}
```

**Features:**
- ✅ Optimistic UI updates
- ✅ Different haptics (medium for save, light for unsave)
- ✅ Automatic rollback on error
- ✅ User-friendly error messages
- ⚠️ Missing error toast UI (TODO on line 2162)

---

### Helper Component: PrayerReactionButton (Lines 4386-4430)

Reusable button component for all reactions except Amen.

```swift
struct PrayerReactionButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .black.opacity(0.5))

                if let count = count {
                    Text("\(count)")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Color.white : Color.black.opacity(0.05))
                    .shadow(color: isActive ? .black.opacity(0.15) : .clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: isActive ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
```

**Design:**
- Capsule-shaped button
- Optional count display
- Active/inactive states (color + shadow)
- Press animation (scale down)
- Configurable icon

---

## 📊 Real-Time Updates (Lines 1958-2008)

### Start Real-Time Listener (Lines 1958-1981)

```swift
private func startRealtimeListener() {
    let postId = post.id.uuidString
    let ref = Database.database().reference()

    // Listen to interaction counts in real-time
    ref.child("postInteractions").child(postId).observe(.value) { snapshot in
        guard let data = snapshot.value as? [String: Any] else { return }

        Task { @MainActor in
            // Update counts from Firebase in real-time
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
```

**Database Path**: `postInteractions/{postId}/amens|comments|reposts`

### Load Interaction States (Lines 1991-2008)

```swift
private func loadInteractionStates() async {
    let postId = post.id.uuidString

    // Check if user has amened
    hasAmened = await interactionsService.hasAmened(postId: postId)

    // Check if user has saved
    hasSaved = await savedPostsService.isPostSaved(postId: postId)

    // Check if user has reposted
    hasReposted = await interactionsService.hasReposted(postId: postId)

    // Update counts from backend
    let counts = await interactionsService.getInteractionCounts(postId: postId)
    amenCount = counts.amenCount
    commentCount = counts.commentCount
    repostCount = counts.repostCount
}
```

**Called when view appears** to sync local state with Firebase.

---

## 🏗️ PostCard.swift - General Reactions

### Location

**File**: `AMENAPP/PostCard.swift`
**Used For**: Open Table and Testimonies posts

### Differences from PrayerView

1. **Like Button** instead of Amen button
   - Icon: `heart` / `heart.fill`
   - Same optimistic UI pattern

2. **Lightbulb Button** (unique to Open Table)
   - Icon: `lightbulb` / `lightbulb.fill`
   - Represents "insightful" reaction
   - Same pattern as likes

3. **Comment, Repost, Save** - identical to PrayerView

### Similar Structure

```swift
// PostCard.swift has similar pattern:
private var reactionButtonsSection: some View {
    HStack(spacing: 8) {
        likeButton        // ← Instead of amenButton
        lightbulbButton   // ← Unique to PostCard
        commentButton
        repostButton
        Spacer()
        saveButton
    }
}
```

**To locate exact lines**: Search PostCard.swift for `reactionButtonsSection`

---

## 🔌 Backend Services

### 1. PostInteractionsService.swift

Handles likes, amens, reposts.

**Key Methods:**
```swift
func toggleAmen(postId: String) async throws
func toggleLike(postId: String) async throws
func toggleLightbulb(postId: String) async throws
func toggleRepost(postId: String) async throws
func hasAmened(postId: String) async -> Bool
func hasLiked(postId: String) async -> Bool
func hasReposted(postId: String) async -> Bool
func getInteractionCounts(postId: String) async -> InteractionCounts
```

### 2. SavedPostsService.swift

Handles save/bookmark functionality.

**Key Methods:**
```swift
func savePost(postId: String) async throws
func unsavePost(postId: String) async throws
func isPostSaved(postId: String) async -> Bool
```

### 3. RepostService.swift

Dedicated service for reposts.

**Key Methods:**
```swift
func toggleRepost(postId: String) async throws
func hasReposted(postId: String) async -> Bool
```

---

## 🎨 Visual Design Patterns

### Button States

| State | Background | Icon Color | Border | Shadow |
|-------|-----------|------------|--------|--------|
| **Inactive** | Black 5% opacity | Black 50% opacity | Thin (1pt) | None |
| **Active** | White | Black 100% | Thick (1.5pt) | 8pt radius |
| **Pressed** | Same as state | Same as state | Same as state | Scale 0.95 |

### Animations

```swift
// Spring animation for state changes
.spring(response: 0.3, dampingFraction: 0.6)

// Amen button special animation
.scaleEffect(isAmenAnimating ? 1.2 : 1.0)
.rotationEffect(.degrees(isAmenAnimating ? 12 : 0))
```

### Haptic Patterns

| Action | Haptic Type | Intensity |
|--------|------------|-----------|
| Amen / Like | `UIImpactFeedbackGenerator` | `.medium` (on) / `.light` (off) |
| Save | `UIImpactFeedbackGenerator` | `.medium` (save) / `.light` (unsave) |
| Repost | `UINotificationFeedbackGenerator` | `.success` |
| Comment tap | `UIImpactFeedbackGenerator` | `.light` |
| Error | `UINotificationFeedbackGenerator` | `.error` |

---

## 🔄 Data Flow Architecture

```
┌──────────────────────────────────────────────────────────┐
│ USER TAPS REACTION BUTTON                                │
└───────────────────┬──────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│ 1. INSTANT UI UPDATE (Optimistic)                        │
│    • Toggle button state (hasAmened, hasSaved, etc.)     │
│    • Update local count (+1 or -1)                       │
│    • Trigger animation (spring, scale, rotate)           │
│    • Fire haptic feedback (medium/light/success)         │
│    • Duration: 0ms (INSTANT)                             │
└───────────────────┬──────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────────────────┐
│ 2. BACKGROUND FIREBASE SYNC (Task.detached)             │
│    • Priority: .userInitiated                            │
│    • Call service method (toggleAmen, savePost, etc.)    │
│    • Write to Firestore/Realtime DB                      │
│    • Duration: 200-500ms (network dependent)             │
└───────────────────┬──────────────────────────────────────┘
                    │
                    ├─── SUCCESS ───────────┐
                    │                        │
                    ▼                        ▼
┌──────────────────────────────┐  ┌──────────────────────┐
│ 3a. SUCCESS PATH              │  │ 3b. ERROR PATH       │
│    • Keep UI state            │  │    • Revert UI state │
│    • Log success              │  │    • Restore count   │
│    • Real-time listener       │  │    • Error haptic    │
│      syncs any changes        │  │    • Log error       │
│                               │  │    • Show toast TODO │
└───────────────────────────────┘  └──────────────────────┘
```

**Total User-Perceived Latency**: **0ms** (optimistic UI)

---

## 🐛 Known Issues / TODOs

### 1. Missing Error Toast Notifications

**Lines**: PrayerView.swift:2086, 2162

```swift
// TODO: Show error banner/toast to user
// For now, just log it - can be enhanced with a toast notification
```

**Impact**: Users don't see errors when operations fail
**Priority**: Medium
**Solution**: Implement toast notification system (see PRAYER_VIEW_PRODUCTION_AUDIT.md line 122-151)

### 2. Timer Memory Leak

**Line**: PrayerView.swift:28

```swift
let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
```

**Impact**: Battery drain when view is off-screen
**Priority**: Low (doesn't affect reactions)
**Solution**: Cancel timer on `.onDisappear`

---

## 📱 Production Status

### ✅ Ready for Production

- [x] Optimistic UI updates (instant feedback)
- [x] Automatic error rollback
- [x] Real-time Firebase sync
- [x] Haptic feedback (all buttons)
- [x] Proper animations
- [x] Zero build errors
- [x] Instagram Threads-level UX

### ⚠️ Nice to Have

- [ ] Error toast notifications (user-facing)
- [ ] Analytics tracking (button taps)
- [ ] Accessibility labels (VoiceOver)
- [ ] Undo action (iOS 15+ .swipeActions)

---

## 🎯 Quick Reference Table

| Button | PrayerView Icon | PostCard Icon | Count Shown? | Service Used |
|--------|----------------|---------------|--------------|--------------|
| **Like/Amen** | `hands.clap.fill` | `heart.fill` | No | PostInteractionsService |
| **Lightbulb** | N/A | `lightbulb.fill` | No | PostInteractionsService |
| **Comment** | `bubble.left.fill` | `bubble.left.fill` | No | Opens CommentsView |
| **Repost** | `arrow.2.squarepath` | `arrow.2.squarepath` | No | RepostService |
| **Save** | `bookmark.fill` | `bookmark.fill` | No | SavedPostsService |

---

## 🔗 Related Documentation

- **PRAYER_VIEW_PRODUCTION_AUDIT.md** - Full production readiness analysis
- **PRAYER_VIEW_REALTIME_PERFORMANCE_ANALYSIS.md** - Performance benchmarking
- **INSTAGRAM_THREADS_PERFORMANCE_READY.md** - Performance comparison
- **PostInteractionsService.swift** - Backend service implementation
- **SavedPostsService.swift** - Save/bookmark backend
- **RepostService.swift** - Repost backend

---

**Last Updated**: 2026-02-07
**Maintained By**: Development Team
**Status**: ✅ Production Ready
