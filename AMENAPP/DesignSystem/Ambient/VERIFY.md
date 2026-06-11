# Adaptive Ambient — Phase 3 Verification

Read-only verification of the 5-surface integration against the frozen Ambient
system (`AmbientContract.swift`, `AmbientEnvironment.swift`, `Components/*`,
`AdaptiveColorEngine.swift`). Date: 2026-06-09.

---

## 1. Hardcoded-color sweep (invariant C8)

Grepped each surface for `Color(red:`, `Color(hex:`, `#colorLiteral`, `UIColor(`,
then cross-checked every hit against `git diff -U0` (added `+` lines only) to
isolate anything introduced by the ambient edits.

| Surface file | Raw hits | NEW (added by ambient edit) |
|---|---|---|
| ProfileView.swift | 0 | 0 |
| FullscreenMediaViewer.swift | 0 | 0 |
| PostDetailView.swift | 5 (lines 561, 563, 565, 917, 1440) | **0** |
| SpaceFeedView.swift | 6 (lines 20, 21, 22, 193, 194, 340, 344, 410, 415) | **0** |
| AdaptiveColorsSetting.swift (new) | 0 | 0 |

**NEW unannotated color hits introduced near ambient edits: 0.**

All hits are pre-existing chrome (PostDetailView reaction/border gradients;
SpaceFeedView's `background`/`accentPurple` design tokens declared at lines
20–22). `git diff -U0 | grep '^+...Color(red:'` returned empty for both files —
none of the hardcoded colors are on lines added by the ambient integration.
They predate this work, so C8 is not regressed by the ambient-touched regions.
(Pre-existing C8 debt in those two files is out of scope for this rollout but
noted as a follow-up.)

---

## 2. Ambient-system reference confirmation

Each surface now references the ambient system (verified by grep for
`AmbientScope` / `Adaptive*` / `coordinator.drive|reset` / `adaptiveNavigationChrome`):

- **Profile** (`ProfileView.swift`) — `integrated`. `AmbientScope` @198,
  `.adaptiveNavigationChrome(collapseProgress:)` @203 driven by real
  `scrollOffset`, `coordinator.reset` @213, `coordinator.drive` @234.
  *Caveat:* drive is passed `image: nil` (avatar is `CachedAsyncImage`-by-URL;
  no decoded `UIImage` reachable) → fails closed to neutral. Static header
  retained instead of `AdaptiveProfileHeader` (bespoke avatar/edit/follow wiring).
- **MediaViewer** (`FullscreenMediaViewer.swift`) — `integrated`. `AmbientScope`
  @68, `AdaptiveAmbientBackground(bleedImage:)` @72, `coordinator.drive` with a
  real decoded image from `ImageCache` @128, `reset` @106, chrome floated in
  `AdaptiveGlassContainer` @238/@249. Pager still hand-wired (TODO to swap to
  `AdaptiveMediaViewer`).
- **Posts** (`PostDetailView.swift`) — **`partial`**. `AmbientScope` @163,
  post body wrapped in `AdaptiveContentCard(isReadingPlane: true)` @182 (C6),
  engagement bar in `AdaptiveGlassContainer` @278, `AdaptiveAmbientBackground()`
  @423, `drive`/`reset` @523/@528. *Why partial:* (a) `drive(with: nil)` — no
  decoded hero image reachable; (b) per-comment `AdaptiveContentCard` wrapping
  deferred to `ConversationThreadView` (separate file owns row chrome) — C6 is
  only partially applied to the comment thread.
- **Spaces** (`SpaceFeedView.swift`) — `integrated`. `AmbientScope` @28,
  `coordinator.drive` @76 / `reset` @64, `AdaptiveGlassContainer` @158/@243/@308,
  `AdaptiveContentCard(isReadingPlane: true)` @331. Reported per-file clean.
- **Settings** (`AdaptiveColorsSetting.swift` new + `AMENSettingsSystem.swift`) —
  `integrated`. New `AdaptiveColorsSetting` binds `@AppStorage(AmbientStorageKeys.mode)`
  and iterates `AdaptiveColorsMode.allCases` with the required footer copy. Wired
  into the **live** settings surface (`AccessibilitySettingsViewNew`, nav row +
  `.navigationDestination` @2316 → `AdaptiveColorsSettingsPage` hosting it in a
  `Form`), not the dead `LegacySettingsView`. Reported clean.

**Partial/skipped:** Posts is the only `partial`. Two intentional gaps: nil hero
image (drive fails closed) and comment-row C6 wrapping deferred to
`ConversationThreadView`. No surface skipped integration entirely.

---

## 3. Preview Gallery (C5 fixture)

`Previews/AmbientPreviewGallery.swift` exists with exactly **5 `#Preview`
fixtures**, each driving a programmatic gradient (no asset/network dependency):

1. `"1 · Dark profile"` — low-key portrait
2. `"2 · Warm media viewer"` — golden worship
3. `"3 · Light post"` — bright & airy
4. `"4 · Colorful room"` — saturated banner
5. `"5 · Neutral fallback (C5)"` — **`fixture: nil` ⇒ fail-closed to canonical
   neutral Liquid Glass.** The neutral-fallback case is present and explicitly
   labeled C5.

Confirmed present. ✅

---

## 4. Contract invariants C1–C8

Based on the frozen code (`AdaptiveColorEngine.swift`, `AmbientEnvironment.swift`,
components) and the surface edits:

| # | Invariant | Status | Evidence |
|---|---|---|---|
| C1 | Text contrast ≥ 4.5:1 (7:1 Increase Contrast) | **enforced-in-system** | `derive()` picks white/black by `contrastRatio`, then force-pushes bg to band edge if `< 4.5` (AdaptiveColorEngine L159–168). |
| C2 | `.off` renders byte-identical neutral | **enforced-in-system** | `coordinator.drive` early-returns `.neutral(for:)` when `mode == .off` (AmbientEnvironment L29); `mode.intensity == 0` zeroes every tint. |
| C3 | Reduce Transparency ⇒ opaque | **enforced-in-system** | `AdaptiveGlassContainer` fills `palette.background` (opaque) when `reduceTransparency` (L38). |
| C4 | Reduce Motion ⇒ instant apply | **enforced-in-system** | `apply()` skips `withAnimation` when `reduceMotion` (AmbientEnvironment L49); `AmbientScope.body` nils the animation too (L69). |
| C5 | Fail-closed to neutral | **enforced-in-system** | nil/undecodable image and extraction failure all return `.neutral(for:)` (Engine L40–44, L122, L131; coordinator L36). Preview fixture 5 exercises it. |
| C6 | Reading-plane tint cap | **enforced-in-system** *(surface-dependent application)* | `AdaptiveContentCard` hard-caps tint at `0.04 × intensity` when `isReadingPlane` (L24). **Surface-dependent:** correct only where reading text is actually wrapped — Posts comment thread still needs per-row wrapping in `ConversationThreadView`. |
| C7 | Extraction off main actor | **enforced-in-system** | `AdaptiveColorEngine` is an `actor`; `palette(for:)` awaited off-main; coordinator debounces 250ms (Engine L15; AmbientEnvironment L34–37). |
| C8 | No hex/raw color in feature code | **enforced-in-surface (no new hits)** + **needs-runtime-check** for pre-existing debt | 0 new hardcoded colors in ambient-touched regions; pre-existing tokens in PostDetailView/SpaceFeedView remain (not introduced here). |

Notes on classification:
- C1–C5, C7 are fully **enforced-in-system** (frozen code guarantees them
  regardless of surface) but each still **needs-runtime-check** in the Preview
  Gallery's 8-way trait matrix (light/dark × default/ReduceTransparency/
  IncreaseContrast/ReduceMotion) to confirm at render time — the gallery is the
  intended verification vehicle and was not rendered in this pass (see §5).
- C6 is **surface-dependent**: the cap exists in the component, but only protects
  text the surface actually routes through `AdaptiveContentCard`. Posts is the
  open item.

---

## 5. Build status — HONEST SIGNAL

**The END-TO-END BUILD was NOT run to green and is currently BLOCKED by an
unrelated issue.** An untracked duplicate file `AMENAPP/ActionThreads/
ActionIntelligenceService 2.swift` (plus sibling ` 2`-suffixed untracked
duplicates: `ActionIntelligenceDetectorTests 2.swift`, `actionIntelligence 2.ts`,
`actionIntelligenceRules.test 2.js`) introduces duplicate symbols and fails the
whole-app compile. This is **pre-existing and unrelated to the Ambient rollout.**

Available signal is therefore **per-file diagnostics** only:
- ProfileView.swift — clean (0 issues, agent-reported).
- FullscreenMediaViewer.swift — clean (0 issues after one index-churn retry).
- SpaceFeedView.swift — clean (0 issues after fixing an onChange deprecation).
- AdaptiveColorsSetting.swift — clean (0 issues).
- AMENSettingsSystem.swift — clean (0 issues).
- PostDetailView.swift — per-file diagnostics **could not be obtained**
  (Xcode index could not resolve the path; index churn). Structural correctness
  verified by manual read of `AmbientScope`/`AdaptiveContentCard`/
  `AdaptiveGlassContainer` open/close balance only.

**Conclusion:** No green end-to-end build exists for this verification. Treat the
result as "per-file clean where measurable, full build blocked by unrelated
duplicate files." Removing the ` 2`-suffixed untracked duplicates is the
prerequisite to a real green build + the Preview Gallery trait-matrix render.

---

## Top follow-ups

1. **Unblock the build:** delete the untracked ` 2`-suffixed duplicate files
   (starting with `ActionIntelligenceService 2.swift`), then run the full app
   build and render `AmbientPreviewGallery` across the 8-way trait matrix to
   convert C1–C7 from enforced-in-code to runtime-verified.
2. **Hero images for real palettes:** Profile, Posts (and the MediaViewer pager
   swap) currently `drive(with: nil)` → neutral. Hoist/look up the decoded hero
   `UIImage` (keyed on the image URL) so the engine extracts real content color.
3. **Finish C6 on Posts:** wrap each comment row in
   `AdaptiveContentCard(isReadingPlane: true)` inside `ConversationThreadView`,
   then re-resolve PostDetailView per-file diagnostics (currently unmeasured).
