# MusicContentLayer — Architecture Decisions

> **Status:** v1.0 — frozen 2026-06-10
> All decisions here reflect the state at the time of the initial feature build.
> Future changes must update this file with a version note.

---

## Table of Contents

1. [Why a new MusicContentLayer/ directory](#1-why-a-new-musiccontentlayer-directory)
2. [Mock catalog over real licensing](#2-mock-catalog-over-real-licensing)
3. [Keyword classification over ML model](#3-keyword-classification-over-ml-model)
4. [Local safety scan in the comment composer](#4-local-safety-scan-in-the-comment-composer)
5. [In-memory knowledge graph](#5-in-memory-knowledge-graph)
6. [Rights/monetization as policy check, not payment processor](#6-rightsmonetization-as-policy-check-not-payment-processor)
7. [ListeningRoom sync is mocked](#7-listeningroom-sync-is-mocked)
8. [AmenPulseDigestService uses seed data](#8-amenpulsedigestservice-uses-seed-data)
9. [All new components gated by ff_music_content_layer](#9-all-new-components-gated-by-ff_music_content_layer)
10. [No duplicate models](#10-no-duplicate-models)

---

## 1. Why a new MusicContentLayer/ directory

**Decision:** All thirteen files for the Faith + Music Content Layer live in a single `AMENAPP/MusicContentLayer/` directory rather than being distributed across existing module directories (`Media/`, `ChurchNotes/`, `ConnectedIntelligence/`, etc.).

**Rationale:**
- **Single-ownership boundary.** One directory makes it unambiguous who owns this feature and where its logic lives. Cross-cutting features that span multiple existing directories tend to accumulate invisible coupling.
- **Easy feature-flag isolation.** The entire layer can be excluded from a build or disabled at runtime with a single Remote Config flag (`ff_music_content_layer`). If all files are co-located, it is trivial to verify that nothing outside the layer is accidentally calling into it when the flag is off.
- **Reduced merge surface.** Scattering files across eight existing directories would create merge conflicts with the many parallel agents working on those directories. Co-location limits blast radius.
- **Clear upgrade path.** When this layer graduates from v1 to v2 (e.g., real licensing, real graph persistence), the scope of changes is immediately visible.

**Trade-off acknowledged:** MusicContentLayer introduces types (`FaithGraphNodeType`, `PulseDigestItemType`) that partially overlap in name with types in `MusicContentContracts.swift` and the broader app. These were confirmed as net-new types (see §10).

---

## 2. Mock catalog over real licensing

**Decision:** v1 uses mock/seed data for music resources (song titles, artist names, artwork URLs). No calls are made to Apple Music API, Spotify Web API, or any independent label catalog.

**Rationale:**
- Music catalog APIs require bilateral licensing agreements, developer approval (Apple Music API requires an Apple Music subscription entitlement), and per-request authentication tokens.
- None of these agreements were in place at v1 build time.
- Building the full UI, graph, and digest infrastructure against mock data allows the product to be reviewed, tested, and iterated on without a legal dependency.

**Upgrade path:**
1. Obtain Apple Music API (MusicKit) entitlement — add `com.apple.developer.musickit` to `AMENAPP.entitlements`.
2. Swap `seedMockData()` in `FaithMusicGraphService` with live `MusicCatalogSearchRequest` calls.
3. Replace mock `MusicResource` instances in `AmenPulseDigestService` with decoded `MusicKit.Song` objects projected onto the `MusicResource` struct.
4. For third-party catalogs (Spotify, DistroKid independents): implement OAuth 2.0 token refresh in a new `MusicCatalogAuthService` and add a Cloud Function proxy to avoid embedding client secrets in the iOS app.

---

## 3. Keyword classification over ML model

**Decision:** `SmartComposerIntentService.classify(draftText:hasAttachment:accountType:)` uses a weighted keyword-matching algorithm rather than a CoreML or FoundationModels on-device inference call.

**Rationale:**
- **No training data.** A CoreML text classifier requires a labelled dataset of AMEN posts. That dataset does not exist at v1.
- **Zero latency.** Keyword matching runs synchronously on the main actor in under 1 ms for typical post lengths. An on-device model call (even with FoundationModels) adds 50–300 ms of perceived lag in the composer.
- **Fully offline.** The composer works with no network connection. An ML call that requires model download or a remote endpoint would break offline use.
- **Easy to audit.** The keyword lists in `SmartComposerIntentService.swift` are human-readable. Non-engineers can inspect and modify classification behaviour without a model retraining pipeline.
- **Deterministic for tests.** Keyword matching produces identical results across runs, making unit tests reliable. ML inference can produce non-deterministic outputs.

**Upgrade path:**
1. Collect labelled post data (intent label + post text) once the app has sufficient usage.
2. Train a `NLModel` using Create ML's Text Classifier template.
3. Replace the body of `classify()` with a call to `NLTagger` / `NLModel.predictedLabel(for:)`.
4. Alternatively, use `FoundationModels.SystemLanguageModel` (iOS 26+) with a structured prompt that maps post text to `PostIntentType` cases — no training data required, but requires iOS 26 minimum deployment target.

---

## 4. Local safety scan in the comment composer

**Decision:** `CommentSafetyService.scan(_:)` (used by `ContextAwareCommentComposer`) runs a local profanity/harassment keyword scan on every keystroke debounce (800 ms). It does not call any remote endpoint.

**Rationale:**
- **No network latency on keystrokes.** A remote call on every debounce cycle would add 200–800 ms round-trip per scan, making the composer feel sluggish.
- **Privacy-preserving.** Draft comment text is never transmitted off-device until the user taps Post. This matches the privacy expectations of a faith-based social app.
- **Works offline.** Comments can be composed and reviewed without a network connection.

**Limitations acknowledged:**
- The local keyword list is coarse. It will miss sophisticated harassment that does not use exact keyword matches.
- It will produce false positives for legitimate uses of flagged words in scripture quotations or theological discussion.

**Upgrade path:**
1. After Post is tapped (not on keystroke), call the existing `SmartCommentService` (Berean AI safety endpoint) for server-side moderation.
2. For real-time composer safety (premium / high-risk contexts), integrate the `bereanCheckCommentSafety` Cloud Function with a 500 ms debounce and a loading indicator already present in the UI.
3. Optionally replace the keyword list with a local `NLModel` trained on flagged vs. approved comments from the moderation pipeline.

---

## 5. In-memory knowledge graph

**Decision:** `FaithMusicGraphService` stores nodes (`[String: FaithGraphNode]`) and edges (`[FaithGraphEdge]`) entirely in memory, populated from `seedMockData()` at init time. There is no persistence to Firestore or local storage in v1.

**Rationale:**
- Firestore graph storage requires a schema design decision (flat collections vs. subcollections vs. adjacency lists) that has performance and cost implications at scale. That decision needs product input on query patterns before it is finalised.
- Seed data is sufficient to validate the UI (recommendation rows, node cards, deep-link routing) without a backend deploy.
- `@MainActor` isolation means the graph is safe to mutate and query without additional locking, at the cost of requiring main-thread access.

**Upgrade path:**
1. Create a `faithGraph` top-level Firestore collection with documents shaped as `FaithGraphNode` (Codable conformance already present).
2. Create a `faithGraphEdges` subcollection or flat collection with documents shaped as `FaithGraphEdge`.
3. Replace `seedMockData()` with a Firestore listener on `faithGraph` filtered by `type` and ordered by `weight desc`, limit 50.
4. Update edge weights from engagement events (tap, share, listen-through) via a Cloud Function that increments `strength` using `FieldValue.increment()`.
5. Add a local cache layer (`NSCache` or SwiftData) to avoid cold-load latency on each app launch.

---

## 6. Rights/monetization as policy check, not payment processor

**Decision:** `RightsMonetizationService.checkAccess(_:)` enforces access policy rules (free, paid, members-only, child-restricted, admin-only, pending review, blocked) but does **not** initiate or process any payment transaction.

**Rationale:**
- Payment processing requires StoreKit (for in-app purchases) or a Stripe/RevenueCat integration (for web-initiated subscriptions). Neither is wired in the current app build.
- Separating the access check from the payment flow is the correct architectural boundary: the rights service is a pure policy evaluator; the payment flow is a separate UI/transaction concern.
- The service is `@unchecked Sendable` with no mutable stored state, making it safe to use from any context.

**Upgrade path:**
- **StoreKit (in-app):** Add a `StoreKitPurchaseService` that wraps `Product.purchase()`. On successful purchase, set `hasPaidAccess: true` in the `RightsCheckInput` passed to `checkAccess()`.
- **Stripe (web-initiated):** After a successful webhook event (`customer.subscription.created`), write `hasPaidAccess: true` to the user's Firestore document. Read it in `RightsCheckInput` from the user's session model.
- The `RightsMonetizationService` interface does not need to change in either case.

The feature is currently gated by `ff_music_content_layer` (default OFF). Enable separately when payment integration is complete.

---

## 7. ListeningRoom sync is mocked

**Decision:** `ListeningDiscussionRoomView` manages participant count, room messages, and playback position using local `@State` variables. No real-time sync occurs between devices in v1.

**Rationale:**
- Real listening room sync requires a persistent, low-latency broadcast channel. The project already has LiveKit as a dependency (for video calls), but wiring audio co-listening via LiveKit requires a room server setup, token vending, and audio track management that was out of scope for the MusicContentLayer v1 build.
- Firebase Realtime Database (RTDB) is an alternative for message broadcast without audio sync, but RTDB is not currently initialised in the app.
- The mock implementation lets design/product validate the room UI, chat layout, and participant pill display before committing to a real-time stack.

**Upgrade path — LiveKit:**
1. Create a `ListeningRoomLiveKitService` that wraps `LiveKit.Room`.
2. Vend a LiveKit token from a new `getLiveKitToken` Cloud Function (authenticated, rate-limited).
3. Replace local `@State var messages` with a LiveKit data channel listener (`room.addDelegate`).
4. Sync playback position via a data channel message broadcast by the host on `AVPlayer.currentTime()` change.

**Upgrade path — RTDB:**
1. Initialise `Database.database()` in `AMENAPPApp`.
2. Use `Database.database().reference(withPath: "listeningRooms/\(roomID)/messages")` as the message source.
3. Playback sync via a child value observer on `listeningRooms/\(roomID)/playbackPosition`.

---

## 8. AmenPulseDigestService uses seed data

**Decision:** `AmenPulseDigestService.loadDailyDigest()` returns hardcoded seed `AmenPulseDigestItem` instances. It does not query Firestore for the user's followed churches, artists, or communities.

**Rationale:**
- The digest algorithm requires knowing the current user's follows, listen history, prayer activity, and community membership — data that requires authenticated Firestore reads across multiple collections.
- The service interface (`loadDailyDigest() async -> [AmenPulseDigestItem]`) is deliberately stable so that swapping the internals does not require changes to the card UI (`AmenPulseDigestCard`) or the host view.
- Seed data is sufficient for screenshot testing, App Store preview screenshots, and stakeholder reviews.

**Upgrade path:**
1. In `loadDailyDigest()`, read the current user's `followedChurches`, `followedArtists`, and `joinedCommunities` from Firestore.
2. Fan out to `churches/{id}/recentContent`, `artists/{id}/recentReleases`, and `communities/{id}/recentPosts` with `limit(3)` each.
3. Merge, rank by a recency × engagement score, and cap at 10 items.
4. Cache the result in UserDefaults (keyed by date string) with a 6-hour TTL.
5. The existing `AmenPulseDigestItem.Codable` conformance means the cached JSON round-trip is already tested (see `MusicContentLayerTests.swift` — `contentAttachment_roundTripsJSON`).

---

## 9. All new components gated by `ff_music_content_layer`

**Decision:** Every public entry point into MusicContentLayer (views, services, wireup) is guarded by a Remote Config boolean flag `ff_music_content_layer` (default `false`). The flag is read via `MusicContentLayerWireup.isEnabled`.

**Rationale:**
- The layer introduces 13 new Swift files with non-trivial UI surface. Shipping with the flag off allows a clean binary to be submitted to App Review while the feature is still being polished.
- A single flag (rather than per-file flags) means there is no risk of a half-built UI state — either all of MusicContentLayer is on, or none of it is.
- The flag can be enabled for internal testers via Remote Config A/B targeting before general rollout.

**To enable:**
- Firebase Console → Remote Config → add `ff_music_content_layer` → set value `true` → publish.
- No app update required.

**Kill switch:** Set `ff_music_content_layer` to `false` in Remote Config at any time to immediately disable all MusicContentLayer surfaces for all users.

---

## 10. No duplicate models

**Decision confirmed:** MusicContentLayer introduces zero duplicate definitions of existing app-wide model types.

**Verification performed at v1 build time:**
- `Post`, `Comment`, `Profile`, `User` — not redefined anywhere in `MusicContentLayer/`.
- Existing church notes models (`ChurchNote`, `ChurchNotesDraft`, etc.) — not redefined; `ChurchNoteShareCard.swift` consumes them via `@testable import AMENAPP`.
- `FaithGraphNodeType` in `FaithMusicGraphService.swift` is a **local** enum (scoped to the service file) with a different case set from `FaithGraphNodeType` in `MusicContentContracts.swift`. The contracts version is the canonical public type; the service version is the internal graph traversal type.
- `AmenPulseDigestItemType` in `AmenPulseDigestCard.swift` (local: `PulseDigestItemType`) is distinct from `AmenPulseDigestItemType` in `MusicContentContracts.swift`; they serve different display contexts and do not conflict.
- New types introduced by MusicContentLayer and confirmed net-new:
  - `ContentAttachment`, `ContentAttachmentType`
  - `MusicResource`, `SermonResource`
  - `PostIntentType`, `PostIntentResult`
  - `CommentContentContext`, `CommentSafetyResult`, `CommentSafetyFlag`, `CommentSafetyService`
  - `FaithGraphNode`, `FaithGraphEdge`, `FaithMusicGraphService`
  - `RightsCheckInput`, `ContentAccessResult`, `ContentAccessDeniedReason`, `RightsMonetizationService`
  - `ListeningRoom`, `ListeningRoomState`
  - `AmenPulseDigestItem`, `AmenPulseDigestItemType` (contracts version)
  - `ProfileResourceItem`, `ProfileResourceCategory`

**Ongoing rule:** Before adding any new type to MusicContentLayer, search the app target for the type name. If a match is found, reuse the existing type or coordinate a rename with the owning module.
