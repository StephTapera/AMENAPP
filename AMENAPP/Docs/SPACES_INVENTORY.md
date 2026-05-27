# AMEN Spaces — Phase 0 Architecture Inventory

Generated: 2026-05-24 · Branch: audit/2026-05-21  
Status: **FROZEN — do not edit without orchestrator approval**

This document maps every existing file that Phase 0 agents must reuse, extend, or build against.
New files created in Phase 0 are listed at the bottom under "Phase 0 Output."

---

## 1. Core Spaces (EXTEND — do not replace)

| File | Path | Status | Notes |
|------|------|--------|-------|
| `Space.swift` | `AMENAPP/Space.swift` | KEEP AS-IS | Defines `AMENSpace`, `SpacePost`, `SpaceMembership`. Kept for backward compat. Phase 0 introduces `AmenSpaceV2` in `SpacesCore.swift`. |
| `SpacesViewModel.swift` | `AMENAPP/SpacesViewModel.swift` | KEEP + FIX | `toggleJoin` and `postToSpace` do direct Firestore writes — **security gap**: `spaceMemberships` write rule is `false`. Agents must route joins/posts through Cloud Function callables. |
| `SpaceFeedView.swift` | `AMENAPP/SpaceFeedView.swift` | KEEP | Feed rendering. Thin wrapper. |
| `SpacesDiscoveryView.swift` | `AMENAPP/SpacesDiscoveryView.swift` | KEEP | Delegates to `AmenSpacesDiscoverView`. |
| `CreateSpaceSheet.swift` | `AMENAPP/CreateSpaceSheet.swift` | KEEP + EXTEND | Sheet for creating a space. Needs DNA generation flow added. |
| `PostToSpaceSheet.swift` | `AMENAPP/PostToSpaceSheet.swift` | KEEP | Post composer. |
| `SpaceCardView.swift` | `AMENAPP/SpaceCardView.swift` | KEEP | Card component. |

---

## 2. Spaces Intelligence (EXISTING — already rich, do not duplicate)

| File | Path | Notes |
|------|------|-------|
| `AmenSpacesIntelligenceModels.swift` | `AMENAPP/AmenSpacesIntelligenceModels.swift` | Defines `AmenSpaceType` (12 types), `AmenMemoryNode`, `AmenSemanticPin`, `AmenAmbientSignal`, `AmenThreadBranch`, `AmenCatchUpIntelligence`, `AmenPresenceUIMode`. All server-owned fields marked. **Import via SpacesCore.swift typealiases.** |
| `AmenSpacesDiscussionDiscoveryModels.swift` | `AMENAPP/AmenSpacesDiscussionDiscoveryModels.swift` | Discussion discovery, access context, filters, trust badges, org spotlight. |
| `AmenSpacesDiscussionDiscoveryService.swift` | `AMENAPP/AmenSpacesDiscussionDiscoveryService.swift` | Service for discussion discovery. |
| `AmenSpacesDiscussionDiscoveryView.swift` | `AMENAPP/AmenSpacesDiscussionDiscoveryView.swift` | Discovery view. |
| `AmenSpaceSemanticSearchView.swift` + `AmenSmartMessageIntelligenceService.swift` | `AMENAPP/SmartMessageIntelligence/` | Space-scoped semantic search. |
| `AmenSpaceBannerRail.swift` | `AMENAPP/AmenSpaceBannerRail.swift` | Banner rail component, `AmenSpaceBannerItem`, `AmenSpaceBannerService`, glass-styled cards. |

---

## 3. Berean AI (REUSE — five modes exist, do not reinvent)

| File | Path | Notes |
|------|------|-------|
| `BereanCoreService.swift` | `AMENAPP/BereanCoreService.swift` | **The AI nervous system.** Defines `AMENSurface` (18 surfaces), `AITaskCategory` (30+ categories), `BereanAIRequest`. All AI calls must use this. |
| `BereanModeEngine.swift` | `AMENAPP/BereanModeEngine.swift` | Three theological lenses: Wisdom / Prayer / Discernment. Lenses are style modifiers — AI speaks as Berean, never roleplays. |
| `BereanConversationService.swift` | `AMENAPP/BereanConversationService.swift` | Conversation session management. |
| `BereanChatSessionManager.swift` | `AMENAPP/BereanChatSessionManager.swift` | Per-session state. |
| `BereanIntegrationService.swift` | `AMENAPP/BereanIntegrationService.swift` | Cross-surface integration hooks. |
| `BereanChurchNotesBridge.swift` | `AMENAPP/BereanChurchNotesBridge.swift` | Church Notes ↔ Berean bridge. |
| `BereanGenkitService.swift` | `AMENAPP/BereanGenkitService.swift` | Firebase Genkit callable proxy. |
| `BereanRAGService.swift` | `AMENAPP/BereanRAGService.swift` | Retrieval-augmented generation. |
| `BereanScriptureEngine.swift` | `AMENAPP/BereanScriptureEngine.swift` | Scripture resolution. |
| `BereanDoctrineChecker.swift` | `AMENAPP/BereanDoctrineChecker.swift` | Doctrine safety check. |
| `BereanVoiceSessionManager.swift` | `AMENAPP/AIIntelligence/BereanVoiceSessionManager.swift` | Voice session. |
| `BereanRealtimeServices.swift` | `AMENAPP/AIIntelligence/BereanRealtimeServices.swift` | Real-time transport. |

**IMPORTANT:** `AMENSurface` needs `spaces` case added. `AITaskCategory` needs `spaceContextSummary` and `spaceMemberSuggestion` categories added. Add via extension in `SpacesCore.swift`.

---

## 4. Semantic Memory / Embeddings

| File | Path | Status | Notes |
|------|------|--------|-------|
| `LivingMemoryService.swift` | `AMENAPP/LivingMemoryService.swift` | **DISCONTINUED** | File contains only a comment: "LivingMemory removed — feature discontinued." Do NOT reference. |
| `LivingMemoryCard.swift` | `AMENAPP/LivingMemoryCard.swift` | CHECK | UI component — may need cleanup. |
| `LivingMemorySection.swift` | `AMENAPP/LivingMemorySection.swift` | CHECK | May reference discontinued service. |
| `SemanticEmbeddingService.swift` | `AMENAPP/SemanticEmbeddingService.swift` | **ACTIVE — USE THIS** | Wraps Cloud Functions for scripture recs, testimony discovery, prayer matching, Pinecone queries. This is the embedding layer. |

**Architecture note:** "Living Memory" as a product concept can live on under the Spaces namespace (ephemeral room summaries become "Living Memory artifacts"). The iOS _service_ is gone but the Cloud Functions it called may still exist. Per-Space namespace isolation must be added in Cloud Functions — see `SpacesContracts.md`. Client never calls Pinecone directly; all vector ops go through `SemanticEmbeddingService` callables.

---

## 5. Church Notes (DO NOT BREAK)

Large, healthy module. Partial inventory of key surfaces:

| File/Dir | Notes |
|----------|-------|
| `ChurchNotes/Editor/RichChurchNoteEditor.swift` | Block editor — do not touch |
| `ChurchNotes/Services/ChurchNotesPersistenceService.swift` | Persistence — do not touch |
| `ChurchNotes/Services/ChurchNotesAIService.swift` (via `AMENAPP/ChurchNotesAIService.swift`) | AI service — extend, do not replace |
| `ChurchNotes/Services/ChurchNotesCollaborationService.swift` | Collab — existing real-time collab |
| `AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesIntelligenceService.swift` | Intelligence pipeline |
| `AMENAPP/AMENAPP/ChurchNotes/Models/ChurchNotesIntelligenceModels.swift` | Intelligence models |
| `BereanChurchNotesBridge.swift` | Berean ↔ Notes bridge |

Church Notes media pipeline (new, from last audit):
- `ChurchNotesMediaProcessingModels.swift`
- `ChurchNotesMediaProcessingService.swift`  
- `ChurchNotesAudioRecorderView.swift`
- `ChurchNotesPhotoOCRCaptureView.swift`

---

## 6. Find a Church (DO NOT BREAK)

| File | Notes |
|------|-------|
| `FindChurchView.swift` | Main view — `Church` model (Codable, Identifiable), MapKit, CoreLocation |
| `ChurchDiscoveryService.swift` | Discovery service |
| `ChurchSearchService.swift` | Search service |
| `ChurchRankingService.swift` | Ranking service |
| `FindChurchGlassComponents.swift` | Glass components for Find a Church |
| `ChurchModels.swift` | Church data models |
| `ChurchDataService.swift` | Firestore data service |

---

## 7. Moderation / GUARDIAN (DO NOT BREAK — extend per Space covenant)

| File | Notes |
|------|-------|
| `ContentModerationService.swift` | Main client-side moderation service. Calls Cloud Functions. Auth-gated. |
| `ContentModerationPrompt.swift` | Prompt configuration |
| `UnifiedSafetyGate.swift` | Unified safety gate (all UGC passes through) |
| `ModerationIngestService.swift` | Ingest |
| `CommentSafetySystem.swift` | Comment safety |
| `ModerationConstitutionModels.swift` | Constitution models |
| `WellnessGuardianService.swift` | Wellness + crisis |
| `AmenSocialSafetyModels.swift` | Social safety models |
| `PrayerRoomModerationEngine.swift` | Prayer room moderation (already Space-aware) |

**GUARDIAN extension for Spaces:** Agent G must add per-space covenant configuration to `ContentModerationService`. The `AmenSpaceCovenant.moderationLevel` drives `AmenGuardianThresholds` — computed server-side, never client-written.

---

## 8. Design System (REUSE ONLY — do not reinvent components)

| File | Notes |
|------|-------|
| `AmenGlassComponents.swift` | `AmenGlassSurface`, `AmenGlassIconButton`. Base glass container. |
| `AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` | Additional liquid glass components |
| `AIIntelligence/LivingHero/AmenLivingHeroSystem.swift` | Living hero banner system |

**Design tokens in use:** `amenGold`, `amenPurple`, `amenBlue`, `amenBlack`, `AmenRadius.card`, `AmenOpacity.glassFill`, `AmenOpacity.shadowIdle`, `Motion.adaptive`.

---

## 9. Feature Flags (ADD TO — do not modify existing flags)

| File | Notes |
|------|-------|
| `AMENFeatureFlags.swift` | 14+ systems, Remote Config backed. `@MainActor final class`. Cannot extend with stored properties. **SpacesFeatureFlags.swift** is Phase 0 output (separate singleton). |

**Existing flags relevant to Spaces:**  
`knowledgeGraphEnabled`, `knowledgeGraphSemanticSearchEnabled`, `bereanRAGEnabled`, `bereanConversationMemoryEnabled`, `presenceIntelligenceEnabled`, `moderationV2Enabled`, `actionThreadsEnabled`, `compoundIdentityGraphEnabled`

---

## 10. Firestore Security Rules

| File | Notes |
|------|-------|
| `firestore.rules` (repo root) | **Primary rules file.** Already has `isSpaceMember()` helper, membership-gated `match /spaces/{spaceId}` at line 621, and many subcollection rules. |
| `AMENAPP/firestore.deploy.rules` | Separate deploy target. Sync with root. |

**Security gaps identified:**
1. Line 1260: duplicate `match /spaces/{docId}` allows ANY signed-in user to read any space — **must be removed or tightened** to defer to line 621's membership gate.
2. Line 1265: `spacePosts` write is `false`, but `SpaceFeedViewModel.postToSpace()` does direct client write — **the ViewModel must be fixed** to call a callable instead.
3. Line 1270: `spaceMemberships` write is `false`, but `SpacesViewModel.toggleJoin()` does direct client write — **same fix needed**.
4. No `isSpaceAdmin()` or `isSpaceModerator()` helpers — needed for admin actions and moderation queue.

---

## 11. Tests

| File | Notes |
|------|-------|
| `AMENAPPTests/AmenSpacesDiscussionDiscoveryTests.swift` | Existing Spaces discovery tests |
| `AMENAPPTests/BereanPremiumLayerTests.swift` | Berean tests |
| `AMENAPPTests/BereanIntelligenceLayerTests.swift` | Berean intelligence tests |
| `AMENAPPTests/AuditLogTests.swift` | Audit log tests |
| `AMENAPPTests/FeedSafetyFilterTests.swift` | Safety filter tests |

---

## 12. Key Security Violations to Fix Before Phase 1

| Location | Issue | Fix |
|----------|-------|-----|
| `SpacesViewModel.toggleJoin()` | Direct client write to `spaceMemberships` — blocked by rules | Route through `joinSpace` / `leaveSpace` callable |
| `SpaceFeedViewModel.postToSpace()` | Direct client write to `spacePosts` — sets `aiConfidenceScore: 0.9` hardcoded | Route through `postToSpace` callable with GUARDIAN |
| `SpacesViewModel.createSpace()` | Direct Firestore write to `spaces` collection | Route through `createSpace` callable |
| `firestore.rules` line 1260 | Broad `isSignedIn()` read on `/spaces/{docId}` overrides membership gate | Remove or restrict |

---

## Phase 0 Output (Files Created by Phase 0)

| File | Path | Purpose |
|------|------|---------|
| `SpacesCore.swift` | `AMENAPP/Spaces/SpacesCore.swift` | **Frozen contract.** `AmenSpaceV2`, `AmenRoom`, `AmenRoomPost`, `AmenSpaceMembershipV2`, `AmenScopedProfile`, `AmenSpaceRole`, `AmenGiftType`, `AmenSpaceDNA`, `AmenSpaceCovenant`, `AmenSpaceRhythm`, `AmenSpacePresence`, `AmenSpaceAIContext`. |
| `ScopedIdentityService.swift` | `AMENAPP/Spaces/ScopedIdentityService.swift` | **Privacy boundary.** Only sanctioned way to read another user's Space-specific data. |
| `BereanSpaceMemberContract.swift` | `AMENAPP/Spaces/BereanSpaceMemberContract.swift` | **Berean-as-member protocol.** Interface for @mention, DM, proactive hooks, cited recall. |
| `SpacesFeatureFlags.swift` | `AMENAPP/Spaces/SpacesFeatureFlags.swift` | **15 kill switches.** Separate from `AMENFeatureFlags`. Remote Config backed. |
| `SPACES_INVENTORY.md` | `AMENAPP/Docs/SPACES_INVENTORY.md` | This file. |
| `SPACES_CONTRACTS.md` | `AMENAPP/Docs/SPACES_CONTRACTS.md` | Frozen interface contracts. |

**NOTE:** All four Swift files must be added to the Xcode target (AMENAPP) in `project.pbxproj` before they will compile.
