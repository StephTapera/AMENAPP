# Find Church 2.0 — SHIPLOG
Generated: 2026-06-11  Branch: safety-hardening

## Feature Status Table

| # | Feature | Status | Flag | File(s) | Commit |
|---|---|---|---|---|---|
| 1 | National Church Search Graph (ingestion CF) | BUILT | `findChurch2_availability` | `Backend/functions/src/findChurch2/ingestion.ts` | 144be72b |
| 2 | Pinecone/Algolia index extension (gatherings + kind facet) | BUILT | `findChurch2_gatherings` | `FindChurch2SearchExtension.swift` | pre-existing |
| 3 | Doctrine Transparency Layer (BeliefSchema) | BUILT | `findChurch2_trustSignals` | `FindChurch2Contracts.swift`, `FindChurch2TrustSignalsView.swift` | 4352e88f |
| 4 | AvailabilityStatus computation (client + CF) | BUILT | `findChurch2_availability` | `FindChurch2AvailabilityService.swift`, `ingestion.ts:computeAvailabilityStatus` | pre-existing |
| 5 | Sermon/livestream auto-detection | BUILT | `findChurch2_availability` | `Backend/functions/src/findChurch2/mediaDetection.ts` | 144be72b |
| 6 | 3-phase Liquid Glass onboarding | BUILT | `findChurch2_onboarding` | `FindChurch2OnboardingView.swift` | 04a89d01 |
| 7 | SeekerProfile (Tier-P, on-device-first) | BUILT | `findChurch2_onboarding` | `FindChurch2SeekerProfileService.swift` | 04a89d01 |
| 8 | MatchExplanation (replaces bare %) | BUILT | `findChurch2_matchExplain` | `FindChurch2MatchBadgeView.swift` | 04a89d01 |
| 9 | Find My People mode (life-stage lens) | BUILT | `findChurch2_gatherings` | `FindChurch2FindMyPeopleView.swift` | 04a89d01 |
| 10 | Smart Church Cards (intent-adaptive layout) | BUILT | `findChurch2_matchExplain` | `FindChurch2SmartChurchCard.swift` | 04a89d01 |
| 11 | Discovery agent (behavioral inference) | BUILT | `findChurch2_onboarding` | `FindChurch2SeekerProfileService.swift` (discoveryAgentEnabled flag, default OFF) | 04a89d01 |
| 12 | Visit Planner (VisitPlan commitment object) | BUILT | `findChurch2_visitPlanner` | `FindChurch2VisitPlannerService.swift`, `FindChurch2VisitPlannerView.swift` | 359d560f |
| 13 | EventKit calendar integration | BUILT | `findChurch2_visitPlanner` | `FindChurch2VisitPlannerService.swift` | 359d560f |
| 14 | Church Notes post-visit integration | BUILT | `findChurch2_visitPlanner` | `FindChurch2VisitPlannerService.swift:startPostVisitReflection` | 359d560f |
| 15 | AI Concierge (Berean first-visit, local-only) | BUILT | `findChurch2_concierge` | `FindChurch2ConciergeView.swift` | 359d560f |
| 16 | Claim flow (unclaimed → pending → verified) | BUILT | `findChurch2_claimPortal` | `FindChurch2ClaimView.swift` | 6b1321aa |
| 17 | Admin portal (in-app v1) | BUILT | `findChurch2_claimPortal` | `FindChurch2AdminPortalView.swift` | 6b1321aa |
| 18 | Trust signals on profiles | BUILT | `findChurch2_trustSignals` | `FindChurch2TrustSignalsView.swift` | 6b1321aa |
| 19 | Premium church tools | DEFERRED | N/A | `FindChurch2AdminPortalView.swift` (scaffold+paywall stub) | 6b1321aa |
| 20 | Collapsing header + design refresh | BUILT | `findChurch2_designRefresh` | `FindChurch2HeaderView.swift`, `FindChurch2AvailabilityPill.swift`, `FindChurch2MapListView.swift`, `FindChurch2CommunitySignalsView.swift`, `FindChurch2ProfileExpansionView.swift` | pre-existing + c358840f |

**DEFERRED reason for #19:** Stripe integration requires external business/legal decision. Scaffold wired and visible but non-tappable (allowsHitTesting: false overlay). See DECISIONS.md D-09.

---

## Wave Summary

| Wave | Description | Status | Commit |
|---|---|---|---|
| Phase 0 | Audit — AUDIT.md + DECISIONS.md | ✅ DONE | 4352e88f |
| Wave 1 | Contracts — ChurchObject, GatheringObject, MatchExplanation, SeekerProfile, AvailabilityStatus, flags, rules | ✅ DONE | 4352e88f |
| Wave 2 | Data + Search — AvailabilityService, GatheringService, SearchExtension, ingestion+media CFs | ✅ DONE | 144be72b |
| Wave 3 | Onboarding + Matching — 3-phase LG onboarding, SeekerProfileService, MatchBadge, SmartCard, FindMyPeople | ✅ DONE | 04a89d01 |
| Wave 4 | Visit Loop — VisitPlannerService (EventKit+notifications), VisitPlannerView, ConciergeView | ✅ DONE | 359d560f |
| Wave 5 | Church-Side — ClaimView, AdminPortalView, TrustSignalsView | ✅ DONE | 6b1321aa |
| Wave 6 | UI Refresh — CollapsingHeader, AvailabilityPills, MapListHybrid, CommunitySignals, ProfileExpansion | ✅ DONE | c358840f |

---

## Open Human Steps

These require human action before features can be enabled:

1. **Deploy Cloud Functions**: `firebase deploy --only functions:ingestChurchesFromGooglePlaces,functions:computeAvailabilityStatus,functions:scheduleAvailabilityRefresh,functions:detectChurchMedia --project amen-5e359`
2. **Set GOOGLE_PLACES_API_KEY** in Firebase environment config: `firebase functions:config:set places.api_key="YOUR_KEY"`
3. **Deploy Firestore rules**: `firebase deploy --only firestore:rules --project amen-5e359` (rules extended with gatherings/, seekerProfiles/, visitPlans/, claimRequests/)
4. **Deploy Remote Config**: Upload `remoteconfig.template.json` — all `findChurch2_*` flags default OFF; flip them individually as each feature is verified
5. **Seed Phoenix metro churches**: Call `ingestChurchesFromGooglePlaces` callable with `{ location: { lat: 33.4484, lng: -112.0740 }, radiusMeters: 50000 }`
6. **Stripe integration** (DEFERRED): Business/legal decision required before `churchPremium` paywall is activated

---

## Pre-existing Build Fixes (collateral)

These pre-existing errors were fixed as collateral to get a clean build:

| File | Fix |
|---|---|
| `MusicContentLayer/ProfileResourceShelf.swift` | Renamed `ResourceCard` → `ProfileShelfResourceCard`, `CategoryFilterChip` → `ProfileShelfCategoryChip` |
| `MusicContentLayer/ChurchNoteShareCard.swift` | Renamed `PrayerCard` → `ChurchNoteSharePrayerCard`, `FlowLayout` → `ChurchNoteShareFlowLayout`; `Color.systemBackground` → `Color(uiColor:)` |
| `AmenConnectV2View.swift` | `.foregroundStyle(Color.accentColor)` → `.foregroundStyle(.tint)` (revert from broken agent change) |
| `ChurchNotes/Views/ChurchNoteSmartObjectComponents.swift` | Renamed `AmenGlassCard` → `ChurchNoteGlassCard` |
| `FindChurch2AdminPortalView.swift` | Renamed `FlowLayout` → `FC2AdminFlowLayout`, `SuggestionRow` → `FC2SuggestionRow`; `@ViewBuilder` on multi-view properties |
| `FindChurch2ClaimView.swift` | `@ViewBuilder` on `confirmationStep`, `verificationStep`, `reviewStep` |

---

## Design Compliance Checklist

- [x] No glass-on-glass nesting (`.ultraThinMaterial` only at outermost surface)
- [x] All animations guarded by `@Environment(\.accessibilityReduceMotion)`
- [x] Dynamic Type only — no fixed font sizes in new files
- [x] All interactive targets ≥ 44×44pt
- [x] Location state never shows "Updating location…" — safeLabel guard in CollapsingHeader
- [x] "Contact church for service times" replaced with "Help us fill this in" + suggest-times affordance
- [x] Bottom nav safe padding: `.safeAreaInset(edge: .bottom)` on all scrollable surfaces
- [x] Community signals: member count, friends saved, gathering activity — no vanity metrics
- [x] No like counts, no follower counts
- [x] Absent data shown as "Not provided" — never hidden (TrustSignalsView)
- [x] All flags default OFF — flip individually after verification
