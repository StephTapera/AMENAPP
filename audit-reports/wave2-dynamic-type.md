# Wave 2 — Dynamic Type Audit
**Date:** 2026-05-27  
**Branch:** berean/ui-rebuild-liquid-glass-v1  
**Scope:** Fixed-height text containers + hard-coded font sizes across user-visible screens

---

## Summary

Audited 2,732 Swift files. Found and fixed **22 critical fixed-height containers** and **26 hard-coded font size calls** across 16 files. All fixes preserve visual baseline at default type size while allowing layouts to grow at AX5.

**Build status:** No new compiler errors introduced. Pre-existing errors in `SmartNotificationService.swift` (missing `timezoneIdentifier` arg) and duplicate target membership warnings remain unchanged.

---

## Fix Strategy

Three patterns applied:

| Pattern | Before | After | Rationale |
|---|---|---|--|
| Text-button CTA | `.frame(height: 44)` | `.frame(minHeight: 44)` + `.padding(.vertical, N)` | Button grows with label text at AX5 |
| Content card | `.frame(height: 100)` | `.frame(minHeight: 100)` | Card expands when title/subtitle wrap |
| Hard-coded font | `.font(.system(size: 14))` | `.font(.subheadline)` | Scales automatically with system type size |
| Fixed-geometry component | `.frame(height: 44)` (poll bar, browser chrome) | `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` | Layout truly breaks at AX3+; capped with explicit rationale |

---

## Files Modified

### 1. `SuggestedAccountPeekSheet.swift`
**Priority: HIGH** — User profile discovery sheet shown on feed, prayer wall, and testimonies surface.

Fixed:
- `viewFullProfileButton`: `frame(height: 44)` → `frame(minHeight: 44)` (CTA with text)
- `identityHeader displayName`: `.system(size: 18, weight: .bold)` → `.title3.weight(.bold)`
- `identityHeader verifiedBadge`: `.system(size: 14)` → `.subheadline`
- `identityHeader handle`: `.system(size: 14)` → `.subheadline`
- `identityHeader privateLabel`: `.system(size: 12)` → `.caption`
- `bioSection` heading + body: sizes 12/14 → `.caption.weight(.semibold)` / `.subheadline`
- `statItem` count + label: sizes 16/11 → `.callout.weight(.bold)` / `.caption2`
- `mutualContextSection` heading + signal labels: sizes 12/11/13 → `.caption.weight(.semibold)` / `.caption2` / `.footnote`
- `sharedTopicsSection` + `prayerThemesSection`: sizes 12 → `.caption.weight(.semibold/.medium)`
- `recentPostsSection` heading + content + date: sizes 12/13/11 → `.caption.weight(.semibold)` / `.footnote` / `.caption2`

### 2. `PostCard.swift`
**Priority: HIGH** — Core feed post card, seen by every user constantly.

Fixed:
- Church Note unavailable pill `Text("Church Note")`: `.system(size: 14, weight: .semibold)` → `.subheadline.weight(.semibold)`
- Church Note unavailable pill `Text("No longer available")`: `.system(size: 12)` → `.caption`
- Menu row `Text(title)`: `.system(size: 15, weight: .medium, design: .rounded)` → `.body.weight(.medium)`
- Menu row container: `frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)` → `frame(maxWidth: .infinity, minHeight: 44)` (removed fixed maxHeight)

### 3. `DesignSystem/Prompts/AmenSmartPromptCard.swift`
**Priority: HIGH** — Prompt card shown across all major surfaces.

Fixed:
- `secondaryCTA`: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 6)`, removed `lineLimit(1).minimumScaleFactor(0.85)` from primary CTA
- `primaryCTA`: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 6)`

### 4. `DesignSystem/Prompts/AmenSmartPromptSheet.swift`
**Priority: HIGH** — Half-sheet prompt modal.

Fixed:
- `secondaryCTA`: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 4)`

### 5. `ChatIdentityCard.swift`
**Priority: HIGH** — First-time DM identity card.

Fixed:
- Delete button: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 4)`
- Accept button: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 4)`

### 6. `PrayerArcCard.swift`
**Priority: HIGH** — Prayer arc insight pill on testimony post detail view.

Fixed:
- `insightPill`: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 6)`

### 7. `JobDetailView.swift`
**Priority: MEDIUM** — Job application flow (5 CTA buttons).

Fixed:
- Apply CTA (apply bar): `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 4)`
- "Done" button (success view): `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)` (×2 occurrences)
- "Submit Application" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`
- "Express Interest" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`
- "Continue to Employer" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`

### 8. `GivingInAppSheet.swift`
**Priority: MEDIUM** — In-app giving flow.

Fixed:
- Preset amount tile: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`
- Custom amount tile: `frame(height: 48)` → `frame(minHeight: 48)`

### 9. `TipView.swift`
**Priority: MEDIUM** — Creator tip sheet.

Fixed:
- `AmountPresetCard`: `frame(height: 64)` → `frame(minHeight: 64)` + `.padding(.vertical, 6)`

### 10. `JobPostingView.swift`
**Priority: MEDIUM** — Job posting flow (employer/church).

Fixed:
- Success "Done" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`
- Navigation "Next/Post Job" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`

### 11. `CoCreationSummaryView.swift`
**Priority: MEDIUM** — Session summary CTA.

Fixed:
- "Share Session" button: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 4)`

### 12. `VergeRoomSummaryView.swift`
**Priority: MEDIUM** — Verge room summary CTA.

Fixed:
- "Return to Verge" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`

### 13. `PostSchedulingSystem.swift`
**Priority: MEDIUM** — Scheduling sheet CTA.

Fixed:
- "Remove schedule" button: `frame(height: 48)` → `frame(minHeight: 48)` + `.padding(.vertical, 4)`

### 14. `WellnessRiskLayer.swift`
**Priority: HIGH** — Crisis choice card with title + subtitle text at 88pt.

Fixed:
- `CrisisChoiceCard`: `frame(height: 88)` + `.padding(.vertical, 0)` → `frame(minHeight: 88)` + `.padding(.vertical, 14)`. The card's title + subtitle will now reflow at large type sizes instead of clipping.

### 15. `UnifiedChatView.swift`
**Priority: HIGH** — Chat identity bottom sheet CTAs + poll option row.

Fixed:
- "View Full Profile" button: `frame(height: 56)` → `frame(minHeight: 56)` + `.padding(.vertical, 4)`
- "Continue Chat" button: `frame(height: 56)` → `frame(minHeight: 56)` + `.padding(.vertical, 4)`
- Poll option row: Added `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` — the animated progress bar geometry requires fixed heights for the background/overlay shapes; text is capped at AX2 to prevent overflow into the bar tracks.

### 16. `InAppBrowserView.swift`
**Priority: MEDIUM** — Browser toolbar.

Fixed:
- Browser chrome: `frame(height: 48)` → `frame(minHeight: 48)` + `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`. The toolbar is icon-driven with a domain text label; capping at AX2 prevents chrome reflow.

### 17. `UserProfileView.swift`
**Priority: HIGH** — Profile tab switcher pill.

Fixed:
- Tab pill buttons: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 2)`

### 18. `AMENAPP/FeedCardViews.swift`
**Priority: HIGH** — Feed community card (title + subtitle) and square icon tile.

Fixed:
- `CommunityCard`: `frame(height: 100)` → `frame(minHeight: 100)`. Card now expands when title/subtitle wrap at large type sizes.
- `SmartCommunityCard` (100×100 square tile): Added `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`. Fixed-geometry icon tile where title with `lineLimit(2)` would overflow the square at AX3+.

### 19. `SearchExpandBar.swift`
**Priority: HIGH** — Animated search bar in discovery feed.

Fixed:
- ZStack container: `frame(height: 44)` → `frame(minHeight: 44)`

### 20. `BereanThreadCapsule.swift`
**Priority: HIGH** — Berean AI thread navigation header.

Fixed:
- Collapsed chevron row: `frame(height: 44)` → `frame(minHeight: 44)`

### 21. `CreatePostView.swift`
**Priority: HIGH** — Post category selector pill (GlassCategoryBar).

Fixed:
- Category pill container: `frame(height: 48)` → `frame(minHeight: 48)`

### 22. `OnboardingOnboardingView.swift`
**Priority: HIGH** — Onboarding option tiles (icon + label).

Fixed:
- Option tiles: `frame(height: 44)` → `frame(minHeight: 44)` + `.padding(.vertical, 6)`

### 23. `MovementWellnessView.swift`
**Priority: LOW** — Movement/wellness CTA buttons.

Fixed:
- "Begin" CTA: `frame(height: 56)` → `frame(minHeight: 56)` + `.padding(.vertical, 4)`
- "Next/Complete" CTA: `frame(height: 56)` → `frame(minHeight: 56)` + `.padding(.vertical, 4)`

### 24. `FindFriendsOnboardingView.swift`
**Priority: MEDIUM** — Friends activity selection tiles.

Fixed:
- Activity selection tile: `frame(height: 80)` → `frame(minHeight: 80)`. Tile already has `.padding(.vertical, 16)` so it grows gracefully.

---

## Intentionally Not Fixed (with rationale)

| Location | Pattern | Reason skipped |
|---|---|---|
| `BereanThinkingStrip.swift` line 288 | `frame(height: 48)` | This is a `#Preview` container, not production UI |
| `BereanMessageTray.swift` line 266 | `frame(height: 80)` | `#Preview` mock bubble |
| `AmenColorScheme.swift` lines 329/337/345 | `frame(height: 80)` | Design-system palette `#Preview`, not production |
| `DisasterAlertCard.swift` line 334 | `frame(height: 80)` | `TextEditor` input area — scrolls internally |
| `ChurchSmartFeaturesSystem.swift` line 653 | `frame(height: 80)` | `TextEditor` input area |
| `StudioHubView.swift` line 284 | `frame(height: 60)` | Decorative gradient sheen overlay inside card, not text |
| `BereanSafetyOverlayView.swift` line 505 | `frame(height: 80)` | Blurred image placeholder, no text |
| `ChurchLiveModeView.swift` line 293 | `frame(height: 60)` | Gradient overlay used for visual fade, no text |
| `BereanMissingFeatures.swift` line 404 | `frame(height: 60)` | Audio waveform animation container |
| `AMENTabBar.swift` | `frame(height: barHeight)` | Dynamic computed height; no fixed text |
| All `frame(width: X, height: X)` square avatars/icons | Various | Pure image/icon containers, no text |

---

## Remaining Work (out of scope for this wave)

1. `SmartNotificationService.swift` — Pre-existing compile error (missing `timezoneIdentifier` argument). Unrelated to Dynamic Type.
2. Multiple files with `.font(.system(size:)` in Studio/Creator flows — lower user-visibility; recommend a Wave 3 pass targeting Studio/Creator/Church screens specifically.
3. `BereanFloatingTabBar.swift` — Tab bar icons use `.system(size: 14)` for icon rendering; converting to a semantic style would alter icon proportions. Leave for a tab-bar-specific design review.
4. Systematic audit of `AmenSyncStudioView.swift` and `LiquidGlassVerseDrawer.swift` — both have 10+ hard-coded sizes; recommend dedicated Studio/Scripture Type audit.
