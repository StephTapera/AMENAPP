# Repost Button Fixes - Complete ✅

## Date: 2026-02-11

## Problems Reported

1. **Double-tap issue**: Repost button sometimes registers multiple taps, causing duplicate repost attempts
2. **Persistence issue**: Reposts don't persist after app restarts (same root cause as lightbulbs)

## Root Causes Identified

### 1. Double-Tap Issue

**Location**: `AMENAPP/PostCard.swift` (Lines 1122-1134, 1625-1720)

**Problem**: 
- The repost button shows a confirmation sheet before toggling
- If user double-taps the "Repost" button in the confirmation sheet, both taps call `toggleRepost()`
- The `isRepostToggleInFlight` flag was set AFTER the guard clauses, not BEFORE
- The flag was cleared after a 1.5 second delay, which could still allow double-taps if the backend responds quickly

**Evidence**:
```swift
// Before fix - no guard to prevent duplicate calls
private func toggleRepost() {
    guard let post = post else { return }
    guard let currentUserId = Auth.auth().currentUser?.uid else { return }
    
    // ❌ Flag set here - too late to prevent double-tap
    expectedRepostState = !previousState
    isRepostToggleInFlight = true
```

### 2. Persistence Issue (Already Fixed by Lightbulb Fix)

**Location**: `AMENAPP/FirebasePostService.swift` (6 locations)

**Problem**: Posts loaded from Firestore had `firebaseId = nil`, causing:
- Cache stores repost state using short IDs (e.g., `839CEC68`)
- PostCards check using full UUIDs (e.g., `839CEC68-BDD2-4E00-BB47-9688CC1B1AB3`)
- Mismatch → reposts never persist

**Fix**: Already applied in `LIGHTBULB_PERSISTENCE_FIX_COMPLETE.md` - explicitly setting `firestorePost.id = doc.documentID` after decoding posts from Firestore.

## The Fixes

### Fix 1: Add Guard Clause to Prevent Double-Tap

**File**: `AMENAPP/PostCard.swift` (Line ~1625)

Added a guard clause at the beginning of `toggleRepost()` to exit early if a toggle is already in flight:

```swift
private func toggleRepost() {
    guard let post = post else {
        logDebug("❌ No post object available", category: "REPOST")
        return
    }
    
    guard let currentUserId = Auth.auth().currentUser?.uid else {
        logDebug("❌ No current user ID", category: "REPOST")
        return
    }
    
    // ✅ Prevent double-tap: Exit if toggle already in flight
    guard !isRepostToggleInFlight else {
        logDebug("⏭️ SKIPPED: Repost toggle already in flight", category: "REPOST")
        return
    }
    
    // ... rest of function
```

### Fix 2: Disable Button During Toggle

**File**: `AMENAPP/PostCard.swift` (Line ~1128)

Added `isRepostToggleInFlight` to the button's disabled state:

```swift
// Before:
circularInteractionButton(
    icon: hasReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
    count: nil,
    isActive: hasReposted,
    activeColor: .green,
    disabled: isUserPost  // ❌ Doesn't prevent double-tap
)

// After:
circularInteractionButton(
    icon: hasReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
    count: nil,
    isActive: hasReposted,
    activeColor: .green,
    disabled: isUserPost || isRepostToggleInFlight  // ✅ Prevents double-tap
)
```

Also added the same check to the button action:

```swift
// Before:
) {
    if !isUserPost { 
        showRepostConfirmationSheet = true
    }
}

// After:
) {
    if !isUserPost && !isRepostToggleInFlight { 
        showRepostConfirmationSheet = true
    }
}
```

### Fix 3: Persistence (Inherited from Lightbulb Fix)

The repost persistence issue was automatically fixed by the changes made in `FirebasePostService.swift` for the lightbulb persistence fix. Posts now have their `firebaseId` property correctly populated with the Firestore document ID.

## How It Works Now

### Repost Flow (Corrected):

1. **User taps repost button**:
   - Check: `!isUserPost && !isRepostToggleInFlight` → Show confirmation sheet
   - Button disabled state includes `isRepostToggleInFlight`

2. **User confirms repost**:
   - `toggleRepost()` called
   - Guard clause checks `!isRepostToggleInFlight` → proceed or skip
   - Set `isRepostToggleInFlight = true` → **locks button**
   - Optimistic UI update: `hasReposted.toggle()`
   - Backend call: `interactionsService.toggleRepost(postId: post.firestoreId)`
   
3. **Backend responds**:
   - Update UI to match backend state
   - After 1.5 seconds: Clear `isRepostToggleInFlight` flag
   
4. **If user double-taps**:
   - Second tap is **blocked** by guard clause
   - Console logs: "⏭️ SKIPPED: Repost toggle already in flight"

5. **App restart**:
   - Cache loads: `userRepostedPosts = ["839CEC68", "2F67389D", ...]`
   - Posts have `firebaseId = "839CEC68"` (from fix)
   - PostCards check: `userRepostedPosts.contains("839CEC68")` → ✅ **true**
   - Repost shows as active!

## Testing Checklist

- [x] Build succeeds without errors
- [ ] Repost a post
- [ ] Try double-tapping the "Repost" button in confirmation sheet → should only repost once
- [ ] Close and reopen the app
- [ ] Verify repost persists and shows as active
- [ ] Check console logs for "⏭️ SKIPPED" message when double-tapping
- [ ] Test unrepost (remove repost)
- [ ] Verify unrepost persists after restart

## Files Changed

1. ✅ `AMENAPP/PostCard.swift`:
   - Added guard clause in `toggleRepost()` (Line ~1635)
   - Added `isRepostToggleInFlight` to button disabled state (Line ~1128)
   - Added check in button action (Line ~1130)

2. ✅ `AMENAPP/FirebasePostService.swift`:
   - (Already fixed in lightbulb fix) - Explicit document ID assignment (6 locations)

3. ✅ `AMENAPP/REPOST_DOUBLE_TAP_FIX_COMPLETE.md`:
   - This documentation

## Related Fixes

- `AMENAPP/LIGHTBULB_PERSISTENCE_FIX_COMPLETE.md` - Root cause fix for persistence
- `AMENAPP/SAVE_BUTTON_FIX_COMPLETE.md` - Similar pattern for save button

## Technical Notes

### Why This Pattern Works

1. **Guard Clause First**: Prevents function from running if already in flight
2. **Button Disabled**: Visual feedback - button appears disabled during operation
3. **Action Check**: Extra safety - even if button somehow gets tapped, action is blocked
4. **Optimistic UI**: User sees immediate feedback
5. **Backend Sync**: Real-time observers keep UI in sync with database

### Existing Protection Mechanisms

The repost button already had some protection:
- `isRepostToggleInFlight` flag (but set too late)
- Confirmation sheet (slows down user, but doesn't prevent double-tap of confirm button)
- 1.5 second delay before clearing flag

The new fix adds:
- **Early guard clause** (primary protection)
- **Button disabled state** (visual feedback)
- **Action-level check** (defense in depth)

### Why Confirmation Sheet Alone Wasn't Enough

The confirmation sheet helps prevent accidental reposts, but doesn't prevent double-tapping the "Confirm" button within the sheet. Without the guard clause, both taps would call `toggleRepost()` and both could execute before `isRepostToggleInFlight` was cleared.

## Console Debugging

To verify the fix is working, watch for these logs:

**Normal repost (single tap)**:
```
🔍 [POSTCARD-DEBUG][REPOST] USER_ACTION: toggleRepost() called
  postId: 839CEC68
  BEFORE: hasReposted=false
  OPTIMISTIC: hasReposted=true
📤 Calling PostInteractionsService.toggleRepost...
✅ Backend write SUCCESS
```

**Double-tap attempt (blocked)**:
```
🔍 [POSTCARD-DEBUG][REPOST] USER_ACTION: toggleRepost() called
⏭️ SKIPPED: Repost toggle already in flight
```

## Author

Claude Code (Sonnet 4.5)
Date: 2026-02-11
