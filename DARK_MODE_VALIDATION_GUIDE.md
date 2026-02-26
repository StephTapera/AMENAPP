# Dark Mode Validation & Testing Guide

## Purpose
This guide ensures dark mode implementation maintains the exact same design structure, layout, and interactions as light mode—only colors adapt.

---

## Pre-Testing Setup

### Enable Quick Dark Mode Switching
1. Open Settings app → Display & Brightness
2. Or use Control Center → Long press brightness slider
3. For faster testing: Add "Dark Mode" toggle to Control Center

### Simulator Testing
```bash
# Toggle dark mode via command line
xcrun simctl ui booted appearance dark
xcrun simctl ui booted appearance light
```

---

## Visual Validation Checklist

### 1. Background Colors

#### Main Backgrounds
- [ ] **Light mode:** White or very light gray
- [ ] **Dark mode:** Deep charcoal (#1A1A1A) or darker
- [ ] **Validation:** No jarring brightness change, maintains premium feel

#### Cards & Surfaces
- [ ] **Light mode:** White with subtle shadow
- [ ] **Dark mode:** Medium gray (#2E2E2E) with adapted shadow
- [ ] **Validation:** Cards visible and separated from background

#### Grouped Backgrounds
- [ ] **Light mode:** Light gray (systemGroupedBackground)
- [ ] **Dark mode:** Very dark gray (#121212)
- [ ] **Validation:** Sections visually separated

### 2. Text Readability

#### Primary Text (Headings, Main Content)
- [ ] **Light mode:** Black
- [ ] **Dark mode:** White
- [ ] **Contrast ratio:** ≥ 7:1 (AAA standard)
- [ ] **Test locations:**
  - Post card author names
  - Profile names
  - Message preview text
  - Create post content

#### Secondary Text (Supporting, Metadata)
- [ ] **Light mode:** Black 70% opacity
- [ ] **Dark mode:** White 70% opacity
- [ ] **Contrast ratio:** ≥ 4.5:1 (AA standard)
- [ ] **Test locations:**
  - Timestamps ("2h ago")
  - Username handles ("@username")
  - Message timestamps
  - Category descriptions

#### Tertiary Text (Captions, Low Priority)
- [ ] **Light mode:** Black 50% opacity
- [ ] **Dark mode:** White 50% opacity
- [ ] **Contrast ratio:** ≥ 4.5:1
- [ ] **Test locations:**
  - View counts
  - Secondary metadata
  - Footer text

#### Placeholder Text
- [ ] **Light mode:** Black 30% opacity
- [ ] **Dark mode:** White 30% opacity
- [ ] **Readable but clearly placeholder**

### 3. UI Elements

#### Borders & Dividers
- [ ] **Light mode:** Black 10% opacity (subtle)
- [ ] **Dark mode:** White 15-20% opacity (slightly more visible)
- [ ] **Validation:** Visible but not distracting
- [ ] **Test locations:**
  - Post card borders
  - Section dividers
  - Tab bar separators
  - Input field borders

#### Shadows
- [ ] **Light mode:** Black 8% opacity, subtle depth
- [ ] **Dark mode:** Black 30-40% opacity, stronger for separation
- [ ] **Validation:** Elements still "float" above background
- [ ] **Test locations:**
  - Compact tab bar
  - Post cards
  - Floating buttons
  - Sheets/modals

#### Icons
- [ ] **Light mode:** Black or `.primary` color
- [ ] **Dark mode:** White or `.primary` color
- [ ] **All icons visible and recognizable**
- [ ] **Test locations:**
  - Tab bar icons
  - Navigation icons
  - Action buttons (like, comment, share)
  - Status icons

#### Buttons
- [ ] **Primary buttons:** High contrast, clearly tappable
- [ ] **Secondary buttons:** Visible with subtle background
- [ ] **Disabled state:** Clearly different from enabled
- [ ] **Pressed state:** Immediate visual feedback
- [ ] **Test locations:**
  - Create post button (center of tab bar)
  - Follow/Unfollow buttons
  - Send message button
  - Save/Edit buttons

### 4. Glassmorphic Effects

#### Compact Tab Bar
- [ ] **Light mode:** Frosted glass with white overlay
- [ ] **Dark mode:** Frosted glass with subtle white highlight
- [ ] **Validation:** 
  - Still feels "glassy" and premium
  - Content underneath partially visible through blur
  - Shadows provide depth
- [ ] **Selected tab:** Background pill visible in both modes

#### Sheet Overlays
- [ ] **Light mode:** White with slight transparency
- [ ] **Dark mode:** Dark gray with adapted transparency
- [ ] **Validation:** Backgrounds dimmed appropriately

#### Badge/Indicator Overlays
- [ ] **Messages badge:** Red, visible in both modes
- [ ] **Notification dot:** Red, clear and prominent
- [ ] **New posts indicator:** Visible without being distracting

### 5. Special Elements

#### Profile Photos
- [ ] **Border adapts to background**
- [ ] **Loading placeholder visible**
- [ ] **Fallback initials readable**

#### Accent Colors
- [ ] **Gold accent:** Same in both modes (inherently high contrast)
- [ ] **Category colors:** Slightly lighter in dark mode for contrast
- [ ] **Success/Warning/Error:** Adapted for readability

#### Status States
- [ ] **Success (green):** ≥ 4.5:1 contrast
- [ ] **Warning (orange):** ≥ 4.5:1 contrast
- [ ] **Error (red):** ≥ 4.5:1 contrast
- [ ] **Info (blue):** ≥ 4.5:1 contrast

---

## Functional Validation

### Navigation & Transitions

#### Tab Bar Navigation
1. **Test:** Tap each tab in sequence
2. **Expected:** 
   - No white flashes during transitions
   - Selected state immediately visible
   - Haptic feedback consistent
   - Animations smooth

#### Sheet Presentations
1. **Test:** Open Create Post, Profile Settings, Messages
2. **Expected:**
   - Sheet background adapts correctly
   - Smooth slide-in animation
   - Dismiss gesture works
   - No color flickering

#### Full Screen Covers
1. **Test:** Open user profiles, post details
2. **Expected:**
   - Background adapts before animation starts
   - Navigation bar adapts
   - No jarring transitions

#### Deep Links
1. **Test:** Open notification → post detail
2. **Expected:**
   - All screens in navigation stack use correct colors
   - Back navigation smooth

### Content Display

#### Feed Scrolling
1. **Test:** Scroll through 50+ posts rapidly
2. **Expected:**
   - No color flashing
   - Smooth 60fps scroll
   - Images load correctly
   - Profile photos visible

#### Pull-to-Refresh
1. **Test:** Pull to refresh on feed
2. **Expected:**
   - Refresh indicator visible
   - Loading state clear
   - Content updates smoothly

#### Lazy Loading
1. **Test:** Scroll to bottom of long list
2. **Expected:**
   - Loading indicator visible
   - New content adapts immediately
   - No color mismatches

### User Interactions

#### Post Creation
1. **Test:** Create a post with text and image
2. **Expected:**
   - Text editor readable
   - Image preview visible
   - Category pills clear
   - Upload progress visible
   - Success toast readable

#### Messaging
1. **Test:** Send and receive messages
2. **Expected:**
   - Sent bubbles: distinct color
   - Received bubbles: different but clear
   - Timestamps readable
   - Input bar visible
   - Placeholder text clear

#### Comments
1. **Test:** Read and post comments
2. **Expected:**
   - Comment text readable
   - Reply indentation visible
   - Action buttons clear
   - Input field visible

#### Reactions
1. **Test:** Like, lightbulb, repost posts
2. **Expected:**
   - Filled state: color changes
   - Count updates visible
   - Animation smooth
   - No color artifacts

---

## System Integration Tests

### Automatic Dark Mode Switching

#### Test 1: System Setting Change
1. Switch system to dark mode via Settings
2. Return to app
3. **Expected:** App immediately reflects dark mode

#### Test 2: Scheduled Appearance
1. Enable automatic dark mode (sunset to sunrise)
2. Wait for transition time
3. **Expected:** App adapts automatically

#### Test 3: While App Running
1. Have app open in light mode
2. Switch system to dark mode via Control Center
3. **Expected:** App adapts within 1 second, no crash

### App Lifecycle

#### Test 1: Foreground/Background
1. Open app in light mode
2. Switch to dark mode
3. Background app
4. Foreground app
5. **Expected:** Dark mode applied correctly

#### Test 2: Force Quit
1. Force quit app in light mode
2. Switch to dark mode
3. Relaunch app
4. **Expected:** App launches in dark mode

---

## Performance Validation

### Frame Rate
- [ ] **Feed scrolling:** Maintains 60fps in dark mode
- [ ] **Animations:** No dropped frames
- [ ] **Transitions:** Smooth 60fps

### Memory Usage
- [ ] **Dark mode uses ≤ same memory as light mode**
- [ ] **No memory leaks when switching modes**

### Battery Impact
- [ ] **Dark mode OLED displays:** Should improve battery (darker pixels)
- [ ] **No CPU spikes when switching**

---

## Regression Testing (Light Mode)

**CRITICAL:** Ensure light mode still works perfectly

### Visual Check
- [ ] All backgrounds still white/light
- [ ] All text still black
- [ ] Shadows still subtle
- [ ] Borders still visible
- [ ] No broken layouts

### Functional Check
- [ ] All features work identically
- [ ] No new bugs introduced
- [ ] Performance unchanged

---

## Accessibility Testing

### VoiceOver
1. Enable VoiceOver
2. Navigate through app in both modes
3. **Expected:**
   - All elements announced correctly
   - Color changes don't break navigation
   - Hints still helpful

### Dynamic Type
1. Increase text size to maximum
2. Switch between light and dark
3. **Expected:**
   - Text still readable
   - Layouts adapt correctly
   - No truncation

### Reduce Motion
1. Enable Reduce Motion
2. Switch between modes
3. **Expected:**
   - Transitions still smooth
   - No broken animations
   - Colors still adapt

### Contrast Ratios (Use Accessibility Inspector)

#### Test All Text Combinations:
- [ ] Primary text on main background: ≥ 7:1
- [ ] Secondary text on main background: ≥ 4.5:1
- [ ] Button text on button background: ≥ 4.5:1
- [ ] Icon color on background: ≥ 3:1 (UI elements)

---

## Edge Cases & Stress Tests

### Rapid Mode Switching
1. Switch light → dark → light → dark rapidly (10 times)
2. **Expected:**
   - No crashes
   - No color artifacts
   - No memory leaks

### Mixed Content
1. Open screen with images, text, icons, buttons
2. Switch modes
3. **Expected:** All elements adapt simultaneously

### Mid-Animation Switch
1. Start navigation animation
2. Switch mode during animation
3. **Expected:** Animation completes smoothly, colors adapt

### Network Loading States
1. Switch to airplane mode
2. Try to load content
3. **Expected:**
   - Loading indicators visible
   - Error states readable
   - Retry buttons clear

---

## Bug Reporting Template

If you find issues, report with:

```markdown
### Screen: [Screen Name]
### Mode: [Light/Dark/Both]
### Issue: [Brief description]

**Steps to Reproduce:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected:** [What should happen]
**Actual:** [What actually happens]

**Screenshot:** [Attach screenshot]

**Severity:**
- [ ] P0 - Crash or unreadable text
- [ ] P1 - Significant visual break
- [ ] P2 - Minor polish issue

**Notes:** [Additional context]
```

---

## Sign-Off Checklist

Before marking dark mode as "complete":

- [ ] All Priority 1-7 components migrated
- [ ] All screens tested in both modes
- [ ] No P0 or P1 bugs remaining
- [ ] Light mode fully regression tested
- [ ] Performance validated (60fps, memory OK)
- [ ] Accessibility tested (VoiceOver, contrast)
- [ ] TestFlight beta tested by 10+ users
- [ ] No crash reports related to dark mode
- [ ] Design team approved visual quality
- [ ] Product team approved feature parity

---

## Tools & Resources

### Xcode Tools
- **Environment Overrides:** Debug bar → Interface Style → Dark/Light
- **Accessibility Inspector:** Xcode → Open Developer Tool → Accessibility Inspector
- **Color Contrast Calculator:** Use built-in contrast checker

### Third-Party Tools
- **Color Oracle:** Colorblind simulation
- **Contrast Ratio Checker:** Online tool for WCAG compliance
- **Charles Proxy:** Test with poor network conditions

### Internal Resources
- `AmenAdaptiveColors.swift` - Color token definitions
- `DARK_MODE_MIGRATION_CHECKLIST.md` - Component migration status
- `CLAUDE.md` - Project standards and guidelines

---

## Contact

For dark mode implementation questions:
- Reference: `DARK_MODE_MIGRATION_CHECKLIST.md`
- Code examples: See `AmenAdaptiveColors.swift` usage comments
- Report bugs: Create issue with template above
