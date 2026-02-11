# Church Notes - Animation & Interaction Guide

## Visual Hierarchy

```
┌─────────────────────────────────────┐
│  🌟 Animated Gradient Background    │
│  ├─ Cycles every 8 seconds          │
│  └─ Subtle, non-distracting         │
├─────────────────────────────────────┤
│  📱 Liquid Glass Header              │
│  ├─ Church Notes [shrinks on scroll]│
│  ├─ Subtitle [hides on scroll]      │
│  ├─ [+] Button [bounce + rotate]    │
│  └─ Search Bar [focus animations]   │
├─────────────────────────────────────┤
│  🔍 Filter Pills [fade on scroll]   │
│  ├─ All Notes [glass pill]          │
│  ├─ Favorites [glass pill]          │
│  └─ Recent [glass pill]             │
├─────────────────────────────────────┤
│  📝 Note Cards [staggered entrance] │
│  ├─ Card 1 [delay: 0ms]            │
│  ├─ Card 2 [delay: 50ms]           │
│  ├─ Card 3 [delay: 100ms]          │
│  └─ ... continues                    │
└─────────────────────────────────────┘
```

## User Interaction Flow

### 1. Opening the View
```
User Opens Church Notes
         ↓
Background Gradient Starts Animating (8s cycle)
         ↓
Header Appears (fade + slide from top)
         ↓
Filter Pills Appear (fade in)
         ↓
Note Cards Stagger In (waterfall effect)
```

### 2. Searching for Notes
```
User Taps Search Bar
         ↓
Focus Animation Triggered
├─ Icon morphs: 🔍 → 🔍●
├─ Border glows purple
├─ Scale increases (1.0 → 1.02)
└─ Haptic feedback (light)
         ↓
User Types
├─ Selection haptic per character
└─ Results filter in real-time
         ↓
User Taps Clear (✕)
├─ Text clears
├─ Focus releases
├─ Scale returns (1.02 → 1.0)
└─ Border fades
```

### 3. Interacting with Note Card
```
User Taps Note Card
         ↓
Press Animation
├─ Scale down (1.0 → 0.97)
├─ Haptic feedback (light)
└─ Spring animation (0.2s)
         ↓
Release Animation
├─ Scale up (0.97 → 1.0)
└─ Spring bounce (0.3s)
         ↓
Sheet Presents (note detail)
└─ Large detent, drag indicator
```

### 4. Favoriting a Note
```
User Taps Star Icon
         ↓
Favorite Toggle Begins
         ↓
┌──────────────┬──────────────┐
│ If Favoriting│ If Removing  │
├──────────────┼──────────────┤
│ Icon: ⭐️ → ★ │ Icon: ★ → ⭐️ │
│ Glow: On     │ Glow: Off    │
│ Rotate: -10° │ Rotate: +10° │
│ Haptic:      │ Haptic:      │
│  Success ✅  │  Warning ⚠️  │
└──────────────┴──────────────┘
         ↓
Return to Center (0°)
└─ Spring bounce (0.3s)
```

### 5. Scrolling
```
User Scrolls Down
         ↓
Scroll Offset Updates
         ↓
If offset > -20:
├─ Header title shrinks (32pt → 28pt)
└─ Subtitle hides
         ↓
If offset > -100:
└─ Filter pills fade out (opacity: 1 → 0)
         ↓
User Scrolls Up
         ↓
Elements Restore
├─ Title grows back
├─ Subtitle returns
└─ Filter pills fade in
```

## Animation Curves

### Spring Physics
```
response: 0.3s (fast)      ━━━╱╲
              damping: 0.5  ━━╱──╲
                            ╱────╲____

response: 0.4s (normal)    ━━━━╱╲
              damping: 0.7  ━━━╱──╲
                            ━━╱────╲__

response: 0.6s (slow)      ━━━━━━╱╲
              damping: 0.8  ━━━━━╱──╲
                            ━━━━╱────╲
```

### Stagger Effect
```
Card 1: ████████░░░░░░░░  (0ms delay)
Card 2: ░████████░░░░░░░  (50ms delay)
Card 3: ░░████████░░░░░░  (100ms delay)
Card 4: ░░░████████░░░░░  (150ms delay)
Card 5: ░░░░████████░░░░  (200ms delay)
```

## Glass Effect Layers

### Layer Stack (bottom to top)
```
┌─────────────────────────────────────┐
│ 5. Border Stroke (gradient)         │ ← Top
├─────────────────────────────────────┤
│ 4. White Gradient Overlay (10-5%)   │
├─────────────────────────────────────┤
│ 3. Black Tint (15-20%)              │
├─────────────────────────────────────┤
│ 2. Ultra Thin Material (frosted)    │
├─────────────────────────────────────┤
│ 1. Shadow Layer (dual)              │ ← Bottom
└─────────────────────────────────────┘
```

### Shadow Configuration
```
Primary Shadow:
├─ color: black @ 30%
├─ radius: 20pt
└─ y-offset: 8pt

Secondary Shadow:
├─ color: black @ 15%
├─ radius: 10pt
└─ y-offset: 4pt
```

## Haptic Patterns

### Light Impact 💫
- Card taps
- Minor button presses
- Search clear
- Tag interactions

### Medium Impact 💥
- Create note button
- Major action confirmations
- Sheet presentations

### Success Notification ✅
- Adding to favorites
- Note saved
- Action completed

### Warning Notification ⚠️
- Removing from favorites
- Canceling actions

### Selection Feedback 🎯
- Typing in search
- Filter changes
- Toggle switches

## Color Transitions

### Focus State
```
Unfocused → Focused

Border:
  white @ 20% ━━━━━━━> purple @ 50%
  
Background:
  transparent ━━━━━━━> purple @ 10%
  
Icon:
  white @ 60% ━━━━━━━> purple @ 100%
  
Scale:
  1.0 ━━━━━━━━━━━━━> 1.02
```

### Favorite State
```
Unfavorited → Favorited

Icon:
  ⭐️ white @ 60% ━━━━> ★ yellow @ 100%
  
Glow:
  none ━━━━━━━━━━━━> yellow @ 20% (radius: 8)
  
Scale:
  1.0 → 1.1 → 1.0 (bounce)
  
Rotation:
  0° → -10° → 0° (wobble)
```

## Performance Metrics

### Target FPS: 60
- Background gradient: GPU-accelerated
- Card animations: Core Animation
- Scroll tracking: Throttled updates
- Shadow rendering: Cached layers

### Memory Usage
- LazyVStack: Only visible cards
- Image caching: Automatic
- Animation cleanup: On disappear

### Optimization Techniques
1. Use `LazyVStack` not `VStack`
2. Cache shadow layers
3. Throttle scroll callbacks
4. Combine similar animations
5. Remove animations on disappear

## Accessibility Considerations

### Reduce Motion
When enabled:
- Disable gradient animation
- Use fade transitions only
- Remove scale effects
- Simplify haptics

### VoiceOver
- All buttons labeled
- Card content announced
- State changes spoken
- Hints provided

### Dynamic Type
- Font sizes scale
- Layout adjusts
- Touch targets expand
- Minimum sizes maintained

## Code Patterns

### Animation Best Practice
```swift
// ✅ GOOD: Named, reusable animation
let cardTapAnimation = Animation.spring(
    response: 0.2,
    dampingFraction: 0.6
)

withAnimation(cardTapAnimation) {
    cardScale = 0.97
}

// ❌ AVOID: Inline, repeated values
withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
    // ...
}
```

### Haptic Best Practice
```swift
// ✅ GOOD: Appropriate feedback type
let haptic = UIImpactFeedbackGenerator(style: .light)
haptic.impactOccurred()

// ❌ AVOID: Wrong feedback type
let haptic = UINotificationFeedbackGenerator()
haptic.notificationOccurred(.success) // for minor tap?
```

### Transition Best Practice
```swift
// ✅ GOOD: Asymmetric, meaningful
.transition(.asymmetric(
    insertion: .move(edge: .bottom).combined(with: .opacity),
    removal: .opacity
))

// ❌ AVOID: Same in/out (jarring)
.transition(.move(edge: .bottom))
```

## Testing Checklist

### Visual
- [ ] Animations smooth at 60fps
- [ ] No frame drops during scroll
- [ ] Glass effect renders correctly
- [ ] Colors match design spec
- [ ] Shadows look natural

### Interactive
- [ ] Taps feel responsive
- [ ] Haptics feel appropriate
- [ ] Gestures don't conflict
- [ ] Animations don't overlap
- [ ] State changes are clear

### Performance
- [ ] Memory stable over time
- [ ] CPU usage reasonable
- [ ] Battery drain acceptable
- [ ] Works on older devices
- [ ] No memory leaks

### Accessibility
- [ ] VoiceOver works correctly
- [ ] Reduce Motion supported
- [ ] Dynamic Type scales
- [ ] High contrast readable
- [ ] Touch targets adequate

## Conclusion

This guide documents the complete animation and interaction system for Church Notes. Every animation has a purpose: to guide attention, confirm actions, or delight users. The Liquid Glass aesthetic creates a premium, modern feel while maintaining excellent performance and accessibility.
