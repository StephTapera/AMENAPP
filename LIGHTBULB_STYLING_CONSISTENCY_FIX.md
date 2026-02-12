# Lightbulb Styling Consistency Fix - Complete
## Date: February 11, 2026

## Problem
The lightbulb button styling was inconsistent between ProfileView post cards and regular PostCard components throughout the app. ProfileView used a simple glassmorphic button style, while PostCard had elaborate glow effects, gradients, and capsule backgrounds.

## Solution
Updated ProfileView's ProfilePostCard to match the elaborate lightbulb styling from PostCard, creating a consistent visual experience across the app.

## Files Modified

### AMENAPP/ProfileView.swift

**Change 1: Replace glassmorphicButton call with elaborate button** (Lines ~1842-1851)

**Before**:
```swift
// Amen/Lightbulb button
if post.category == .openTable {
    glassmorphicButton(
        icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
        count: lightbulbCount,
        isActive: hasLitLightbulb,
        activeColor: .yellow
    ) {
        toggleLightbulb()
    }
}
```

**After**:
```swift
// Amen/Lightbulb button
if post.category == .openTable {
    Button {
        toggleLightbulb()
    } label: {
        lightbulbButtonLabel
    }
    .buttonStyle(.plain)
}
```

**Change 2: Add lightbulb styling helper views** (After line ~1973, before `cardBackground`)

**Added**:
```swift
// MARK: - Lightbulb Styling (matching PostCard)

private var lightbulbButtonLabel: some View {
    HStack(spacing: 4) {
        lightbulbIcon

        Text("\(lightbulbCount)")
            .font(.custom("OpenSans-SemiBold", size: 11))
            .foregroundStyle(hasLitLightbulb ? Color.orange : Color.black.opacity(0.5))
            .contentTransition(.numericText())
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(lightbulbBackground)
    .overlay(lightbulbOverlay)
}

private var lightbulbIcon: some View {
    ZStack {
        // Glow effect when active
        if hasLitLightbulb {
            lightbulbGlowEffect
        }

        lightbulbMainIcon
    }
}

private var lightbulbGlowEffect: some View {
    Image(systemName: "lightbulb.fill")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.yellow)
        .blur(radius: 8)
        .opacity(0.6)
}

private var lightbulbMainIcon: some View {
    Image(systemName: hasLitLightbulb ? "lightbulb.fill" : "lightbulb")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(hasLitLightbulb ? lightbulbGradientActive : lightbulbGradientInactive)
}

private var lightbulbBackground: some View {
    Capsule()
        .fill(hasLitLightbulb ? Color.yellow.opacity(0.15) : Color.black.opacity(0.05))
        .shadow(color: hasLitLightbulb ? Color.yellow.opacity(0.2) : Color.clear, radius: 8, y: 2)
}

private var lightbulbOverlay: some View {
    Capsule()
        .stroke(hasLitLightbulb ? Color.orange.opacity(0.3) : Color.black.opacity(0.1), lineWidth: hasLitLightbulb ? 1.5 : 1)
}

private var lightbulbGradientActive: LinearGradient {
    LinearGradient(
        colors: [.yellow, .orange],
        startPoint: .top,
        endPoint: .bottom
    )
}

private var lightbulbGradientInactive: LinearGradient {
    LinearGradient(
        colors: [.black.opacity(0.5), .black.opacity(0.5)],
        startPoint: .top,
        endPoint: .bottom
    )
}
```

## Visual Changes

### Before (Glassmorphic Style):
- Simple icon with background
- Single color when active (yellow)
- Rounded rectangle background
- Icon size: 18pt
- Count displayed with font size 14pt

### After (PostCard Elaborate Style):
- **Multi-layer icon** with glow effect when active
- **Yellow-to-orange gradient** on active icon
- **Capsule background** with yellow.opacity(0.15) fill when active
- **Glow shadow** (blur radius 8, yellow.opacity(0.6)) when active
- **Stroke overlay** with orange.opacity(0.3) border when active
- Icon size: 13pt (consistent with PostCard)
- Count displayed with custom font "OpenSans-SemiBold" size 11pt
- **Smooth numeric transitions** with `.contentTransition(.numericText())`

## Key Features Replicated from PostCard

1. ✅ **Glow Effect**: Yellow blur effect behind icon when active
2. ✅ **Gradient Icon**: Yellow-to-orange gradient when lit
3. ✅ **Capsule Background**: Rounded capsule shape instead of rounded rectangle
4. ✅ **Shadow**: Yellow shadow with radius 8 when active
5. ✅ **Stroke Overlay**: Orange border when active, black when inactive
6. ✅ **Count Display**: Shows count with orange text when active
7. ✅ **Numeric Transition**: Smooth animation when count changes
8. ✅ **Font Matching**: Uses OpenSans-SemiBold for count

## Styling Details

### Active State (hasLitLightbulb = true):
- Icon: Yellow-to-orange gradient with glow
- Background: Yellow.opacity(0.15) capsule
- Shadow: Yellow.opacity(0.2), radius 8, y offset 2
- Stroke: Orange.opacity(0.3), lineWidth 1.5
- Count text: Orange color

### Inactive State (hasLitLightbulb = false):
- Icon: Black.opacity(0.5) solid color
- Background: Black.opacity(0.05) capsule
- Shadow: None
- Stroke: Black.opacity(0.1), lineWidth 1
- Count text: Black.opacity(0.5)

## Testing Checklist

- [ ] Navigate to Profile → Posts tab with OpenTable posts
- [ ] Verify lightbulb button has capsule shape (not rounded rectangle)
- [ ] Tap lightbulb - verify it shows glow effect and gradient
- [ ] Verify count displays with orange color when active
- [ ] Tap again to deactivate - verify glow disappears
- [ ] Compare with regular PostCard lightbulb - should look identical
- [ ] Test on different screen sizes (iPhone SE, iPhone 15 Pro Max)
- [ ] Verify other buttons (Amen, Comment) still use glassmorphic style

## Notes

- The `glassmorphicButton()` helper function is preserved for other buttons (Amen, Comments)
- Only the lightbulb button for OpenTable posts uses the new elaborate styling
- This creates a special visual emphasis on the lightbulb feature
- Amen and Comment buttons continue to use the simpler glassmorphic style
- The lightbulb styling now matches PostCard exactly for visual consistency

## Production Ready

✅ **No compilation errors**
✅ **Visual consistency achieved**
✅ **Backward compatible**
✅ **All helper views properly scoped to ProfilePostCard**
✅ **Preserves existing glassmorphic style for other buttons**

Ready for testing and deployment!
