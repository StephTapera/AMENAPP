# Quick Start: Testing the New Swipable Cards

## How to Test

### 1. **Using Xcode Previews**
The fastest way to see the new design:

```swift
// In Xcode, select the preview:
#Preview("Swipable Black & White Cards")
```

This will show just the "Let's Stay Connected" section with swipable cards.

### 2. **Running the Full Search View**
To test in context:

```swift
// Run the main search preview:
#Preview("Search View")
```

Then scroll down to find the "Let's Stay Connected" section.

### 3. **In the Running App**
Navigate to the Search tab/view in your app to see the live implementation.

---

## Testing Checklist

### Basic Interactions ✅
- [ ] Card displays with user info
- [ ] Swipe right to connect
- [ ] Swipe left to skip
- [ ] Tap card to view profile
- [ ] Press ♥ button to connect
- [ ] Press ✕ button to skip
- [ ] Press "Discover More" to view all

### Visual Design ✅
- [ ] Black and white glassmorphic styling
- [ ] Avatar with frosted glass border
- [ ] User info in glassmorphic container
- [ ] Card stack shows 3 layers
- [ ] Smooth shadows and gradients
- [ ] Progress dots update correctly

### Animations ✅
- [ ] Smooth swipe gesture
- [ ] Card rotates during drag
- [ ] Next card scales up smoothly
- [ ] Haptic feedback on actions
- [ ] Bounce animation on release
- [ ] Stack transitions are smooth

### Edge Cases ✅
- [ ] Loading skeleton appears
- [ ] Empty state when no users
- [ ] Last card behavior
- [ ] Rapid swipes handled
- [ ] Network error handling
- [ ] Profile sheet opens correctly

---

## Mock Data Setup

If `UserSearchService` needs mock data for testing:

```swift
// Add to UserSearchService or create mock:
extension UserSearchService {
    func mockSuggestedUsers() -> [FirebaseSearchUser] {
        return [
            FirebaseSearchUser(
                id: "1",
                email: "john@example.com",
                displayName: "John Smith",
                username: "johnsmith",
                bio: "Passionate about serving God and helping others grow in faith.",
                profileImageURL: nil,
                isVerified: true,
                followersCount: 1250,
                followingCount: 845
            ),
            FirebaseSearchUser(
                id: "2",
                email: "jane@example.com",
                displayName: "Jane Anderson",
                username: "janeanderson",
                bio: "Walking by faith, not by sight. Love missions and worship.",
                profileImageURL: nil,
                isVerified: false,
                followersCount: 2500,
                followingCount: 892
            ),
            FirebaseSearchUser(
                id: "3",
                email: "david@example.com",
                displayName: "David Wilson",
                username: "davidwilson",
                bio: "Bible teacher, husband, father. Sharing God's Word daily.",
                profileImageURL: nil,
                isVerified: true,
                followersCount: 5400,
                followingCount: 1200
            ),
            // Add more as needed...
        ]
    }
}
```

---

## Common Issues & Solutions

### Issue: Cards don't swipe
**Solution**: Make sure `DragGesture` is applied to the top card only. Check that `isTop` parameter is set correctly.

### Issue: No users showing
**Solution**: Verify `UserSearchService.fetchSuggestedUsers()` returns data. Use mock data for testing.

### Issue: Cards overlap weirdly
**Solution**: Check `zIndex` values - top card should have highest z-index, decreasing for background cards.

### Issue: Animation stutters
**Solution**: Ensure spring animations have proper parameters: `response: 0.4, dampingFraction: 0.8`

### Issue: Haptics don't work
**Solution**: Test on a real device. Haptics don't work in Simulator.

### Issue: Profile sheet won't open
**Solution**: Make sure `UserProfileView` exists and accepts `userId` parameter.

---

## Customization Options

### Change Card Height
```swift
// In DiscoverPeopleSection
.frame(height: 400) // Change from 380
```

### Adjust Swipe Threshold
```swift
// In handleSwipe function
let threshold: CGFloat = geometry.size.width * 0.25 // Change from 0.3
```

### Modify Card Stack Depth
```swift
// In getVisibleUsers()
for i in 0..<min(5, suggestedUsers.count) // Show 5 instead of 3
```

### Change Colors
```swift
// Replace .black with your brand color
Text("John Smith")
    .foregroundStyle(.black) // ← Change here
```

### Adjust Animation Speed
```swift
.spring(response: 0.3, dampingFraction: 0.7) // Faster
.spring(response: 0.5, dampingFraction: 0.9) // Slower
```

---

## Integration Points

### Where It's Used
The `DiscoverPeopleSection` component is embedded in:
- `SearchView` (empty state)
- `SearchViewComponents.swift` (line ~120)

### Dependencies Required
- `UserSearchService` - User discovery
- `FollowService` - Follow/unfollow
- `FirebaseSearchUser` - User model
- `UserProfileView` - Profile display

### Optional Enhancements
- `NotificationService` - Alert on new connection
- `AnalyticsService` - Track swipe behavior
- `RecommendationEngine` - Smart user suggestions
- `ChatService` - Send message on connect

---

## Performance Tips

### Optimize Images
```swift
AsyncImage(url: url) { image in
    image
        .resizable()
        .aspectRatio(contentMode: .fill)
}
// Add caching:
.transaction { $0.animation = .easeInOut }
```

### Limit API Calls
```swift
// Batch load users
let batchSize = 20
let users = try await userSearchService.fetchSuggestedUsers(limit: batchSize)
```

### Reduce Re-renders
```swift
// Use @StateObject for services
@StateObject private var userSearchService = UserSearchService.shared
// Not @ObservedObject
```

---

## Debugging Tools

### Print Current State
```swift
private func skipUser() {
    print("🔄 Skipping user \(currentIndex) of \(suggestedUsers.count)")
    print("👤 Current: \(getVisibleUsers().first?.username ?? "none")")
    // ... rest of function
}
```

### Visual Debugging
```swift
// Show card index
Text("Card \(currentIndex + 1) of \(suggestedUsers.count)")
    .font(.caption)
    .padding(8)
    .background(.ultraThinMaterial)
    .cornerRadius(8)
    .overlay(content) // Add to card
```

### Gesture Debugging
```swift
.gesture(
    DragGesture()
        .onChanged { value in
            print("📏 Drag: \(value.translation.width)")
            dragOffset = value.translation.width
        }
)
```

---

## Next Steps

### Short Term
1. ✅ Test with real user data
2. ✅ Verify haptics on device
3. ✅ Check accessibility
4. ✅ Test on different screen sizes

### Medium Term
1. Add undo functionality
2. Implement user filtering
3. Add swipe statistics
4. Create onboarding tutorial

### Long Term
1. Machine learning recommendations
2. Gamification (daily swipe limits)
3. Premium features
4. Advanced matching algorithms

---

## Support

### Files to Reference
- `SearchViewComponents.swift` - Main implementation
- `SWIPABLE_BLACK_WHITE_GLASSMORPHIC_IMPLEMENTATION.md` - Full docs
- `SWIPABLE_CARDS_VISUAL_GUIDE.md` - Visual reference

### Key Components
- `DiscoverPeopleSection` - Main container
- `BlackWhiteGlassPersonCard` - Individual card
- `SwipablePersonCardSkeleton` - Loading state
- `BlackWhiteGlassEmptyCard` - Empty state

### Services Used
- `UserSearchService.shared`
- `FollowService.shared`

---

## Questions?

If you encounter issues:
1. Check console for error messages
2. Verify network connectivity for user fetching
3. Ensure all services are properly initialized
4. Test with mock data first
5. Check that `FirebaseSearchUser` model matches expected structure

Happy testing! 🎉
