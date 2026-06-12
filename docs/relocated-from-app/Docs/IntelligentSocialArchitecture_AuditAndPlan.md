# AMEN Intelligent Social Architecture — Audit + Implementation Plan
**Date:** 2026-04-15  
**Status:** Implementation In Progress  
**Systems:** Action Threads · Compound Identity Graph · Proof of Human + Care

---

## SECTION 1 — AUDIT SUMMARY

### What Already Exists (Do Not Duplicate)

#### A. ACTION THREADS — Partial ✅
| File | Status | Notes |
|------|--------|-------|
| `ActionThreads/ActionThreadModels.swift` | ✅ Complete | Full domain models incl. ActionThread, ActionStep, ActionSuggestion, ActionReminder, ActionThreadPermissionSet, ActionThreadAuditEntry |
| `ActionThreads/ActionSuggestionEngine.swift` | ✅ Complete | Keyword-based suggestion logic, cooldowns, confidence thresholds, ContentRiskAnalyzer integration, crisis detection, Firestore persistence |
| `ActionThreads/ActionThreadService.swift` | ⚠️ STUB | Intentionally empty — must implement |
| `ActionThreads/ActionThreadPermissionsService.swift` | ⚠️ STUB | Intentionally empty — must implement |
| `ActionThreads/ActionThreadNotificationService.swift` | ⚠️ STUB | Intentionally empty — must implement |

#### B. COMPOUND IDENTITY GRAPH — Partial ✅
| File | Status | Notes |
|------|--------|-------|
| `CompoundIdentityGraph/CompoundIdentityGraphModels.swift` | ✅ Complete | AgentType, AgentPermissionBoundary, AgentRecommendation, AgentPrioritySignal, UserContextWindow |
| `CompoundIdentityGraph/UserIntelligenceOrchestrator.swift` | ✅ Complete | Priority routing, agent evaluation, confidence filtering, Firestore persistence |
| `CompoundIdentityGraph/CompoundIdentityGraphService.swift` | ⚠️ STUB | Intentionally empty — must implement |

#### C. PROOF OF HUMAN + PROOF OF CARE — Mostly Complete ✅
| File | Status | Notes |
|------|--------|-------|
| `TrustSignals/TrustSignalModels.swift` | ✅ Complete | ProofOfHumanScore, ProofOfCareScore, TrustEvent, TrustScoreSnapshot, TrustEligibility, TrustActionConstraint |
| `TrustSignals/TrustScoringEngine.swift` | ✅ Complete | Weighted scoring, event window, snapshot persistence, throttling |
| `TrustSignals/ProofOfHumanService.swift` | ✅ Complete | Cache layer, score fetch, current user tracking |
| `TrustSignals/ProofOfCareService.swift` | ✅ Complete | Cache layer, score fetch, current user tracking |
| `TrustSignals/TrustSignalService.swift` | ⚠️ STUB | Intentionally empty — must implement trust event recording |

#### D. FEATURE FLAGS — Complete ✅
`AMENFeatureFlags.swift` has all required flags:
- `actionThreadsEnabled`, `actionSuggestionsEnabled`, `careFollowupsEnabled`
- `compoundIdentityGraphEnabled`, `agentRecommendationsEnabled`
- `proofOfHumanEnabled`, `proofOfCareEnabled`, `trustSignalsEnabled`
All default to `false`. Remote Config backed. ✅

#### E. BACKEND (Cloud Functions) — Partial ✅
| File | Status | Notes |
|------|--------|-------|
| `trustIntelligence.ts` | ✅ Exists | writeAgentInsight, writeAgentRecommendation, writeAgentExecutionLog, writeTrustEvent, writeTrustSnapshot callables |
| `notifications/types.ts` | ✅ Exists | ActionThreadInvite, ActionThreadUpdate, ActionThreadReminder notification types already defined |
| `notifications/onSocialEvent.ts` | ✅ Exists | Comprehensive notification pipeline with grouping, policies, block checks |
| Cloud Functions for Action Thread CRUD | ❌ Missing | Need: createActionThread, activateThread, completeStep, scheduleReminder |

#### F. EXISTING INTEGRATION POINTS (reusable)
- **Post model** (`PostsManager.swift`/`Post`): has `category`, `isAnsweredPrayer`, `verseReference`, `authorId`, `firebaseId`
- **PostCard.swift**: 5,690 lines, complex render system — do NOT touch UI
- **ContentRiskAnalyzer**: Used by ActionSuggestionEngine for crisis detection — confirmed exists
- **BlockService**: `blockedUsers` collection enforced
- **FollowService**: follow graph, private account logic
- **NotificationService/SmartNotificationEngine**: Full push + inbox pipeline
- **AntiHarassmentEngine**: restriction checking, enforcement ladder
- **CommentService**: comment creation hooks for trust events
- **FirebasePostService**: post creation hooks for trust events
- **ModerationService**: moderation hit tracking for trust signals

---

### What Must NOT Be Touched
- PostCard.swift UI layout (zero visible changes without approval)
- PostDetailView.swift UI
- AMENTabBar.swift navigation
- OnboardingFlowView.swift
- Any existing notification UI views
- AMENFeatureFlags.swift structure (only additive changes allowed)
- Existing Firestore security rules schema

---

### What Must Be Implemented (Gaps)
1. **ActionThreadService** — full CRUD for threads, steps, participants, audit log
2. **ActionThreadPermissionsService** — per-role permission evaluation, block/follow/private checks
3. **ActionThreadNotificationService** — thread-aware grouped notifications
4. **TrustSignalService** — trust event recording from app-layer hooks
5. **CompoundIdentityGraphService** — agent insight write abstraction
6. **Cloud Functions** — createActionThread, activateThread, completeActionStep, scheduleActionReminder

---

### Performance Concerns
- `ActionSuggestionEngine` already has per-post/cooldown dedup — safe
- `TrustScoringEngine` has 1-hour throttle per user — safe
- `UserIntelligenceOrchestrator` processes max 3 agents per evaluation — safe
- Trust event recording must be async, non-blocking, fire-and-forget
- Action thread creation must use batch writes where possible

### Security/Privacy Concerns
- All Action Thread writes must be owner-scoped (server must validate)
- Trust scores are private subcollections — rules must prevent cross-user reads
- Participants can only be invited (not auto-added) without owner approval
- Crisis resource prompts must never be surfaced publicly

### UI Changes Needed — NONE AT THIS TIME
All three systems are infrastructural. No visible UI is required to complete the service layer. When ready to activate, a UI change request will be submitted for:
- Action Thread suggestion pill in post composer completion flow
- Optional care workflow entry in post detail (owner only)

---

## SECTION 2 — IMPLEMENTATION PLAN

### Phase 1 — Service Stubs → Full Implementations
**Files to create/replace:**
1. `ActionThreads/ActionThreadService.swift` — full Firestore CRUD
2. `ActionThreads/ActionThreadPermissionsService.swift` — permission gate
3. `ActionThreads/ActionThreadNotificationService.swift` — grouped notifications
4. `TrustSignals/TrustSignalService.swift` — trust event recorder
5. `CompoundIdentityGraph/CompoundIdentityGraphService.swift` — agent insight writer

### Phase 2 — Backend Cloud Functions
**Files to create:**
1. `Backend/functions/src/actionThreads.ts` — createActionThread, activateThread, completeStep, scheduleReminder

### Phase 3 — Invisible App-Layer Wiring
**Hooks to add (no visible UI):**
1. `CreatePostView.swift` — call `ActionSuggestionEngine.evaluatePost()` after post creation
2. `CommentService.swift` — emit `meaningfulReply` trust event
3. `FirebasePostService.swift` — emit `postCreated` trust event
4. `PrayerView.swift` / prayer commitment flows — emit `prayerCommitment` trust event

### Phase 4 — Tests
Unit tests for all three systems.

### Rollback Plan
All features default to `false` in `AMENFeatureFlags`. Setting any flag to `false` in Firebase Remote Config immediately disables the feature. No data migration is needed to disable. Firestore subcollections are additive — removing them has zero impact on core app behavior.

---

## SECTION 3 — DATA MODEL (Firestore)

```
posts/{postId}/
  actionThreads/{threadId}          — ActionThread
  actionThreads/{threadId}/
    steps/{stepId}                  — ActionStep  
    participants/{participantId}    — ActionThreadParticipant
    audit/{entryId}                 — ActionThreadAuditEntry
    reminders/{reminderId}          — ActionReminder

users/{userId}/
  actionSuggestions/{suggestionId}  — ActionSuggestion (already written by ActionSuggestionEngine)
  intelligence/
    recommendations/items/{id}      — AgentRecommendation
    agentInsights/{id}              — AgentInsight (via Cloud Function)
    agentRecommendations/{id}       — (via Cloud Function)
    executionLogs/{id}              — (via Cloud Function)
  trust/
    events/items/{id}               — TrustEvent
    proofSnapshots/items/{id}       — TrustScoreSnapshot
    humanScore                      — ProofOfHumanScore (latest)
    careScore                       — ProofOfCareScore (latest)
```

---

## SECTION 4 — SECURITY MODEL

### Action Threads
- `posts/{postId}/actionThreads/{threadId}`: write = `request.auth.uid == resource.data.creatorUserId` OR server function
- Participants subcollection: only thread creator can add
- Audit log: append-only, no client deletes

### Trust Signals
- `users/{userId}/trust/**`: read/write only by `request.auth.uid == userId`
- Trust events written server-side where possible (via `writeTrustEvent` callable)
- No cross-user trust reads

### Intelligence
- `users/{userId}/intelligence/**`: read/write only by `request.auth.uid == userId`
- Agent insights written via `writeAgentInsight` callable (server-authoritative)
