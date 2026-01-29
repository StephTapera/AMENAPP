# Daily Spiritual Check-In Feature

## Overview

A beautiful, non-intrusive daily spiritual check-in system that encourages users to prioritize their time with God before using the app.

## How It Works

1. **On App Launch**: When the user opens the app for the first time each day, a glassmorphism popup appears asking "Have you spent time with God today?"

2. **User Response**:
   - **YES**: User proceeds to use the app normally
   - **NO**: User is shown an encouraging block screen that prevents app usage until they've spent time with God

3. **Daily Reset**: The check-in resets at midnight, so users are only asked once per day.

4. **App Resume**: When the app becomes active from background, it checks if the user has answered today. If they answered "No", the block screen is shown again.

## Files Created

### 1. `DailyCheckInView.swift`
The main popup dialog that asks the daily question.

**Features**:
- Beautiful glassmorphism design matching the reference image
- Smooth spring animations
- Haptic feedback
- Two-button interface (Yes/No)

### 2. `DailyCheckInManager.swift`
Manages the state and logic for the daily check-in.

**Key Responsibilities**:
- Tracks whether user has been asked today
- Stores user's answer in UserDefaults
- Handles day changes (midnight reset)
- Provides state to the app

**Properties**:
- `shouldShowCheckIn`: Whether to show the popup
- `hasAnsweredToday`: Whether user has answered today
- `userAnsweredYes`: What the user answered

**Methods**:
- `checkIfShouldShowCheckIn()`: Checks if popup should appear
- `recordAnswer(_ answeredYes: Bool)`: Saves user's response
- `handleAppBecameActive()`: Called when app becomes active
- `reset()`: For testing - clears saved data

### 3. `SpiritualBlockView.swift`
The encouraging block screen shown when user answers "No".

**Features**:
- Calming dark theme
- Animated prayer hands icon with pulsing effect
- Bible verse (Matthew 6:33)
- Practical suggestions for spending time with God:
  - Read a chapter from the Bible
  - Pray for 10 minutes
  - Listen to worship music
  - Journal what God is speaking
- Beautiful animations and transitions

### 4. `AMENAPPApp.swift` (Updated)
Integration point for the entire feature.

**Changes**:
- Added `@StateObject` for `DailyCheckInManager`
- Added state variables for showing check-in and block views
- Implemented z-index layering for proper view hierarchy
- Added notification observer for app becoming active
- Handles check-in answer logic

## Technical Implementation

### State Management

```swift
@StateObject private var checkInManager = DailyCheckInManager.shared
@State private var showCheckIn = false
@State private var showSpiritualBlock = false
```

### View Hierarchy (z-index)

```
0 - Main app (ContentView) or SpiritualBlockView
1 - Welcome screen (existing)
2 - Daily check-in popup (highest priority)
```

### Data Persistence

Uses `UserDefaults` to store:
- Last check-in date (as timestamp)
- Last answer (boolean)
- Whether user has answered today (boolean)

### Day Detection

```swift
let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())
// Compare with saved date to detect new day
```

## User Experience Flow

### Scenario 1: User Answers "Yes"
1. App launches
2. Popup appears after 0.5s delay
3. User taps "Yes"
4. Popup animates away
5. User can use app normally
6. App remembers answer until midnight

### Scenario 2: User Answers "No"
1. App launches
2. Popup appears after 0.5s delay
3. User taps "No"
4. Popup animates away
5. Block screen fades in with:
   - Encouraging message
   - Bible verse
   - Practical suggestions
6. User must close app and return after spending time with God
7. On return, if still same day, block screen shows again

### Scenario 3: App Returns from Background
1. User switches back to app
2. Manager checks if:
   - New day → Show check-in
   - Same day + answered "No" → Show block screen
   - Same day + answered "Yes" → Continue normally

## Design Philosophy

### Encouragement, Not Punishment
The block screen is designed to be:
- Calming and peaceful (dark theme, soft animations)
- Encouraging (positive messaging)
- Instructive (practical suggestions)
- Scripture-based (Matthew 6:33)

### Beautiful Aesthetics
- Glassmorphism effects matching modern iOS design
- Smooth spring animations
- Thoughtful transitions
- Haptic feedback for tactile response

### Non-Intrusive
- Only asks once per day
- Quick to answer (2 buttons)
- Remembers answer

## Customization Options

### Change the Question
Edit `DailyCheckInView.swift`:
```swift
Text("Have you spent time")
Text("with God today?")
```

### Modify Suggestions
Edit `SpiritualBlockView.swift`:
```swift
SuggestionRow(icon: "book.fill", text: "Your suggestion")
```

### Change Bible Verse
Edit `SpiritualBlockView.swift`:
```swift
Text("Your verse here")
Text("Reference")
```

### Adjust Timing
Edit `AMENAPPApp.swift`:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    // Change 0.5 to desired delay in seconds
}
```

### Testing
Reset the check-in for testing:
```swift
DailyCheckInManager.shared.reset()
```

## Integration with Authentication

Currently works independently of authentication. To integrate with Firebase Auth:

```swift
// In DailyCheckInManager
func checkIfShouldShowCheckIn() {
    guard Auth.auth().currentUser != nil else {
        // Don't show check-in if user not logged in
        shouldShowCheckIn = false
        return
    }
    // ... rest of logic
}
```

## Future Enhancements

Potential improvements:
1. **Streak Tracking**: Show "X days in a row" badge
2. **Reminders**: Optional notification if user hasn't opened app
3. **Custom Timing**: Allow users to set when their "day" starts
4. **Activity Logging**: Track what spiritual activities user did
5. **Sharing**: Let users share their consistency
6. **Firebase Sync**: Store responses in Firestore for multi-device sync
7. **Analytics**: Track engagement with the feature

## Accessibility

The feature supports:
- Dynamic Type (uses custom fonts that can scale)
- VoiceOver (all buttons and text are accessible)
- Dark Mode (designed specifically for dark theme)
- Color Contrast (high contrast text and buttons)

## Performance

- Lightweight: Only uses UserDefaults (no network calls)
- Fast: Animations are hardware-accelerated
- Efficient: Checks happen only on app launch/resume

## Privacy

- All data stored locally on device
- No tracking or analytics by default
- No personal information collected
- User can reset anytime

---

## Quick Start

The feature is already integrated! Just build and run your app.

To test:
1. Run the app
2. Answer the check-in question
3. Close and reopen the app (same day)
4. See that you're not asked again
5. To test again: `DailyCheckInManager.shared.reset()`

---

## Support

If you need to temporarily disable the feature:

```swift
// In AMENAPPApp.swift
// Comment out this line:
// if checkInManager.shouldShowCheckIn {
```

---

Built with ❤️ to encourage daily time with God.
