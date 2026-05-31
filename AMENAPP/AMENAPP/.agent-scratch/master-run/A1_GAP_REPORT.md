# A1 GAP REPORT — 2026-05-31
**Branch:** `feature/master-run-20260531`
**Agent:** A1 — Discovery/Audit

---

## Executive Summary
The AMEN codebase is **60–70% ready** for the five master-run phases. Foundational infrastructure (Liquid Glass, TabBar, Feature Flags, Posts surfaces, Subscription, Media Provenance, Intelligence Engines, and Berean AI) is largely in place. Critical gaps are in Phase 1 (Find a Church location services), Phase 3 (PostProvenance UI/service), and Phase 5 (Story system from scratch).

---

## Phase 1 — Find a Church

### Exists
- **Church model**: `SmartChurch` struct in `SmartChurchSearch/SmartChurchModels.swift`
- **Map infrastructure**: Dual-provider map (Apple Maps + Google Maps SDK) in `ChurchGoogleMapsView.swift`
- **Algolia integration**: `AlgoliaConfig.swift`, `AlgoliaSearchService.swift`, `AlgoliaSyncService.swift`
- **Search service**: `SmartChurchSearchService.swift` + `ChurchSearchViewModel.swift`
- **UI surfaces**: `ChurchSearchView.swift`, `ChurchDetailView.swift`, `SmartChurchBereanFinderView.swift`

### Missing / Needs Build
1. **CoreLocation manager** — No `CLLocationManager` wrapper; no permission gating; no "current location → nearby" flow
2. **Clustering infrastructure** — No `MKClusterAnnotation` or clustering algorithm
3. **Location-based filtering** — No distance-radius filtering (e.g., "within 25 miles")
4. **Church first-visit companion** — Flag exists (`churchFirstVisitCompanionEnabled`) but no implementation
5. **Service reminders** — Flag exists (`churchServiceRemindersEnabled`) but no reminder orchestration
6. **Church journey timeline** — Flags exist but no timeline view or tracking service

### Reuse Opportunities
- Reuse `SmartChurch` model as-is (it's complete)
- Reuse `AmenSubscriptionService` tier-checking
- Reuse `NotificationDeepLinkRouter` pattern for service-time reminders

### Naming Conflicts
- None. The frozen contract uses `Church` (simpler), while codebase uses `SmartChurch`. A2 should decide whether to alias or use SmartChurch directly.

---

## Phase 2 — Posts Liquid Glass + Global Nav

### Exists
- **Tab bar implementations (3 variants)**:
  1. `AMENTabBar.swift` — Floating dock (circle orbs)
  2. `AmenLiquidGlassTabBar.swift` — Scrollable pills, scroll-responsive (CANONICAL)
  3. `BereanFloatingTabBar.swift` — Berean-specific 4-tab
- **Liquid Glass kit**: `AmenLiquidGlassComponents.swift` (330 lines) + `AmenGlassKit.swift` (1135 lines)
- **Post surfaces**: Feed views, `PostDetailView.swift`, `CreatePostView.swift`, `CommentsView.swift`, `SmartLinkClassifier.swift`, media player, action bar
- **Motion system**: `Motion.swift` with `Motion.adaptive(_:)` for reduce-motion

### Missing / Needs Build
1. **Material usage audit** — Verify no stray `.ultraThinMaterial`/`.regularMaterial` outside kit
2. **Post provenance badge** — Not integrated into feed cell or detail (Phase 3 dependency)
3. **Global nav routing** — Unclear which tab bar is canonical for main app; no unified selection state

### Reuse Opportunities
- `AmenLiquidGlassComponents.swift` + `AmenGlassKit.swift` — complete glass system
- `Motion.swift` — all animation primitives
- `SmartLinkClassifier` — link detection

---

## Phase 3 — Provenance / "Why You're Seeing This"

### Exists
- **Media provenance** (3 files): `AmenMediaProvenanceService.swift`, `ProvenanceLabelView.swift`, `ProvenanceTrustPanel.swift`
- **Models**: `TSMediaProvenance`, `TSCreatorDeclaration`, `AIDisclosureRecord`
- **Intelligence settings**: `FeedIntelligenceSettingsView.swift` (feed directions UI)
- **Services**: `FeedIntelligenceService.swift`, `RecommendationIntelligenceService.swift`

### Missing / Needs Build
1. **Post-level provenance display** — No integration of provenance into feed cells or `PostDetailView`
2. **"Why Seeing This" UI** — No user-facing disclosure on the post itself (info icon → sheet)
3. **PostProvenance model** — No struct for "This post was recommended because..."
4. **Intelligence Engine orchestration** — No unified "2I" coordinator; individual engines exist but disconnected
5. **Reason caching** — No per-post reason storage to avoid recomputation

### Reuse Opportunities
- `ProvenanceTrustPanel` as template for "Why Seeing This" sheet
- `AmenLiquidGlassBottomSheet` for the disclosure sheet
- `FeedIntelligenceSettingsView` pattern for reason settings

---

## Phase 4 — Security / A11y

### Exists
- **Feature flags**: `AMENFeatureFlags.swift` (550+ lines) — full flag system
- **App Check**: `AppCheckDebugProviderFactory.swift` — debug + App Attest
- **Motion adaptive**: `Motion.adaptive(_:)` in `Motion.swift`
- **Reduce Transparency**: Environment variable used in glass components
- **Subscription/entitlement**: `AmenSubscriptionService.swift` — tier-based gating
- **Trust scoring**: `TrustScoringEngine.swift` (650+ lines)
- **A11y labels**: Present throughout (verified in prior audits)

### Missing / Needs Build
1. **GUARDIAN client-side safety wall** — Crisis escalation flag exists; no UI
2. **Pastoral care routing** — `checkInCrisisEscalationEnabled` flag; no service
3. **A11y contrast validation** — No automated checker in design system

---

## Phase 5 — Selah Stories

### Exists
- **Selah infrastructure**: `SelahScripture/` (25+ files) — scripture viewer, reflection composer, Berean AI modes, safety preflight
- **Voice infrastructure**: `AmenVoiceModules.swift`, `BereanVoiceSessionManager.swift`, `WhisperVoiceService.swift`
- **Living Memory**: `BereanMemoryService.swift`, `ChatMemoryService.swift`, `LivingMemoryCard.swift`, `LivingMemorySection.swift`
- **Berean AI**: 50+ files — contextual translation, scripture context cards, realtime services, voice companion

### Missing / Needs Build
1. **`SelahStory` model** — No story struct at all
2. **Story composer UI** — No story creation flow
3. **Story viewer** — No story detail/playback view
4. **Story feed** — No discovery/browsing
5. **Story-to-post bridge** — No "Save story as post" action
6. **Verse recognition / OCR** — No explicit OCR; Berean parses voice only
7. **Liturgical season awareness** — No church calendar model anywhere
8. **Semantic audio matching** — No audio-to-verse-theme matching system

### Reuse Opportunities
- `SelahReflectionComposerView.swift` pattern for composer
- `BereanMemoryService` for story context storage
- `BereanScriptureContextCardView` for verse display in stories
- `CommentsView.swift` + `CommentService.swift` for story reactions/replies
- `AmenMediaUploadFlowView.swift` for media attachment
- `CreatePostView` infrastructure for stories-to-posts bridge

### Naming Conflicts
- `SelahStory` vs. `SelahReflection` — existing `SelahReflection*` files cover text-only journal. Stories are multimedia. Keep both; they are distinct.

---

## Cross-Cutting Gaps

| Gap | Status | Phase |
|---|---|---|
| Liturgical-season awareness | NOT FOUND | Affects P1, P3, P5 |
| GUARDIAN safety wall | NOT FOUND (flag only) | P4, P5 |
| Pastoral care routing | NOT FOUND (flag only) | P4 |
| Deep-link for Stories | NOT FOUND | P5 |
| Analytics — anti-engagement-bait | Partial (`feedQualityMetricsEnabled` flag) | P2, P5 |
| Clustering for Map | NOT FOUND | P1 |

---

## Tab Bar Canonical Decision (for A0)
Three implementations exist. Recommend: `AmenLiquidGlassTabBar.swift` = canonical for main app. `AMENTabBar.swift` = home layout variant. `BereanFloatingTabBar.swift` = Berean-only context.

---

## Recommended Build Order
Phase 4 (quick gating wins) → Phase 2 (glass foundation) → Phase 1 (parallel to P2) → Phase 3 (post-integration) → Phase 5 (final, depends on P2 post bridge)

---

## Key Files
| File | Purpose |
|---|---|
| `AMENFeatureFlags.swift` | Feature flag system — READ FIRST |
| `AmenGlassKit.swift` | Frozen glass kit (A13 Phase 0 output) |
| `Motion.swift` | Animation primitives |
| `SmartChurchModels.swift` | Church data model |
| `PostDetailView.swift` | Post detail anatomy |
| `AmenSubscriptionService.swift` | Subscription tier system |
| `AmenMediaProvenanceService.swift` | Media provenance |
| `AmenVoiceModules.swift` | Voice session components |
