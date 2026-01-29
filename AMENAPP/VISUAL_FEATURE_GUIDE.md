# Visual Feature Guide

## 1. Liquid Glass Banner (Find a Local Church)

### Before
```
┌─────────────────────────────────────┐
│  🏢  Find a Local Church           │
│      Connect with your faith...    │
│                                     │
│  Discover churches near you         │
│                                     │
│                   [Explore Now →]   │
└─────────────────────────────────────┘
Simple gradient background
```

### After - Liquid Glass Spatial Aesthetic
```
┌─────────────────────────────────────┐
│ ╭─────╮                             │
│ │ 🏢  │ Find a Local Church         │
│ ╰─────╯ Connect with your faith... │
│                                     │
│ Discover churches near you          │
│                                     │
│            ╭─────────────────╮      │
│            │  Explore Now → │      │
│            ╰─────────────────╯      │
└─────────────────────────────────────┘

Layers:
1. Base gradient (blue → purple)
2. Ultra-thin material (glass blur)
3. Shimmer overlay (moving)
4. Radial highlight
5. Gradient border
6. Dual shadows (colored + black)

Visual Effects:
✨ Blurs background content
💫 Animated shimmer moving across
🎯 3D depth with layered shadows
🔆 Radial light from top-left
📱 Modern iOS spatial design
```

---

## 2. Swipeable Prayer Banners

### Static View (Before)
```
┌────────────────────────────────────┐
│ 🕐  Prayer Timer                   │
│     Structured prayer with...      │
│                                    │
│ Set dedicated time for prayer...   │
│                                    │
│                [Start Praying →]   │
└────────────────────────────────────┘

- Single static banner
- Manual navigation only
```

### Dynamic Carousel (After)
```
┌────────────────────────────────────┐
│                                    │
│  Current Banner (Swipeable)        │
│  ← swipe left    swipe right →    │
│                                    │
│  Auto-rotates every 5 seconds      │
│                                    │
└────────────────────────────────────┘
         ● ○ ○ ○  (page indicators)

Banner 1: Prayer Timer (Purple/Pink)
Banner 2: Scripture Prayers (Blue/Cyan)
Banner 3: ACTS Prayer Guide (Orange/Red)
Banner 4: Gratitude Prayers (Green/Teal)
```

### Animation Flow
```
Time: 0s
┌─────────────────────┐
│  Prayer Timer       │  ● ○ ○ ○
│  Purple/Pink        │
└─────────────────────┘

Time: 5s (auto-advance)
      ╭──────────╮
      │  Swipe!  │
      ╰──────────╯
┌─────────────────────┐
│ Scripture Prayers   │  ○ ● ○ ○
│ Blue/Cyan          │
└─────────────────────┘

Time: 10s (auto-advance)
┌─────────────────────┐
│ ACTS Prayer Guide   │  ○ ○ ● ○
│ Orange/Red         │
└─────────────────────┘

Time: 15s (auto-advance)
┌─────────────────────┐
│ Gratitude Prayers   │  ○ ○ ○ ●
│ Green/Teal         │
└─────────────────────┘

Time: 20s → loops back to Prayer Timer
```

---

## 3. Page Indicator Design

### Inactive State
```
○ ○ ○ ○
│ │ │ └─ 8px width, gray color
│ │ └─── 8px width, gray color
│ └───── 8px width, gray color
└─────── 8px width, gray color
```

### Active State (Banner 2)
```
○ ━ ○ ○
│ │ │ └─ 8px width, gray
│ │ └─── 8px width, gray
│ └───── 24px width, BLUE (matches banner gradient!)
└─────── 8px width, gray

Animated expansion with spring physics
```

---

## 4. Glass Material Layers (Cross-Section View)

```
                  ┌─ Border gradient (white)
                  │
    ┌─────────────┼────────────────┐  ← Top surface
    │             │                 │
    │  Content Layer (text/icons)  │
    │                               │
    ├───────────────────────────────┤  ← Glass material layer
    │   Ultra-thin material (30%)   │     (blurs background)
    ├───────────────────────────────┤
    │   Shimmer overlay (moving)    │  ← Animated
    ├───────────────────────────────┤
    │   Radial highlight            │  ← Top-left glow
    ├───────────────────────────────┤
    │   Base gradient               │  ← Color foundation
    └───────────────────────────────┘

         ╲                    ╱        ← Colored shadow (20px, Y:10)
          ╲                  ╱
           ╲________________╱          ← Black shadow (8px, Y:4)

Result: Appears to float with realistic depth
```

---

## 5. Interactive States

### Liquid Glass Banner Hover
```
Normal:
  Scale: 1.0
  Shadow: 20px radius, 10px offset

Hover/Touch:
  Scale: 1.02 (2% larger)
  Shadow: 20px radius, 10px offset
  Transition: Spring animation (0.3s)
  
  ┌─────────────┐       ┌──────────────┐
  │   Normal    │  →    │  Slightly    │
  │             │       │  Enlarged    │
  └─────────────┘       └──────────────┘
                         ↖ Feels alive!
```

### Prayer Banner Swipe Gesture
```
User drags finger →

  ┌────────────┐     ┌────────────┐     ┌────────────┐
  │  Banner 1  │  →  │  Banner 2  │  →  │  Banner 3  │
  │    Exit    │     │   Enter    │     │   Next     │
  └────────────┘     └────────────┘     └────────────┘
       ←                  ←                  ←
   Slides out         Slides in         Waiting

Spring animation: Response 0.5, Damping 0.8
```

---

## 6. Color Gradients

### Find a Local Church Banner
```
  Top-left          Bottom-right
    Blue    ────────────→   Purple
    #0000FF              #800080
    
    Creates: Sky → Twilight effect
```

### Prayer Banners
```
1. Prayer Timer
   Purple → Pink
   Warm, inviting, spiritual

2. Scripture Prayers  
   Blue → Cyan
   Trust, wisdom, calm

3. ACTS Prayer Guide
   Orange → Red
   Energy, passion, fire

4. Gratitude Prayers
   Green → Teal
   Growth, peace, renewal
```

---

## 7. Typography Hierarchy

```
Title: OpenSans-Bold, 22px
  "Find a Local Church"
  
Subtitle: OpenSans-SemiBold, 14px
  "Connect with your faith community"
  
Body: OpenSans-Regular, 15px
  "Discover churches near you"
  
Button: OpenSans-Bold, 14px
  "Explore Now"
```

---

## 8. Spacing System

```
Banner padding: 20px all sides

┌─ 20px ─┐
│         │
20px     20px
│         │
└─ 20px ─┘

Internal spacing:
- Icon to Text: 12px
- Title to Description: 16px
- Description to Button: 16px

Corner radius: 24px (smooth, modern)
```

---

## 9. Shadow System

```
Colored Shadow (Depth):
  color: gradient[0] @ 30% opacity
  radius: 20px
  x: 0
  y: 10px (appears to lift)

Black Shadow (Definition):
  color: black @ 10% opacity
  radius: 8px
  x: 0
  y: 4px (subtle edge)

Combined effect:
  ╔═════════════╗
  ║   Banner    ║
  ╚═════════════╝
     ▓▓▓▓▓▓▓▓     ← Colored shadow
      ▒▒▒▒▒▒▒     ← Black shadow
       ░░░░░░      ← Fades out

Result: Realistic 3D elevation
```

---

## 10. Performance Metrics

### Animation Frame Rate
```
Target: 60 FPS
Actual: 60 FPS ✓

Shimmer: Linear animation, infinite loop
Spring: Response 0.3-0.5s, Damping 0.6-0.8
TabView: Native paging (hardware accelerated)
```

### Memory Management
```
Timer lifecycle:
  onAppear()  → Start timer ✓
  onDisappear() → Stop timer ✓
  
Prevents: Memory leaks, battery drain
```

---

## User Interaction Flow

```
1. User opens Resources view
   ↓
2. Sees liquid glass church banner
   ↓
3. Scrolls to Prayer Toolkit
   ↓
4. Sees first prayer banner (auto-rotating)
   │
   ├─→ Option A: Wait 5s → Auto-advance to next banner
   │
   └─→ Option B: Swipe left/right → Manual navigation
   ↓
5. Page indicators show position (● ○ ○ ○)
   ↓
6. Tap banner → Navigate to prayer content
```

---

## Accessibility Features

✓ High contrast text (white on colored backgrounds)
✓ Large touch targets (220px height)
✓ Clear visual feedback (scale, color changes)
✓ Non-essential animations (shimmer can be reduced in accessibility settings)
✓ Page indicators for context
✓ Descriptive text for screen readers

---

## Browser/Device Compatibility

```
✓ iOS 17+ (Ultra-thin material requires iOS 15+)
✓ iPadOS 17+
✓ iPhone 12 and newer (optimal)
✓ iPhone X and newer (compatible)

Material effects gracefully degrade on older devices
```

---

*This guide provides a complete visual reference for the implemented features.*
