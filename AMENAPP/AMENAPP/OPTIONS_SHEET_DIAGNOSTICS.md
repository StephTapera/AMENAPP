# Options Sheet Scroll Diagnostics - Complete

**Date:** March 27, 2026
**Status:** ✅ Complete
**File:** AmenOptionsSheet.swift

---

## Summary

Added comprehensive logging to the post card options sheet (3-dot menu) to diagnose scrolling issues and interaction problems.

---

## Logging Added

### 1. Sheet Lifecycle Tracking

**Lines:** 140-145

```swift
.onAppear {
    dlog("🎭 [SHEET DEBUG] Options sheet appeared (isPresented: \(isPresented))")
}
.onDisappear {
    dlog("🎭 [SHEET DEBUG] Options sheet disappeared")
}
```

**What it logs:**
- When the sheet appears
- When the sheet disappears
- The presentation state

**Use case:** Track if sheet is actually showing/hiding properly

---

### 2. ScrollView Appearance

**Lines:** 106, 133

```swift
grabber
    .onAppear {
        dlog("📜 [SHEET DEBUG] Options sheet content appeared")
    }

// ...

.onAppear {
    dlog("📜 [SHEET DEBUG] Options sheet ScrollView appeared")
}
```

**What it logs:**
- When ScrollView renders
- When content is loaded

**Use case:** Verify sheet content is rendering

---

### 3. Scroll Gesture Tracking

**Lines:** 132-138

```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            dlog("👆 [SHEET DEBUG] Sheet scroll gesture - translation: \(value.translation)")
        }
)
```

**What it logs:**
- Every scroll/drag gesture on the sheet
- Translation values (X, Y movement)

**Use case:** Identify if scrolling is working or blocked

---

### 4. Quick Action Taps

**Lines:** 214-220 (AmenQuickActionTile)

```swift
Button {
    guard action.isEnabled else {
        dlog("⚠️ [SHEET DEBUG] Quick action '\(action.title)' tapped but disabled")
        return
    }
    dlog("✅ [SHEET DEBUG] Quick action '\(action.title)' tapped")
    action.action()
}
```

**What it logs:**
- When quick action button is tapped
- If button is disabled

**Use case:** Verify button interactions are working

---

### 5. Option Row Taps

**Lines:** 317-323 (AmenOptionRow)

```swift
Button {
    guard action.isEnabled else {
        dlog("⚠️ [SHEET DEBUG] Option '\(action.title)' tapped but disabled")
        return
    }
    dlog("✅ [SHEET DEBUG] Option '\(action.title)' tapped")
    action.action()
}
```

**What it logs:**
- When option row is tapped
- If option is disabled

**Use case:** Verify list interactions are working

---

## How to Use

### Step 1: Run the app and open options sheet

1. Tap the 3-dot menu on any post card
2. Watch console logs filtered by `[SHEET DEBUG]`

### Step 2: Expected Log Sequence

When opening the sheet:
```
🎭 [SHEET DEBUG] Options sheet appeared (isPresented: true)
📜 [SHEET DEBUG] Options sheet content appeared
📜 [SHEET DEBUG] Options sheet ScrollView appeared
```

### Step 3: Try to scroll the sheet

You should see:
```
👆 [SHEET DEBUG] Sheet scroll gesture - translation: (0.0, -15.2)
👆 [SHEET DEBUG] Sheet scroll gesture - translation: (0.0, -42.8)
...
```

**If you DON'T see scroll gestures when dragging:**
- Something is blocking touch events on the sheet
- The ScrollView might not be interactive

### Step 4: Tap an action

You should see:
```
✅ [SHEET DEBUG] Quick action 'Save' tapped
```

or

```
✅ [SHEET DEBUG] Option 'Share' tapped
```

**If you DON'T see tap logs:**
- Button interactions are blocked
- The action might be disabled

---

## Common Issues & Diagnostics

### Issue 1: Sheet appears but can't scroll

**Symptoms:**
```
🎭 [SHEET DEBUG] Options sheet appeared
📜 [SHEET DEBUG] Options sheet ScrollView appeared
(no scroll gesture logs when dragging)
```

**Possible causes:**
- ScrollView has `.disabled(true)` modifier
- Another gesture is blocking the scroll
- Content is too short to scroll

**Solution:** Check if content height > screen height

---

### Issue 2: Actions don't respond to taps

**Symptoms:**
```
📜 [SHEET DEBUG] Options sheet appeared
(no tap logs when pressing buttons)
```

**Possible causes:**
- Buttons are `.disabled(true)`
- Overlay blocking touches
- Button actions are `isEnabled: false`

**Solution:** Check action `isEnabled` property

---

### Issue 3: Sheet not appearing at all

**Symptoms:**
```
(no sheet debug logs at all)
```

**Possible causes:**
- `isPresented` binding not set to `true`
- Sheet presentation failed
- Sheet view not in hierarchy

**Solution:** Check where sheet is called from PostCard

---

## Integration with PostCard

The options sheet is presented from PostCard.swift when the user taps the 3-dot menu button.

**To find the presentation code:**
```bash
grep -n "AmenOptionsSheet" PostCard.swift
```

**Expected usage:**
```swift
.sheet(isPresented: $showOptionsSheet) {
    AmenOptionsSheet(
        isPresented: $showOptionsSheet,
        title: "Post Options",
        subtitle: nil,
        quickActions: quickActions,
        sections: sections
    )
}
```

---

## Performance Notes

The sheet uses:
- **Liquid Glass design** - `.ultraThinMaterial` + gradients
- **Smooth animations** - Spring curves with 0.42s response
- **Lazy rendering** - `LazyVGrid` for quick actions
- **Optimized gestures** - `simultaneousGesture` doesn't block scrolling

All logging uses `dlog()` which compiles to no-op in Release builds, so there's zero performance impact in production.

---

## Next Steps

1. **Run the app** with the options sheet
2. **Filter console** by `[SHEET DEBUG]`
3. **Report findings:**
   - Does sheet appear? (`🎭 Options sheet appeared`)
   - Can you scroll? (`👆 Sheet scroll gesture` logs)
   - Do buttons work? (`✅ Option tapped` logs)

---

**Status:** Ready for testing - comprehensive logging in place
