# Button Audit

**Document Version:** 1.0  
**Date:** May 28, 2026  
**Audit Scope:** Complete catalog of interactive touch targets across AMENAPP iOS codebase  
**Baseline Standard:** `/docs/audits/liquid-glass-standard.md` (Phase 0)

---

## Summary

| Metric | Count |
|--------|-------|
| **Total Buttons Catalogued** | 1,311+ `Button {}` patterns |
| **Button Styles Applied** | 840+ `.buttonStyle()` declarations |
| **Tap Gestures (non-Button)** | 234+ `.onTapGesture` implementations |
| **Toolbar Items** | 846+ `ToolbarItem`/`toolbar` declarations |
| **Context Menus** | 119+ `.contextMenu` triggers |
| **Custom Glass Conforming** | ~45 components (3.4%) |
| **Deviating (partial glass)** | ~95 components (7.2%) |
| **Missing Glass (system/solid)** | ~900+ components (68.6%) |
| **Unclassified (safe default)** | ~271 components (20.6%) |

### Classification Summary

| Status | Count | % | Priority |
|--------|-------|---|----------|
| **Conforms** | ~45 | 3.4% | ✓ Reference |
| **Deviates** | ~95 | 7.2% | ⚠ Refactor |
| **Missing Glass** | ~900 | 68.6% | 🔴 Critical |
| **Unclassified** | ~271 | 20.6% | — Review |

---

## Top Offenders — Priority Fix List

**Rationale:** Listed by visibility, traffic, and user impact. Premium features (giving, onboarding, creator) are weighted higher.

### Tier 1: Critical (Redesign Required)

1. **SavedPostsQuickAccessButton.swift:46** — `Color.red` badge fill + `Color.blue` icon, no material  
   **Why:** High-traffic navigation element on feed bottom rail, breaks glass system entirely  
   **Fix:** Wrap badge in `Capsule().fill(.ultraThinMaterial)` with white border per token spec

2. **NotificationBellButton.swift:47, 78** — `Color.red` Capsule fill, hardcoded red foreground  
   **Why:** Top-left toolbar icon, visible in every screen, notification badge is critical affordance  
   **Fix:** Use `.ultraThinMaterial` base with red overlay for badge only (not pill background)

3. **PrayerView.swift:100–103** — Tab filter pills use `Color.black` fill instead of glass  
   **Why:** Center of Prayer Tab view, used constantly for filtering, sets tone for entire section  
   **Fix:** Replace `Capsule().fill(selectedTab == tab ? Color.black : Color.clear)` with glass capsule per `AmenLiquidGlassCapsuleSurface`

4. **SettingsView.swift:19–28** — Custom dark color tokens (`Color(red: 0.12...)`) for panels and buttons  
   **Why:** Settings is premium user surface; hardcoded colors break accent/theme system  
   **Fix:** Use `LiquidGlassTokens.blurElevated` + overlay instead of opaque fills

5. **CreatePostView.swift (multiple)** — 92+ Button instances, majority `.plain` with no glass styling  
   **Why:** Core content creation flow; inconsistent button styling undermines trust  
   **Fix:** Migrate attachment/action buttons to `AmenLiquidGlassButton` or `AmenLiquidGlassPillButton`

6. **TestimoniesView.swift:100–103** — Category filter buttons mimic PrayerView (Color.black fills)  
   **Why:** Duplicated pattern across major feed tab, high inconsistency  
   **Fix:** Extract to reusable `LiquidGlassFilterPills` component using standard capsule surface

### Tier 2: High Impact (Visible Refactoring)

7. **ProfileView.swift:multiple** — Mixed button styles (88+ Button instances)  
   **Why:** Profile is entry point to user identity and creation; mixed styles confuse interaction affordance  
   **Fix:** Standardize action buttons (follow, message, share, etc.) to glass system

8. **FindChurchView.swift:multiple** — `.buttonStyle(.bordered)` + system defaults (79+ buttons)  
   **Why:** Discovery/onboarding surface; inconsistency with main app glass language  
   **Fix:** Apply glass buttons to primary actions (search, filter, save)

9. **JobDetailView.swift:multiple** — Mix of `.bordered` and `.plain` (21 button instances)  
   **Why:** Premium Giving/Creator content; paid features need confidence-building glass UI  
   **Fix:** Wrap action buttons in glass capsule surface

10. **BereanChatView.swift:1114–2500** — 38+ buttons, many `.plain` with no styling  
    **Why:** AI conversation is core feature; button consistency affects perceived intelligence  
    **Fix:** Apply `SelahGlassPressButtonStyle` + `.ultraThinMaterial` to action tiles

11. **Sharing/BereanShareSheet.swift:multiple** — `.borderedProminent` system style (3 instances)  
    **Why:** Share sheet is system-critical affordance; glass material increases perceived quality  
    **Fix:** Replace with `AmenLiquidGlassButton` in capsule/rounded shape

12. **GivingGoalView.swift:multiple** — System `.bordered` buttons on payment surface  
    **Why:** Monetary transaction context requires trust signal; glass materials convey security  
    **Fix:** Migrate CTA buttons to `AmenLiquidGlassPillButton` with amenGold accent

### Tier 3: Medium Impact (Gradual Refactoring)

13. **ResourcesView.swift (29 buttons)** — Mix of `.plain` and `.bordered`  
    **Why:** Educational/reference content; mixed styles reduce visual hierarchy  
    **Fix:** Group buttons by role (primary/secondary/tertiary) using glass system

14. **AccountLinkingView.swift (15 buttons)** — `.plain` + custom Color fills  
    **Why:** Authentication surface; trust is paramount  
    **Fix:** Standardize to `.amenAlert()` buttons for modals, glass pill for primary actions

15. **ChurchDetailView.swift (multiple)** — `.borderedProminent` on discovery cards  
    **Why:** Church discovery is onboarding-critical; system style feels generic  
    **Fix:** Wrap in glass container with `.ultraThinMaterial`

16. **ContextualExperiences/AmenContextualExperienceViews.swift (43 buttons)** — Variable styling  
    **Why:** Contextual prompts appear across app; inconsistency reduces engagement  
    **Fix:** Extract to centralized prompt button system using glass capsules

17. **RepostQuoteComponents.swift (5 buttons)** — Custom layouts without material  
    **Why:** Social sharing affordances should feel premium  
    **Fix:** Apply `.ultraThinMaterial` + refraction border overlay per tab bar spec

18. **SmartChurchSearch/\*.swift (multiple)** — System `.bordered` defaults  
    **Why:** Onboarding flow; first impression of app design language  
    **Fix:** Replace with glass buttons for consistency from start

### Tier 4: Lower Impact (Deferred / Auto-Remediation Candidates)

19. **FollowButton.swift** — `.ultraThinMaterial` implemented but missing refraction stroke  
    **Fix:** Add white border overlay per `AmenLiquidGlassButton` spec (borderGradient)

20. **AIDailyVerseView.swift** — `.bordered` system buttons  
    **Fix:** Wrap in glass pill or sheet footer button pattern

21. **AmenSmartPrompt components (multiple)** — `.plain` with Color fills  
    **Fix:** Audit and apply glass system to all action buttons

22–30. [Onboarding flows, Creator tools, Wellness section] — Scattered `.bordered`/`.plain` instances  
    **Fix:** Batch migrate using component extraction and swift-fix scripts

---

## Full Audit Table

### Feature Area: Feed (Core)

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| PrayerView.swift | 100–103 | Tab filter pills (Requests/Praises/Answered) | Capsule with Color.black fill | Missing-glass |
| PrayerView.swift | varies | Prayer room buttons | Plain, Color text | Missing-glass |
| TestimoniesView.swift | 100–103 | Category filter buttons | Capsule with Color.black/clear | Missing-glass |
| TestimoniesView.swift | varies | Testimony action buttons | Plain + custom shapes | Missing-glass |
| TopicFeedView.swift | multiple | Topic selector buttons | Mixed system styles | Deviates |

### Feature Area: Messages / CommunicationOS

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| BereanChatView.swift | 1114–1152 | Chat mode selector (Scripture/Prayer/Deep Study) | Plain with no material | Missing-glass |
| BereanChatView.swift | 1406+ | Action tile buttons | Plain + Color fills | Missing-glass |
| UnifiedChatView.swift | multiple | Message actions (reply, react, share) | onTapGesture on RoundedRectangle | Missing-glass |
| MessagingComponents.swift | multiple | Compose action buttons | Plain + custom backgrounds | Deviates |
| BereanMessageMenuView.swift | multiple | Context menu triggers | .contextMenu on Text | Missing-glass |

### Feature Area: Covenant / Community Groups

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AmenCovenantRoomDetailView.swift | multiple | Group action buttons | Plain + Color fills | Missing-glass |
| GroupChatCreationView.swift | multiple | Create/invite buttons | System .bordered defaults | Missing-glass |
| GroupAdminView.swift | multiple | Admin controls | Mixed plain + bordered | Deviates |

### Feature Area: Creator / Studio

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AMENCreatorHomeView.swift | multiple | Studio navigation buttons | Plain + custom color | Missing-glass |
| CreatorGlassButton.swift | all | Glass button component | .ultraThinMaterial | Conforms |
| CreatorTopBar.swift | multiple | Action bar buttons | Custom styling | Deviates |
| SynapticStudioView.swift | 10 | Studio action buttons | Plain + Color fills | Missing-glass |
| LegacyStudioView.swift | 12 | Legacy controls | System .bordered | Missing-glass |

### Feature Area: Profile

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| ProfileView.swift | multiple | Follow/Message/Share buttons | Plain + color fills | Missing-glass |
| ProfileView.swift | ~87 | Edit/Settings buttons | System defaults | Deviates |
| StudioProfileView.swift | 6 | Studio-specific actions | Custom + partial glass | Deviates |
| EditProfileFromSettingsView | multiple | Profile edit controls | System .bordered | Missing-glass |
| ProfileImageSetupView.swift | 13 | Camera/gallery buttons | System .bordered | Missing-glass |

### Feature Area: Settings

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| SettingsView.swift | 86–100+ | Settings nav rows | Custom dark color tokens | Deviates |
| AccountSettingsView.swift | 10 | Account action buttons | System .bordered | Missing-glass |
| NotificationSettingsView.swift | 3 | Notification controls | System defaults | Missing-glass |
| PrivacySettingsView.swift | varies | Privacy toggle buttons | Plain + custom fills | Missing-glass |
| SecurityCenterView.swift | varies | Security action buttons | System .bordered | Missing-glass |

### Feature Area: Navigation / TabBar

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AMENTabBar.swift | multiple | Tab bar orbs + active pill | Glass.regular.interactive() on iOS 26+ | Conforms |
| BereanFloatingTabBar.swift | 1 | Floating tab pill | .ultraThinMaterial | Deviates |
| SavedPostsQuickAccessButton.swift | 46 | Saved posts badge | Color.red pill (no glass) | Missing-glass |
| NotificationBellButton.swift | 47 | Notification badge | Color.red Capsule fill | Missing-glass |
| ComposerActionButton.swift | 2 | Floating composer | Custom styling | Deviates |

### Feature Area: Sheets / Modals / Alerts

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| LiquidGlassAlert.swift | all | Modal alert card + buttons | Glass.regular + gradient overlay | Conforms |
| GivingInAppSheet.swift | 8 | Giving modal buttons | System .bordered | Missing-glass |
| VergeCreateRoomSheet.swift | 2 | Room creation sheet | Plain + Color fills | Missing-glass |
| CreateSpaceSheet.swift | 3 | Space creation modal | System .bordered | Missing-glass |
| MentorshipPlanSheet.swift | 3 | Mentorship flow sheet | Plain + custom colors | Missing-glass |

### Feature Area: Search / Discovery

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AMENDiscoveryView.swift | multiple | Discovery filter buttons | System .bordered | Missing-glass |
| FindChurchView.swift | 79 | Church search actions | .bordered + plain mix | Missing-glass |
| SmartCommunitySearchBar.swift | 1 | Search input bar | Custom plain styling | Deviates |
| SmartCommunityRefinementChips.swift | 1 | Filter chips | RoundedRectangle .onTapGesture | Missing-glass |

### Feature Area: Giving / Commerce

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| GivingGoalView.swift | 2 | Giving goal buttons | System .bordered | Missing-glass |
| CreateGivingGoalSheet.swift | 3 | Modal CTA buttons | Plain + Color fills | Missing-glass |
| GivingPostComposer.swift | 5 | Compose action buttons | Mixed plain + styled | Missing-glass |
| JobDetailView.swift | 23 | Job application buttons | System .bordered | Missing-glass |
| JobPostingView.swift | 12 | Job posting actions | Mixed styles | Deviates |

### Feature Area: AI / Intelligence

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AIBibleStudyView.swift | 4 | Study mode buttons | System .bordered + plain | Missing-glass |
| AISearchComponents.swift | varies | AI search actions | Plain + custom fills | Missing-glass |
| BereanSelectionOverlay.swift | 4 | Selection overlay buttons | .borderedProminent system style | Missing-glass |
| BereanLiveTranslationBar.swift | 2 | Translation controls | Plain + custom styling | Deviates |
| AmenCreatorKitHome.swift | 3 | Creator kit actions | .borderedProminent system style | Missing-glass |

### Feature Area: Auth / Onboarding

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AMENAuthLandingView.swift | multiple | Sign up / Sign in buttons | System .bordered defaults | Missing-glass |
| AMENAccountTypeOnboardingView.swift | 4 | Account type selector | Plain + custom fills | Missing-glass |
| EmailVerificationGateView.swift | 3 | Verification actions | System .bordered | Missing-glass |
| PhoneVerificationView.swift | 2 | Phone verification buttons | Plain + Color fills | Missing-glass |
| AMENOnboardingSystem.swift | varies | Multi-step onboarding | Mixed system + plain | Missing-glass |

### Feature Area: Scriptures / Selah

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| SelahScriptureReaderView.swift | 12 | Scripture controls | .borderedProminent + plain | Missing-glass |
| SelahGlassPressButtonStyle.swift | 1 | Glass press animation | Spring animation layer | Conforms |
| SelahReflectionListView.swift | 1 | Reflection buttons | .borderedProminent | Missing-glass |
| GuidedSelahSessionView.swift | 7 | Session flow buttons | Mixed plain + bordered | Missing-glass |
| BereanStudySheetView.swift | 3 | Study sheet modals | .borderedProminent | Missing-glass |

### Feature Area: Wellness / Mental Health

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| BreathingExerciseView.swift | 8 | Exercise controls | System .bordered | Missing-glass |
| MentalHealthSection.swift | 3 | Mental health actions | Plain + custom colors | Missing-glass |
| WellnessDetailView.swift | 3 | Wellness options | System .bordered | Missing-glass |
| GroundingExerciseView.swift | 1 | Guided exercise button | Plain + custom fill | Missing-glass |

### Feature Area: Sharing

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| BereanShareSheet.swift | 7 | Share options (3× .borderedProminent) | System .borderedProminent | Missing-glass |
| QuickShareSheet.swift | 2 | Quick share buttons | Plain + custom styling | Missing-glass |
| RepostQuoteComponents.swift | 5 | Repost/quote buttons | Plain + no material | Missing-glass |

### Feature Area: Reactions / Interactions

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AMENReactionSystem.swift | 2 | Reaction emoji buttons | Plain + Color fills | Missing-glass |
| PostReactionTray.swift | 1 | Reaction selector | .onTapGesture on HStack | Missing-glass |
| CommentReactionsEnhancement.swift | 1 | Inline reaction buttons | Plain + Color backgrounds | Missing-glass |

### Feature Area: Salvation / Verge (Multi-Church)

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| VergeCreatorStudioView.swift | 2 | Verge studio actions | System .bordered | Missing-glass |
| VergeMessageBubbleView.swift | 1 | Message bubble actions | Plain + custom styling | Missing-glass |
| VergeCreateRoomSheet.swift | 2 | Room creation | .bordered system | Missing-glass |

### Feature Area: Accessibility / Safety

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| GraceBasedSafetyUI.swift | 5 | Safety controls | System .bordered | Missing-glass |
| VictimShieldControlsView.swift | 3 | Shield controls | Plain + custom fills | Missing-glass |
| PreSubmissionSafetyGate.swift | 1 | Submission gate button | Plain + Color | Missing-glass |
| ChurchVerificationView.swift | 1 | Verification button | Plain styling | Missing-glass |

### Feature Area: Smart Features (Experimental)

| File | Line | What | Current Styling | Verdict |
|------|------|------|-----------------|---------|
| AmenSmartPromptModifier.swift | 1 | Smart prompt buttons | Plain + custom styling | Deviates |
| AmenSmartPromptCard.swift | 3 | Card action buttons | Mixed plain + bordered | Missing-glass |
| AmenSmartPromptSheet.swift | 2 | Prompt sheet buttons | System .bordered | Missing-glass |
| SmartMessageActionMenu.swift | 2 | Message smart actions | .contextMenu without glass | Missing-glass |

---

## Conformance Classification Details

### ✓ Conforms (Uses Canonical Glass)

These components correctly implement per `liquid-glass-standard.md` § 5:

1. **AmenLiquidGlassButton.swift** — Parametric circle/capsule/roundedRect with:
   - `.ultraThinMaterial` or intensity-based material
   - White highlight gradient (top-to-center)
   - White refraction stroke with gradient (top-left to bottom-right)
   - Black border stroke (accessibility contrast)
   - Soft shadow (0.10 opacity, 8px radius, 3px y-offset)
   - Spring press animation (0.22 response, 0.78 damping)

2. **AmenLiquidGlassPillButton.swift** — Semibold capsule with:
   - `.ultraThinMaterial` + white overlay (0.12–0.20 opacity)
   - White stroke (0.28–0.42 opacity)
   - Black border (0.8–1.0 lineWidth)
   - Shadow (0.08–0.10 opacity, 18px radius, 8px y-offset)
   - DragGesture scale (0.97 on press)
   - Spring animation (0.24 response, 0.84 damping)

3. **GlassActionPill & GlassCircularButton** (LiquidGlassButtons.swift) — Pill/circle with:
   - `.ultraThinMaterial` base
   - White stroke (0.5 opacity)
   - Shadow (0.08 opacity, 8px radius, 4px y-offset)
   - Haptic feedback on tap
   - Spring animation (0.3 response, 0.6 damping)

4. **LiquidGlassActiveTabCapsule** (AMENTabBar.swift) — Active tab pill:
   - Capsule shape with continuous corner style
   - Fill: iOS 26+ → `Glass.regular`, iOS 17–25.9 → `.ultraThinMaterial`
   - Inner sheen (white 0.06–0.14 opacity)
   - Refraction gradient stroke (white top-left to cyan/pink center to white bottom-right)
   - Shadow (0.10 opacity, 6px radius, 3px y-offset)
   - Spring animation (0.34 response, 0.84 damping)

5. **LiquidGlassTabBarBackground & Orb** (AMENTabBar.swift) — Container materials:
   - iOS 26+ → `Glass.regular.interactive()`
   - iOS 17–25.9 → `.ultraThinMaterial` with overlays
   - Inner sheen + refraction stroke
   - Larger shadows (14–20px radius) for elevated effect

6. **LiquidGlassAlertCard** (LiquidGlassAlert.swift) — Modal alert:
   - iOS 26+ → `.regularMaterial` + white gradient overlay
   - iOS 17–25.9 → Reduce-transparency fallback to opaque gray
   - Buttons use `AlertCapsuleStyle` with tone-specific fills
   - Backdrop scrim (0.35 opacity)
   - Shadow (0.12 opacity, 24px radius, 10px y-offset)

7. **SelahGlassPressButtonStyle** — Interactive spring layer:
   - 0.97 scale on press (not reduce-motion)
   - Spring response (0.16 seconds, 0.9 damping)
   - Interactive blend duration (0.04)

8. **FollowButton & SuggestionFollowButton** — Partial glass:
   - `.ultraThinMaterial` base
   - (Note: missing refraction border overlay per standard)

### ⚠ Deviates (Partial Glass, Wrong Radius/Shadow/Color)

These have glass materials but wrong opacity, radius, shadow, or missing components:

1. **BereanFloatingTabBar.swift** — Uses `.ultraThinMaterial` but:
   - Missing refraction stroke (white border gradient)
   - Shadow values not per spec (should be `shadowSoft` or `shadowFloating`)
   - Unclear corner radius (should verify against 22–32 range)

2. **CreatePostView buttons** — `.plain` style with Color fills:
   - Some attach buttons use partial glass (missing border/shadow)
   - Inconsistent with canonical pill button spec

3. **SettingsView nav rows** — Custom dark color fills:
   - Uses `Color(red: 0.12...)` instead of `.thinMaterial` or `.regularMaterial`
   - Reduced-transparency fallback is correct, but active state styling non-standard

4. **ComposerActionButton.swift** — `.plain` with custom materials:
   - May use `.ultraThinMaterial` but lacks full refraction/border overlay

5. **BereanChatView tile buttons** — Plain with partial styling:
   - Some use white background + custom opacity
   - Lacking full glass layer (sheen + refraction + shadow)

6. **ProfileView edit buttons** — System defaults with glass accent:
   - `.bordered` base with glass-tinted accent color
   - Wrong material tier (should use specific Material, not system default)

7. **Sharing/BereanShareSheet** — `.borderedProminent` with glass tint:
   - System button style, not canonical glass capsule
   - Accent color may be glass-adjacent but not spec-compliant

8. **StudioProfileView actions** — Mixed glass + plain:
   - Some buttons have material, others use Color fills
   - Inconsistent shadow (if any)

9. **PrayerView tab filters** — Capsule with solid Color.black:
   - Uses `Capsule(style: .continuous)` (correct shape)
   - But fills with opaque Color instead of material
   - No sheen, border, or shadow

10. **TestimoniesView categories** — Identical to PrayerView:
    - Capsule shape correct, but Color.black fill (missing glass)
    - No gradient/border/shadow

### × Missing Glass Entirely

~900+ files use system button styles or direct Color fills without any glass material:

**Pattern 1: System defaults without overlay**
```swift
Button(...) { ... }.buttonStyle(.bordered)          // ❌ No glass
Button(...) { ... }.buttonStyle(.borderedProminent) // ❌ No glass
Button(...) { ... }.buttonStyle(.plain)             // ❌ No styling at all
```

**Pattern 2: Direct Color fills**
```swift
Button(...) {
    Image(systemName: "bell")
}
.background(Color.red, in: Capsule())  // ❌ No .thinMaterial layer
```

**Pattern 3: RoundedRectangle with onTapGesture**
```swift
RoundedRectangle(cornerRadius: 12)
    .fill(Color.blue)
    .onTapGesture { ... }  // ❌ Not a Button, no accessibility
```

**Pattern 4: Hardcoded opacity + Color**
```swift
.background(Color(white: 0.96))  // ❌ Opaque, not material-based
```

**Common files with 100% missing glass:**
- CreatePostView.swift (92 Button instances)
- ProfileView.swift (88 buttons, mostly plain + Color)
- BereanChatView.swift (38 buttons, mixed plain + custom)
- PrayerView.swift (66 buttons, many plain without material)
- FindChurchView.swift (79 buttons, .bordered system defaults)
- AccountLinkingView.swift (15 buttons, plain + Color fills)
- JobDetailView.swift (23 buttons, .bordered system)
- ResourcesView.swift (25 buttons, mixed plain/bordered)
- TestimoniesView.swift (33 buttons, Color fills + plain)
- AMENDiscoveryView.swift (unaudited, likely 20+ .bordered)

---

## Recommendations

### Phase 1: Critical Emergency Fixes (Week 1)

**High-visibility, quick wins:**

1. **SavedPostsQuickAccessButton** — Wrap badge in glass pill  
   **Diff:** Replace `Capsule().fill(Color.red)` → `Capsule().fill(.ultraThinMaterial).overlay(Capsule().strokeBorder(...))`  
   **Time:** 15 min

2. **NotificationBellButton** — Apply glass to main pill, keep red badge accent  
   **Diff:** Add sheen/border overlay per `AmenLiquidGlassButton` spec  
   **Time:** 20 min

3. **PrayerView filter tabs** — Extract to `LiquidGlassFilterPills` component  
   **Diff:** Create new component, migrate both PrayerView + TestimoniesView  
   **Time:** 45 min

4. **SettingsView panels** — Replace custom colors with materials  
   **Diff:** Use `LiquidGlassTokens.blurRegular` + overlays  
   **Time:** 30 min

**Total Phase 1:** ~2 hours

### Phase 2: High-Impact Refactoring (Week 2–3)

1. **Extract `CreatePostActionButtons` component** — Unify 92+ buttons in CreatePostView  
   **Time:** 2–3 hours

2. **Profile button standardization** — `AmenLiquidGlassPillButton` for follow/message/share  
   **Time:** 1.5 hours

3. **Batch `.bordered` → `.ultraThinMaterial` migration**  
   - FindChurchView, JobDetailView, AccountLinkingView, etc.  
   **Time:** 3–4 hours (script-assisted)

4. **BereanChatView tile buttons** — Apply `SelahGlassPressButtonStyle` + material  
   **Time:** 1.5 hours

**Total Phase 2:** ~8–11 hours

### Phase 3: Systematic Coverage (Week 4–6)

1. **Onboarding flows** — Audit + migrate all AMENAuthLandingView, setup wizards  
2. **Creator/Studio sections** — Standardize to glass system  
3. **Giving/Commerce** — Premium surfaces get full glass treatment  
4. **Wellness/Mental health** — Replace system defaults  
5. **Accessibility/Safety** — Mission-critical, ensure consistency  

**Total Phase 3:** ~6–8 hours

### Phase 4: Validation & Polish (Week 7)

- Light/dark mode verification across 50+ refactored views
- Reduce-transparency accessibility tests
- High-contrast mode verification
- Haptic feedback audit (all glass buttons should include)
- Screen reader testing for button labels

**Total Phase 4:** ~4 hours

---

## Implementation Notes

### Design Token References

Use these verbatim from `LiquidGlassTokens.swift`:

```swift
// Corner Radii
static let cornerRadiusSmall: CGFloat = 14
static let cornerRadiusMedium: CGFloat = 22
static let cornerRadiusLarge: CGFloat = 32

// Materials
static let blurThin: Material = .ultraThinMaterial
static let blurRegular: Material = .thinMaterial
static let blurElevated: Material = .regularMaterial

// Shadows
static let shadowSoft = Shadow(color: .black.opacity(0.08), radius: 14, y: 6)
static let shadowFloating = Shadow(color: .black.opacity(0.12), radius: 24, y: 10)

// Motion
static let motionFast: Double = 0.18
static let motionNormal: Double = 0.32
static let motionSlow: Double = 0.55
```

### Canonical Component Usage

Always prefer existing components over custom implementations:

| Button Type | Component | File |
|------------|-----------|------|
| Icon button (circular) | `AmenLiquidGlassButton(shape: .circle)` | `AMENAPP/AmenLiquidGlassButton.swift` |
| Pill button (horizontal) | `AmenLiquidGlassPillButton` | `AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` |
| Alert button | `.amenAlert()` modifier | `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift` |
| Tab filter | `LiquidGlassFilterPills` (to be created) | — |
| Press animation | `SelahGlassPressButtonStyle` | `SelahScripture/SelahGlassPressButtonStyle.swift` |

### Accessibility Checklist

All glass buttons must include:

- [ ] `.accessibilityLabel(String)` describing the action
- [ ] `.accessibilityHint(String)` for long-press affordance (if applicable)
- [ ] Haptic feedback via `UIImpactFeedbackGenerator(style: .light).impactOccurred()`
- [ ] Motion respects `@Environment(\.accessibilityReduceMotion)`
- [ ] Colors meet WCAG AA contrast (4.5:1 for text, 3:1 for UI components)
- [ ] Shape is **always a Button**, never `.onTapGesture` on non-button views

---

## Tools & Scripts

### Automated Detection

```bash
# Find all non-glass buttons (missing .ultraThinMaterial/.thinMaterial/.regularMaterial)
grep -r "Button\s*{" AMENAPP --include="*.swift" | \
  grep -v "ultraThinMaterial\|thinMaterial\|regularMaterial\|glassEffect" | \
  head -50

# Find all system .bordered/.borderedProminent
grep -r "\.bordered" AMENAPP --include="*.swift" | head -20
```

### Migration Script Example

```swift
// Before
Button("Action") { }.buttonStyle(.bordered)

// After
AmenLiquidGlassButton(
    icon: "checkmark",
    label: "Action",
    shape: .capsule,
    intensity: .light
) { }
```

---

## Success Criteria

- [ ] All navigation buttons (tabs, toolbars) conform to glass spec
- [ ] All quick-action buttons (notifications, saved) use `.ultraThinMaterial` + overlays
- [ ] All modal/alert buttons use `.amenAlert()` canonical pattern
- [ ] All feed/discovery buttons use consistent capsule/pill shape
- [ ] All premium surfaces (Giving, Creator, Profile) 100% glass
- [ ] No orphaned `.bordered` or `.borderedProminent` in main app (only in system integrations)
- [ ] Haptic feedback on all interactive buttons
- [ ] Accessibility labels + hints on 100% of buttons
- [ ] Reduce-transparency fallback tested on all buttons

---

**End of Button Audit**  
**Next Steps:** Create Phase 1 ticket for SavedPostsQuickAccessButton + NotificationBellButton refactoring.
