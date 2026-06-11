# Find Church 2.0 — Phase 0 Audit
Generated: 2026-06-11

## Surface Inventory

| Surface | File(s) | Exists? | Quality | Wave |
|---|---|---|---|---|
| Primary view | `AMENAPP/FindChurchView.swift` | ✅ | WEAK — 5000+ lines, redundant `Church` struct, "Contact church for service times" dead-end, lingering location state | W6 |
| Church card | `AMENAPP/EnhancedChurchCard.swift`, `ChurchCardEnhancements.swift`, `ChurchPillCard.swift` | ✅ | WEAK — bare percentage badge, no MatchExplanation | W3/W6 |
| Church profile | `AMENAPP/ChurchProfileView.swift`, `AMENAPP/AMENAPP/CommunityOS/Church/AmenChurchProfileView.swift` | ✅ | WEAK — duplicate views, no claim state, no beliefs transparency | W5/W6 |
| Church model | `AMENAPP/ChurchModels.swift` | ✅ | WEAK — missing beliefs schema, denomination lineage, claim state machine, structured recurring service times, EIN, gatherings | W1 |
| FindChurchView.Church | `AMENAPP/FindChurchView.swift:18` | ✅ | WEAK — redundant local struct, conflicts with ChurchEntity | W1 |
| Fit score service | `AMENAPP/ChurchFitScoreService.swift` | ✅ | WEAK — only denomination/distance/style/community; no structured MatchExplanation | W1/W3 |
| Church search | `AMENAPP/ChurchSearchService.swift`, `ChurchDiscoveryService.swift` | ✅ | GOOD — Pinecone/Algolia hybrid exists | W2 |
| AI recommendation | `AMENAPP/AIChurchRecommendationService.swift` | ✅ | GOOD — keep, extend with MatchExplanation | W3 |
| Church matcher | `AMENAPP/ChurchMatcherService.swift` | ✅ | WEAK — extend with structured reasons | W3 |
| Church ranking | `AMENAPP/ChurchRankingService.swift` | ✅ | GOOD — keep | — |
| Church data service | `AMENAPP/ChurchDataService.swift` | ✅ | GOOD | — |
| Church profile service | `AMENAPP/ChurchProfileService.swift` | ✅ | GOOD | — |
| Church proximity engine | `AMENAPP/ChurchProximityEngine.swift` | ✅ | GOOD | — |
| Visit session | `AMENAPP/ChurchVisitSessionManager.swift` | ✅ | GOOD — reuse in W4 | W4 |
| Visit reminder | `AMENAPP/ChurchVisitReminderService.swift`, `ChurchVisitNotificationScheduler.swift` | ✅ | GOOD — reuse in W4 | W4 |
| First visit guide | `AMENAPP/ChurchFirstVisitGuideView.swift` | ✅ | GOOD — reuse/extend in W4 | W4 |
| Church journey | `AMENAPP/ChurchJourneyTimelineService.swift`, `ChurchJourneyPlanner.swift` | ✅ | GOOD — foundation for VisitPlan | W4 |
| Berean church AI | `AMENAPP/BereanChurchGroundingService.swift`, `BereanChurchNotesBridge.swift` | ✅ | GOOD — reuse in W4 concierge | W4 |
| Church verification | `AMENAPP/ChurchVerificationService.swift` | ✅ | WEAK — no claim state machine (unclaimed→pending→verified) | W5 |
| Church trust safety | `AMENAPP/ChurchTrustSafetyService.swift` | ✅ | GOOD | W5 |
| Church notes | `AMENAPP/ChurchNotes/*` (70+ files) | ✅ | GOOD — rich notes system, integrate in W4 | W4 |
| Living entry bridge | `AMENAPP/AMENAPP/LivingEntries/FindChurchLivingEntryBridge.swift` | ✅ | GOOD | — |
| Glass components | `AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift`, `CommunicationOSGlassKit.swift` | ✅ | GOOD — use as design foundation | W6 |
| GatheringObject | — | ❌ | MISSING — no gatherings collection anywhere | W1 |
| MatchExplanation | — | ❌ | MISSING — bare FitScore.topReason string only | W1 |
| SeekerProfile | — | ❌ | MISSING — no private seeker profile | W1 |
| VisitPlan | — | ❌ | MISSING — no commitment object | W1 |
| AvailabilityStatus | — | ❌ | MISSING — "Contact church for service times" dead end | W1/W2 |
| findChurch2_ flags | — | ❌ | MISSING — no findChurch2_* flags in remoteconfig | W1 |
| Firestore rules for new collections | — | ❌ | MISSING | W1 |
| 3-phase LG onboarding | — | ❌ | MISSING | W3 |
| Find My People mode | — | ❌ | MISSING | W3 |
| Claim flow UI | — | ❌ | MISSING — ClaimState machine not in models | W5 |
| Admin portal | — | ❌ | MISSING | W5 |
| Trust signals UI | — | ❌ | MISSING (service exists, no UI) | W5 |
| National ingestion CF | — | ❌ | MISSING | W2 |
| AvailabilityStatus CF | — | ❌ | MISSING | W2 |
| Live Activity (visit) | — | ❌ | MISSING | W4 |
| Map/List hybrid toggle | — | ❌ | MISSING | W6 |
| Header collapse-on-scroll | — | ❌ | MISSING | W6 |
| matchedGeometry card→profile | — | ❌ | MISSING | W6 |

## Design Conformance Findings

| Issue | Severity | Wave |
|---|---|---|
| "Updating location…" lingers — no fast fallback to city name | HIGH | W6 |
| Match badge is bare percentage — no chip reasons | HIGH | W3 |
| "Contact church for service times" dead-end card | HIGH | W2 |
| Bottom nav covers card actions — no card-aware safe insets | MEDIUM | W6 |
| Card → profile is jump-cut navigation, not expansion | MEDIUM | W6 |
| Status pills (Verified/Service Today/Open Now) inconsistent style | MEDIUM | W6 |
| FindChurchView.Church conflicts with ChurchEntity — two parallel models | HIGH | W1 |
| `.ultraThinMaterial` approximations instead of native `.glassEffect()` | LOW | W6 |

## Firestore Schema Gaps

| Gap | Wave |
|---|---|
| `churches/{id}` missing: beliefs schema, claim state, EIN, denomination lineage, accessibility, child safety policy, gatherings refs | W1 |
| No `gatherings/{id}` collection | W1 |
| No `seekerProfiles/{uid}` collection | W1 |
| No `visitPlans/{id}` collection | W1 |
| No computed `availabilityStatus` field or computed cache | W2 |
| No ingestion pipeline or seed corpus | W2 |
