# Find Church 2.0 — Total Control Wiring Certificate
Generated: 2026-06-11 | Branch: safety-hardening

## Legend
- **Gate expression**: exact Swift/TS guard that blocks this surface when the flag is OFF
- **Mounted**: visible entry point in navigation (✅ = wired, ⬜ = behind flag, pending human wire-up)
- **Screenshot**: populated by fleet capture sweep (all blank until human flip + screenshot)

---

## Surface 1 — 3-Phase Onboarding

**File:** `AMENAPP/FindChurchOS/FindChurch2OnboardingView.swift`  
**Gate:** `AMENFeatureFlags.shared.findChurch2OnboardingEnabled` (line 40: `if !flags.findChurch2OnboardingEnabled { EmptyView() }`)  
**Flag:** `findChurch2_onboarding` (default OFF)

| Control | File:Line | Behavior when tapped | Gate enforced? |
|---|---|---|---|
| Phase 0 — Intent pill (any) | `FindChurch2OnboardingView.swift:~80` | Toggle selection in `selectedIntents: Set<SeekerIntent>` | ✅ (whole view gated) |
| Phase 0 → Phase 1 "Next" | `BottomNavBar` in same file | `phase = 1` via `TabView` tag | ✅ |
| Phase 1 — Fit chip (any) | `~120` | Toggle in `selectedFitChips`, filters by `chip.relevantIntents` | ✅ |
| Phase 2 — Comfort chip (.showParking etc.) | `~160` | Toggle in `selectedComfortChips` | ✅ |
| Phase 2 — Comfort chip (.privateRecs) | `~165` | Toggle + gold tint visual treatment | ✅ |
| Phase 2 — Comfort chip (.noLocation) | `~165` | Toggle + lock icon treatment | ✅ |
| "Find Churches →" (phase 2 Next) | `~195` | Calls `onComplete(selectedIntents.first, Array(selectedFitChips), Array(selectedComfortChips))` | ✅ |
| "Skip" toolbar button | `~200` | Calls `onSkip()` | ✅ |
| Back arrow | `~185` | `phase -= 1` | ✅ |

**Mounted:** ⬜ Not yet surface-wired — caller site must be added to `FindChurchView.swift` or profile entry point once flag is ON and human verifies flow.

**Screenshot:** _pending_

---

## Surface 2 — Smart Church Card

**File:** `AMENAPP/FindChurchOS/FindChurch2SmartChurchCard.swift`  
**Gate:** Consumed by callers that pass `intent: SeekerProfile.SeekerIntent` — no standalone gate; cards are rendered only from gated parent lists.  
**Flag:** N/A (card variant is intent-driven; parent list gates via `findChurch2_designRefresh`)

| Control | File:Line | Behavior | Intent variant |
|---|---|---|---|
| Card — visitSunday layout | `~60` | Shows service time + AvailabilityPill + "What to expect" | `.visitSunday`, `.findChurch` |
| Card — watchOnline layout | `~80` | Leads with livestream pill if `livestreamActive`, else service time | `.watchOnline` |
| Card — bibleStudy layout | `~95` | Shows `GatheringCountBadge` from `gatheringIds.count` | `.bibleStudy` |
| Card — findCommunity layout | `~110` | Shows `MemberCountHint` + first 3 ministry tags | `.findCommunity` |
| Card — default layout | `~125` | Name + distance + denomination + match badge | all others |
| Match badge (if `match != nil`) | `FindChurch2MatchBadgeView.swift:~55` | Opens `FindChurch2WhyThisChurchSheet` as sheet | flag: `findChurch2_matchExplain` |
| `.findChurch2ProfileExpansion()` modifier | `FindChurch2ProfileExpansionView.swift:~270` | `.onTapGesture` → `showProfile = true` → sheet | wraps any card |

**Mounted:** ⬜ Replace `EnhancedChurchCard` usages in `FindChurchView.swift` after `findChurch2_designRefresh` is ON.

**Screenshot:** _pending_

---

## Surface 3 — MatchExplanation ("Why this church?") Sheet

**File:** `AMENAPP/FindChurchOS/FindChurch2MatchBadgeView.swift`  
**Gate:** `AMENFeatureFlags.shared.findChurch2MatchExplainEnabled` — line ~60: badge is non-tappable (no sheet) when flag is OFF.  
**Flag:** `findChurch2_matchExplain` (default OFF)

| Control | File:Line | Behavior |
|---|---|---|
| Match badge pill (tappable) | `~55` | Presents `FindChurch2WhyThisChurchSheet` as `.sheet` |
| Score circle (in sheet) | `~110` | Static display; color: gold ≥80, green 60–79, secondary else |
| Reason chip row (topReasons) | `~130` | ForEach `match.topReasons` → `ReasonChipRow` |
| Mismatch section | `~150` | ForEach `match.mismatches` — only rendered when `!mismatches.isEmpty` |
| Berean caption | `~160` | `"Based on [church]'s profile"` — never names user preference fields |
| "Find your fit" dismiss | `~170` | `dismiss()` |

**Mounted:** ⬜ Replace `FitScore.topReason` badge in `FindChurchView.swift` / `ChurchProfileView.swift`.

**Screenshot:** _pending_

---

## Surface 4 — Visit Planner

**File:** `AMENAPP/FindChurchOS/FindChurch2VisitPlannerView.swift`  
**Gate:** `AMENFeatureFlags.shared.findChurch2VisitPlannerEnabled` — view body returns `EmptyView()` when OFF.  
**Flag:** `findChurch2_visitPlanner` (default OFF)

| Control | File:Line | Behavior |
|---|---|---|
| Service time row (tap to select) | `~80` | `selectedTime = time` binding update |
| "Suggest times" affordance (when no times) | `~110` | Opens `SuggestTimesSheet` stub |
| WhatToExpectSection — all rows | `~145` | Nil fields render "Not provided" — never hidden |
| "I'm going this Sunday" CTA | `~200` | Async: `FindChurch2VisitPlannerService.shared.planVisit(to:serviceTime:comfortPrefs:)` → EventKit + UNNotification + Firestore |
| Loading state | `~210` | `ProgressView` during `isLoading = true` |
| Already-planned state | `~225` | "You're going! ✓" + "Need to cancel?" link → `updateStatus(.cancelled, for: planId)` |

**Mounted:** ⬜ Surface from `FindChurch2ChurchProfileSheet` section 5 (already wired — file:line ~130 in `FindChurch2ProfileExpansionView.swift`). Gate controls visibility.

**Screenshot:** _pending_

---

## Surface 5 — AI Concierge

**File:** `AMENAPP/FindChurchOS/FindChurch2ConciergeView.swift`  
**Gate:** `AMENFeatureFlags.shared.findChurch2ConciergeEnabled` — `EmptyView()` when OFF.  
**Flag:** `findChurch2_concierge` (default OFF)

| Control | File:Line | Behavior |
|---|---|---|
| Quick-question chip (any of 6) | `~65` | Populates `questionText`, triggers `submitQuestion()` |
| Custom question TextField | `~80` | `questionText` binding |
| "Ask Berean" / send button | `~95` | Calls `submitQuestion()` → `localAnswer(question:church:)` |
| Streaming reveal | `~115` | Character-by-character at 15 ms, `reduceMotion` → instant |
| Source indicator | `~130` | `"Based on [ChurchName]'s profile"` — static, no user data |

**Hard guardrail** (line ~140): `localAnswer(question:church:)` answers ONLY from `ChurchObject` fields. Unknown fields → `"That information isn't listed yet for this church. You can contact them at [website/phone] if available."` No external API call. No fabrication path.

**Mounted:** ⬜ Wired in `FindChurch2ChurchProfileSheet` section 6 (line ~140 of `FindChurch2ProfileExpansionView.swift`). Gate controls.

**Screenshot:** _pending_

---

## Surface 6 — Claim Flow

**File:** `AMENAPP/FindChurchOS/FindChurch2ClaimView.swift`  
**Gate:** `AMENFeatureFlags.shared.findChurch2ClaimPortalEnabled` (line ~20 in `FindChurch2ClaimButton`)  
**Flag:** `findChurch2_claimPortal` (default OFF)

| Control | File:Line | Behavior |
|---|---|---|
| "Is this your church?" button | `FindChurch2ClaimButton` | Visible only when `church.claimState == .unclaimed` AND flag ON |
| Step 1 "Yes, I manage this church" | `confirmationStep` | `advance()` → phase 1 |
| Step 2 — Domain email card | `verificationStep:~60` | Expands TextField for email; sets `selectedMethod = .domain` |
| Step 2 — EIN card | `~90` | Expands EIN TextField (format hint XX-XXXXXXX); `selectedMethod = .ein` |
| Step 2 — Manual docs card | `~115` | Sets `selectedMethod = .manual` |
| Step 2 "Continue" | `~145` | Non-empty validation; `advance()` |
| Step 3 "Submit Claim" | `reviewStep:~90` | Async `submitClaim()` → builds `ClaimRequest` → `claimRequests/{uuid}` Firestore write |
| Success state | `~110` | "Your claim is under review. We'll notify you within 3 business days." |

**Mounted:** ⬜ Wired in `FindChurch2ChurchProfileSheet` section 8 (line ~165 in `FindChurch2ProfileExpansionView.swift`). Gate controls.

**Screenshot:** _pending_

---

## Surface 7 — Admin Portal

**File:** `AMENAPP/FindChurchOS/FindChurch2AdminPortalView.swift`  
**Gate:** `claimState == .verified && claimedBy == currentUid && flags.findChurch2ClaimPortalEnabled`  
**Flag:** `findChurch2_claimPortal` (default OFF)

| Control | File:Line | Behavior |
|---|---|---|
| Service time row — day Picker | `profileSection:~55` | Updates `StructuredServiceTime.dayOfWeek` via local shadow + `commitChange()` |
| Service time row — hour/minute Pickers | `~65` | Updates `startHour`, `startMinute` |
| Add service time button | `~90` | Appends new `StructuredServiceTime(dayOfWeek:1, startHour:10, ...)` |
| Delete service time (swipe) | `~95` | `serviceTimes.remove(atOffsets:)` |
| Beliefs — baptismView Picker | `beliefsSection:~20` | `beliefs.baptismView` binding |
| Beliefs — worshipStyle Picker | `~40` | `beliefs.worshipStyle` binding |
| Beliefs — governance Picker | `~50` | `beliefs.governance` binding |
| Beliefs — womenInMinistry Picker | `~60` | `beliefs.womenInMinistry` binding |
| Suggestion approve | `suggestionsSection:~30` | `isApproved = true` local state (CF write deferred) |
| Suggestion reject | `~35` | `isApproved = false` local state |
| Premium upsell section | `premiumSection:~10` | `allowsHitTesting(false)` — non-tappable; "Coming Soon" badge |
| "Save profile" button | `~210` | Async `saveProfile()` → `churches/{id}` Firestore `setData(merge:true)` |

**Mounted:** ⬜ Accessible via "Manage this church" entry point on verified profiles (not yet surface-wired in `FindChurch2ChurchProfileSheet`).

**Screenshot:** _pending_

---

## Surface 8 — Map/List Hybrid Toggle

**File:** `AMENAPP/FindChurchOS/FindChurch2MapListView.swift`  
**Gate (toggle modes):** `mapHybridEnabled: Bool` parameter from `AMENFeatureFlags.shared.findChurch2MapHybridEnabled` — when OFF, only `.list` is shown.  
**Flag:** `findChurch2_mapHybrid` (default OFF)

| Control | File:Line | Behavior |
|---|---|---|
| "List" mode chip | `FindChurch2MapListToggle:~30` | `mode = .list` binding |
| "Map" mode chip | `~35` | `mode = .map` — only rendered when `mapHybridEnabled` |
| "Saved" mode chip | `~40` | `mode = .saved` — only rendered when `mapHybridEnabled` |
| "Visited" mode chip | `~45` | `mode = .visited` — only rendered when `mapHybridEnabled` |
| List — church row tap | `FindChurch2SmartListRow:~70` | Not yet wired to profile sheet — see mounting note |
| Map — pin tap | `FindChurch2MapRepresentable:~150` | Default callout (title + subtitle); full card deferred |

**Mounted:** ⬜ Embed `FindChurch2MapListView` + `FindChurch2CollapsingHeader` in `FindChurchView.swift` when `findChurch2_designRefresh` ON.

**Screenshot:** _pending_

---

## Surface 9 — Church Profile Sheet (card-to-profile expansion)

**File:** `AMENAPP/FindChurchOS/FindChurch2ProfileExpansionView.swift`  
**Gate:** `findChurch2ProfileExpansion(church:match:availability:comfortPrefs:)` modifier — callers decide when to apply. No standalone gate; sheet sections individually gated by their own flags.  
**Flag:** `findChurch2_designRefresh` governs whether the modifier replaces existing navigation.

| Control | File:Line | Behavior |
|---|---|---|
| Card tap (anywhere) | `FindChurch2CardToProfileTransition:~35` | `showProfile = true` → `.sheet` |
| Church name (matchedGeometry) | `FindChurch2ChurchProfileSheet:~50` | `.matchedGeometryEffect(id: cardId, in: namespace)` — disabled when `reduceMotion` |
| Save button | `SaveShareFooter:~10` | TODO: wire to ChurchProfileService saved state |
| Share button | `SaveShareFooter:~20` | `ShareLink` with church name + website |
| Visit Planner section | `~130` | Shown when `flags.findChurch2VisitPlannerEnabled` |
| Concierge section | `~140` | Shown when `flags.findChurch2ConciergeEnabled` |
| Beliefs section | `~150` | Shown when `claimState == .verified && beliefs != nil` |
| Claim button | `~165` | Shown when `claimState == .unclaimed`, flag `findChurch2_claimPortal` |

**Mounted:** ⬜ Apply `.findChurch2ProfileExpansion(...)` to church cards in `FindChurchView.swift` when `findChurch2_designRefresh` ON.

**Screenshot:** _pending_

---

## Tier-P Invariant Verification

| Invariant | Evidence |
|---|---|
| Firestore sync is opt-in only | `FindChurch2SeekerProfileService.swift:78` — `guard updatedProfile.privacySyncEnabled else { return }` — sync path is never reached unless user has explicitly set `privacySyncEnabled = true` |
| `.noLocation` chip is functional | `FindChurch2SeekerProfileService.swift:158-159` — `if chips.contains(.noLocation) { updated.dontShareLocation = true }` |
| `.privateRecs` chip is functional | `FindChurch2SeekerProfileService.swift:162-163` — `if chips.contains(.privateRecs) { updated.privateRecommendationsOnly = true }` |
| No Tier-P fields in CF logs | `grep -r "SeekerProfile\|dontShareLocation\|privateRecommendations\|inferredSignal\|fitChips\|comfortPref" Backend/functions/src/findChurch2/` → **zero matches** |
| MatchExplanation payload carries no user preference fields | `FindChurch2Contracts.swift` — `MatchExplanation` has `score`, `topReasons`, `mismatches`, `generatedBy`, `generatedAt` only; `ReasonChip` has `category`, `label`, `weight`, `isPositive` — no SeekerProfile fields, no user intent, no location data |
| `computeAvailabilityStatus` CF reads church data only | `ingestion.ts:402-475` — reads `churches/{churchId}.serviceTimes` only; no `seekerProfiles/` read |
| Auth + AppCheck on all findChurch2 CFs | `ingestion.ts:107-120,262-265,402-405` — `requireAuth()` + `requireAppCheck()` called at top of every handler body; emulator-exempt |
| Rate limit enforced | `ingestion.ts:122-125,262+` — `_systemLocks/ingestChurches` Firestore lock doc, 5000 ms minimum between calls |
