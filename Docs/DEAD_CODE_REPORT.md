# Dead Code Report — AMENAPP

**Date:** 2026-06-20
**Scope:** iOS app target (3,599 tracked `.swift` files)
**Method:** Build-free static analysis — git file listing, `project.pbxproj` membership, duplicate/orphan detection, and whole-repo token-frequency cross-referencing for unused types. No build was run (`.build-lock` protocol + concurrent agents in tree).

**Headline:** 22 stray files + 1 duplicate file + 4 duplicate directories (Tier 1, safe delete) · **924 unused types across 77 entirely-dead files** (Tier 3, triage required).

---

## Tier 1 — Confirmed dead files (safe to delete, zero build impact)

### A. Stray `.swift` files inside the `AMENAPP.xcodeproj/` bundle (21 files)

These live *inside* the `.xcodeproj` package directory, which is **not** a synced source root. Xcode's build system never compiles them — they are pure dead weight and invisible to the app.

| Category | Files |
|----------|-------|
| Duplicate `_`-variant scratch copies | `DailyCheckInManager.swift` + `DailyCheckIn_Manager.swift`, `DailyCheckInView.swift` + `DailyCheckIn_View.swift`, `DebugCheckInPanel.swift` + `DebugCheckIn_Panel.swift`, `SpiritualBlockView.swift` + `SpiritualBlock_View.swift` |
| Scratch / examples | `TABVIEW_EXAMPLE.swift`, `WorshipMusicView_IMPLEMENTATION.swift`, `MusicKitTest.swift`, `Extensions.swift` |
| Stale onboarding set (no live twin elsewhere) | `OnboardingCompletionView.swift`, `OnboardingContainerView.swift`, `OnboardingCoordinator.swift`, `OnboardingDenominationView.swift`, `OnboardingInterestsView.swift`, `OnboardingNotificationsView.swift`, `OnboardingStepViews.swift`, `OnboardingWelcomeView.swift` |
| Stale duplicate of a live file | `SafetyReportingService.swift` (live copy: `AMENAPP/SafetyReportingService.swift`) |

All paths are under `AMENAPP.xcodeproj/`.

### B. Duplicate-suffix orphan (1 file)

- `AMENShareExtension/ShareExtensionViewController 2.swift` — classic Finder/merge-collision duplicate (note the ` 2` suffix). The canonical file is `ShareExtensionViewController.swift` in the same folder.

### C. Duplicate ` 2` / ` 3`-suffixed directories (repo-root orphans)

Whole directory trees copied by Finder/merge collisions, not wired into the build:

- `AMENAPPUITests 2/`
- `Contracts 2/`
- `MusicContentLayer 2/`
- `MusicContentLayer 3/`

(Canonical siblings `AMENAPPUITests/`, `Contracts/`, `MusicContentLayer/` exist alongside each.)

**Tier 1 total: 22 stray files + 1 duplicate file + 4 duplicate directories.**

---

## Tier 2 — Caveat: per-file pbxproj heuristic is unreliable here

The project uses **Xcode 16 synced folders** (`objectVersion 77`, `PBXFileSystemSynchronizedRootGroup`). Files are compiled by **folder membership**, not individual `project.pbxproj` references. As a result:

- `project.pbxproj` only names **316** of the **3,599** Swift files.
- A "not listed in pbxproj → dead" rule produces **thousands of false positives** and must not be used.
- The only deliberate membership exceptions are `AMENBuildInfo.swift` and `BereanActivityAttributes.swift` — these are intentionally scoped, **not** dead.

---

## Tier 3 — Unused types (build-free static analysis)

A whole-repo token-frequency analysis identified types that are **declared once and never referenced anywhere** in the codebase.

**Method:**
1. Counted every capitalized identifier across all `AMENAPP/` Swift sources (3,388 files).
2. Cross-referenced against all declared types (`struct`/`class`/`enum`/`protocol`/`actor` — 13,656 unique).
3. Kept types whose name appears **exactly once** total (the declaration line only).
4. Removed `*_Previews` Xcode scaffolding (53) and `*Tests` suites (runner-discovered by reflection).
5. Verified each survivor appears **zero** times in every other target/dir (tests, extensions, `Contracts/`, `Sources/`, `SpacesOS/`, `MusicContentLayer/`, `ONE/`, etc.).

**Result: 924 unused types**, of which **77 non-test files are *entirely* dead** (every type they declare is unreferenced). These are overwhelmingly **built-but-never-wired** SwiftUI views — features that were implemented but never mounted into navigation.

### Largest dead clusters (whole files, all types unused)

| Module | Dead files | Notes |
|--------|-----------:|-------|
| `AMENAPP/Creator/` (Views/ViewModels/Utilities/Components/Models) | 22 | Entire Creator-studio module appears unwired. Distinct from the live `AIIntelligence/CreatorKit/`. |
| `AMENAPP/ChurchNotes/` (Views/ViewModels/Editor/Enums) | 11 | Most of the ChurchNotes editor surface. |
| `AMENAPP/.../SpiritualOS/` insight cards | 6 | `WeightOfWordsMeter`, `TruthEmotionOverlayView`, `SilenceInsightCard`, `ScriptureDriftInsightCard`, `PostActionReflectionSheet`, `CommunityDiscernmentBanner`. |
| `AMENAPP/.../IntegrationOS/` provider adapters | 3 | `MediaProviderAdapter`, `MapProviderAdapter`, `EventProviderAdapter`. |
| `AIIntelligence/` | 4 | `LiveCaptionOverlay`, `AmenGeneratedDraftPreview`, `AmenAIReviewViewModel`, `AmenAIReviewActionsView`. |
| Misc single-file orphans | ~31 | e.g. `GraceBasedSafetyUI.swift` (6 types), `FCM_TOKEN_INTEGRATION_GUIDE.swift` (a guide masquerading as code), `CorrectTheAIView`, `ManageSubscriptionView`, `AmenCommunityHubView`, `GuideMyFeedComposerChip`, `WeeklyAlignmentSummaryView`, `ReleaseVerificationHarnessView`. |

The full machine-readable lists were generated in `./.deadcode-scratch/` (not committed):
- `truly_unused.txt` — 924 unused type names
- `dead_files_clean.txt` — 77 entirely-dead non-test files

### Confidence & caveats
- **High confidence** these are unreferenced *by name*. Spot-checked repo-wide (`CreatorPublishSheet`, `ChurchNotesViewModel`, `AmenCommunityHubView`, etc.) — each appears exactly once, at its own declaration.
- **Residual false-positive sources** (verify before deleting): types reached only via Remote Config feature flags + runtime string dispatch, `@main`/App-entry types, or types instantiated solely through reflection. Feature-flag-gated-but-unmounted views are *intentionally dormant*, not necessarily deletable.
- This finds unused **types**, not unused methods/properties **within** live types — for that, run Periphery.

---

## Tier 4 — Deeper scan (Periphery, requires a build; not yet run)

For unused *methods, properties, and parameters* inside live types, the gold-standard tool **Periphery 2.21.2 is installed** (`/opt/homebrew/bin/periphery`). It needs a full `xcodebuild`, which collides with the repo's one-build-at-a-time `.build-lock` protocol and the agents currently active in this tree, so it was **not run**. Recommended on a quiet tree:
```sh
periphery scan --project AMENAPP.xcodeproj --schemes AMENAPP \
  --clean-build --skip-build false
```

---

## Recommended actions

1. **Delete Tier 1** (22 stray files + 1 duplicate file + 4 duplicate dirs) — no build impact; none are compiled. Branch + path-scoped commit per repo discipline.
2. **Triage Tier 3** — for each of the 77 dead files, decide *delete* (abandoned) vs *wire up* (intended feature stranded). Start with the `Creator/` and `ChurchNotes/` clusters: confirm whether they're superseded or pending integration.
3. **Schedule a Periphery scan** on a quiet tree for method/property-level dead code.
4. Investigate the stale `Onboarding*` set in `AMENAPP.xcodeproj/` — confirm the live onboarding flow has superseded it before deleting.
