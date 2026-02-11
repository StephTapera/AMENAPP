# 🎨 UserProfileView: Visual Interaction Guide

## 📱 Tap-to-Expand Interaction

```
┌─────────────────────────────────────────┐
│  Post Content (Collapsed - 4 lines)     │
│  ─────────────────────────────────      │
│  Lorem ipsum dolor sit amet,            │
│  consectetur adipiscing elit. Sed do    │
│  eiusmod tempor incididunt ut labore    │
│  et dolore magna aliqua. Ut enim...     │
│                                         │
│  ▼ See More                             │  ← Tap this
│  ─────────────────────────────────      │
│  2h ago  ⚪ Prayer                      │
│                                         │
│  👏  💬 12                              │
└─────────────────────────────────────────┘

        ↓ TAPS "See More"

┌─────────────────────────────────────────┐
│  Post Content (Expanded - Full)         │
│  ─────────────────────────────────      │
│  Lorem ipsum dolor sit amet,            │
│  consectetur adipiscing elit. Sed do    │
│  eiusmod tempor incididunt ut labore    │
│  et dolore magna aliqua. Ut enim ad     │
│  minim veniam, quis nostrud             │
│  exercitation ullamco laboris nisi ut   │
│  aliquip ex ea commodo consequat.       │
│  Duis aute irure dolor in               │
│  reprehenderit in voluptate velit esse  │
│  cillum dolore eu fugiat nulla          │
│  pariatur. Excepteur sint occaecat      │
│  cupidatat non proident, sunt in        │
│  culpa qui officia deserunt mollit      │
│  anim id est laborum.                   │
│                                         │
│  ▲ See Less                             │  ← Now shows this
│  ─────────────────────────────────      │
│  2h ago  ⚪ Prayer                      │
│                                         │
│  👏  💬 12                              │
└─────────────────────────────────────────┘
```

**Animation:**
- Smooth height change with spring animation
- Chevron rotates 180° (▼ → ▲)
- Button text changes instantly
- Haptic feedback: Light tap

---

## 👉 Swipe Right = Amen

```
BEFORE SWIPE:
┌─────────────────────────────────────────┐
│  Post content here...                   │
│                                         │
│  2h ago  ⚪ Prayer                      │
│                                         │
│  👏  💬 12                 234          │
└─────────────────────────────────────────┘


DURING SWIPE (< 60pt):
┌─────────────────────────────────────────┐
│                  Post content here...   │  ← Card moves right
│  ⚪               2h ago  ⚪ Prayer      │  ← Icon shows on left
│  👏               👏  💬 12        234  │
└─────────────────────────────────────────┘
   ↑
   Amen icon appears


AFTER SWIPE (> 60pt):
┌─────────────────────────────────────────┐
│  Post content here...                   │  ← Card bounces back
│                                         │
│  2h ago  ⚪ Prayer                      │
│                                         │
│  👏  💬 12                 234          │  ← Amen is now active
└─────────────────────────────────────────┘
    ↑
    Filled icon
```

**Animation Sequence:**
1. **Start**: Swipe gesture begins (> 20pt)
2. **During**: Card moves with finger, icon fades in
3. **Threshold**: Reaches 60pt, icon pulses larger
4. **Trigger**: Release finger, card snaps back
5. **Complete**: Amen icon fills, haptic feedback

**Haptic:** Medium impact when triggered

---

## 👈 Swipe Left = Comment

```
BEFORE SWIPE:
┌─────────────────────────────────────────┐
│  Post content here...                   │
│                                         │
│  2h ago  ⚪ Prayer                      │
│                                         │
│  👏  💬 12                 234          │
└─────────────────────────────────────────┘


DURING SWIPE (< 60pt):
┌─────────────────────────────────────────┐
│  Post content here...                   │  ← Card moves left
│  2h ago  ⚪ Prayer               💬     │  ← Icon shows on right
│  👏  💬 12                 234   💬     │
└─────────────────────────────────────────┘
                                    ↑
                             Comment icon appears


AFTER SWIPE (> 60pt):
┌─────────────────────────────────────────┐
│                                         │
│   📱 Comments Sheet Opens               │  ← Full sheet appears
│                                         │
│   💬 Comments (12)                      │
│   ─────────────────────────────────     │
│   @user1: Great post!                   │
│   @user2: Amen! 🙏                      │
│   ...                                   │
│                                         │
└─────────────────────────────────────────┘
```

**Animation Sequence:**
1. **Start**: Swipe gesture begins (> 20pt)
2. **During**: Card moves with finger, icon fades in
3. **Threshold**: Reaches 60pt, icon pulses larger
4. **Trigger**: Release finger, sheet animates up
5. **Complete**: Comments view presented

**Haptic:** Light tap when triggered

---

## 🎯 Swipe Gesture Zones

```
Card Position Breakdown:

←────────── 80pt ─────────────│──────── 80pt ───────────→
                              │
        MAX SWIPE LEFT        │       MAX SWIPE RIGHT
                              │
←────── 60pt ──────│          │          │────── 60pt ──────→
                   │          │          │
            TRIGGER ZONE      │      TRIGGER ZONE
                   │          │          │
←──── 20pt ───│    │          │          │    │──── 20pt ───→
              │    │          │          │    │
       START  │ MIN│          │          │MIN │  START
       HINT   │    │          │          │    │  HINT
              │    │          │          │    │
              ↓    ↓          ↓          ↓    ↓
        ──────────────────────┼──────────────────────
              💬   💬    🏠  CARD  🏠    👏   👏
        ──────────────────────┼──────────────────────
              │    │          │          │    │
              │    │          │          │    │
        Icon  │ Icon│    No   │    No   │Icon│  Icon
        Hint  │ Full│   Icon  │   Icon  │Full│  Hint
              │    │          │          │    │


Legend:
🏠 = Card resting position
👏 = Amen icon (right swipe)
💬 = Comment icon (left swipe)
```

**Swipe Distances:**
- **0-20pt**: No feedback
- **20-60pt**: Icon appears, card moves
- **60-80pt**: Trigger zone, icon emphasized
- **> 80pt**: Maximum swipe (clamped)

---

## 🎨 Visual States

### Post Card States

```
┌─────────────────────┐
│  1. DEFAULT         │  ← Normal state
│  • 0.06 shadow      │
│  • 1.0 scale        │
│  • No offset        │
└─────────────────────┘

┌─────────────────────┐
│  2. PRESSED         │  ← Tap feedback
│  • 0.15 shadow      │
│  • 0.97 scale       │
│  • Darker appearance│
└─────────────────────┘

┌─────────────────────┐
│  3. SWIPING         │  ← During gesture
│  • 0.06 shadow      │
│  • 1.0 scale        │
│  • X offset varies  │
└─────────────────────┘

┌─────────────────────┐
│  4. EXPANDED        │  ← After "See More"
│  • 0.06 shadow      │
│  • 1.0 scale        │
│  • Increased height │
└─────────────────────┘
```

### Icon States

```
Amen Icon (👏):
  • Inactive: hands.clap (outline)
  • Active:   hands.clap.fill (solid)
  • Color:    Black @ 0.4 → Black @ 1.0
  • Scale:    1.0 → 1.1 (when active)

Comment Icon (💬):
  • Icon:     bubble.left
  • Badge:    Black capsule with count
  • Position: Top-right offset (8, -4)
  • Shows:    Only when replies > 0

Swipe Icons:
  • Size:     50x50pt circle
  • BG:       Black @ 0.1 opacity
  • Icon:     24pt, semibold
  • Color:    Black @ 0.6 opacity
```

---

## ⚡ Animation Timing

### Tap-to-Expand
```
Action: Tap "See More"
├─ Button press: 0.2s (spring)
├─ Content expand: 0.3s (easeInOut)
├─ Chevron rotate: 0.3s (easeInOut)
└─ Haptic feedback: instant

Total duration: ~0.3s
```

### Swipe Actions
```
Action: Swipe right (Amen)
├─ Card offset: Follows finger (0ms delay)
├─ Icon fade in: 0.2s (easeOut)
├─ Icon scale: 0.2s (spring)
├─ Snap back: 0.3s (spring, 0.8 damping)
├─ Amen trigger: 0.1s delay
└─ Haptic feedback: instant

Total duration: ~0.4s
```

### Swipe Reset (Cancel)
```
Action: Release before threshold
├─ Card snap back: 0.3s (spring, 0.8 damping)
├─ Icon fade out: 0.2s (easeOut)
└─ No haptic

Total duration: ~0.3s
```

---

## 📐 Precise Measurements

### Card Dimensions
```
Component              Size/Position
─────────────────────────────────────────
Corner Radius          18pt
Horizontal Padding     16pt
Vertical Padding       6pt
Content Padding        16pt
Shadow Blur            12pt
Shadow Offset Y        4pt
Shadow Opacity         0.06 (normal)
                       0.15 (pressed)
```

### Button Dimensions
```
Component              Size/Position
─────────────────────────────────────────
Amen/Comment Button    32x32pt circle
Icon Size              16pt medium
Glassmorphic BG        ultraThinMaterial
Border                 0.5pt @ 0.08 opacity
Spacing                16pt between buttons
Badge Font             9pt bold
Badge Padding H        5pt
Badge Padding V        2pt
Badge Offset X         8pt
Badge Offset Y         -4pt
```

### Typography
```
Component              Font
─────────────────────────────────────────
Post Content           14pt OpenSans-Regular
Timestamp              11pt OpenSans-Regular
Post Type              9pt OpenSans-SemiBold
See More/Less          12pt OpenSans-SemiBold
Like Count             11pt OpenSans-SemiBold
Comment Badge          9pt OpenSans-Bold
```

---

## 🎯 User Feedback System

### Visual Feedback
```
Action               Visual Response
─────────────────────────────────────────
Tap post             Card scales to 0.97
Tap "See More"       Content expands smoothly
Swipe start          Icon fades in (0.2s)
Swipe threshold      Icon pulses larger
Swipe trigger        Card snaps back
Amen given           Icon fills & scales 1.1x
Comment opened       Sheet slides up
```

### Haptic Feedback
```
Action               Haptic Type
─────────────────────────────────────────
Tap "See More"       Light impact
Swipe amen           Medium impact
Swipe comment        Light tap
Swipe cancel         None
Error state          Error notification
```

### Audio Feedback (Optional)
```
Action               Sound (if enabled)
─────────────────────────────────────────
Amen given           Soft "pop" (0.1s)
Comment opened       Soft "swoosh" (0.2s)
Expand post          Soft "tick" (0.05s)
```

---

## 🔍 Accessibility Features

### VoiceOver Support
```
Element              VoiceOver Label
─────────────────────────────────────────
Post content         "Post content. [text]"
See More btn         "See More. Double tap to expand"
See Less btn         "See Less. Double tap to collapse"
Amen button          "Give amen. Double tap to toggle"
Comment button       "Comments. [count] replies. Double tap to view"
Like count           "[count] amens"
Swipe gesture        "Swipe right to amen, swipe left to comment"
```

### Dynamic Type
```
Size Category        Adjustments
─────────────────────────────────────────
XS - S               Default sizes
M - L                +2pt all text
XL - XXL             +4pt all text
XXXL                 +6pt all text, +4pt buttons
Accessibility        +8pt text, +6pt buttons, increase tap targets
```

### Reduced Motion
```
Preference           Behavior Change
─────────────────────────────────────────
Reduce Motion ON     • Instant expand/collapse (no animation)
                     • No swipe offset (buttons instead)
                     • No icon scale effects
                     • Crossfade only

Reduce Motion OFF    • Full spring animations
                     • Swipe gestures enabled
                     • All scale effects
                     • All transitions
```

---

## 💡 Usage Tips

### For Users:
1. **Tap "See More"** to read full posts
2. **Swipe right quickly** for fast amen
3. **Swipe left** to jump to comments
4. **Multiple posts** can be expanded at once
5. **Swipe back** works in comments sheet

### For Developers:
1. **Monitor** `expandedPosts` size for memory
2. **Clear** expanded state on view disappear
3. **Test** with VoiceOver enabled
4. **Verify** gestures don't conflict with scroll
5. **Add** analytics for swipe vs. tap usage

---

## 🎉 Complete Interaction Flow

```
User sees truncated post
        ↓
Taps "See More"
        ↓
Post expands smoothly (0.3s)
        ↓
User reads full content
        ↓
Swipes right to amen →
        ↓
Icon appears during swipe
        ↓
Releases at 65pt
        ↓
Card snaps back + haptic
        ↓
Amen icon fills (1.1x scale)
        ↓
Swipes left to comment ←
        ↓
Comment sheet slides up
        ↓
User adds comment
        ↓
Sheet dismisses
        ↓
Badge count increments
        ↓
Taps "See Less"
        ↓
Post collapses smoothly
```

**Total interaction time:** ~3-5 seconds
**User delight:** ⭐⭐⭐⭐⭐

---

## 📊 Comparison: Before vs. After

### Before Implementation
```
To amen a post:
1. Tap amen button
   Total: 1 tap

To comment on post:
1. Tap comment button
   Total: 1 tap

To read full post:
1. (Not possible - content truncated)
2. (Would need to navigate away)
   Total: N/A
```

### After Implementation
```
To amen a post:
Option A (Button): 1 tap
Option B (Swipe):  1 swipe → (faster!)
   Total: 1 action

To comment on post:
Option A (Button): 1 tap
Option B (Swipe):  1 swipe → (faster!)
   Total: 1 action

To read full post:
1. Tap "See More"
2. Read content inline
3. Tap "See Less" (optional)
   Total: 1-2 taps ✨ NEW FEATURE!
```

**Improvement:**
- ✅ **Same or fewer** actions required
- ✅ **More options** for user preference
- ✅ **New capability** (inline reading)
- ✅ **Better UX** with gestures

---

**Visual guide complete! 🎨**
All interactions designed for speed, clarity, and delight.
