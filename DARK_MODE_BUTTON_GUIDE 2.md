# Dark Mode Button Visibility Guide

## Purpose
Ensure **all buttons are visible and have proper contrast** in both light and dark modes. This guide covers every button type in the AMEN app.

---

## Button Color Tokens (All Adaptive)

### Primary Buttons (High Emphasis)
**Use for:** Main CTAs (Follow, Post, Send Message, Create Post)

```swift
// Light: Black background, white text
// Dark: White background, black text
.background(Color.adaptiveButtonPrimaryBackground)
.foregroundColor(Color.adaptiveButtonPrimaryText)
```

**Contrast:**
- Light: White on black = 21:1 (AAA+++)
- Dark: Black on white = 21:1 (AAA+++)

**Example:**
```swift
Button("Follow") {
    // Action
}
.foregroundColor(Color.adaptiveButtonPrimaryText)
.padding(.horizontal, 20)
.padding(.vertical, 10)
.background(Color.adaptiveButtonPrimaryBackground)
.cornerRadius(20)
```

---

### Secondary Buttons (Medium Emphasis)
**Use for:** Follow/Following toggle, Edit Profile, Settings actions

```swift
// Light: White background with black border, black text
// Dark: Medium gray background with white border, white text
.background(Color.adaptiveButtonSecondaryBackground)
.foregroundColor(Color.adaptiveButtonSecondaryText)
.overlay(
    RoundedRectangle(cornerRadius: 20)
        .stroke(Color.adaptiveBorder, lineWidth: 1.5)
)
```

**Contrast:**
- Light: Black on white = 21:1 (AAA+++)
- Dark: White on gray = 12:1 (AAA++)

**Example:**
```swift
Button("Following") {
    // Action
}
.foregroundColor(Color.adaptiveButtonSecondaryText)
.padding(.horizontal, 20)
.padding(.vertical, 10)
.background(Color.adaptiveButtonSecondaryBackground)
.cornerRadius(20)
.overlay(
    RoundedRectangle(cornerRadius: 20)
        .stroke(Color.adaptiveBorder, lineWidth: 1.5)
)
```

---

### Tertiary Buttons (Low Emphasis)
**Use for:** Ghost buttons, subtle actions, Cancel buttons

```swift
// Light: Black 5% opacity background, black text
// Dark: White 10% opacity background, white text
.background(Color.adaptiveButtonTertiaryBackground)
.foregroundColor(Color.adaptiveButtonTertiaryText)
```

**Contrast:**
- Light: Black on very light gray ≥ 12:1 (AAA++)
- Dark: White on subtle gray ≥ 10:1 (AAA+)

**Example:**
```swift
Button("Cancel") {
    // Action
}
.foregroundColor(Color.adaptiveButtonTertiaryText)
.padding(.horizontal, 16)
.padding(.vertical, 8)
.background(Color.adaptiveButtonTertiaryBackground)
.cornerRadius(16)
```

---

### Destructive Buttons (Delete, Remove)
**Use for:** Delete post, Remove follower, Block user

```swift
// Light: Red background, white text
// Dark: Lighter red background, white text
.background(Color.adaptiveButtonDestructiveBackground)
.foregroundColor(Color.adaptiveButtonDestructiveText)
```

**Contrast:**
- Light: White on red ≥ 4.5:1 (AA+)
- Dark: White on lighter red ≥ 4.5:1 (AA+)

**Example:**
```swift
Button("Delete") {
    // Action
}
.foregroundColor(Color.adaptiveButtonDestructiveText)
.padding(.horizontal, 20)
.padding(.vertical, 10)
.background(Color.adaptiveButtonDestructiveBackground)
.cornerRadius(20)
```

---

### Icon Buttons (Icon-Only)
**Use for:** More menu (•••), Back button, Close (×), Settings gear

```swift
// Light: Black 5% opacity background, black 70% icon
// Dark: White 8% opacity background, white 70% icon
Circle()
    .fill(Color.adaptiveIconButtonBackground)
    .frame(width: 44, height: 44)
    .overlay(
        Image(systemName: "ellipsis")
            .foregroundColor(Color.adaptiveIconButtonForeground)
    )
```

**Contrast:**
- Light: Black icon on light gray ≥ 7:1 (AAA++)
- Dark: White icon on subtle gray ≥ 6:1 (AAA+)

**Example:**
```swift
Button {
    // Action
} label: {
    Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(Color.adaptiveIconButtonForeground)
        .frame(width: 44, height: 44)
        .background(
            Circle()
                .fill(Color.adaptiveIconButtonBackground)
        )
}
```

---

### Disabled Buttons
**Use for:** Non-interactive state (grayed out, cannot tap)

```swift
// Light: Black 10% opacity background, black 30% text
// Dark: White 10% opacity background, white 30% text
.background(Color.adaptiveButtonDisabledBackground)
.foregroundColor(Color.adaptiveButtonDisabledText)
.disabled(true)
```

**Contrast:**
- Light: Subtle gray background, faded text (intentionally low contrast)
- Dark: Subtle background, faded text

**Example:**
```swift
Button("Post") {
    // Action
}
.foregroundColor(postText.isEmpty ? Color.adaptiveButtonDisabledText : Color.adaptiveButtonPrimaryText)
.padding(.horizontal, 20)
.padding(.vertical, 10)
.background(postText.isEmpty ? Color.adaptiveButtonDisabledBackground : Color.adaptiveButtonPrimaryBackground)
.cornerRadius(20)
.disabled(postText.isEmpty)
```

---

### Accent Buttons (Gold, Category Colors)
**Use for:** Premium actions, category-specific buttons

```swift
// Gold buttons (same in both modes - inherently high contrast)
.background(Color.amenGold)
.foregroundColor(.white)  // Or .black depending on gold brightness

// Category buttons (adaptive, slightly lighter in dark mode)
.background(Color.amenPrayer)  // Purple
.foregroundColor(.white)
```

**Contrast:**
- Gold on white/dark: ≥ 4.5:1 (AA+)
- Category colors: ≥ 4.5:1 (AA+)

**Example:**
```swift
Button("Upgrade to Premium") {
    // Action
}
.foregroundColor(.white)
.padding(.horizontal, 24)
.padding(.vertical, 12)
.background(
    LinearGradient(
        colors: [Color.amenGold, Color.amenBronze],
        startPoint: .leading,
        endPoint: .trailing
    )
)
.cornerRadius(24)
```

---

## Button Types by Location

### Tab Bar Buttons
**Current:** Icon-only with selected state

```swift
// ✅ Tab icons - Already using .primary/.secondary (adaptive)
Image(systemName: "house.fill")
    .foregroundStyle(isSelected ? .primary : .secondary)

// ✅ Selected background - Works in both modes
.background(
    Capsule()
        .fill(Color.black.opacity(0.2))  // Keeps this - works well
)
```

**Status:** ✅ Already adaptive via `.primary`/`.secondary`

---

### Compact Tab Bar - Create Button
**Current:** Center circular button with plus icon

```swift
// ❌ BEFORE (Hardcoded)
Circle()
    .fill(Color.black)
    .overlay(
        Image(systemName: "plus")
            .foregroundColor(.white)
    )

// ✅ AFTER (Adaptive)
Circle()
    .fill(Color.adaptiveButtonPrimaryBackground)
    .overlay(
        Image(systemName: "plus")
            .foregroundColor(Color.adaptiveButtonPrimaryText)
    )
```

**Location:** ContentView.swift:996-1087

---

### Post Card Buttons

#### Like/Amen Button
```swift
// ✅ Already adaptive - using .primary with state
Image(systemName: hasAmen ? "heart.fill" : "heart")
    .foregroundStyle(hasAmen ? .red : .primary)
```

#### Lightbulb Button
```swift
// ✅ Already adaptive - using .primary with state
Image(systemName: hasLightbulb ? "lightbulb.fill" : "lightbulb")
    .foregroundStyle(hasLightbulb ? .yellow : .primary)
```

#### Comment Button
```swift
// ✅ Already adaptive
Image(systemName: "bubble.left")
    .foregroundStyle(.primary)
```

#### Share/Repost Buttons
```swift
// ✅ Already adaptive
Image(systemName: "arrow.2.squarepath")
    .foregroundStyle(hasReposted ? .green : .primary)
```

**Status:** ✅ Post card action buttons already use `.primary` (adaptive)

---

### Follow Buttons (Profile Avatar Overlay)

```swift
// ❌ BEFORE (Small button with hardcoded colors)
Circle()
    .fill(Color.blue)
    .overlay(
        Image(systemName: "plus")
            .foregroundColor(.white)
    )

// ✅ AFTER (Adaptive with clear visibility)
Circle()
    .fill(isFollowing ? Color.adaptiveButtonSecondaryBackground : Color.adaptiveButtonPrimaryBackground)
    .overlay(
        Image(systemName: isFollowing ? "checkmark" : "plus")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(isFollowing ? Color.adaptiveButtonSecondaryText : Color.adaptiveButtonPrimaryText)
    )
    .overlay(
        Circle()
            .stroke(Color.adaptiveBorder, lineWidth: 1.5)
    )
```

**Location:** PostCard.swift (follow button on avatar)

---

### Profile Header Buttons

#### Edit Profile Button
```swift
// ✅ Use secondary button style
Button("Edit Profile") {
    // Action
}
.foregroundColor(Color.adaptiveButtonSecondaryText)
.padding(.horizontal, 20)
.padding(.vertical, 10)
.background(Color.adaptiveButtonSecondaryBackground)
.cornerRadius(20)
.overlay(
    RoundedRectangle(cornerRadius: 20)
        .stroke(Color.adaptiveBorder, lineWidth: 1.5)
)
```

#### Follow/Following Button
```swift
// ✅ Toggles between primary and secondary
Button(isFollowing ? "Following" : "Follow") {
    // Action
}
.foregroundColor(isFollowing ? Color.adaptiveButtonSecondaryText : Color.adaptiveButtonPrimaryText)
.padding(.horizontal, 20)
.padding(.vertical, 10)
.background(isFollowing ? Color.adaptiveButtonSecondaryBackground : Color.adaptiveButtonPrimaryBackground)
.cornerRadius(20)
.overlay(
    RoundedRectangle(cornerRadius: 20)
        .stroke(isFollowing ? Color.adaptiveBorder : Color.clear, lineWidth: 1.5)
)
```

**Location:** ProfileView.swift, UserProfileView.swift

---

### Message Send Button

```swift
// ❌ BEFORE (Blue circle with white arrow)
Circle()
    .fill(Color.blue)
    .overlay(
        Image(systemName: "arrow.up")
            .foregroundColor(.white)
    )

// ✅ AFTER (Adaptive primary button)
Circle()
    .fill(messageText.isEmpty ? Color.adaptiveButtonDisabledBackground : Color.adaptiveButtonPrimaryBackground)
    .overlay(
        Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(messageText.isEmpty ? Color.adaptiveButtonDisabledText : Color.adaptiveButtonPrimaryText)
    )
```

**Location:** UnifiedChatView.swift, MessagesView.swift

---

### Create Post Buttons

#### Post/Publish Button (Toolbar)
```swift
// ✅ Primary button style
Button("Post") {
    // Action
}
.foregroundColor(postText.isEmpty ? Color.adaptiveButtonDisabledText : Color.adaptiveButtonPrimaryText)
.padding(.horizontal, 16)
.padding(.vertical, 8)
.background(
    Capsule()
        .fill(postText.isEmpty ? Color.adaptiveButtonDisabledBackground : Color.adaptiveButtonPrimaryBackground)
)
.disabled(postText.isEmpty)
```

#### Category Pills (Selection)
```swift
// ✅ Toggle between selected/unselected
Button(category.displayName) {
    // Action
}
.foregroundColor(isSelected ? Color.adaptiveButtonPrimaryText : Color.adaptiveButtonSecondaryText)
.padding(.horizontal, 16)
.padding(.vertical, 10)
.background(
    Capsule()
        .fill(isSelected ? Color.adaptiveButtonPrimaryBackground : Color.adaptiveButtonSecondaryBackground)
)
.overlay(
    Capsule()
        .stroke(Color.adaptiveBorder, lineWidth: isSelected ? 0 : 1.5)
)
```

**Location:** CreatePostView.swift

---

### Sheet/Modal Close Buttons

```swift
// ✅ Icon button style (top-leading X button)
Button {
    dismiss()
} label: {
    Image(systemName: "xmark")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(Color.adaptiveIconButtonForeground)
        .frame(width: 44, height: 44)
        .background(
            Circle()
                .fill(Color.adaptiveIconButtonBackground)
        )
}
```

---

### Settings Buttons

#### List Row Buttons (Chevron navigation)
```swift
// ✅ Already adaptive with .primary
NavigationLink {
    // Destination
} label: {
    HStack {
        Text("Account Settings")
            .foregroundColor(Color.adaptiveTextPrimary)
        Spacer()
        Image(systemName: "chevron.right")
            .foregroundColor(Color.adaptiveTextTertiary)
    }
}
```

#### Toggle Switches
```swift
// ✅ Native SwiftUI toggles - automatically adaptive
Toggle("Dark Mode", isOn: $isDarkMode)
    .tint(Color.amenGold)  // Accent color for "on" state
```

#### Action Buttons (Sign Out, Delete Account)
```swift
// ✅ Destructive button style
Button("Sign Out") {
    // Action
}
.foregroundColor(Color.adaptiveButtonDestructiveText)
.padding()
.frame(maxWidth: .infinity)
.background(Color.adaptiveButtonDestructiveBackground)
.cornerRadius(12)
```

**Location:** SettingsView.swift, AccountSettingsView.swift

---

## Critical Button Visibility Checklist

For each button in the app, verify:

### Visual Validation
- [ ] **Light mode:** Button clearly visible on white/light background
- [ ] **Dark mode:** Button clearly visible on dark/charcoal background
- [ ] **Contrast ratio:** ≥ 4.5:1 for text, ≥ 3:1 for UI elements
- [ ] **Pressed state:** Immediate visual feedback (opacity change, scale, etc.)
- [ ] **Disabled state:** Clearly different from enabled state
- [ ] **Selected state:** (if applicable) Clearly shows selection
- [ ] **Hover state:** (iPad with pointer) Shows hover feedback

### Functional Validation
- [ ] **Tappable area:** ≥ 44x44 points (Apple HIG minimum)
- [ ] **Haptic feedback:** Immediate tactile response
- [ ] **Animation:** Smooth press/release animation
- [ ] **Loading state:** Spinner or disabled state during action
- [ ] **Error state:** Red/destructive color if action fails

### Accessibility Validation
- [ ] **VoiceOver:** Button label announced correctly
- [ ] **Dynamic Type:** Button accommodates larger text sizes
- [ ] **Reduce Motion:** Button still visible without animations
- [ ] **High Contrast:** Button maintains visibility in high contrast mode

---

## Testing Script for Button Visibility

### Rapid Testing Workflow
1. **Build and run app**
2. **Switch to dark mode** (Settings → Display → Dark)
3. **Visit each screen** in order:
   - Home feed (tab bar buttons)
   - Post card (action buttons)
   - Profile (follow button, edit profile)
   - Messages (send button)
   - Create Post (post button, category pills)
   - Notifications (action buttons)
   - Settings (list buttons, toggles)

4. **For each button:**
   - **Tap it** - Does it respond immediately?
   - **Look at it** - Can you clearly see it?
   - **Switch modes** - Still visible in both?

5. **Switch back to light mode**
6. **Repeat test** - All buttons still work?

---

## Common Button Issues & Fixes

### Issue: Button disappears in dark mode
**Cause:** Hardcoded white background on dark surface  
**Fix:** Use `Color.adaptiveButtonSecondaryBackground`

### Issue: Button text unreadable
**Cause:** Same color text and background  
**Fix:** Use contrasting pair (e.g., `adaptiveButtonPrimaryBackground` + `adaptiveButtonPrimaryText`)

### Issue: Icon button invisible
**Cause:** Black icon on dark background  
**Fix:** Use `Color.adaptiveIconButtonForeground` (auto-adapts to white 70% in dark)

### Issue: Disabled button looks the same as enabled
**Cause:** Not using disabled color tokens  
**Fix:** Use `Color.adaptiveButtonDisabledBackground` and `Color.adaptiveButtonDisabledText`

### Issue: Button has no border in dark mode
**Cause:** Black border on dark background  
**Fix:** Use `Color.adaptiveBorder` (white 20% in dark)

---

## Migration Priority - Buttons

### Phase 1: Critical Buttons (Day 1)
1. ✅ Create Post button (center of tab bar)
2. ✅ Follow/Unfollow buttons (everywhere)
3. ✅ Post/Send buttons (CreatePostView, MessagesView)
4. ✅ Tab bar icons (already adaptive via `.primary`)

### Phase 2: Interaction Buttons (Day 2)
5. ✅ Like/Amen buttons (post cards)
6. ✅ Comment buttons
7. ✅ Share/Repost buttons
8. ✅ More menu buttons (•••)

### Phase 3: Navigation Buttons (Day 3)
9. ✅ Back buttons
10. ✅ Close buttons (sheets)
11. ✅ Settings navigation
12. ✅ Profile navigation

### Phase 4: Special Buttons (Day 4)
13. ✅ Category pills (CreatePostView)
14. ✅ Filter chips (NotificationsView, MessagesView)
15. ✅ Quick action buttons
16. ✅ Destructive buttons (Delete, Block)

---

## Button Component Examples

### Reusable Button Component
Create a reusable button component to ensure consistency:

```swift
// AdaptiveButton.swift
struct AdaptiveButton: View {
    let title: String
    let style: ButtonStyle
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case tertiary
        case destructive
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundColor(textColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(backgroundColor)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(borderColor, lineWidth: style == .secondary ? 1.5 : 0)
                )
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary: return Color.adaptiveButtonPrimaryBackground
        case .secondary: return Color.adaptiveButtonSecondaryBackground
        case .tertiary: return Color.adaptiveButtonTertiaryBackground
        case .destructive: return Color.adaptiveButtonDestructiveBackground
        }
    }
    
    private var textColor: Color {
        switch style {
        case .primary: return Color.adaptiveButtonPrimaryText
        case .secondary: return Color.adaptiveButtonSecondaryText
        case .tertiary: return Color.adaptiveButtonTertiaryText
        case .destructive: return Color.adaptiveButtonDestructiveText
        }
    }
    
    private var borderColor: Color {
        style == .secondary ? Color.adaptiveBorder : Color.clear
    }
}

// Usage:
AdaptiveButton(title: "Follow", style: .primary) {
    // Action
}
```

---

## Success Metrics

Button visibility is successful when:
- [ ] **100% of buttons visible** in both light and dark modes
- [ ] **All contrast ratios ≥ 4.5:1** (WCAG AA minimum)
- [ ] **Zero user reports** of "can't find button" or "button invisible"
- [ ] **Immediate feedback** on all button taps (< 100ms)
- [ ] **Consistent styling** across app (no outliers)

---

## Resources

- **Color tokens:** `AmenAdaptiveColors.swift` (lines 130-210)
- **Migration checklist:** `DARK_MODE_MIGRATION_CHECKLIST.md`
- **Testing guide:** `DARK_MODE_VALIDATION_GUIDE.md`
- **Apple HIG:** [Human Interface Guidelines - Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- **WCAG:** [Web Content Accessibility Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

---

**Next Step:** Start button migration with CompactTabBar create button (most visible), then follow priority list above.
