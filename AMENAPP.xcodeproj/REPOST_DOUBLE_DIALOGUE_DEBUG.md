# Repost Double-Dialogue Debug - Investigation in Progress
## Date: February 11, 2026

## Problem
User reports: "when i press repost, the dialogue 'remove repost?' and remove post diallgue shows up right when i press repost button"

Both the RepostConfirmationSheet ("Remove Repost?") and Delete Post alert ("Delete Post") appear simultaneously when tapping the repost button.

## Investigation Strategy

Since SwiftUI can only show ONE sheet or alert at a time, the fact that both dialogues appear suggests one of these scenarios:

1. **Both state variables are being set to `true` simultaneously**
2. **There's a gesture conflict or overlapping tap targets**
3. **The `isUserPost` flag is incorrectly set, causing unexpected behavior**
4. **There's a race condition or timing issue**

## Debug Logging Added

### File: AMENAPP/PostCard.swift

Added extensive debug logging to track when state variables are set and changed:

#### 1. Repost Button Action (Lines ~1125-1150)
```swift
circularInteractionButton(
    icon: hasReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
    count: nil,
    isActive: hasReposted,
    activeColor: .green,
    disabled: isUserPost || isRepostToggleInFlight
) {
    print("🔵 [REPOST-BUTTON] Tapped repost button")
    print("   isUserPost: \(isUserPost)")
    print("   isRepostToggleInFlight: \(isRepostToggleInFlight)")
    print("   BEFORE: showRepostConfirmationSheet = \(showRepostConfirmationSheet)")
    print("   BEFORE: showingDeleteAlert = \(showingDeleteAlert)")
    
    if !isUserPost && !isRepostToggleInFlight { 
        showRepostConfirmationSheet = true
        print("   AFTER: showRepostConfirmationSheet = \(showRepostConfirmationSheet)")
    } else {
        print("   ⚠️ Repost blocked - isUserPost=\(isUserPost) or inFlight=\(isRepostToggleInFlight)")
    }
    
    print("   FINAL: showingDeleteAlert = \(showingDeleteAlert)")
}
```

**What this tracks:**
- Current value of `isUserPost` and `isRepostToggleInFlight`
- State of both dialogue variables BEFORE and AFTER the button action
- Whether the guard condition blocks the repost

#### 2. Delete Button in Menu (Lines ~463-471)
```swift
Button(role: .destructive) {
    print("🔴 [DELETE-BUTTON] Tapped delete button in menu")
    print("   BEFORE: showingDeleteAlert = \(showingDeleteAlert)")
    print("   BEFORE: showRepostConfirmationSheet = \(showRepostConfirmationSheet)")
    showingDeleteAlert = true
    print("   AFTER: showingDeleteAlert = \(showingDeleteAlert)")
} label: {
    Label("Delete Post", systemImage: "trash")
}
```

**What this tracks:**
- Confirms when the delete button is actually tapped
- State of both dialogue variables before and after

#### 3. Repost Menu Option (Lines ~476-494)
```swift
Button {
    print("🟢 [REPOST-MENU] Tapped 'Repost to Profile' in menu")
    print("   isUserPost: \(isUserPost)")
    print("   isRepostToggleInFlight: \(isRepostToggleInFlight)")
    print("   BEFORE: showRepostConfirmationSheet = \(showRepostConfirmationSheet)")
    print("   BEFORE: showingDeleteAlert = \(showingDeleteAlert)")
    
    if !isUserPost && !isRepostToggleInFlight {
        showRepostConfirmationSheet = true
        print("   AFTER: showRepostConfirmationSheet = \(showRepostConfirmationSheet)")
    } else {
        print("   ⚠️ Repost blocked - isUserPost=\(isUserPost) or inFlight=\(isRepostToggleInFlight)")
    }
    
    print("   FINAL: showingDeleteAlert = \(showingDeleteAlert)")
} label: {
    Label("Repost to Profile", systemImage: "arrow.triangle.2.circlepath")
}
```

**What this tracks:**
- When the menu "Repost to Profile" option is tapped
- Same state tracking as the repost button

#### 4. State Change Observers (After PostCardInteractionsModifier)
```swift
.onChange(of: showRepostConfirmationSheet) { oldValue, newValue in
    print("📊 [STATE-CHANGE] showRepostConfirmationSheet changed: \(oldValue) → \(newValue)")
    if newValue {
        print("   showingDeleteAlert is currently: \(showingDeleteAlert)")
    }
}
.onChange(of: showingDeleteAlert) { oldValue, newValue in
    print("📊 [STATE-CHANGE] showingDeleteAlert changed: \(oldValue) → \(newValue)")
    if newValue {
        print("   showRepostConfirmationSheet is currently: \(showRepostConfirmationSheet)")
    }
}
```

**What this tracks:**
- ANY change to either state variable (from any source)
- The state of the OTHER variable when one changes
- Helps identify if both are being set simultaneously or in sequence

## How to Test

1. **Open the app and navigate to a post**
2. **Tap the repost button** (the circular button with two arrows)
3. **Observe the console output** with the filter:
   ```
   REPOST-BUTTON | DELETE-BUTTON | REPOST-MENU | STATE-CHANGE
   ```

## Expected Console Output Patterns

### Normal Behavior (Should see):
```
🔵 [REPOST-BUTTON] Tapped repost button
   isUserPost: false
   isRepostToggleInFlight: false
   BEFORE: showRepostConfirmationSheet = false
   BEFORE: showingDeleteAlert = false
   AFTER: showRepostConfirmationSheet = true
   FINAL: showingDeleteAlert = false
📊 [STATE-CHANGE] showRepostConfirmationSheet changed: false → true
   showingDeleteAlert is currently: false
```

### If Delete Button is Accidentally Triggered:
```
🔵 [REPOST-BUTTON] Tapped repost button
   ...
🔴 [DELETE-BUTTON] Tapped delete button in menu
   BEFORE: showingDeleteAlert = false
   BEFORE: showRepostConfirmationSheet = true
   AFTER: showingDeleteAlert = true
📊 [STATE-CHANGE] showingDeleteAlert changed: false → true
   showRepostConfirmationSheet is currently: true
```

### If Both Are Set Simultaneously:
```
🔵 [REPOST-BUTTON] Tapped repost button
   ...
   AFTER: showRepostConfirmationSheet = true
   FINAL: showingDeleteAlert = true  ← ⚠️ This shouldn't happen!
📊 [STATE-CHANGE] showRepostConfirmationSheet changed: false → true
   showingDeleteAlert is currently: true
📊 [STATE-CHANGE] showingDeleteAlert changed: false → true
   showRepostConfirmationSheet is currently: true
```

## Key Questions to Answer

1. **Is the repost button being tapped, or the menu option?**
   - Look for `🔵 [REPOST-BUTTON]` vs `🟢 [REPOST-MENU]`

2. **Is the delete button being triggered somehow?**
   - Look for `🔴 [DELETE-BUTTON]` in the logs

3. **Are both state variables set to true?**
   - Check the `FINAL:` lines and `[STATE-CHANGE]` logs

4. **Is `isUserPost` incorrectly set to `true` on other users' posts?**
   - Check the `isUserPost:` value in the logs

5. **Is there a gesture conflict?**
   - Multiple button taps logged in quick succession

## Next Steps Based on Results

### Scenario A: Both buttons are being tapped
**Diagnosis:** Gesture conflict or overlapping tap targets  
**Fix:** Adjust button layout/hit areas, add `.allowsHitTesting(false)` to overlapping views

### Scenario B: Only repost button tapped, but both states set
**Diagnosis:** Code bug - something else is setting `showingDeleteAlert`  
**Fix:** Search for other places `showingDeleteAlert` might be set

### Scenario C: `isUserPost` is `true` when it shouldn't be
**Diagnosis:** User identity detection bug  
**Fix:** Fix the `isUserPost` initialization logic

### Scenario D: Delete button appears in logs
**Diagnosis:** User accidentally tapping delete in menu  
**Fix:** UI/UX improvement - make it clearer which button is which

## Files Modified

- **AMENAPP/PostCard.swift**
  - Added debug logging to repost button action (lines ~1125-1150)
  - Added debug logging to delete button action (lines ~463-471)
  - Added debug logging to menu repost option (lines ~476-494)
  - Added state change observers (after PostCardInteractionsModifier)

## Build Status

✅ **Build successful** - No compilation errors

## Testing Checklist

- [ ] Tap repost button on someone else's post (not yours)
- [ ] Tap repost button on your own post (should be disabled)
- [ ] Tap three-dot menu → "Repost to Profile"
- [ ] Tap three-dot menu → "Delete Post" (on your own post)
- [ ] Check console logs for all scenarios
- [ ] Note which dialogues appear for each scenario
- [ ] Copy console output and share for analysis

## Current Status

🔍 **Awaiting user testing** - Debug logging in place, ready to identify root cause

---

**Next Update:** After user provides console output from testing
