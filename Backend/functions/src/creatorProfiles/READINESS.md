# Creator Profiles — Build Readiness Report

**Date:** 2026-06-18 · **Feature:** AMEN Creator Profiles (ministry hubs) · **Flags:** all 10 default OFF
**Branch discipline:** nothing pushed/deployed by agent. Tracked edits additive-only (199 insertions, 0 deletions). No `project.pbxproj` edits.

## Wave status

| Wave | Status | Evidence |
|---|---|---|
| 0 — Contracts (TS + Swift mirror) frozen | ✅ | `swiftc -parse` 0, `tsc` clean, `WAVE0_FREEZE.md` |
| 1 — Backend (13 callables + foundation) | ✅ | `tsc --strict` clean for all `creatorProfiles/*` (5 unrelated pre-existing errors remain in `billing/`+`ingestion/`) |
| 2 — Firestore + Storage rules + emulator tests | ✅ | `creator-profiles.rules.test.ts` → **39 passed, 1 skipped** under live emulator |
| 3 — SwiftUI (22 files, skeleton-first) | ✅ (syntax) | all `swiftc -parse` 0; full type-check HUMAN-PENDING on target add |
| 4 — Grounded assistant (baseline) | ✅ baseline | `askCreatorAssistant.ts` refuse-on-unsupported + citations; GUARDIAN/Pinecone seams |
| 5 — Smart features | ◑ partial | featured-module, per-category FCM follow, replay package, Kingdom Metrics, roles, series/drafts/multi-speaker done; SCRIBE/Live-Companion/Knowledge-Graph/Discovery-integration declared as seams (below) |

## Files delivered

**Backend** `Backend/functions/src/creatorProfiles/` — `creatorProfileTypes.ts` (source of truth), `creatorProfilesFlags.ts`, `creatorProfilesShared.ts`, `creatorProfileMappers.ts`, + 13 callables: `assembleCreatorProfile`, `pageCreatorModule`, `searchCreatorTeachings`, `manageCreatorEvent`, `rsvpCreatorEvent`, `generateEventReplayPackage`, `submitPrayerRequest`, `submitCommunityPost`, `moderateCreatorContent`, `askCreatorAssistant`, `processTeachingMedia`, `computeKingdomMetrics`, `enqueueCreatorMedia`. Exports wired in `index.ts`.

**Rules** root `firestore.rules` (+132 lines) and `storage.rules` (+46) — namespaced `creatorHub*` collections; the deploying files per `firebase.json`.

**Test** `Backend/rules-tests/creator-profiles.rules.test.ts` (points at live root rules).

**iOS** `AMENAPP/AMENAPP/CreatorProfiles/` (22 files): `CreatorProfilesContracts.swift`, `CreatorHubService.swift`, `CreatorHubSkeletons.swift`, `CreatorHubHeroHeader.swift`, `LiquidGlassPillBar.swift`, `CreatorProfileView.swift`, `FeaturedSmartModuleCard.swift`, `EventCard.swift`, `EventListModule.swift`, `TeachingCard.swift`, `TeachingLibraryModule.swift`, `TeachingSearchView.swift`, `CoursesModule.swift`, `ResourceCard.swift`, `ResourceCenterModule.swift`, `PrayerRequestComposer.swift`, `PrayerBoardModule.swift`, `CommunityModule.swift`, `CreatorAssistantView.swift`, `KingdomMetricsModule.swift`, `ModerationQueueView.swift`, `UnifiedTimelineView.swift`.

## Acceptance evidence (§13)

| Item | Status | Evidence |
|---|---|---|
| Contracts frozen; Swift mirror compiles | PASS | `swiftc -parse` 0; `WAVE0_FREEZE.md` checksums |
| 10 flags present, default OFF | PASS | `creatorProfileTypes.ts` `CREATOR_HUB_FLAG_DEFAULTS` (all false); `creatorProfilesFlags.ts` `OFF_DEFAULTS`; `CreatorProfilesContracts.swift` `CreatorHubFlags` |
| `assembleCreatorProfile` returns full payload, one call | PASS | `assembleCreatorProfile.ts` returns `CreatorHubProfilePayload` |
| Skeleton before data; cached re-entry | PASS | `CreatorProfileView.swift` (skeleton-first + `CreatorHubService.cachedPayloads`) |
| Rules: every collection read+write, both sides emulator-tested | PASS | 39 passing assertions in `creator-profiles.rules.test.ts` |
| Moderation gating: pending UGC not public; public only after approved | PASS | tests "pending prayer is NOT readable…", "approved … IS readable", community equivalents |
| MEDIA-GATE fail-closed: quarantined/rejected media not servable | PASS | tests "quarantined object is NOT client-readable", "client cannot write the approved path" |
| Assistant: creator-scoped retrieval, citations required, refuse-on-unsupported | PASS | `askCreatorAssistant.ts` (hard-wall + refused branch); `CreatorAssistantView.swift` (refusal UI + citations) |
| No `project.pbxproj` diff | PASS | `git diff --stat -- '*.pbxproj'` empty |
| All functions target `us-east1` | PASS | every callable `onCall({ region: "us-east1", … })` |
| §3 blockers routed flag-OFF / fail-closed | PASS | see below |
| Readiness report emitted; nothing pushed/deployed | PASS | this file |

## §3 human-decision blockers (NOT resolved in code — flag-OFF / fail-closed)

- CSAM scan stays OFF → media via `enqueueCreatorMedia` is `quarantined`, never servable; Storage quarantine `read: if false`.
- COPPA child-directed → `audienceTag` captured; kids/youth surfaces NOT enabled (needs counsel).
- Transcription transport → `processTeachingMedia` `transport: "deferred"`, behind flag.
- Raw-media retention → none by default.
- Donations → `creator_support_donations_enabled` OFF; Support button hidden unless flag true.
- Search backend → Pinecone seam only; **no Algolia reintroduced** (verified — no Algolia import in `creatorProfiles/`).

## §4 reuse corrections (affect future waves)

- **Living Memory iOS client DISCONTINUED** → assistant/search grounding uses a Firestore keyword baseline now, with a `// TODO(pinecone)` seam to backend Pinecone (`bereanChat`). No vector RAG yet.
- **SCRIBE not implemented** → Smart-Notes / Live-Companion deferred.
- **Hero**: extends the existing `.creator` `HeroSurface.kind` per your decision (`HeroSurface.creatorHubSurface` in `CreatorHubHeroHeader.swift`, `#if canImport(AdaptiveHeroEngine)`). ⚠ Verify it does not conflict with the existing `.creator` (UserModel) usage when wired.

## Declared seams / follow-ups (not built — would touch hot files or absent systems)

- Discovery integration (feed approved creator content into `assembleDiscoveryFeed`) — touches the live discovery function; do on a quiet tree.
- "Can I attend?" dedicated check, Event-Prep pack, Live Companion (needs SCRIBE), Creator Knowledge Graph.
- Team/Org multi-campus UI (roles + rules scaffolding exists).

## HUMAN STEPS (broker protocol — agent does NOT run these)

1. **Add the 22 iOS files + (if desired) the new module to the Xcode target** via Xcode UI (no pbxproj hand-edit). Add to AMENAPP target.
2. **Wire the flag** in `AMENFeatureFlags.swift` (declare `creatorProfilesEnabled` etc. default false) and add the 10 keys to `remoteconfig.template.json`. Create Firestore `system/creatorProfileFlags` doc (all camel fields false) for the **server** gate.
3. **Canonical build** (acquire `.build-lock` first):
   `xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build -clonedSourcePackagesDirPath ./SourcePackages.nosync -derivedDataPath ./DerivedData.nosync`
   Expect first-pass fixes from full type-check (cross-module symbols only validated at build).
4. **Commit (path-scoped — do NOT `git add -A`; tree is hot):**
   `git add AMENAPP/AMENAPP/CreatorProfiles Backend/functions/src/creatorProfiles Backend/rules-tests/creator-profiles.rules.test.ts Backend/functions/src/index.ts firestore.rules storage.rules && git commit -m "feat(creator): Creator Profiles ministry hubs (flags OFF)"`
5. **Per-function deploys** (creator codebase, us-east1), e.g.:
   `firebase deploy --only functions:creator:assembleCreatorProfile --project amen-5e359` … (repeat for all 13).
6. **Rules deploy:** `firebase deploy --only firestore:rules --project amen-5e359` and `firebase deploy --only storage --project amen-5e359`.
7. **Rules test (full):** run under co-started emulators to also cover the skipped manager-upload case:
   `firebase emulators:exec --only firestore,storage "cd Backend/rules-tests && npx jest creator-profiles"`.
