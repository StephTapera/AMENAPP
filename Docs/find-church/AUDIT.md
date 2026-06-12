# Find Church 2.0 Audit

Updated: 2026-06-12

| Surface | Exists? | Quality | Wave | Status | Notes |
|---|---:|---|---:|---|---|
| Legacy `FindChurchView` live flow | Yes | WEAK | 6 | ALREADY-GOOD for live continuity | Large legacy SwiftUI file preserves current search, check-in, share, planning, AI recommendations, and notes hooks; do not churn until gated replacement is ready. |
| `ChurchDataService` canonical lookup/search | Yes | WEAK | 2 | ALREADY-GOOD for live continuity | Firestore plus Apple Maps fallback exists; Algolia/Pinecone hybrid is referenced elsewhere, but this service still has Firestore prefix search comments. |
| `FindChurch2Contracts.swift` | Yes | GOOD | 1 | ALREADY-GOOD | Defines `ChurchObject`, `GatheringObject`, `MatchExplanation`, `SeekerProfile`, `AvailabilityStatus`, claim request, and VisitPlan extensions. |
| Feature flags in `AMENFeatureFlags` | Yes | GOOD | 1 | ALREADY-GOOD | All required `findChurch2_` Remote Config keys exist and default OFF. |
| Firestore rules for `seekerProfiles` | Yes | WEAK | 1 | FIXED | Tier-P owner-only rule now denies client admin override. |
| Firestore rules for church claim fields | Partial | WEAK | 1 | FIXED | Direct client updates to claim/verification fields are blocked; claim changes must go through CF/Admin flow. |
| Firestore rules for `gatherings` | Yes | GOOD | 1 | ALREADY-GOOD | Public signed-in read, member read, no direct client writes. |
| Firestore rules for `visitPlans` | Yes | GOOD | 1 | ALREADY-GOOD | Owner read/write lifecycle, hard delete denied. |
| Firestore rules for `claimRequests` | Yes | WEAK | 5 | ALREADY-GOOD for scaffold | Claimant submit/read exists; approval remains CF-only. Field schema should be tightened in Wave 5. |
| `FindChurch2AvailabilityService` | Yes | GOOD | 2 | ALREADY-GOOD | Computes structured availability with gathering and livestream heuristics behind flag. |
| `FindChurch2SearchExtension` | Yes | GOOD | 2 | ALREADY-GOOD | Pure helpers for fit-chip filtering and life-stage sorting. |
| Gatherings service | Yes | GOOD | 2 | ALREADY-GOOD | Gated Firestore fetch for church and standalone gatherings. |
| Backend church trust callables | Yes | WEAK | 2/5 | ALREADY-GOOD for scaffold | Verification, profile edit queue, livestream refresh, grounded answer exist; contract naming and national ingestion still incomplete. |
| National church ingestion | No | MISSING | 2 | DEFERRED | Requires external Places/API key and rollout budget. |
| Doctrine transparency | Partial | WEAK | 2 | ALREADY-GOOD for contract | Beliefs schema exists; claimant editing and profile rendering need integration. |
| Media/livestream detection | Partial | WEAK | 2 | ALREADY-GOOD for scaffold | Livestream callable and service exist; YouTube/provider sync stubs remain. |
| Onboarding SwiftUI | Yes | WEAK | 3 | ALREADY-GOOD for scaffold | Three phases exist and are flagged OFF; uses material comments/styles instead of native glass conformance. |
| Onboarding HTML demo | No | MISSING | 3 | DEFERRED | Non-app artifact missing; lower priority than production SwiftUI/contracts. |
| Match explanation UI | Yes | WEAK | 3 | ALREADY-GOOD for scaffold | Badge and drawer exist, but fallback still shows bare score and materials need design pass. |
| Find My People mode | Yes | WEAK | 3 | ALREADY-GOOD for scaffold | Dedicated view exists; integration into legacy results not verified. |
| Smart church cards | Yes | WEAK | 3 | ALREADY-GOOD for scaffold | Intent-adaptive card exists; design comments conflict with native glass rules. |
| Discovery agent foundation | Partial | WEAK | 3 | ALREADY-GOOD for contract | `discoveryAgentEnabled` defaults OFF; behavioral inference pipeline not complete. |
| Visit planner service/view | Yes | GOOD | 4 | ALREADY-GOOD | Gated planner persists VisitPlan, EventKit, notifications, status lifecycle. |
| Church Notes visit integration | Partial | WEAK | 4 | ALREADY-GOOD for scaffold | Existing Church Notes hooks are present; backlink contract needs verification. |
| AI concierge | Yes | WEAK | 4 | ALREADY-GOOD for scaffold | Grounded church answer callable and view exist; guardrails should be hardened against untrusted profile fields. |
| Claim flow UI | Yes | WEAK | 5 | ALREADY-GOOD for scaffold | Gated claim sheet exists but currently writes claim requests directly rather than callable-only. |
| Admin portal | Yes | WEAK | 5 | ALREADY-GOOD for scaffold | View exists; claimant authorization and queue approval need CF integration. |
| Trust signals UI | Yes | WEAK | 5 | ALREADY-GOOD for scaffold | View exists; needs profile integration and honest absent-data rows verified. |
| Premium tools scaffold | Partial | WEAK | 5 | DEFERRED | Payment/business/legal decision required; entitlement gate only should remain. |
| Header refresh | Yes | WEAK | 6 | ALREADY-GOOD for scaffold | `FindChurch2HeaderView` exists; legacy header still bulky until design flag integration. |
| Adaptive status pills | Yes | WEAK | 6 | ALREADY-GOOD for scaffold | `FindChurch2AvailabilityPill` exists; private duplicate pill remains in smart card. |
| Card to profile expansion | Yes | WEAK | 6 | ALREADY-GOOD for scaffold | Expansion view exists; legacy navigation still jump-cuts. |
| Map/list hybrid | Yes | WEAK | 6 | ALREADY-GOOD for scaffold | Gated view exists; live integration not verified. |
| Bottom nav safe padding | Partial | WEAK | 6 | ALREADY-GOOD for legacy | Legacy has some padding, but smallest-device verification is still needed. |

## Design Conformance Findings

| Rule | Quality | Status | Notes |
|---|---|---|---|
| Native `.glassEffect()` through GlassKit | WEAK | DEFERRED | Multiple FindChurch2 files still use/comment `.ultraThinMaterial`; requires coordinated UI pass under `findChurch2_designRefresh`. |
| No glass-on-glass nesting | WEAK | DEFERRED | Comments claim no nesting, but nested material overlays appear in onboarding chips. |
| Motion through `Motion.adaptive` | WEAK | DEFERRED | SwiftUI animations check reduce motion but do not route through shared Motion token. |
| Shared radius/blur/spacing tokens | WEAK | DEFERRED | Several local constants and ad hoc colors remain. |
| No lingering location state | WEAK | DEFERRED | Legacy `currentLocationName = "Locating..."` remains. |
| Match badge with explanation | WEAK | ALREADY-GOOD for scaffold | Match drawer exists; must ensure every score has at least two reasons before rendering. |
| Dead-end service time card | WEAK | DEFERRED | Contract supports suggestion queue count; legacy unknown-state replacement still needs integration. |
| Bottom nav safe padding | WEAK | DEFERRED | Requires device verification. |

## Firestore Schema Findings

| Collection | Exists? | Quality | Status | Notes |
|---|---:|---|---|---|
| `churches/{id}` canonical church | Yes | GOOD | ALREADY-GOOD | `ChurchObject` is additive over existing church documents. |
| `gatherings/{id}` | Yes | GOOD | ALREADY-GOOD | Contract and rules exist. |
| `seekerProfiles/{uid}` | Yes | GOOD | FIXED | Owner-only Tier-P rule enforced. |
| `visitPlans/{id}` | Yes | GOOD | ALREADY-GOOD | Owner lifecycle rules exist. |
| `claimRequests/{id}` | Yes | WEAK | ALREADY-GOOD for scaffold | Needs callable-only submit in Wave 5 to fully satisfy claim portal requirement. |
