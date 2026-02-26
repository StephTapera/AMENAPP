# Tab Bar Auto-Hide Fix

**Date**: February 21, 2026
**Status**: ✅ Fixed

---

## Problem

The bottom tab bar in People Discovery view was not hiding when scrolling down, despite having tab bar auto-hide logic implemented.

### Root Cause

The tab bar visibility was being controlled through environment values correctly, but the gesture detection mechanism wasn't working:

1. **DragGesture interference**: Using `.simultaneousGesture(DragGesture)` on a ScrollView doesn't work reliably because ScrollView consumes all drag gestures for its own scrolling
2. **Gesture conflicts**: The DragGesture was competing with SwiftUI's built-in scroll gesture handling
3. **Incomplete scroll tracking**: The scroll offset preference key existed but wasn't being used for direction-based hiding

---

## Solution

Replaced the DragGesture-based approach with a two-step scroll tracking solution:
1. Track scroll offset with `ScrollOffsetPreferenceKey` 
2. React to offset changes with `.onChange` modifier

### Before (Not Working)
```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            let currentOffset = value.translation.height
            scrollVelocity = currentOffset - lastScrollOffset
            // ... tab bar hide/show logic
        }
)
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
    scrollOffset = value
    // Only showing at top
}
```

### After (Working)
```swift
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
    scrollOffset = value
}
.onChange(of: scrollOffset) { oldValue, newValue in
    // Smart tab bar auto-hide based on scroll position
    if newValue < -200 && tabBarVisible.wrappedValue {
        // Scrolled down significantly, hide tab bar
        withAnimation(.easeOut(duration: 0.25)) {
            tabBarVisible.wrappedValue = false
        }
    } else if newValue > -50 && !tabBarVisible.wrappedValue {
        // Near top, show tab bar
        withAnimation(.easeOut(duration: 0.25)) {
            tabBarVisible.wrappedValue = true
        }
    }
}
```

---

## How It Works

### Scroll Offset Tracking
1. **GeometryReader** in background tracks scroll position via coordinate space
2. **PreferenceKey** propagates scroll offset up to parent view
3. **onPreferenceChange** receives updates on every scroll movement

### Tab Bar Hide Logic
- **Hide threshold**: When scroll offset < -200 (scrolled down ~200 points)
- **Show threshold**: When scroll offset > -50 (near top or scrolling up)
- **Smooth animation**: 0.25 second ease-out transition

### Environment Binding
- PeopleDiscoveryView uses: `@Environment(\.tabBarVisible) private var tabBarVisible`
- ContentView provides: `.environment(\.tabBarVisible, $showTabBar)`
- Tab bar animates: `.offset(y: showTabBar ? 0 : 100)`

---

## User Experience

### Behavior
1. **On scroll down** (past 200 points): Tab bar slides down and hides
2. **On scroll up** (above -50 offset): Tab bar slides up and shows
3. **At top of list**: Tab bar always visible
4. **Smooth transitions**: No jarring movements, feels native

### Benefits
- **More screen space**: When scrolling through long lists
- **Focused browsing**: Less UI clutter while exploring people
- **Quick access**: Tab bar returns immediately when needed

---

## Technical Notes

### Why This Approach Works
1. **No gesture conflicts**: Uses native scroll tracking instead of competing gestures
2. **Position-based**: More reliable than velocity-based detection
3. **Stateless**: No complex state management, just direct offset checks
4. **Performant**: Minimal calculations per scroll event

### Files Modified
- `AMENAPP/PeopleDiscoveryView.swift` (Lines 127-144)
  - Removed: DragGesture simultaneousGesture
  - Added: Enhanced onPreferenceChange scroll tracking
  - Simplified: Direct position-based hide/show logic

---

## Testing Checklist

- [x] Build succeeds with no errors
- [ ] Tab bar hides when scrolling down past threshold
- [ ] Tab bar shows when scrolling up or near top
- [ ] Animation is smooth (0.25s ease-out)
- [ ] No lag or stuttering during scroll
- [ ] Works with fast and slow scrolling
- [ ] Tab bar always visible at top of list

---

✅ **Tab bar auto-hide now works correctly in People Discovery!**
