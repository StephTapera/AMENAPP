# State Persistence Fix Plan - EnhancedPostCard

## 🔍 ROOT CAUSE ANALYSIS

### Current Implementation Issues:

1. **`.task` modifier only runs ONCE** (line 340)
   - When view first appears, states load correctly
   - When user switches tabs or navigates away, view is deallocated
   - When returning, `.task` doesn't re-run because SwiftUI reuses the view
   - Result: Stale state from initial load

2. **No real-time listeners** for lightbulb/amen
   - `hasLitLightbulb` and `hasSaidAmen` are set once
   - PostInteractionsService has `@Published` properties but card doesn't observe them
   - When user toggles in another view, this card doesn't know

3. **Optimistic updates without proper rollback**
   - `toggleLightbulb()` updates UI immediately (line 451)
   - If Firebase write fails, state reverts (line 463)
   - BUT if user navigates away before completion, state is lost

4. **Service state not properly observed**
   - `savedPostsService.savedPostIds` is Published (line 19: @StateObject)
   - `onChange` listener exists (line 379)
   - BUT initial load might complete before service finishes loading from Firebase

## 🎯 FIX STRATEGY

### Fix 1: Add `.onAppear` to reload states
- `.task` runs once per view lifecycle
- `.onAppear` runs every time view appears
- Use `.onAppear` to refresh states from services

### Fix 2: Observe PostInteractionsService published properties
- Add onChange listeners for:
  - `postLightbulbs` dictionary
  - `postAmens` dictionary
  - `postComments` dictionary
  - `postReposts` dictionary

### Fix 3: Add real-time sync on view appearance
- When view appears, sync with RTDB
- When view appears, sync with service caches

### Fix 4: Fix repost state tracking
- Ensure RepostService properly loads user's reposts
- Add proper state update mechanism

### Fix 5: Fix saved state random activation
- Add defensive checks in `updateSavedState()`
- Ensure service has finished loading before checking state

## 📝 IMPLEMENTATION PLAN

### Step 1: Add `.onAppear` lifecycle handler
```swift
.onAppear {
    Task {
        await refreshInteractionStates()
    }
}
```

### Step 2: Create `refreshInteractionStates()` function
```swift
private func refreshInteractionStates() async {
    // Re-query RTDB for current user's interactions
    // This ensures we get latest state even if view was cached
}
```

### Step 3: Observe PostInteractionsService published properties
```swift
.onChange(of: PostInteractionsService.shared.userLightbulbedPosts) { _, newSet in
    hasLitLightbulb = newSet.contains(post.backendId)
}

.onChange(of: PostInteractionsService.shared.userAmenedPosts) { _, newSet in
    hasSaidAmen = newSet.contains(post.backendId)
}
```

### Step 4: Add lifecycle logging
```swift
print("🎬 [CARD] View appeared for post: \(post.backendId)")
print("   Lightbulb: \(hasLitLightbulb), Amen: \(hasSaidAmen)")
print("   Saved: \(isSaved), Reposted: \(hasReposted)")
```

### Step 5: Ensure services load user data on init
- Check SavedPostsService loads user's saved posts
- Check RepostService loads user's reposts
- Check PostInteractionsService loads user's interactions

## 🔧 FILES TO MODIFY

1. **EnhancedPostCard.swift**
   - Add `.onAppear` handler
   - Add `refreshInteractionStates()`
   - Add observers for PostInteractionsService
   - Add defensive state checks

2. **PostInteractionsService.swift**
   - Verify `loadUserInteractions()` is called on init
   - Ensure Published properties are updated correctly

3. **SavedPostsService.swift**
   - Verify saved posts are loaded from Firebase on init
   - Ensure Published `savedPostIds` is populated

4. **RepostService.swift**
   - Verify reposts are loaded from Firebase on init
   - Ensure Published `repostedPostIds` is populated

## ✅ EXPECTED BEHAVIOR AFTER FIX

### Lightbulb/Amen:
- [ ] Tap → illuminates immediately
- [ ] Switch tabs → returns still illuminated
- [ ] Kill app → reopen → still illuminated
- [ ] Tap again → un-illuminates
- [ ] Switch tabs → returns still un-illuminated

### Saved:
- [ ] Tap → illuminates immediately
- [ ] Switch tabs → returns still illuminated
- [ ] Kill app → reopen → still illuminated
- [ ] Never self-activates randomly

### Repost:
- [ ] Tap → illuminates immediately
- [ ] Switch tabs → returns still illuminated
- [ ] Kill app → reopen → still illuminated
- [ ] Menu shows "Unrepost" when active

### Comments:
- [ ] Add comment → count increments
- [ ] Switch tabs → count persists
- [ ] Kill app → reopen → count correct
- [ ] Comments visible in CommentsView

## 🐛 DEBUGGING CHECKLIST

- [ ] Add console logs for all state changes
- [ ] Log when `.task` fires
- [ ] Log when `.onAppear` fires
- [ ] Log when `onChange` fires for each service
- [ ] Log RTDB query results
- [ ] Verify service initialization order

---

**Status:** Ready for implementation
**Priority:** CRITICAL - Core user experience
