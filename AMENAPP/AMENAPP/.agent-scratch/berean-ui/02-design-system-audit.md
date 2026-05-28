# Berean Design System Audit
**Audited:** 2026-05-28  
**Agent:** Agent B — Design System Audit  
**Scope:** 7 new Liquid Glass v1 rebuild components + BereanChatView main screen  
**Design system reference:** `AMENAPP/BereanDesignSystem.swift`

---

## Token Usage Summary (file × category matrix)

| File | BereanColor.* | AmenTheme.Colors.* | Color.amen* (global) | Hardcoded colors | Springs | Material bgs | Accessibility guards |
|---|---|---|---|---|---|---|---|
| BereanDesignSystem.swift | ✅ defines all | ✅ delegates to | N/A | ⚠️ 1 (Color.white opacity fills) | ✅ spring-only | ✅ | N/A |
| BereanThreadCapsule.swift | ✅ consistent | ✅ | ✅ amenGold | ⚠️ 2 (white opacity borders) | ✅ spring-only | ✅ | ✅ both guards |
| BereanConversationSpine.swift | ✅ | ⚠️ partial | ✅ amenGold/amenBlack | ❌ 2 private RGB colors | ✅ spring-only | ✅ | ✅ both guards |
| BereanThinkingStrip.swift | ✅ | ✅ | ✅ amenGold | ❌ 2 private RGB colors | ⚠️ easeInOut pulse | ✅ | ✅ both guards |
| BereanMemoryChip.swift | ✅ | ✅ | ✅ amenGold | ❌ 1 private RGB color | ⚠️ easeInOut border | ✅ | ✅ both guards |
| BereanMessageTray.swift | ✅ | ✅ | — | ✅ none | ✅ spring-only | ✅ | ✅ reduceMotion |
| BereanCitationTile.swift | ✅ | — | ✅ amenGold | ✅ none | ✅ spring-only | ✅ | ✅ both guards |
| BereanComposerTray.swift | ✅ | — | ✅ amenGold/amenPurple/amenBlue | ✅ none | ✅ spring-only | ✅ | ✅ reduceMotion |
| BereanChatView.swift | ✅ heavy use | ✅ | ✅ amenGold | ❌ many raw RGB/opacity | ⚠️ easeInOut/easeOut in 4 places | ✅ | ⚠️ reduceMotion inconsistent |

---

## Drift Findings

| # | File | Line(s) | Issue | Severity | Recommendation |
|---|---|---|---|---|---|
| 1 | BereanConversationSpine.swift | 42–44 | **Hardcoded private RGB colors** — `Color(red: 0.42, green: 0.28, blue: 1.00)` and `Color(red: 0.40, green: 0.70, blue: 0.95)` defined in `BereanConversationSpineColors` enum instead of using `Color.amenPurple` / `Color.amenBlue` global tokens | HIGH | Replace with `Color.amenPurple` and `Color.amenBlue` once those tokens are promoted to the global `Color` extension. The file comment says "audit item DS-9" — assign a ticket and track. |
| 2 | BereanThinkingStrip.swift | 24–26 | **Hardcoded private RGB colors** — `Color(red: 0.42, green: 0.28, blue: 1.00)` as `._bereanPurple` and `Color(red: 0.20, green: 0.48, blue: 0.96)` as `._bereanBlue`. Same values as DS-9 item but duplicated in a second file. | HIGH | Same fix as finding #1. The duplication across three files (Spine, ThinkingStrip, MemoryChip) confirms `amenPurple`/`amenBlue` must be promoted to the global `Color` extension to eliminate drift. |
| 3 | BereanMemoryChip.swift | 23–24 | **Hardcoded private RGB color** — `Color(red: 0.42, green: 0.28, blue: 1.00)` as `._memoryPurple`. Third occurrence of the same amenPurple value, confirming systemic gap. | HIGH | Same fix as findings #1 and #2. |
| 4 | BereanThinkingStrip.swift | 168–172 | **Non-spring interactive animation** — `.easeInOut(duration: 0.72).repeatForever(autoreverses: true)` applied to the pulse dot `scaleEffect`. This is an interactive-adjacent element (live during user sessions), not a pre-approved shimmer sweep. | MEDIUM | Replace with a repeating spring or use `Animation.spring(response: 0.72, dampingFraction: 0.55).repeatForever(autoreverses: true)` which yields the same slow-pulse feel using only the approved spring curve. |
| 5 | BereanThinkingStrip.swift | 226–231 | **Non-spring interactive animation** — `startPulse()` calls `withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true))`. Duplicate of the declarative easeInOut on the same element; both animate `pulseScale`. | MEDIUM | Consolidate to the `.onAppear`/`.onChange` declarative path only and use a spring. Remove the imperative `withAnimation` call. |
| 6 | BereanMemoryChip.swift | 197–205 | **Non-spring interactive animation** — `startBorderPulse()` calls `withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true))` for the border opacity pulse. This is applied to a visible chip that responds to active memory state. | MEDIUM | Replace with `.spring(response: 1.1, dampingFraction: 0.50).repeatForever(autoreverses: true)` to stay within the approved animation system. |
| 7 | BereanChatView.swift | 1481–1482 | **Non-spring scroll-reactive animations** — `Motion.adaptive(.easeOut(duration: 0.18))` and `Motion.adaptive(.easeOut(duration: 0.15))` used for header blur/compression reactions. `.easeOut` is not approved for interactive animations per the design spec. | MEDIUM | `easeOut` is borderline here since these are pure scroll-position responses, not tap/drag interactions. If `Motion.adaptive` wraps a spring when reduceMotion is off, the violation is in `Motion.adaptive`'s implementation. Verify that `Motion.adaptive(.easeOut(...))` never passes the easeOut through unmodified when `reduceMotion == false`. If it does, replace with `Motion.adaptive(.spring(response: 0.20, dampingFraction: 0.90))`. |
| 8 | BereanChatView.swift | 1275 | **Non-spring interactive animation** — `.easeInOut(duration: 0.25)` on `showSavedToNotesToast`. This drives a visible toast overlay in direct response to a user context-menu action. | MEDIUM | Replace with `.spring(response: 0.28, dampingFraction: 0.88)` (the approved fastSettle preset). |
| 9 | BereanChatView.swift | 1696 | **Non-spring list animation** — `.easeOut(duration: 0.2)` animates `vm.isThinking` on the `LazyVStack`. This affects the appearance/disappearance of the thinking indicator, which is user-triggered. | LOW | Replace with `.spring(response: 0.28, dampingFraction: 0.88)` for consistency. |
| 10 | BereanChatView.swift | 1729 | **Non-spring scroll reaction** — `.easeOut(duration: 0.3)` drives `showHero = false` when user scrolls past 50pt. Scroll-linked state changes should use springs. | LOW | Replace with `Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.88))`. |
| 11 | BereanChatView.swift | 1746 | **Non-spring auto-scroll animation** — `.easeOut(duration: 0.30)` on `proxy.scrollTo("bottom")`. Programmatic scroll jumps are borderline; however this fires when new messages arrive. | LOW | Replace with `.spring(response: 0.42, dampingFraction: 0.85)` to keep the scroll feel consistent with other spring-driven list transitions. |
| 12 | BereanChatView.swift | 924–940 | **Hardcoded RGB colors in workspace cards** — `Color(red: 0.79, green: 0.66, blue: 0.30)`, `Color(red: 0.53, green: 0.61, blue: 0.84)`, `Color(red: 0.51, green: 0.71, blue: 0.62)` used as `accent` values in `workspaceCards`. These are static data literals so they never adapt to dark mode. | HIGH | Map to `Color.amenGold`, `Color.amenBlue`, and a new `BereanColor.accentSage` token respectively. At minimum declare them as named constants in BereanDesignSystem.swift. |
| 13 | BereanChatView.swift | 2844–2845 | **Hardcoded hex-equivalent RGB** — `Color(red: 0.788, green: 0.659, blue: 0.298)` in `paywallBanner` for the lock icon. This is amenGold expressed as literal RGB without using the token. | HIGH | Replace with `Color.amenGold`. |
| 14 | BereanChatView.swift | 2932–2933 | **Hardcoded RGB color** — `Color(red: 0.55, green: 0.40, blue: 0.80)` used three times in `modeFallbackBanner` for the icon, fill, and border. There is no registered token for this purple shade. | HIGH | Either map to `Color.amenPurple` (once promoted) or add `BereanColor.accentPurpleMuted` to the design system and use it. |
| 15 | BereanChatView.swift | 3110–3118 | **Hardcoded RGB colors in section cards** — `Color(red: 0.30, green: 0.50, blue: 0.90)`, `Color(red: 0.35, green: 0.30, blue: 0.90)`, `Color(red: 0.55, green: 0.30, blue: 0.85)` in `sectionCard(title:icon:content:accentColor:)`. | MEDIUM | Map to design tokens or, if these are genuinely unique semantic colors, register them in BereanDesignSystem.swift as `BereanColor.studyMeaning`, `BereanColor.studyContext`, `BereanColor.studyApplication`. |
| 16 | BereanChatView.swift | 3164 | **Hardcoded RGB color** — `Color(red: 0.30, green: 0.65, blue: 0.55)` for the direct-answer card checkmark and border. No matching token. | MEDIUM | Register as `BereanColor.accentTeal` or map to an existing semantic token. |
| 17 | BereanChatView.swift | 3352–3353 | **Hardcoded RGB color** — `Color(red: 0.788, green: 0.659, blue: 0.298)` in `BereanVersePreviewSheet` for the book icon. Same raw amenGold value as finding #13. | HIGH | Replace with `Color.amenGold`. |
| 18 | BereanChatView.swift | 2336–2337 | **Hardcoded RGB warm tint in gradient** — `Color(red: 1.0, green: 0.96, blue: 0.93)` used as a warm glass tint in `modeChip` and `quickActionPill` background gradients. Not in any token. | LOW | Extract as `BereanColor.glassWarmTint` in BereanDesignSystem.swift, or fold into the existing `AmenTheme.Colors.glassFill` if the warm tone is intentional on all platforms. |
| 19 | BereanChatView.swift | 2597–2598 | **Hardcoded semantic color (Black opacity)** — `Color.black.opacity(0.45)` and `Color.black.opacity(0.76)` used for unselected/selected chip text in `bereanContextMemoryRail`. These will not adapt to dark mode. | HIGH | Replace with `BereanColor.textSecondary` and `BereanColor.textPrimary` respectively. |
| 20 | BereanConversationSpine.swift | 182 | **Tap target below 44×44pt** — `SpineDot` uses `.frame(width: 22, height: 22)` as the hit area. The comment acknowledges this should be ≥ 44×44 but the actual frame is 22×22. | HIGH | Change `.frame(width: 22, height: 22)` to `.frame(width: 44, height: 44)`. The dot visual stays at `baseDiameter` because the visual circle is sized separately from the frame. |
| 21 | BereanComposerTray.swift | 496–498 | **Tap target at 44×36pt** — `capabilitiesToggleButton` uses `.frame(width: 44, height: 36)`. Width meets the minimum but height is 36pt, 8pt short of the 44pt minimum. | MEDIUM | Change to `.frame(minWidth: 44, minHeight: 44)` or set explicit `.frame(width: 44, height: 44)`. |
| 22 | BereanComposerTray.swift | 531–532 | **Tap target at 36×36pt** — `modePickerToggleButton` uses `.frame(width: 36, height: 36)`. Both dimensions are 8pt short of the 44pt minimum. | MEDIUM | Change to `.frame(width: 44, height: 44)` with `.contentShape(Rectangle())`. |
| 23 | BereanChatView.swift | 1261–1263 | **Missing accessibilityReduceTransparency guard on "Saved to Church Notes" toast** — The toast renders `.background(Capsule().fill(Color.black.opacity(0.82)))`. When `reduceTransparency` is on, `.ultraThinMaterial` should not be used here (it is not), but `opacity(0.82)` on pure black still renders semi-transparent, which may fail the accessibility guideline for reduce-transparency surfaces. | LOW | When `reduceTransparency` is true, use `Color.black` (fully opaque) instead of `Color.black.opacity(0.82)`. |
| 24 | BereanChatView.swift | 1481–1482 | **Missing accessibilityReduceMotion guard on header compression animation** — `.animation(Motion.adaptive(.easeOut(...)), value: compressionProgress)` drives continuous header reflow during scrolling with no `reduceMotion` check. If `Motion.adaptive` does not internally gate this, the header will animate even when the user has requested no motion. | MEDIUM | Wrap in `reduceMotion ? .none : Motion.adaptive(...)` or confirm `Motion.adaptive` implements the guard. |
| 25 | BereanChatView.swift | 1608 | **Non-spring entrance animation** — `Motion.adaptive(.spring(...)).delay(0.05)` — the spring itself is compliant, but verify that `Motion.adaptive` does not change the curve type on the adaptive path. If it passes through the spring as-is on the non-reduced path, this is fine. Flag for code review. | INFO | No change needed if `Motion.adaptive` wraps a guard; add a comment confirming the behavior. |
| 26 | BereanDesignSystem.swift | 252–254 | **Hardcoded `Color(white: 0.85)`** in `BereanInputComposer` for the send button disabled state — `Color(white: 0.85)` is a raw brightness value that will not adapt to dark mode. | MEDIUM | Replace with `AmenTheme.Colors.surfaceChip` or `Color(uiColor: .quaternarySystemFill)` which adapts automatically. |
| 27 | BereanChatView.swift | 2026 | **Magic-number font size** — `.font(.system(size: 56, weight: .semibold, design: .rounded))` in `heroSection` does not use BereanType tokens. BereanType maxes out at `displayTitle()` (32pt). | LOW | Either add `BereanType.heroDisplay()` at 56pt to the design system, or document this as an approved one-off hero size in BereanDesignSystem.swift. |
| 28 | BereanChatView.swift | 2029–2030 | **Magic-number font sizes** in hero subtitle — `.font(.system(size: 18, weight: .regular))` — no token for 18pt. | LOW | Add `BereanType.bodyLarge()` at 18pt to BereanDesignSystem.swift, or remap to `BereanType.headline()` (17pt) which is the nearest token. |
| 29 | BereanChatView.swift | 2209–2211 | **Magic-number font sizes** in adaptive prompt surface — `size: 28` and `size: 14` have no BereanType tokens. 14pt is absent from the token sheet (13pt caption exists, 15pt subheadline exists). | LOW | Add `BereanType.sectionSubtitle()` at 28pt and `BereanType.caption2()` at 14pt, or remap to nearest existing tokens. |

---

## Springs Inventory

All springs found across the 8 audited files are listed below. "Compliant" = uses only `.spring(response:dampingFraction:)` form. "Exempt" = `.linear` on shimmer sweeps (approved). "Non-compliant" = interactive animation using a forbidden curve.

| File | Location | Curve | Status |
|---|---|---|---|
| BereanThreadCapsule | `expandSpring`, `fastSettle` | `.spring(0.42, 0.82)` / `.spring(0.28, 0.88)` | ✅ Compliant |
| BereanThreadCapsule | `.linear(duration: 0)` on reduceMotion path | zero-duration linear | ✅ Compliant (instant, reduceMotion guard) |
| BereanConversationSpine | `contentAppear`, `fastSettle` | `.spring(0.36, 0.76)` / `.spring(0.28, 0.88)` | ✅ Compliant |
| BereanThinkingStrip | `fastSpring`, `capsuleSpring` | `.spring(0.28, 0.88)` / `.spring(0.42, 0.82)` | ✅ Compliant |
| BereanThinkingStrip | `pulseDot` `.easeInOut(duration: 0.72).repeatForever` | `.easeInOut` | ❌ Non-compliant (finding #4) |
| BereanThinkingStrip | `startPulse()` withAnimation | `.easeInOut(duration: 0.72).repeatForever` | ❌ Non-compliant (finding #5) |
| BereanThinkingStrip | `startShimmer()` | `.linear(duration: 1.8).repeatForever` | ✅ Exempt (shimmer sweep) |
| BereanMemoryChip | `fastSpring`, `capsuleSpring` | `.spring(0.28, 0.88)` / `.spring(0.42, 0.82)` | ✅ Compliant |
| BereanMemoryChip | `startShimmer()` | `.linear(duration: 1.4).repeatForever` | ✅ Exempt (shimmer sweep) |
| BereanMemoryChip | `startBorderPulse()` | `.easeInOut(duration: 1.1).repeatForever` | ❌ Non-compliant (finding #6) |
| BereanMessageTray | `floatIn` | `.spring(0.32, 0.80)` | ✅ Compliant |
| BereanMessageTray | copy dismiss | `.spring(0.30, 0.78)` / `.spring(0.28, 0.82)` | ✅ Compliant |
| BereanCitationTile | `tileSpring` | `.spring(0.32, 0.80)` | ✅ Compliant |
| BereanCitationTile | `_CitationChipButtonStyle` | `Motion.liquidSpring` | ✅ Compliant (defers to Motion token) |
| BereanComposerTray | All `.spring(response:dampingFraction:)` calls | various compliant params | ✅ Compliant |
| BereanComposerTray | `startGoldPulse()` | `.spring(response: 1.1, dampingFraction: 0.55)` | ✅ Compliant (slow-oscillating spring, acceptable) |
| BereanChatView | `vm.isThinking` change | `.spring(0.42, 0.82)` | ✅ Compliant |
| BereanChatView | hero entrance | `Motion.adaptive(.spring(0.52, 0.82))` | ✅ Compliant |
| BereanChatView | header compression | `Motion.adaptive(.easeOut(0.18))` | ❌ Non-compliant (finding #7) |
| BereanChatView | toast show/hide | `.easeInOut(duration: 0.25)` | ❌ Non-compliant (finding #8) |
| BereanChatView | `vm.isThinking` LazyVStack | `.easeOut(duration: 0.2)` | ❌ Non-compliant (finding #9) |
| BereanChatView | hero hide on scroll | `.easeOut(duration: 0.3)` | ❌ Non-compliant (finding #10) |
| BereanChatView | auto-scroll to bottom | `.easeOut(duration: 0.30)` | ❌ Non-compliant (finding #11) |
| BereanChatView | modeFallbackBanner dismiss | `.spring(0.25, 0.8)` | ✅ Compliant |

---

## Approved Exceptions

The following items were reviewed and are **not** findings — they are either spec-compliant or legitimately exempt:

1. **Shimmer sweeps using `.linear`** — All three shimmer implementations (ThinkingStrip, MemoryChip shimmer layer, BereanComposerTray gold pulse) use `.linear` exclusively for the sweeping gradient phase offset. The spec explicitly approves `.linear` for shimmer sweeps. No action required.

2. **`.linear(duration: 0)` on reduceMotion paths** — All uses of zero-duration linear are correctly gated behind `reduceMotion == true`. These produce instant state changes as expected and are not violations.

3. **`Color.white.opacity(...)` border/overlay fills** — Translucent white overlay strokes and glass highlights throughout are cosmetic layering on top of `.ultraThinMaterial`. This is the standard glass-on-material technique and is not a hardcoded color violation (white opacity is a standard glass rendering element, not a semantic or brand color replacement).

4. **`Color.black` fill on user message bubble** (`BereanChatView.swift` line 3092) — The black user-bubble background is an intentional AMEN Studio choice (user = black, AI = glass), not a missing token. This is a documented design decision.

5. **`Color.accentColor` in intelligence follow-up chips** (`BereanChatView.swift` line 2704) — `Color.accentColor` resolves to the app's UIKit accent color (configured in Assets), which adapts automatically. This is acceptable for a secondary semantic context.

6. **`BereanConversationSpineColors` private enum comment** — The spine file correctly documents that `amenPurple`/`amenBlue` are provisional and references "audit item DS-9". The design intent is sound; the gap is the missing global tokens, not a careless hardcode.

---

## Summary Score (0–10 compliance per file)

| File | Color Tokens | Animation Curves | Material Bgs | Tap Targets | A11y Guards | **Total / 50** | **Score / 10** |
|---|---|---|---|---|---|---|---|
| BereanDesignSystem.swift | 9/10 | 10/10 | 10/10 | 10/10 | 10/10 | 49/50 | **9.8** |
| BereanThreadCapsule.swift | 9/10 | 10/10 | 10/10 | 10/10 | 10/10 | 49/50 | **9.8** |
| BereanConversationSpine.swift | 5/10 | 10/10 | 10/10 | 4/10 | 10/10 | 39/50 | **7.8** |
| BereanThinkingStrip.swift | 5/10 | 4/10 | 10/10 | 10/10 | 10/10 | 39/50 | **7.8** |
| BereanMemoryChip.swift | 5/10 | 7/10 | 10/10 | 10/10 | 10/10 | 42/50 | **8.4** |
| BereanMessageTray.swift | 10/10 | 10/10 | 10/10 | 10/10 | 9/10 | 49/50 | **9.8** |
| BereanCitationTile.swift | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 50/50 | **10.0** |
| BereanComposerTray.swift | 10/10 | 10/10 | 10/10 | 7/10 | 10/10 | 47/50 | **9.4** |
| BereanChatView.swift | 4/10 | 5/10 | 10/10 | 9/10 | 7/10 | 35/50 | **7.0** |

### Score Rationale

**BereanCitationTile (10.0):** Zero drift. Full token use, spring-only animations, correct material backgrounds, 44pt targets met, both accessibility guards present.

**BereanMessageTray + BereanThreadCapsule (9.8):** Near-perfect. Minor marks deducted for `reduceTransparency` not guarding the error-dismiss tap target (28×28pt frame in `BereanMessageTray` line 2902) and the white-opacity border opacities which are borderline cosmetic.

**BereanComposerTray (9.4):** Strong token usage and spring compliance. Loses points for two tap targets below 44pt minimum (findings #21, #22).

**BereanMemoryChip (8.4):** Good structure, accessibility well-guarded. One private RGB token and one `.easeInOut` border pulse prevent a higher score.

**BereanConversationSpine + BereanThinkingStrip (7.8 each):** The systemic `amenPurple`/`amenBlue` token gap is the primary driver of lower scores. For the spine, the 22×22 tap target is a direct WCAG violation.

**BereanChatView (7.0):** The lowest-scoring file due to widespread hardcoded RGB values across workspace card accents, banner colors, section cards, and the paywall banner. Five non-spring animation uses also accumulate. Core glass architecture and material backgrounds are excellent, but color discipline is the biggest gap to address before release.

---

## Priority Action List

**P0 — Blocker (must fix before TestFlight):**
- Finding #20: `SpineDot` 22×22 tap target — VoiceOver/switch control users cannot reliably tap spine dots.

**P1 — High (fix before App Store submission):**
- Findings #1, #2, #3: Promote `amenPurple` and `amenBlue` to global `Color` extension in `AmenTheme` or as `Color.amenPurple` / `Color.amenBlue`, then replace all three private copies.
- Findings #12, #13, #17: Replace `Color(red: 0.788, green: 0.659, blue: 0.298)` with `Color.amenGold` in all three locations.
- Finding #14: Replace the hardcoded `modeFallbackBanner` purple with a token.
- Finding #19: Replace `Color.black.opacity(...)` in `bereanContextMemoryRail` with `BereanColor.textPrimary` / `BereanColor.textSecondary`.

**P2 — Medium (fix before public launch):**
- Findings #4, #5, #6: Replace `.easeInOut` repeat-forever animations with spring equivalents.
- Findings #7, #8: Replace `.easeOut` / `.easeInOut` on interactive transitions in BereanChatView.
- Findings #21, #22: Fix `BereanComposerTray` button tap targets to 44×44pt.
- Finding #26: Replace `Color(white: 0.85)` in send button with an adaptive token.

**P3 — Low (design polish backlog):**
- Findings #9, #10, #11: Remaining easeOut scroll animations in BereanChatView.
- Findings #15, #16, #18: Section card accent colors and warm glass tint — register as tokens.
- Findings #27, #28, #29: Undocumented hero font sizes — add to BereanType or annotate as approved exceptions.
