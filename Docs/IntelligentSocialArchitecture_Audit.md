# Intelligent Social Architecture Audit

## Existing Systems Found

- Feature flags already exist in `AMENAPP/AMENFeatureFlags.swift` for:
  - `actionThreadsEnabled`
  - `actionSuggestionsEnabled`
  - `careFollowupsEnabled`
  - `compoundIdentityGraphEnabled`
  - `agentRecommendationsEnabled`
  - `proofOfHumanEnabled`
  - `proofOfCareEnabled`
  - `trustSignalsEnabled`
- Action Thread client infrastructure already exists in root-level files:
  - `ActionThreadModels.swift`
  - `ActionSuggestionEngine.swift`
  - `ActionThreadService.swift`
  - `ActionThreadPermissionsService.swift`
  - `ActionThreadNotificationService.swift`
- Compound Identity Graph client infrastructure already exists:
  - `CompoundIdentityModels.swift`
  - `UserIntelligenceOrchestrator.swift`
- Trust infrastructure already exists:
  - `ProofOfTrustModels.swift`
  - `TrustEventRecorder.swift`
  - `TrustScoringEngine.swift`
  - `ProofOfHumanService.swift`
  - `ProofOfCareService.swift`
- Post model already supports Action Thread denormalization in `AMENAPP/PostsManager.swift`:
  - `actionThreadId`
  - `actionThreadType`
  - `hasActiveActionThread`
- Existing trust/safety systems already in place:
  - `AIContentDetectionService`
  - `PostTrustAnalysisService`
  - `TrustByDesignMessagingControls`
  - `NewAccountRestrictionService`
  - `AntiHarassmentEngine`
  - `ModerationService`
- Existing prayer follow-through infrastructure overlaps with care workflows:
  - `AMENAPP/PrayerFollowThroughService.swift`
- Existing notification grouping and routing already exist:
  - `AMENAPP/NotificationAggregationService.swift`
  - `AMENAPP/NotificationDeepLinkRouter.swift`
- Existing Firestore rules already contain partial sections for:
  - action threads
  - intelligence data
  - trust events and snapshots
- Existing Cloud Functions already contain partial support:
  - `functions/actionThreadFunctions.js`
  - `functions/trustScoreSystem.js`
  - `functions/index.js`

## Reusable Components / Services

- `ActionSuggestionEngine` already detects prayer, distress, care, testimony, scripture, and crisis patterns.
- `ActionThreadService` already supports:
  - thread creation
  - participant invites
  - step completion
  - audit entries
  - membership denormalization
- `UserIntelligenceOrchestrator` already routes to scoped agent services and suppresses low-confidence output.
- `TrustEventRecorder` already supports append-only trust event buffering and audit-safe writes.
- `TrustScoringEngine` already computes snapshot-based proof scores with factor explanations.
- `ComposerIntegrityTracker` already captures typed vs pasted behavior and can be exported safely as `AuthenticitySignals`.
- `PrayerFollowThroughService` already schedules reminders and can feed Proof of Care signals instead of duplicating follow-up logic.

## Extension Points

- Post creation success is the cleanest existing non-UI integration point.
- Existing post flows can record:
  - composer integrity
  - post-created trust events
  - action suggestions
  - compound-agent orchestration
- Notification grouping can later extend to action-thread group keys without changing UI first.
- Existing post denormalization fields are sufficient for dark-shipped action-thread linking.

## Conflicts / Risk Areas

- Real Action Thread implementation exists in root files, while `AMENAPP/AMENAPP/ActionThreads/*` contains duplicate stub files. Those stub files should not be treated as the source of truth.
- Firestore rules currently reference a top-level `/actionThreads/{threadId}` path, while the client uses `posts/{postId}/actionThreads/{threadId}`.
- Trust rules currently only partially cover the client write paths:
  - nested `trust/events/items`
  - nested `trust/proofSnapshots/items`
  - `users/{userId}/actionSuggestions`
  - `users/{userId}/actionThreadMemberships`
  - nested intelligence recommendation storage
- There are multiple live post creation paths:
  - `FirebasePostService`
  - direct write flow in `CreatePostView`
- If integrations are only added to one path, the system will drift.

## Performance Concerns

- Avoid listener expansion for Action Threads until there is an approved visible entry point.
- Avoid recomputing trust scores on every minor event; rely on existing throttling in `TrustScoringEngine`.
- Avoid synchronous extra reads in posting flow.
- Avoid fan-out writes for action suggestions or trust snapshots.

## Security / Privacy Concerns

- Sensitive workflows must stay private by default.
- No workflow may auto-contact other users without explicit approval.
- Trust signals must remain internal and non-gamified.
- Client writes must not be authoritative for:
  - inviting participants
  - sensitive thread transitions
  - trust score mutation
- Blocked/private-account restrictions must continue to gate participation.

## What Must Not Be Touched

- Existing visible UI and interaction patterns.
- Existing moderation and safety pipelines.
- Existing app routing semantics.
- Existing attach / messaging / prayer / Berean implementations.

## What Can Be Safely Extended

- Post-success background processing
- Trust event recording
- Non-visible action suggestion persistence
- Non-visible recommendation persistence
- Feature-flagged orchestration
- Rules / indexes / backend alignment

## Backend Changes Needed

- Align Firestore rules to the real nested Action Thread paths.
- Add explicit rules for:
  - `users/{userId}/actionSuggestions`
  - `users/{userId}/actionThreadMemberships`
  - `users/{userId}/trust/events/items`
  - `users/{userId}/trust/proofSnapshots/items`
  - nested intelligence recommendation paths
- Align Cloud Functions with the client Action Thread schema.
- Add indexes for memberships, trust event timestamps, and thread-state queries where missing.

## Visible UI Change Assessment

- No visible UI change is required for the first dark-shipped infrastructure phase.
- A future visible entry point for suggestions or support workflows will require approval before implementation.
