# AMEN Intelligence Graph / Your Journey - Phase 0 Audit Findings

Date: 2026-06-17
Scope: audit only. No shared implementation surfaces changed.

## Fit Map

### 1. Feed / ranking

- Primary local ranker: `AMENAPP/AMENAPP/HomeFeedAlgorithm.swift`.
  - Current scoring already uses recency, following relationship, topic relevance, onboarding goals, author affinity, engagement quality, diversity, category boosts, controversy penalty, repetition penalty, Hey Feed topic weights, boosted posts/authors, Living Wall momentum, trust score, recommendation relevance, mutual-follow depth, NL preference deltas, session-mode deltas, saturation penalties, and contradiction multipliers.
  - Existing hard gates include muted authors, hidden posts, followers/private visibility, and trusted-circle client suppression.
- Server ranking hook: `AMENAPP/AMENAPP/FeedAPIService.swift`.
  - Calls Cloud Run `FEED_RANKING_URL/rank`, then falls back to `HomeFeedAlgorithm` on timeout/error.
  - This is the best attachment point for a gated `ff_your_journey` rerank path because it can remain additive and return `nil` to preserve legacy behavior.
- Existing user control surfaces:
  - `HeyFeedPreferencesService` stores `userFeedPrefs/{uid}` and `userFeedSignals/{uid}/signals`.
  - `PostFeedActions.swift` provides "Why am I seeing this?", "More like this", "Less like this", "Hide this post", and "Mute author".
  - `FeedIntelligenceWhyThisPostSheet.swift` calls `explainWhyThisPost` and `adjustPostRecommendationSignal`.
  - `YourFeedView.swift` is already a Liquid Glass feed stewardship center.
- Recommendation-adjacent services:
  - `WellbeingFeedRankingService` calls `applyWellbeingBoosts`, `reportPostWellbeingImpact`, and `getUserWellbeingScore`.
  - `FeedRankingContextManager` derives context from `AmenFeedDirectionService.getFeedIntelligenceSummary()`.

Recommended hook: add a Wave 0 contract for `YourJourneyRecommendationReranker` and wire later behind `ff_your_journey` either in the server rank path or immediately after server/local candidate scoring. Flag OFF must skip all new reads/writes and preserve current ordering.

### 2. GUARDIAN / Aegis / moderation

- Existing moderation gateway: `ModerationGatewayService.swift` calls `checkContentSafety` and fails closed in production.
- Existing pre-submit pipeline: `ModerationIngestService.swift`.
  - LocalContentGuard, DoxxingScanner, GroomingScanner, ThinkFirstGuardrails, and a Firestore `moderation_ingest_events` callout.
  - Note: Stage 5 allows content immediately and runs server callout asynchronously, so recommendation eligibility must use server-side moderation projections, not this pre-submit result.
- Rules enforce moderation ownership:
  - `posts/{postId}` clients cannot set `visible: true` or moderation fields on create.
  - `moderationQueue`, `moderationDecisions`, `moderationCases`, `trustSafetyEvents`, `evidenceVault`, and `ncmecReadiness` are locked or CF/admin-owned.
- Aegis files found:
  - `AegisC59Detector.swift`
  - `AegisEnforcementService.swift`
  - `AmenConnectSpacesAegisService.swift`
- Contracts docs define the broader moderation architecture:
  - `Contracts/C4-cf-signatures.md` documents `moderatePost`, `checkContentSafety`, media moderation, `moderationQueue`, `moderationDecisions`, and fail-closed behavior.
  - `Contracts/stubs/cf-type-stubs.ts` states the fail-closed moderation contract.

Recommended integration: `ContentSafetyProfile` must be a read-model projection from existing GUARDIAN/Aegis outputs. New classifiers should register as Aegis/GUARDIAN capabilities and write only through backend/admin paths.

### 3. Berean callable proxies

- Client-side AI surfaces route through Firebase callables; no client API keys found in these Swift paths.
- Active client callables include:
  - `BereanConstitutionalPipeline.swift`: `bereanConstitutionalPipeline`, `bereanSubmitFeedback`; has consent gate and local crisis pre-screen.
  - `BereanContextActionEngine.swift`: `routeBereanContextualAction` with constitutional pre-flight gate.
  - `AmenAIFeaturesService.swift`: `generateCreatorDraft`, `ragSearch`; enforces consent/rate limits client-side.
- Contracts docs identify active proxy expectations:
  - `Contracts/C4-cf-signatures.md`: active gen2 `bereanChatProxy` in `Backend/functions/lib/bereanChatProxy.js`, `openAIProxy`, `whisperProxy`, and Anthropic/OpenAI dependencies.
  - It also warns that legacy gen1 Berean wrappers exist and should not be expanded.
- Region collision:
  - Several existing Swift clients use `Functions.functions(region: "us-central1")` or default region.
  - New functions in this project must use `us-east1` per prompt.

Recommended integration: `generateJourneySummary` should be a new `us-east1` callable that internally uses the existing Berean proxy/pipeline contract. The client should call only that callable and should never assemble hidden/sensitive profile data locally.

### 4. Search

- Algolia:
  - `AlgoliaSearchService.swift` uses indices `users` and `posts`.
  - Existing service supports user suggestions/search and post search.
- Pinecone / RAG:
  - `AmenAIFeaturesService.ragSearch()` calls `ragSearch` for `churchNotes`, `savedVerses`, `posts`, `sermons`, and `all`.
  - `Contracts/C4-cf-signatures.md` documents `PINECONE_API_KEY`, `PINECONE_HOST`, `ragSearch`, and vector cleanup.
- Local semantic fallback:
  - `SemanticSearchService.swift` has keyword-vector search over recent public posts and a `semanticSearch` callable fallback.
- Discovery:
  - `AmenDiscoverView`, `AmenDiscoverService`, `AmenDiscoverViewModel`, `DiscoverySearchView`, and related `DiscoveryOS` files are likely Explore/Discover insertion points.

Recommended integration: reuse Algolia `posts`/`users` and existing `ragSearch`; do not stand up a new search stack. Add topic/user-saved-journey filtering as query/filter parameters after contracts are frozen.

### 5. Design system

- Liquid Glass primitives:
  - `AmenLiquidGlassComponents.swift`: `AmenLiquidGlassPillButton`, `AmenLiquidGlassControlDock`, `AmenLiquidGlassBottomSheet`.
  - `CommunicationOSGlassKit.swift`: `AmenGlassInsightChip`, `AmenGlassInsightBar`, `AmenGlassActionSheet`, `AmenGlassMemoryCard`; explicitly documents no glass-on-glass, Reduce Transparency fallback, Dynamic Type, VoiceOver labels, and minimum tap targets.
- Existing feed control UI:
  - `YourFeedView.swift` already implements a full "Your Feed" stewardship surface with chips, modes, tuning, session controls, and advanced controls.
- Theme tokens:
  - `AmenTheme.Colors.amenGold` and related AMEN theme colors are present in multiple surfaces.
  - The exact `amenGold` / `amenPurple` / `amenBlue` / `amenBlack` canonical token location should be frozen in Wave 0 before new UI is built, because multiple local color definitions exist.

Recommended integration: build `YourJourneyView` from existing Liquid Glass/chip primitives and avoid adding new ad-hoc hex colors. Confirm canonical token type in Wave 0 before UI work.

### 6. Feature flags

- Main feature flag source: `AMENAPP/AMENAPP/AMENFeatureFlags.swift`.
  - Uses Firebase Remote Config defaults via `buildDefaults()`.
  - Most keys are snake_case, with some `ff_` keys for distinctives/onboarding.
  - Defaults are mixed: many legacy systems default ON; newer unapproved rollouts default OFF.
- Existing relevant flags:
  - `feed_ranking_v2_enabled`
  - `feed_intelligence_enabled`
  - `guide_my_feed_enabled`
  - `why_this_post_backend_enabled`
  - `feed_modes_enabled`
  - `wellbeing_feed_ranking_enabled`
  - `trust_scoring_enabled`

Proposed Your Journey flags, default OFF:

- `ff_your_journey`
- `ff_feed_feedback_menu`
- `ff_why_seeing_this`
- `ff_feed_nutrition`
- `ff_life_compass`
- `ff_digital_shepherd`
- `ff_trust_graph_labels`
- `ff_creator_metrics`

Recommendation: keep the prompt's `ff_` names for the frozen contract because the project already supports some `ff_` names, but add Swift properties in `AMENFeatureFlags` and Remote Config defaults in Wave 0. If the team prefers the dominant convention, use aliases in Wave 0 only, not later.

### 7. Existing models / Firestore collections

Relevant current collections and rules:

- `userFeedPrefs/{uid}` and `userFeedSignals/{uid}/signals` are used by Hey Feed.
- `users/{uid}/safety/feedControls/{controlId}` is readable by owner and CF-owned for writes.
- `users/{uid}/trust/{trustDocId}` is owner-readable and CF-owned.
- `feedExplanations/{explanationId}` is recipient-readable and CF-owned.
- `posts/{postId}` moderation fields are protected from client writes.
- `moderationQueue`, `moderationDecisions`, `moderationCases`, `trustSafetyEvents`, `evidenceVault`, `ncmecReadiness` are server/moderation owned.
- `trustProfiles/{userId}` exists in rules; inspect before adding `CreatorTrustProfile`.
- `users/{uid}/topics/{topicId}` exists in rules; inspect before adding journey topics to avoid collision.

Recommended Firestore shape for Wave 0:

- `userPersonalizationProfiles/{uid}` or `users/{uid}/personalization/profile`
- `users/{uid}/contentInterestSignals/{signalId}` or a top-level `contentInterestSignals/{uid_signalId}`
- `recommendationExplanations/{recommendationId}` or reuse/extend `feedExplanations/{explanationId}` only if fields can be frozen without breaking existing readers.
- `feedNutritionSnapshots/{uid_weekStart}` or `users/{uid}/feedNutritionSnapshots/{weekId}`
- `contentSafetyProfiles/{contentId}` admin-only
- `creatorTrustProfiles/{creatorId}` admin-only

Decision needed in Wave 0: top-level vs user-subcollection ownership for user-owned data. Subcollections simplify owner rules and export/delete; top-level can simplify backend analytics jobs.

### 8. Surface insertion points

- Settings:
  - `SettingsView.swift`, `ContentFeedGroupView` currently has `Feed & Content -> Your Feed`.
  - Add `Your Journey` here behind `ff_your_journey`; decide whether it replaces or sits beside `Your Feed`.
- Home Feed:
  - `PostFeedActions.swift` and `FeedIntelligenceWhyThisPostSheet.swift`.
  - Must bridge existing Hey Feed actions to frozen `ContentInterestSignal.signalType`.
- Explore / Discover:
  - `AmenDiscoverView`, `AmenDiscoverService`, `AmenDiscoverViewModel`, `DiscoverySearchView`, `DiscoverFeedService`.
- Onboarding:
  - `OnboardingFlowView.swift`, `OnboardingQuizView.swift`, `AMENOnboardingSystem.swift`, and `LongitudinalOnboardingView.swift`.
  - Existing `HomeFeedAlgorithm.UserInterests.onboardingGoals` should be migrated/bridged to `LifeGoal`.
- Creator Profile:
  - `CreatorProfile.swift`, `CreatorProfileGate.swift`, `CreatorTrustBadgeView.swift`, `CreatorTrustAndGateViews.swift`, `StudioProfileView.swift`, `UserProfileView.swift`.
- Post Details:
  - `NotificationPostDetailView.swift`, `PostFeedActions.swift`, feed card/detail host files.
- Notifications:
  - `SmartNotificationEngine.swift`, `SmartNotificationService.swift`, `NotificationScheduler.swift`, `NotificationDigestService.swift`, `NotificationSettingsService.swift`.
  - Current notification priority is recency/type/relationship/engagement; Life Compass and quiet-hour integration should be additive and gated.
- Moderation:
  - Existing moderation and rules surfaces above.
- Search:
  - `AlgoliaSearchService.swift`, `AmenAIFeaturesService.ragSearch`, `SemanticSearchService.swift`, `DiscoverySearchView.swift`.

## Collision Risks

- `Your Feed` vs `Your Journey`: there is already a user-facing personalization center. Product needs to decide if `Your Journey` is a superset/rebrand or a separate settings path.
- Explanation surfaces: existing `WhyAmISeeingThisSheet`, `FeedIntelligenceWhyThisPostSheet`, and `feedExplanations` overlap with `RecommendationExplanation`.
- Signal taxonomy mismatch: current signals include `moreLikeThis`, `lessLikeThis`, `muteAuthor`; the requested enum uses `view`, `longView`, `like`, `save`, `share`, `comment`, `follow`, `hide`, `report`, `notInterested`, `muteTopic`, `completeStudy`, `joinCommunity`. Wave 0 must freeze a mapping.
- Trust score exposure: existing `ContentTrustScoreService` computes 0-100 client-side from user and relationship data. New creator trust profile must not expose raw trust scores to clients.
- Safety projection: current pre-submit server callout can be best-effort; recommendations need fail-closed eligibility from server-owned moderation state.
- Region mismatch: existing callables often use default/us-central1. New Cloud Functions must be explicit `us-east1`.
- Firestore catch-all denies new collections, so Wave 0 must add rules skeleton before any client write path is built.
- Existing rules have open legal/T&S questions around minor age thresholds, guardian tools, NCMEC timing, and anonymous identity shielding. Your Journey must not depend on resolving those except where child-safety gates require fail-closed behavior.
- Other active agents are working in this workspace. Avoid touching broad hotspots (`AMENFeatureFlags.swift`, `firestore.rules`, `SettingsView.swift`, `HomeFeedAlgorithm.swift`) until Wave 0 sign-off and coordination.

## Reuse List

- Ranking: `HomeFeedAlgorithm`, `FeedAPIService`, `WellbeingFeedRankingService`, `FeedRankingContextManager`.
- Preferences/signals: `HeyFeedPreferencesService`, `HeyFeedNLPreferencesService`, `HeyFeedSessionModeService`, `AmenFeedDirectionService`.
- Explainability: `FeedIntelligenceWhyThisPostSheet`, `WhyAmISeeingThisSheet`, `feedExplanations`.
- Safety: `ModerationGatewayService`, `ModerationIngestService`, `ContentModerationService`, `AdvancedModerationService`, `AegisC59Detector`, rules-owned moderation collections.
- Trust: `ContentTrustScoreService`, `TrustSignals/*`, `CreatorTrustBadgeView`, `CreatorTrustAndGateViews`.
- AI/Berean: `BereanConstitutionalPipeline`, `BereanContextActionEngine`, `AmenAIFeaturesService`.
- Search: `AlgoliaSearchService`, `SemanticSearchService`, `AmenAIFeaturesService.ragSearch`.
- UI: `AmenLiquidGlassComponents`, `CommunicationOSGlassKit`, `YourFeedView`, settings `SD*` components.

## Proposed Wave 0 Contract Work

1. Freeze Swift and TypeScript models exactly from the prompt.
2. Freeze enum mappings:
   - `ExplanationReason.type`: `followsCreator`, `similarTopic`, `communityEngagement`, `userGoal`, `savedSimilar`, `trustedSource`, `studyPlanRelated`, `trendingSafely`.
   - `ContentInterestSignal.signalType`: `view`, `longView`, `like`, `save`, `share`, `comment`, `follow`, `hide`, `report`, `notInterested`, `muteTopic`, `completeStudy`, `joinCommunity`.
3. Add feature flags to contract, defaults OFF.
4. Add Firestore rules skeleton for user-owned personalization data and backend-owned safety/trust profiles.
5. Define a backend-only ranking weights/config document path and rule it CF/admin-only.
6. Define the mapping from existing Hey Feed actions to frozen signal types.
7. Decide whether `RecommendationExplanation` reuses `feedExplanations` or gets a new collection.
8. Define a safe-label enum for creator trust labels; raw trust scores remain backend-only.
9. Define `generateJourneySummary` as a `us-east1` callable routed through existing Berean proxy/pipeline semantics.
10. Document new Swift files for human Xcode target membership; do not edit `project.pbxproj`.

## Human Sign-Off Questions

1. Should `Your Journey` replace `Your Feed` in Settings, or live alongside it during the flagged rollout?
2. Should user personalization live top-level or under `users/{uid}`?
3. Should recommendation explanations extend existing `feedExplanations` or use a new `recommendationExplanations` collection?
4. Confirm the proposed `ff_` flag names despite the codebase's dominant snake_case convention.
5. Confirm canonical design token source for `amenGold`, `amenPurple`, `amenBlue`, and `amenBlack`.
6. Confirm whether existing client-side `ContentTrustScoreService` should be deprecated for recommendation trust scoring once `CreatorTrustProfile` exists.
7. Confirm whether Wave 0 may touch `AMENFeatureFlags.swift`, `firestore.rules`, shared model contracts, and settings/feed hot spots while other agents are active.

## Stop Point

Phase 0 audit is complete. Per the build prompt, stop here for human sign-off before Wave 0 contract changes.
