# UnifiedChatView Visual Guide

## Layout Structure

```
┌─────────────────────────────────────┐
│  ← [Back]  ●  John Doe       [i]   │ ← Header (50px)
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────────────┐          │ ← Received message
│  │ Hey, how are you?    │          │   (white bubble)
│  └──────────────────────┘          │
│  10:30 AM                           │
│                                     │
│         ┌──────────────────────┐   │ ← Sent message
│         │ I'm good, thanks!    │   │   (black bubble)
│         └──────────────────────┘   │
│                        10:31 AM     │
│                                     │
│                                     │
│  ... more messages ...              │
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ [Media Section - Collapsed]         │ ← Only shown when expanded
│ ┌───┐ ┌───┐ ┌───┐ ┌───┐           │
│ │📷 │ │🎥 │ │📄 │ │🔗 │           │
│ └───┘ └───┘ └───┘ └───┘           │
│ Photo Video Files Link              │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ [+] [Message...        ] [↑]       │ ← Input bar (52px)
└─────────────────────────────────────┘
  ↑    ↑                    ↑
  │    └─ Text input        └─ Send button
  └─ Expand media
```

## State Transitions

### Collapsed State (Default)
```
┌─────────────────────────────────────┐
│ [+] [Message...        ] [↑]       │
└─────────────────────────────────────┘
     ↑ 
     Click to expand media section
```

### Expanded State
```
┌─────────────────────────────────────┐
│ ┌───┐ ┌───┐ ┌───┐ ┌───┐           │
│ │📷 │ │🎥 │ │📄 │ │🔗 │           │ ← Slides up
│ └───┘ └───┘ └───┘ └───┘           │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ [˅] [Message...        ] [↑]       │
└─────────────────────────────────────┘
     ↑
     Click to collapse
```

### Typing State
```
┌─────────────────────────────────────┐
│ [+] [Hello there    [x]] [↑]       │
└─────────────────────────────────────┘
                      ↑
                      Clear button appears
```

### Keyboard Visible
```
┌─────────────────────────────────────┐
│ [+] [Message...        ] [↑]       │
├─────────────────────────────────────┤
│                                     │
│  Q  W  E  R  T  Y  U  I  O  P     │
│   A  S  D  F  G  H  J  K  L       │
│    Z  X  C  V  B  N  M             │
│         [  space  ]                 │
│                                     │
└─────────────────────────────────────┘
Note: Media section auto-collapses
```

## Color Palette

### Blacks & Grays
```
██████  0.05  Deep Black (send button bottom)
██████  0.10  Dark Text (header, labels)
██████  0.15  UI Elements (buttons, messages)
██████  0.95  Light Gray (background)
██████  0.98  Very Light (background)
██████  1.00  Pure White (received messages)
```

### Shadows
```
Light:  black @ 0.04 opacity
Medium: black @ 0.06 opacity
Heavy:  black @ 0.08 opacity
Strong: black @ 0.20 opacity (sent messages)
```

## Component Sizes

### Buttons
```
┌──────┐
│  +   │  36x36pt  Expand button
└──────┘

┌──────┐
│  ↑   │  36x36pt  Send button
└──────┘

┌────────┐
│   📷   │  52x52pt  Media button
│ Photos │
└────────┘
```

### Input Elements
```
┌─────────────────────────┐
│ Message...              │  Variable width
└─────────────────────────┘  20pt radius, 9pt v-padding

┌───────────────────────────────┐
│ [+] [Input...] [↑]           │  52pt height
└───────────────────────────────┘  28pt radius
```

## Animations Timeline

```
Media Expand (400ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
0ms        200ms             400ms
├──────────┼─────────────────┤
│ Start    │ Mid-point       │ End
│ Hidden   │ 50% visible     │ Fully visible
│ y: 60    │ y: 30           │ y: 0

Button Press (250ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━
0ms      125ms     250ms
├────────┼─────────┤
│ Scale  │ Mid     │ Release
│ 1.0    │ 0.88    │ 1.0

Keyboard Slide (350ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
0ms         175ms            350ms
├───────────┼────────────────┤
│ Start     │ Mid            │ End
│ y: 0      │ y: -175px      │ y: -350px
```

## Touch Targets

All interactive elements meet 44x44pt minimum:
```
✅ Back button:     38x38pt + 3pt padding = 44pt
✅ Info button:     38x38pt + 3pt padding = 44pt
✅ Expand button:   36x36pt + 4pt padding = 44pt
✅ Send button:     36x36pt + 4pt padding = 44pt
✅ Media buttons:   52x52pt (exceeds minimum) ✨
```

## Message Bubble Anatomy

### Sent Message (User)
```
                 ┌───────────────────┐
                 │ Hello there!      │ ← White text
                 └───────────────────┘
                 ╲                     
                  ╲ Black gradient
                   ╲ (0.15 → 0.05)
                    ╲
                     └─ Shadow: black @ 0.2, 12pt blur
                        
                            10:45 AM
```

### Received Message (Other)
```
┌───────────────────┐
│ Hey, how are you? │ ← Black text
└───────────────────┘
╱                     
╱ White background
╱ Subtle border
╱
└─ Shadow: black @ 0.06, 12pt blur

10:30 AM
```

## Layout Measurements

```
Header
├─ Height: 50px
├─ H-Padding: 16px
├─ V-Padding: 10px
└─ Item spacing: 12px

Messages Area
├─ H-Padding: 16px
├─ V-Spacing: 12px
├─ Bubble padding: 16px H, 10px V
└─ Bubble radius: 20pt continuous

Media Section (Expanded)
├─ Height: ~60px
├─ H-Padding: 20px
├─ V-Padding: 16px
├─ Grid spacing: 12px
└─ Background: white

Input Bar
├─ Height: 52px
├─ Outer radius: 28pt
├─ H-Padding: 8px
├─ V-Padding: 4px
├─ Element spacing: 8px
└─ Input radius: 20pt

Bottom Spacing
├─ Base: 8px
├─ + Safe area (varies by device)
└─ + Keyboard height (when visible)
```

## Interaction Flows

### Sending a Message
```
1. User types text
   └─> Clear button [x] appears
   
2. Text in input field
   └─> Send button activates (black gradient)
   
3. User taps Send [↑]
   ├─> Haptic feedback (light)
   ├─> Input clears immediately
   ├─> Message appears at bottom
   └─> Success haptic
```

### Opening Media
```
1. User taps Expand [+]
   ├─> Haptic feedback (light)
   ├─> Icon rotates to chevron down [˅]
   ├─> Media section slides up (400ms)
   └─> If keyboard visible, dismiss it
   
2. User taps media button (e.g., Photos)
   ├─> Haptic feedback (light)
   ├─> Media section auto-collapses
   ├─> Photo picker opens
   └─> Icon returns to [+]
```

### Keyboard Interaction
```
1. User taps input field
   ├─> Input field gets focus ring
   ├─> Keyboard slides up (350ms)
   ├─> Input bar follows keyboard
   └─> Media section auto-collapses
   
2. User taps outside
   ├─> Keyboard dismisses
   ├─> Input bar returns to bottom
   └─> Focus ring disappears
```

## Responsive Behavior

### iPhone SE (Small)
```
Screen: 375 x 667 pts
Messages visible: ~8-10
Input bar adapts: ✅
Media grid: 4 columns ✅
```

### iPhone 15 Pro (Medium)
```
Screen: 393 x 852 pts
Messages visible: ~12-15
Input bar adapts: ✅
Media grid: 4 columns ✅
```

### iPhone 15 Pro Max (Large)
```
Screen: 430 x 932 pts
Messages visible: ~15-18
Input bar adapts: ✅
Media grid: 4 columns ✅
```

### Landscape Mode
```
Messages side by side: Possible
Input bar: Full width at bottom
Media section: Maintains 4-column grid
Header: Compact height
```

## Accessibility

### VoiceOver Labels
```
[+] Button         → "Expand media options"
[˅] Button         → "Collapse media options"
Text Field         → "Message, text field"
[↑] Send Button   → "Send message"
[x] Clear Button  → "Clear text"
Media Buttons     → "Attach photo", "Attach video", etc.
```

### Dynamic Type Support
```
Small:  Input 13pt, Messages 13pt
Medium: Input 15pt, Messages 15pt (default)
Large:  Input 17pt, Messages 17pt
XL:     Input 19pt, Messages 19pt
XXL:    Input 21pt, Messages 21pt
```

### Contrast Ratios (WCAG AA)
```
White text on black (sent):      17.4:1 ✅ (AAA)
Black text on white (received):  17.4:1 ✅ (AAA)
Gray labels on white:             4.6:1 ✅ (AA)
Dark icons on light buttons:      8.2:1 ✅ (AAA)
```

---

## Quick Reference Card

```
╔═══════════════════════════════════════╗
║   UNIFIEDCHATVIEW QUICK REFERENCE     ║
╠═══════════════════════════════════════╣
║                                       ║
║  Colors                               ║
║  ├─ Sent: Black gradient (0.15→0.05) ║
║  ├─ Received: Pure white (#FFFFFF)    ║
║  └─ Background: Light gray (0.95-0.98)║
║                                       ║
║  Sizes                                ║
║  ├─ Input bar: 52px height            ║
║  ├─ Media section: 60px height        ║
║  ├─ Buttons: 36-52px diameter         ║
║  └─ Bubbles: 20pt radius              ║
║                                       ║
║  Animations                           ║
║  ├─ Media: 400ms spring (0.8 damp)    ║
║  ├─ Keyboard: 350ms spring (0.85)     ║
║  └─ Button: 250ms spring (0.6)        ║
║                                       ║
║  Key Features                         ║
║  ✓ Collapsible media section          ║
║  ✓ Smart keyboard management          ║
║  ✓ Auto-scrolling messages            ║
║  ✓ Haptic feedback                    ║
║  ✓ Black/white design                 ║
║  ✓ Production-ready                   ║
║                                       ║
╚═══════════════════════════════════════╝
```
