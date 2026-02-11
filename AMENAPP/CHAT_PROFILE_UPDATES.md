# UnifiedChatView Updates - Dynamic Placeholders & Profile Sheet

## Changes Made

### 1. Dynamic Placeholder Messages
The chat input field now displays a random placeholder message every time the user enters a chat, making the interface feel more dynamic and engaging.

**Placeholder Options:**
- "Type a new message here..."
- "Send a message..."
- "What's on your mind?"
- "Say something..."
- "Start typing..."
- "Write your message..."
- "Share your thoughts..."

**Implementation:**
```swift
@State private var placeholderText = ""

private func generateRandomPlaceholder() {
    let placeholders = [
        "Type a new message here...",
        "Send a message...",
        "What's on your mind?",
        // ... more options
    ]
    placeholderText = placeholders.randomElement() ?? "Type a new message here..."
}
```

The function is called in `.onAppear` so a new message appears each time the chat is opened.

### 2. User Profile Sheet
Tapping the "info" (i) button now opens a beautiful profile sheet with a black and white liquid glass design, matching the reference image provided.

**Profile Sheet Features:**
- **Clean Design**: Black and white theme with frosted glass effects
- **User Avatar**: Large circular avatar with gradient background
- **User Info**: Name, bio, and member status
- **Tags**: Displays user status (Active, Community, etc.)
- **Stats Section**: Shows rating, message count, and response time
- **Action Buttons**:
  - Primary "Start Chat" button (returns to chat)
  - Secondary bookmark/save button (white circular button)
- **Share Button**: Top-right corner for sharing profile

**Visual Elements:**
- Liquid glass background with subtle gradients
- Frosted glass card with blur effects
- Clean shadows and borders
- Spring animations on buttons
- Responsive layout with `.presentationDetents([.medium, .large])`

**Design References:**
- Avatar gradient: Dark black (0.15) to darker black (0.05)
- Background: Light grays (0.98, 0.95, 0.97)
- Shadows: Subtle black opacity (0.06 - 0.15)
- Border strokes: White with gradient opacity

### 3. New Components Added

#### `ChatUserProfileSheet`
Main profile sheet view that displays when user taps info button.

#### `TagPill`
Reusable component for displaying tags (Active, Community, etc.)
```swift
struct TagPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.gray.opacity(0.1)))
    }
}
```

#### `StatItem`
Displays individual stats with icon, value, and label
```swift
struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    // ... implementation
}
```

## Usage

### Opening Profile Sheet
```swift
// The info button in the header now triggers:
Button {
    showUserProfile = true
} label: {
    // Info icon
}
```

### Customizing Placeholders
To add more placeholder messages, edit the `generateRandomPlaceholder()` function:
```swift
let placeholders = [
    "Type a new message here...",
    "Your custom message...",
    // Add more here
]
```

### Customizing Profile Data
The profile sheet currently uses placeholder data. To display real user data:
1. Fetch user profile from Firestore
2. Pass user data to `ChatUserProfileSheet`
3. Update stats with real values (rating, messages, response time)

## Future Enhancements

1. **Real User Data**: Connect to Firestore to fetch actual user stats
2. **Profile Actions**: Implement mute, block, report actions
3. **Shared Media**: Add section showing shared photos/files
4. **Mutual Connections**: Show mutual friends or groups
5. **Activity Status**: Display online/offline status
6. **Customizable Stats**: Allow different stats for different user types

## Design Philosophy

The profile sheet follows the liquid glass design principles:
- **Clarity**: Clean typography and spacing
- **Depth**: Layered shadows and blur effects
- **Fluidity**: Spring animations and smooth transitions
- **Consistency**: Matches the overall black and white theme

## Accessibility

The profile sheet includes:
- Semantic spacing for screen readers
- High contrast text (black on light gray)
- Clear button labels
- Drag indicator for sheet dismissal
- Multiple presentation sizes (.medium, .large)

## Testing Checklist

- [x] Dynamic placeholder changes on each chat open
- [x] Info button opens profile sheet
- [x] Profile sheet displays correctly
- [x] Start Chat button dismisses sheet
- [x] Sheet is draggable
- [x] Spring animations work smoothly
- [ ] Real user data integration
- [ ] Share button functionality
- [ ] Bookmark button functionality

## Status
✅ **COMPLETE** - Dynamic placeholders and profile sheet implemented with liquid glass design
