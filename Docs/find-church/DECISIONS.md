# Find Church 2.0 — Decisions Log

All decisions made autonomously per the AUTONOMY MANDATE.

---

## D-01 · ChurchEntity vs FindChurchView.Church
**Decision:** Extend `ChurchEntity` in `ChurchModels.swift` as the canonical `ChurchObject` (renamed). Deprecate the local `Church` struct in `FindChurchView.swift` by typealias + migration adapter so existing code doesn't break.  
**Rationale:** Two parallel structs is the source of the bulky FindChurchView. Consolidating now prevents wave 6 thrash.

## D-02 · Wave 1 contracts file location
**Decision:** New contracts go in `AMENAPP/FindChurchOS/FindChurch2Contracts.swift`.  
**Rationale:** `FindChurchOS/` directory already exists (`ChurchCommunityProfileView.swift` is there). Keeps wave 1 contained without scattering new types across existing files.

## D-03 · GatheringObject is a separate Firestore collection
**Decision:** `/gatherings/{id}` is its own top-level collection, not a subcollection of churches.  
**Rationale:** Standalone gatherings (campus ministries, non-church Bible studies) are first-class; subcollection would block standalone use.

## D-04 · SeekerProfile encryption tier
**Decision:** `SeekerProfile` is **Tier-P** — on-device storage via `UserDefaults` with keychain-backed encryption key; Firestore sync only when user explicitly enables "Save my preferences across devices." Firebase path: `seekerProfiles/{uid}` owner-only.  
**Rationale:** Matches tiered encryption model. Privacy chips in onboarding Phase 3 control sync behavior.

## D-05 · MatchExplanation replaces FitScore
**Decision:** `MatchExplanation` **adds to** `ChurchFitScoreService` — FitScore is kept for the internal computation, MatchExplanation is the public-facing contract. No breaking change.  
**Rationale:** Avoids rewriting the scoring logic; just wraps the output.

## D-06 · AvailabilityStatus computed on-device from cached structured service times
**Decision:** `AvailabilityStatus` is computed on the client from the structured `serviceTimes` array in `ChurchObject`, with a `availabilityCache` Firestore field updated by a scheduled Cloud Function for scale. Client falls back gracefully.  
**Rationale:** Avoids requiring a CF round-trip for every card render. Scheduled CF keeps cache warm.

## D-07 · Claim state machine uses Aegis review queue
**Decision:** Claim submissions trigger `submitChurchClaim` callable; EIN/domain auto-approvals use server-side verification; all others enter `AegisReviewQueue` with type `churchClaim`.  
**Rationale:** Trust OS/Aegis architecture wins over custom claim pipeline per scope guards.

## D-08 · National ingestion uses Google Places + Pinecone
**Decision:** Phase 1 ingestion uses Google Places `textsearch` with query "church" for Phoenix metro. Pinecone upsert uses church ID as vector ID. Full national rollout deferred — log as DEFERRED.  
**Rationale:** Phoenix metro is the stated proof corpus. National key pipeline is designed but not seeded at scale.

## D-09 · Premium church tools
**Decision:** DEFERRED — `churchPremium` entitlement gate stubbed with a paywall scaffold. Stripe integration is a known business/legal decision.  
**Reason:** External business decision required.

## D-10 · Gatherings index
**Decision:** Gatherings are co-indexed in Algolia alongside churches with a `kind: "gathering"` facet. No separate Algolia index needed.  
**Rationale:** Keeps search unified; `kind` filter surfaces church-only or gathering-only results.

## D-11 · Live Activity reuse
**Decision:** Visit Planner Live Activity reuses `ChurchVisitSessionManager` infrastructure rather than creating a new Live Activity type.  
**Rationale:** Existing infrastructure exists; new type would duplicate it.

## D-12 · App Store review changes
**Decision:** Any feature requiring a new permission string (calendar access for EventKit, background location) is logged and gated OFF by default. Manifest entries added; no plist changes needed in this run — they already exist.  
**Reason:** App Store review change if we added new plist entries without review.

## D-13 · HTML prototype for onboarding
**Decision:** HTML prototype of 3-phase onboarding is written to `docs/find-church/onboarding-prototype.html` for review validation, then SwiftUI is built from that spec. The HTML is NOT an intermediate approval gate — SwiftUI follows immediately.  
**Rationale:** Standard methodology per project directives.
