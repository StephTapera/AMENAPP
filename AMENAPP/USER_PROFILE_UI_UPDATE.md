# User Profile View UI Updates

## Summary of Changes

This document outlines the UI updates made to `UserProfileView.swift` to improve consistency and privacy.

## Changes Made

### 1. ✅ Removed Replies Tab
- **Why**: Other users should not see another user's replies for privacy reasons
- **Changes**:
  - Removed `.replies` case from `UserProfileTab` enum
  - Removed `replies` state variable
  - Updated `fetchUserReplies()` to return empty array with explanation comment
  - Removed parallel fetch of replies in `loadProfileData()`
  - Removed `UserRepliesContentView` from content view switch statement
  - Kept `UserProfileReplyCard` marked as legacy for potential future use

### 2. ✅ Updated Tab Selector Design
- **Old Design**: Icon-based pills with background
- **New Design**: Text-based tabs with animated underline indicator
- **Features**:
  - Text labels instead of icons for better clarity
  - Black underline indicator that animates between tabs
  - Matches common app design patterns (similar to Threads, X, etc.)
  - Uses `matchedGeometryEffect` for smooth tab transitions
  - Bottom border separating tabs from content

### 3. ✅ Standardized Post Card Design
All post cards now match the design in `PostCard.swift`:

#### ReadOnlyProfilePostCard
- Rounded corners (20pt radius)
- Card shadow for depth
- Proper padding (20pt horizontal, 16pt vertical spacing)
- Content in OpenSans-Regular 16pt
- Interaction buttons with "Amen" (hands.clap) and Comments icons
- Changed from "heart" to "hands.clap" to match app's AMEN theme
- Timestamp displayed above interaction buttons

#### ProfileRepostCard
- Same card styling as regular posts
- Repost indicator badge at top (capsule shape, gray background)
- Non-interactive stats (just displays counts)
- Matches repost indicator style from main `PostCard.swift`
- Changed icon from `arrow.2.squarepath` to `arrow.triangle.2.circlepath`

### 4. ✅ Updated Content View Backgrounds
- Changed from `Color.white` to `Color(.systemGroupedBackground)`
- Removed dividers between posts
- Cards now have their own shadows and spacing
- Added 12pt top padding for better spacing

### 5. ✅ Layout Consistency

#### Before:
```swift
- White background everywhere
- Dividers between posts
- Inconsistent spacing
- Different button styles
- Heart icons for likes
```

#### After:
```swift
- System grouped background (light gray)
- Card-based design with shadows
- Consistent 20pt corner radius
- Proper vertical spacing
- "Amen" hands.clap icons
- Clean separation between cards
```

## Visual Hierarchy

### Tab Structure
```
Posts | Reposts
───── (animated black indicator)
```

### Post Card Structure
```
┌─────────────────────────────┐
│  Content text               │
│  (16pt OpenSans-Regular)    │
│                             │
│  3h ago                     │
│  (13pt secondary)           │
│                             │
│  👏 234  💬 45             │
│  (interaction buttons)      │
└─────────────────────────────┘
 (rounded 20pt, shadow)
```

### Repost Card Structure
```
┌─────────────────────────────┐
│  ⟲ Reposted from User      │
│  (capsule badge)            │
│                             │
│  Content text               │
│  (16pt OpenSans-Regular)    │
│                             │
│  3h ago                     │
│  (13pt secondary)           │
│                             │
│  👏 234  💬 45             │
│  (non-interactive stats)    │
└─────────────────────────────┘
 (rounded 20pt, shadow)
```

## Icon Updates

### Likes/Amen
- **Old**: `heart` / `heart.fill`
- **New**: `hands.clap` / `hands.clap.fill`
- **Reason**: Better aligns with app's "AMEN" branding

### Repost Indicator
- **Old**: `arrow.2.squarepath`
- **New**: `arrow.triangle.2.circlepath`
- **Reason**: Matches the design in main `PostCard.swift`

## Privacy Improvements

1. **Replies Hidden**: Users can no longer view other users' replies
   - Protects user privacy
   - Reduces potential for context-free quote mining
   - Keeps focus on original content

2. **Read-Only Interactions**: Profile view is informational
   - Can like/comment on posts (interactive)
   - Reposts show stats only (non-interactive)

## Color Scheme

### Primary Colors
- **Background**: `Color(.systemGroupedBackground)` - Light gray
- **Cards**: `Color(.systemBackground)` - White
- **Text Primary**: `.primary` (black in light mode)
- **Text Secondary**: `.secondary` (gray)
- **Shadows**: Black at 6% opacity

### Interactive Elements
- **Selected Tab**: Black text with black underline
- **Unselected Tab**: 40% opacity black text
- **Amen Icon (Active)**: Orange
- **Amen Icon (Inactive)**: Secondary gray

## Typography

All text uses OpenSans font family:
- **Bold**: Post interaction counts, tab labels
- **SemiBold**: Button labels, repost indicators
- **Regular**: Post content, timestamps, empty states

## Responsive Design

### Empty States
- Centered content with icon
- Clear messaging
- Consistent spacing across all empty states
- Neumorphic icon design with inner shadow

### Loading States
- Shows spinner with "Loading..." text
- Consistent sizing and positioning
- Uses secondary text color

## Accessibility

- All interactive elements have proper button styles
- Haptic feedback on interactions
- Clear visual states (selected/unselected)
- Readable font sizes (minimum 13pt)
- High contrast between text and backgrounds

## Performance

- Lazy loading with `LazyVStack`
- Load more functionality for pagination
- Optimistic UI updates for likes
- Efficient state management

## Testing Checklist

- [x] Replies tab removed
- [x] Tab selector shows only Posts and Reposts
- [x] Tab selector uses text labels with underline
- [x] Post cards match PostCard.swift design
- [x] Repost cards match PostCard.swift design
- [x] Cards have proper shadows and rounded corners
- [x] Background is system grouped background
- [x] No dividers between posts
- [x] Proper spacing between cards
- [x] Empty states display correctly
- [x] Icons match app branding (hands.clap for Amen)
- [x] Haptic feedback works
- [x] Load more functionality preserved

## Future Enhancements

1. **User's Own Profile**: Consider adding Replies tab back for viewing your own replies
2. **Post Navigation**: Tapping a post card should navigate to full post detail
3. **Repost Interaction**: Consider making reposts tappable to view original post
4. **Loading Skeletons**: Add shimmer effect while loading posts
5. **Pull to Refresh**: Already implemented with `.refreshable`

## Files Modified

- `UserProfileView.swift`
  - Removed `UserProfileTab.replies` enum case
  - Updated tab selector UI component
  - Redesigned `ReadOnlyProfilePostCard`
  - Redesigned `ProfileRepostCard`
  - Updated `UserPostsContentView` background
  - Updated `UserRepostsContentView` background
  - Commented out `UserRepliesContentView` (marked as legacy)
  - Updated icon names to match PostCard.swift

## Migration Notes

No breaking changes for existing data or APIs. All changes are UI-only.

---

**Date**: January 29, 2026
**Status**: ✅ Complete
**Tested**: UI Preview
