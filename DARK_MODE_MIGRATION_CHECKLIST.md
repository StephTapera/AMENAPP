# Dark Mode Migration Checklist

## Overview
This document tracks the migration of AMEN app components from hardcoded light-mode colors to adaptive dark mode support.

**Migration Strategy:** Replace hardcoded `Color.white`, `Color.black`, etc. with adaptive semantic tokens from `AmenAdaptiveColors.swift`

---

## Core Color Replacements

### Common Patterns

| Before (Hardcoded) | After (Adaptive) |
|---|---|
| `.background(Color.white)` | `.background(Color.adaptiveBackground)` |
| `.background(.white)` | `.background(Color.adaptiveBackground)` |
| `.foregroundColor(.black)` | `.foregroundColor(Color.adaptiveTextPrimary)` |
| `.foregroundStyle(.black)` | `.foregroundStyle(Color.adaptiveTextPrimary)` |
| `.foregroundStyle(.black.opacity(0.7))` | `.foregroundStyle(Color.adaptiveTextSecondary)` |
| `.foregroundStyle(.black.opacity(0.5))` | `.foregroundStyle(Color.adaptiveTextTertiary)` |
| `.background(Color(.systemBackground))` | `.background(Color.adaptiveSurface)` |
| `.background(Color(.systemGroupedBackground))` | `.background(Color.adaptiveGroupedBackground)` |
| `.stroke(Color.black.opacity(0.1))` | `.stroke(Color.adaptiveBorder)` |
| `.fill(Color.white)` | `.fill(Color.adaptiveSurface)` |
| `.shadow(color: .black.opacity(0.08), ...)` | `.adaptiveShadow(...)` |
| `Color.white.opacity(0.3)` | `Color.adaptiveGlassOverlay` |
| `Color.white.opacity(0.1)` | `Color.adaptiveGlassSecondary` |

---

## Component Migration Status

### ✅ Foundation (Complete)
- [x] **AmenAdaptiveColors.swift** - Created adaptive color system

### 🔄 Core Navigation (Priority 1)
- [ ] **ContentView.swift** (Lines 1-1000)
  - [ ] CompactTabBar background (line 679-814)
  - [ ] Tab button selected state (line 860-886)
  - [ ] Create button styling (line 996-1087)
  - [ ] Profile tab badge (line 890-925)
  - [ ] Glassmorphic overlays
  - [ ] Toast notifications (line 276-285)
  
  **Key changes:**
  ```swift
  // Line 679: glassmorphicBackground
  Capsule().fill(.ultraThinMaterial)  // Keep this (auto-adapts)
  Color.white.opacity(0.25) → Color.adaptiveGlassOverlay
  Color.white.opacity(0.4) → Color.adaptiveGlassBorder
  
  // Line 681-683: Shadows
  .shadow(color: .black.opacity(0.18), ...) → .adaptiveShadow(radius: 20, y: 8)
  .shadow(color: .white.opacity(0.1), ...) → Remove (doesn't work in dark)
  
  // Line 865-867: Selected tab background
  Color.black.opacity(0.2) → Keep (works in both modes)
  
  // Line 232: Toast background
  .fill(Color.black.opacity(0.9)) → .fill(Color.adaptiveSurface.opacity(0.95))
  ```

### 🔄 Feed & Posts (Priority 2)
- [ ] **PostCard.swift** (Lines 1-3894)
  - [ ] Card background (multiple instances)
  - [ ] Avatar circles (line 300-310)
  - [ ] Text colors (author name, content, timestamps)
  - [ ] Button backgrounds
  - [ ] Dividers/separators
  - [ ] Glassmorphic overlays
  
  **Key changes:**
  ```swift
  // Card background
  RoundedRectangle().fill(Color.white) → .fill(Color.adaptiveSurface)
  
  // Text colors
  .foregroundStyle(.black) → .foregroundStyle(Color.adaptiveTextPrimary)
  .foregroundStyle(.black.opacity(0.7)) → .foregroundStyle(Color.adaptiveTextSecondary)
  
  // Borders
  .stroke(Color.black.opacity(0.1)) → .stroke(Color.adaptiveBorder)
  ```

- [ ] **HomeView.swift** (Find actual file location)
  - [ ] Feed background
  - [ ] Pull-to-refresh indicator
  - [ ] New posts banner
  - [ ] Empty state views

### 🔄 Profile (Priority 3)
- [ ] **ProfileView.swift** (Lines 1-6539)
  - [ ] Main background (line 215, 244)
  - [ ] Header section backgrounds
  - [ ] Tab bar styling (line 146-213)
  - [ ] Stats cards
  - [ ] Avatar borders
  - [ ] Toast notifications (line 218-243)
  - [ ] Compact header (line 250-277)
  
  **Key changes:**
  ```swift
  // Line 215: Main background
  .background(Color.white) → .background(Color.adaptiveBackground)
  
  // Line 232: Toast background
  .fill(Color.black.opacity(0.9)) → .fill(Color.adaptiveSurface.opacity(0.95))
  
  // Line 254: Compact avatar
  .fill(Color.black) → .fill(Color.adaptiveTextPrimary)
  
  // Line 266, 271: Text
  .foregroundStyle(.black) → .foregroundStyle(Color.adaptiveTextPrimary)
  .foregroundStyle(.black.opacity(0.5)) → .foregroundStyle(Color.adaptiveTextSecondary)
  ```

### 🔄 Messages (Priority 4)
- [ ] **MessagesView.swift** (Lines 1-4798)
  - [ ] Header background (line 154-167)
  - [ ] Message bubbles
  - [ ] Conversation cells
  - [ ] Search bar
  - [ ] Tab pills (line 251-299)
  
  **Key changes:**
  ```swift
  // Line 154: Header background
  .background(Color(.systemBackground)) → .background(Color.adaptiveBackground)
  
  // Line 268-271: Back button
  Circle().fill(.ultraThinMaterial)  // Keep (auto-adapts)
  .shadow(color: .black.opacity(0.05), ...) → .adaptiveShadow(...)
  ```

- [ ] **UnifiedChatView.swift**
  - [ ] Chat background
  - [ ] Message bubbles (sent/received)
  - [ ] Input bar
  - [ ] Timestamps

### 🔄 Content Creation (Priority 5)
- [ ] **CreatePostView.swift** (Lines 1-3782)
  - [ ] Main background (line 161)
  - [ ] Category pills (line 164-167)
  - [ ] Text editor background
  - [ ] Upload progress overlay (line 172-200)
  - [ ] Draft saved notice (line 203-227)
  - [ ] Success toast (line 230-258)
  - [ ] Toolbar buttons
  
  **Key changes:**
  ```swift
  // Line 161: Main background
  Color(.systemGroupedBackground) → Color.adaptiveGroupedBackground
  
  // Line 192-194: Upload overlay
  .fill(Color(.systemBackground)) → .fill(Color.adaptiveSurface)
  .shadow(color: .black.opacity(0.15), ...) → .adaptiveShadow(radius: 20, y: 8)
  
  // Line 220-221: Draft saved background
  .fill(Color(.systemBackground)) → .fill(Color.adaptiveSurface)
  .shadow(color: .black.opacity(0.15), ...) → .adaptiveShadow(...)
  
  // Line 246-252: Success toast
  .fill(.white) → .fill(Color.adaptiveSurface)
  .stroke(.black.opacity(0.1), ...) → .stroke(Color.adaptiveBorder, ...)
  .foregroundStyle(.black) → .foregroundStyle(Color.adaptiveTextPrimary)
  ```

### 🔄 Notifications (Priority 6)
- [ ] **NotificationsView.swift** (Lines 1-2539)
  - [ ] Header background (line 154)
  - [ ] Notification cards
  - [ ] Filter pills
  - [ ] Follow request button (line 173-200)
  - [ ] Action buttons
  
  **Key changes:**
  ```swift
  // Line 154: Header background
  .background(Color(.systemBackground)) → .background(Color.adaptiveBackground)
  
  // Notification cards - find and replace
  .background(.white) → .background(Color.adaptiveSurface)
  ```

### 🔄 Shared Components (Priority 7)
- [ ] **SharedUIComponents.swift** (Lines 1-94)
  - [ ] FilterChip (line 23-69)
  - [ ] QuickReplyChip (line 73-92)
  
  **Key changes:**
  ```swift
  // FilterChip (line 41-64)
  .foregroundStyle(isSelected ? .white : .black.opacity(0.7))
  → .foregroundStyle(isSelected ? Color.adaptiveBackground : Color.adaptiveTextSecondary)
  
  .fill(isSelected ? Color.black : Color.white)
  → .fill(isSelected ? Color.adaptiveTextPrimary : Color.adaptiveSurface)
  
  .shadow(color: isSelected ? .black.opacity(0.3) : .black.opacity(0.08), ...)
  → Use .adaptiveShadow(...)
  
  .stroke(Color.black.opacity(isSelected ? 0 : 0.1), ...)
  → .stroke(Color.adaptiveBorder.opacity(isSelected ? 0 : 1), ...)
  ```

### 🔄 Settings & Account (Priority 8)
- [ ] **SettingsView.swift**
  - [ ] List backgrounds
  - [ ] Section headers
  - [ ] Toggle switches
  - [ ] Navigation links

- [ ] **AccountSettingsView.swift**
  - [ ] Form backgrounds
  - [ ] Input fields
  - [ ] Save buttons

### 🔄 Resources (Priority 9)
- [ ] **ResourcesView.swift**
  - [ ] Tab bar
  - [ ] Resource cards
  - [ ] Section headers

- [ ] **FaithPodcastsView.swift**
  - [ ] Podcast cards
  - [ ] Player controls

- [ ] **ChurchNotesView.swift**
  - [ ] Note cards
  - [ ] Editor background

### 🔄 Authentication (Priority 10)
- [ ] **SignInView.swift**
  - [ ] Background
  - [ ] Input fields
  - [ ] Buttons
  - [ ] Logo (may need dark variant)

- [ ] **WelcomeScreenView.swift**
  - [ ] Splash background
  - [ ] Logo
  - [ ] Text colors

---

## Testing Checklist

### Per-Screen Validation
For each migrated screen, verify:

- [ ] **Background colors**
  - [ ] Main background adapts correctly
  - [ ] Cards/surfaces have proper contrast
  - [ ] Overlays/sheets show correctly

- [ ] **Text readability**
  - [ ] All text is readable in dark mode
  - [ ] Hierarchy preserved (primary/secondary/tertiary)
  - [ ] No white-on-white or black-on-black text

- [ ] **UI Elements**
  - [ ] Buttons visible and pressable
  - [ ] Icons show with proper contrast
  - [ ] Badges/indicators visible
  - [ ] Dividers/borders visible but subtle

- [ ] **Glassmorphic effects**
  - [ ] Tab bar shows properly
  - [ ] Overlays maintain premium feel
  - [ ] Shadows adapted for dark backgrounds

- [ ] **Navigation**
  - [ ] No white flashes during transitions
  - [ ] Sheet presentations smooth
  - [ ] Navigation bars adapt correctly

- [ ] **Animations**
  - [ ] All animations work the same
  - [ ] Transitions smooth
  - [ ] No broken matched geometry effects

### System Integration
- [ ] Respects system dark mode setting
- [ ] Switches instantly when system changes
- [ ] No regressions in light mode
- [ ] No performance degradation

### Accessibility
- [ ] Meets contrast ratios (WCAG AA minimum 4.5:1)
- [ ] VoiceOver works correctly
- [ ] Dynamic Type supported
- [ ] Reduce Motion respected

---

## Rollout Plan

### Phase 1: Foundation (Week 1)
1. ✅ Create `AmenAdaptiveColors.swift`
2. Update `ContentView.swift` (CompactTabBar)
3. Test tab bar in dark mode
4. Fix any issues

### Phase 2: Core Screens (Week 2)
5. Migrate `PostCard.swift`
6. Migrate `ProfileView.swift`
7. Migrate `MessagesView.swift`
8. Test feed, profile, and messages

### Phase 3: Content & Engagement (Week 3)
9. Migrate `CreatePostView.swift`
10. Migrate `NotificationsView.swift`
11. Migrate shared components
12. Test post creation and notifications

### Phase 4: Supporting Features (Week 4)
13. Migrate settings screens
14. Migrate resources screens
15. Migrate authentication screens
16. Full app testing

### Phase 5: Polish & Launch (Week 5)
17. Fix edge cases
18. Performance testing
19. Accessibility audit
20. Release to TestFlight

---

## Notes

- **Do NOT redesign** - Only change colors, keep all layouts/spacing/interactions
- **Test frequently** - Switch between light/dark mode often
- **Preserve behavior** - Animations and features must work identically
- **Material backgrounds auto-adapt** - Keep `.ultraThinMaterial`, `.regularMaterial` as-is
- **Accent colors stay the same** - Gold, bronze, category colors work in both modes
