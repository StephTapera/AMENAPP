# AMEN Liquid Glass — Remediation Plan

**Date:** May 27, 2026  
**Input docs:** liquid-glass-standard.md, button-audit.md, error-surface-audit.md, error-coverage-gaps.md  
**Scope:** Ordered fix list to achieve full Liquid Glass conformance across buttons, alerts, and error coverage  

---

## Pre-Fix Decision: Canonical Components

### Buttons — ADOPT existing, do NOT create new
Three button systems already exist and conform to standard. Problem is adoption, not absence:

| System | File | Role |
|--------|------|------|
| **PRIMARY** | `AMENAPP/AmenGlassButtonSystem.swift` | Role-aware `.amenGlass()` style modifier (primary/neutral/dismiss), handles all shapes |
| **SECONDARY** | `AMENAPP/AmenLiquidGlassButtons.swift` | `AmenLiquidGlassCapsuleButton`, icon buttons, control groups |
| **ATOMIC** | `AMENAPP/LiquidGlass/LiquidGlassButtons.swift` | `GlassActionPill`, low-level shapes |

**Rule:** All new/migrated buttons must use `.amenGlass()` or `AmenLiquidGlassCapsuleButton`. Nothing else.

### Alerts — CREATE `LiquidGlassAlert.swift`
**No glass alert component exists.** This is Fix 0 and is a blocker for all subsequent fixes.  
**Location:** `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift`  
**Spec:**
- Presentation: `ZStack` overlay with black 0.35 dim, centered card
- Card: `.ultraThinMaterial` background, `RoundedRectangle(cornerRadius: 28, style: .continuous)`
- Shadow: radius 24, y 10, black 0.15
- Spring in: `.spring(response: 0.34, dampingFraction: 0.84)` with scale 0.88→1.0
- Title: `.title3`, semibold
- Body: `.body`, regular, secondary
- Buttons: Two capsule buttons — primary uses `amenGold`/`amenPurple` fill, secondary uses `.ultraThinMaterial`
- Accessibility: Reduce motion → easeOut(0.16s); Reduce transparency → opaque fills
- Usage: via `View.amenAlert(isPresented:config:)` modifier

---

## Fix Order (by severity + user-trust impact)

### Fix 0 — Create `LiquidGlassAlert` component *(blocker)*
**File to create:** `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift`  
**Why first:** All 265 native `.alert()` conversions depend on this.  
**Build after:** Yes.

---

### Fix 1 — Auth & Verification flows *(CRITICAL — 0% conformance)*
**Affected files:**
- `AmenVerificationFlowCoordinator.swift` — Verify/Success buttons (`Color.blue`/`Color.green` fills → `.amenGlass(.primary)`)
- `DeleteAccountView.swift` — Confirm deletion button (`Color.black` fill → `.amenGlass(.destructive)`); convert `.alert("Delete Account")` → `LiquidGlassAlert`
- `SignInView.swift` — Convert `.alert("Error")` → `LiquidGlassAlert`
- `TwoFactorAuthView.swift` — Convert `.alert("Invalid Code")` → `LiquidGlassAlert`
- `PhoneVerificationService.swift:113,117` — Add `@Published var errorMessage` + surface via `LiquidGlassAlert` in call-site views

**Tokens to use:** corner radius 14pt for small buttons, capsule for primary CTAs, `amenGold` for primary confirm.  
**Build after:** Yes.

---

### Fix 2 — Account Deletion error coverage *(CRITICAL — data loss risk)*
**Affected files:**
- `AccountDeletionService.swift:45,104,111` — Wrap all three steps (`cancelStripeSubscriptions`, Firestore delete, Auth delete) in proper try/catch; publish distinct `DeletionStep` error states
- `DeleteAccountView.swift` — Observe deletion step errors and show `LiquidGlassAlert` with context-specific messages:
  - "Subscription cancellation may still be pending. Check your account settings."
  - "Account deletion partially complete — please try again or contact support."
  - "Your account couldn't be fully deleted. Please sign in and try again."

**Build after:** Yes.

---

### Fix 3 — Payment & Access Passes *(CRITICAL — silent payment failure)*
**Affected files:**
- `AmenCovenantCheckoutService.swift:68-81` — `.failed(error)` state already exists but no view observes it; wire `checkoutState` to `LiquidGlassAlert` in the checkout view
- `AmenAccessPassService.swift:59,127,131,155` — Add `@Published var error: Error?` to the service; wrap all four callables in do/catch; surface via `LiquidGlassAlert` in `AmenAccessPassAdminConsoleView` and `AmenAccessPassCreateSheet`

**Build after:** Yes.

---

### Fix 4 — Covenant & Moderation *(CRITICAL — trust & safety audit trail)*
**Affected files:**
- `AmenCovenantModerationQueueView.swift:65-69` — Replace plain `Button()` with `.role(.destructive)` → `AmenLiquidGlassCapsuleButton(.destructive)`
- `AmenReportContentSheet.swift:90` — Replace `Color.red` solid button → `.amenGlass(.destructive)`
- `CovenantService.swift:215-222` — Add `@Published var moderationError: Error?`; catch `updateData` failure; surface "Your moderation action couldn't be saved. Try again." via `LiquidGlassAlert`
- `AmenCovenantModerationQueueView.swift` `.alert("Error")` → `LiquidGlassAlert`

**Build after:** Yes.

---

### Fix 5 — In-App Browser *(P0 visible — 0% conformance)*
**Affected files:**
- `InAppBrowserView.swift:72-80` — Close button: wrap in 36pt circle with `.ultraThinMaterial` + `Glass.regular.interactive()` overlay (iOS 26), scale-press style
- `InAppBrowserView.swift:84-93` — Back/Forward: `AmenLiquidGlassIconButton`
- `InAppBrowserView.swift:159-165` — Overflow: `AmenLiquidGlassIconButton`
- `InAppBrowserView.swift:189-208` — Error overlay Retry/Open buttons: replace `RoundedRectangle(10).fill(Color.black)` → `AmenLiquidGlassCapsuleButton(.primary)` and `AmenLiquidGlassCapsuleButton(.neutral)`

**Build after:** Yes.

---

### Fix 6 — Content Creation errors *(HIGH — high frequency)*
**Affected files (CreatePostView.swift):**
- `:1506` Publish error `.alert` → `LiquidGlassAlert` with retry button
- `:1420` Safety check `.alert` → `LiquidGlassAlert` (amenPurple tone, educational)
- `:1527` AI-detected content `.alert` → `LiquidGlassAlert`
- `:1633` Draft recovery `.alert` → `LiquidGlassAlert` (two capsule buttons: Recover / Discard)
- `:7464` Paywall `.alert` → `LiquidGlassAlert` with upgrade CTA (amenGold)
- `QuoteComposerView.swift:69` `.alert` → `LiquidGlassAlert`
- `EditPostSheet.swift` `.alert` → `LiquidGlassAlert`

**Build after:** Yes.

---

### Fix 7 — Messaging & Chat errors *(HIGH)*
**Affected files:**
- `GroupChatCreationView.swift:134` → `LiquidGlassAlert`
- `MessagesViewFix.swift:77` `.confirmationDialog` → `LiquidGlassAlert` (two capsule: Delete / Cancel, amenPurple or destructive red)
- `ChatIdentityCard.swift:425` `.confirmationDialog` → `LiquidGlassAlert`
- `BereanRealtimeWebSocketTransport.swift:40,84-94` + `BereanRealtimeSessionManager.swift:34,86` — Add `@Published var connectionError` states; surface inline banner (not modal) using existing `ErrorBannerView` upgraded to glass card

**Build after:** Yes.

---

### Fix 8 — Prayer & Devotional *(MEDIUM)*
**Affected files:**
- `PrayerView.swift` delete `.alert` → `LiquidGlassAlert` (destructive, amenPurple)
- `GuidedSelahSessionView.swift` session error `.alert` → `LiquidGlassAlert` (soft tone, no harsh red)
- `PrayerSuggestedRailView.swift:44` why-shown info `.alert` → educational `LiquidGlassAlert` (single dismiss button)

**Build after:** Yes.

---

### Fix 9 — Discovery & Social *(MEDIUM)*
**Affected files:**
- `SearchExpandBar.swift:151` — Close button: add `.ultraThinMaterial` circle background
- `DiscoverSearchComponents.swift` filter pills → `GlassActionPill` from `LiquidGlassButtons.swift`
- `AmenDiscoverPillsRow.swift` discovery pills → same
- `SuggestedAccountPeekSheet.swift:50` unfollow `.confirmationDialog` → `LiquidGlassAlert`
- `FollowingListView.swift` block `.confirmationDialog` → `LiquidGlassAlert`
- `FollowButton` — audit state-toggle to ensure glass on both follow and unfollow states (no solid black fill in following state)

**Build after:** Yes.

---

### Fix 10 — Berean AI error surfaces *(HIGH — silent AI failures)*
**Affected files:**
- `BereanAnswerEngine.swift:181,196` — Add `@Published var answerError: String?`; surface via inline `LiquidGlassAlert` card within the chat view (not modal overlay — inline inline "Couldn't generate answer" card with retry)
- `AmenMediaReflectionSheet.swift:95` — Surface save error via `LiquidGlassAlert` with "Your reflection is still in the text box" reassurance message
- `TestimonyViralSheet.swift:63-67` — Upgrade from generic `errorMessage` Text to `LiquidGlassAlert`

**Build after:** Yes.

---

## Summary Stats

| Metric | Count |
|--------|-------|
| Buttons to migrate | ~165 (95 Deviating + 70 Missing-glass) |
| Alerts to convert | 265 native `.alert()` + 68 `.confirmationDialog()` |
| Critical coverage gaps to close | 5 |
| High coverage gaps to close | 12 |
| New component to create | 1 (`LiquidGlassAlert.swift`) |
| Files touched across all fixes | ~85 |

## Conformance Target

After all 10 fix groups: **95%+ glass conformance** on buttons, **100% glass conformance** on user-facing alerts, all 5 CRITICAL coverage gaps closed.
