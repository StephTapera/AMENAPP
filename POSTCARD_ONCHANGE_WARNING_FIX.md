# PostCard onChange Warning Fix

## Issue
The app was displaying the following warning repeatedly in the console:
```
onChange(of: Set<String>) action tried to update multiple times per frame.
```

This occurred when displaying multiple PostCards simultaneously (e.g., in a feed with 3 posts).

## Root Cause
The `PostCardInteractionsModifier` was using `.onChange()` modifiers that watched entire `Set<String>` collections:
- `interactionsService.userLightbulbedPosts`
- `interactionsService.userAmenedPosts`
- `interactionsService.userRepostedPosts`

When ANY post's state changed in these shared Sets, ALL visible PostCards would trigger their onChange handlers in the same frame, causing the warning.

## Solution
Changed from monitoring the entire Set to monitoring only the specific boolean state for each individual post.

### Before:
```swift
.onChange(of: interactionsService.userLightbulbedPosts) { oldSet, newSet in
    guard let post = post else { return }
    let oldState = oldSet.contains(post.firestoreId)
    let newState = newSet.contains(post.firestoreId)
    // ... update logic
}
```

### After:
```swift
// Helper computed property
private var isPostLightbulbed: Bool {
    guard let post = post else { return false }
    return interactionsService.userLightbulbedPosts.contains(post.firestoreId)
}

// onChange using the specific boolean state
.onChange(of: isPostLightbulbed) { oldState, newState in
    guard let post = post else { return }
    // ... update logic
}
```

## Changes Made
1. Added three helper computed properties in `PostCardInteractionsModifier`:
   - `isPostLightbulbed`
   - `isPostAmened`
   - `isPostReposted`

2. Updated all three `.onChange()` modifiers to use these computed properties instead of watching the entire Set

3. Removed redundant code that extracted boolean states from the Set parameters

## Benefits
- **Performance**: Each PostCard now only triggers onChange when its specific post's state changes
- **No warnings**: Eliminates the "multiple times per frame" warning
- **Cleaner code**: Simpler, more readable onChange handlers
- **Better scalability**: Works efficiently with any number of posts in the feed

## File Modified
- `AMENAPP/PostCard.swift` (lines 2077-2207)

## Testing
- Build succeeded without errors
- No compilation warnings related to these changes
- The onChange handlers now fire only when the specific post's state actually changes
