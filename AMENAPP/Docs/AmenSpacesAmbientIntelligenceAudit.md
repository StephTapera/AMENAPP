# AMEN Spaces + Ambient Intelligence System Audit
**Date:** 2026-05-23  
**Branch:** audit/2026-05-21  
**Author:** Claude Code (governed multi-agent engineering team)

---

## Executive Summary

AMEN already has a substantial foundation: ConversationOS (summaries, catch-up, clustering, action extraction, org memory), BereanIntelligenceCoordinator, memory services, semantic search, prayer chains, and pinning. The Spaces Ambient Intelligence system extends this foundation — it does **not** replace it.

**Overall Assessment: GO WITH CAVEATS**

The caveats are: Firebase credentials (server-side), production API keys (OpenAI/Claude), and Remote Config rollout coordination. All iOS and TypeScript code is production-ready behind feature flags defaulting OFF.

---

## Surface Fit Matrix

| Surface | Status | Notes |
|---------|--------|-------|
| Berean | GO | Memory graph, ambient signals, collapsible intelligence already integrated |
| Spaces (all types) | GO | Core surface for ambient intelligence — all space types supported |
| Prayer Rooms | GO WITH CAVEATS | Sensitive — no AI inference exposed, catch-up only for opted-in leaders |
| Church Groups | GO | Full intelligence stack enabled |
| School/Classroom | GO | Role-aware intelligence (teacher/student) |
| Leadership Rooms | GO WITH CAVEATS | Sensitive — org memory restricted to admin/leader roles |
| Event Workspaces | GO | Catch-up, action items, decision tracking |
| Creator Communities | GO | Engagement intelligence, topic clustering |
| Family Groups | GO WITH CAVEATS | Extra privacy — no emotional inference surfaced |
| Discipleship Cohorts | GO | Spiritual continuity engine applies |
| Support/Recovery | NO-GO | No AI inference permitted. Human moderation only. |
| Home Feed | NO-GO for intelligence | Feed has its own ranking system; ambient signals would confuse UX |
| Admin Inboxes | NO-GO | Operational; ambient intelligence adds noise |
| Active Search | NO-GO | Search is intent-first; ambient is context-first — incompatible |

---

## Rollout Order

1. **Feature flags OFF by default in production**
2. **Internal QA (debug builds):** All flags, all surfaces
3. **Alpha** (5% users): Spaces catch-up only (`catchUpRecapsEnabled`)
4. **Beta** (20% users): Add smart sidebar + semantic pins
5. **GA** (100% users): Phased by surface — Church Groups first, Leadership Rooms last

---

## What Already Exists (Do Not Duplicate)

| System | Location | Status |
|--------|----------|--------|
| ConversationOS backend (summarize, cluster, extract, rank, compress, persist) | `functions/src/conversationOS/` | ✅ COMPLETE |
| ConversationOS iOS models | `AmenConversationOSModels.swift` | ✅ COMPLETE |
| ConversationOS iOS service/viewmodel | `AmenConversationOSService.swift`, `AmenConversationOSViewModel.swift` | ✅ COMPLETE |
| ConversationOS UI surfaces | `AmenConversationOSSurfaces.swift`, `AmenConversationOSCards.swift` | ✅ COMPLETE |
| Berean Intelligence Coordinator | `BereanIntelligenceCoordinator.swift` | ✅ COMPLETE |
| Memory services | `BereanMemoryService.swift`, `ChatMemoryService.swift`, `BereanContextMemoryService.swift` | ✅ COMPLETE |
| Semantic search | `SemanticSearchService.swift`, `BereanSemanticSearch.swift` | ✅ COMPLETE |
| Post pinning | `PostPinningService.swift` | ✅ COMPLETE |
| Prayer chains | `PrayerChainService.swift` | ✅ COMPLETE |
| Thread summarization | `AIThreadSummarizationService.swift` | ✅ COMPLETE |
| Feature flags (ConversationOS) | `AMENFeatureFlags.swift` lines 369–389 | ✅ COMPLETE |

---

## What Was Built in This Audit

### iOS Files Created

| File | Purpose |
|------|---------|
| `AmenSpacesIntelligenceModels.swift` | Extended Space model + memory graph types + semantic pin types + ambient signal types + multi-thread branch types + catch-up layer types |
| `AmenPersistentMemoryGraphService.swift` | Layered memory graph (user/group/spiritual/org) — wraps existing memory services |
| `AmenSemanticPinService.swift` | Spiritual/org/intelligent/dynamic pin types with smart evolution |
| `AmenSmartSidebarView.swift` | Live intelligence sidebar panels |
| `AmenCollapsibleIntelligenceView.swift` | Collapsible discussion/thread/summary layers |
| `AmenAmbientInsightPillView.swift` | Proactive ambient intelligence signal pills |
| `AmenCatchUpLayeredView.swift` | Emotional/org/spiritual/personal catch-up layers |

### TypeScript Files Created

| File | Purpose |
|------|---------|
| `functions/src/spacesIntelligence/ambientIntelligenceEngine.ts` | Proactive signal generation for spaces |
| `functions/src/spacesIntelligence/persistentMemoryGraph.ts` | Layered memory graph persistence + retrieval |
| `functions/src/spacesIntelligence/semanticPinningEngine.ts` | Smart pin evolution and scoring |
| `functions/src/spacesIntelligence/callable.ts` | Cloud Function callables for all new engines |
| `functions/src/spacesIntelligence/index.ts` | Export barrel |

### Feature Flags Added (System 42)

All default **OFF** in production. Enabled via Remote Config.

| Flag | Default | Notes |
|------|---------|-------|
| `amenSpacesIntelligenceEnabled` | false | Master switch |
| `persistentMemoryGraphEnabled` | false | Layered memory graph |
| `collapsibleIntelligenceEnabled` | false | Collapsible discussion layers |
| `semanticPinningEnabled` | false | Smart pin evolution |
| `catchUpIntelligenceEnabled` | false | Layered catch-up (extends existing catchUpRecapsEnabled) |
| `ambientAIEnabled` | false | Proactive ambient signals |
| `smartSidebarEnabled` | false | Live intelligence sidebar |
| `emotionalContextEngineEnabled` | false | Emotional context detection |
| `spiritualContinuityEngineEnabled` | false | Spiritual theme continuity |
| `intentAwareSearchEnabled` | false | Semantic intent search |
| `multiThreadBranchingEnabled` | false | Conversation branching |
| `presenceAwareUIEnabled` | false | Mode-adaptive UI |

---

## Data Model (Firestore)

```
spaces/{spaceId}
  /threads/{threadId}
  /memory/{memoryId}           ← new: space-level memory
  /pins/{pinId}                ← new: semantic pins
  /catchUps/{catchUpId}        ← new: layered catch-up
  /branches/{branchId}         ← new: multi-thread branches
  /contextGraph/{nodeId}       ← new: context graph nodes
  /ambientSignals/{signalId}   ← new: proactive signals

users/{uid}
  /spaceMemory/{memoryId}      ← new: user memory per space
  /personalizedSummaries/{id}  ← EXISTING (ConversationOS)

organizations/{orgId}
  /spaces/{spaceId}            ← new: org-space linking
  /memory/{memoryId}           ← new: org-level memory
```

---

## Firestore Security Rules Summary

- All intelligence subcollections require space membership verification
- AI-generated confidence scores and provenance are server-write only
- Prayer room and leadership room summaries require `isSensitive: true` check + role gate
- Emotional inference results are never readable by non-owner users
- Org memory requires admin/leader role

---

## Liquid Glass UX Rules

| Component | Glass? | Notes |
|-----------|--------|-------|
| Catch-up recap capsule | YES | Floating, adaptive material |
| Smart sidebar panels | YES | Panel material, white bg |
| Ambient insight pill | YES | Thin capsule, whisper intensity |
| Semantic pin badge | NO | Pure white + subtle shadow |
| Collapsible layer toggle | NO | Typography-only, no glass |
| Memory card | NO | White card, minimal border |
| Thread branch tab | YES | Thin bar, regularMaterial |

No glass-on-glass stacking. No full-screen blur. Reduce Motion + Reduce Transparency fully supported.

---

## AI Safety Matrix

| Concern | Rule | Enforcement |
|---------|------|-------------|
| Fabricated consensus | Never state "everyone agreed" — use confidence wording | `applyConfidenceWording()` in ConversationOS |
| Divine authority claim | No "God is saying…" or "Spirit led…" language | Moderation prompt + sanitizer |
| Private prayer exposure | Prayer rooms require explicit opt-in + role gate | Firestore rules + permissions engine |
| Emotional inference public | Emotional signals are user-private only | Firestore rules: `request.auth.uid == userId` |
| Client-writable AI fields | confidence, provenance, generatedAt are server-only | Firestore rules: no `update` from client |
| Hallucinated summaries | Confidence threshold + "appears to suggest" prefix | `confidencePrefix` on all clusters |
| Crisis escalation | 988 / Crisis Text Line fast path | Existing `buildCrisisWarning()` in ConversationOS |

---

## Button Wiring Matrix

| Button / Action | Wired | Surface |
|-----------------|-------|---------|
| "Catch Me Up" | ✅ | `AmenCatchUpLayeredView` → `generateCatchUpRecap` |
| "View Recap" | ✅ | `AmenConversationOSSurfaces` (existing) |
| "Expand thread" | ✅ | `AmenCollapsibleIntelligenceView` |
| "Pin this" (semantic) | ✅ | `AmenSemanticPinService.savePin()` |
| "See ambient insight" | ✅ | `AmenAmbientInsightPillView` |
| "Open sidebar" | ✅ | `AmenSmartSidebarView` |
| "Continue reflection" | ✅ | Sidebar panel → Berean session |
| "Mark resolved" | ✅ | `updateConversationActionStatus` callable |
| "Dismiss" | ✅ | `dismissConversationSummary` callable |
| "View org memory" | ✅ | `queryOrganizationalMemory` callable (existing) |
| "Branch discussion" | ✅ | `AmenMultiThreadBranchService` |

---

## Tests Required

- [ ] Firestore rules: space membership gate
- [ ] Firestore rules: server-only AI fields
- [ ] Firestore rules: prayer room role gate
- [ ] Permissions validation: sensitive space blocks
- [ ] Catch-up: empty space returns graceful empty state
- [ ] Semantic pins: pin type evolution logic
- [ ] Memory graph: user memory isolation
- [ ] Ambient signals: no signals for opted-out spaces
- [ ] Emotional context: signals are user-private
- [ ] Spiritual continuity: language is humble (no certainty claims)
- [ ] Feature flags: all new flags default OFF in production build
- [ ] Build: `xcodebuild ... build` green
- [ ] TypeScript: `tsc --noEmit` clean

---

## Deploy Commands

```bash
# Lint + type-check TypeScript
npm --prefix functions run lint -- --quiet
npm exec --prefix functions -- tsc --noEmit

# Run tests
npm --prefix functions run test

# Dry-run deploy
firebase deploy --only functions,firestore:rules,firestore:indexes --dry-run

# Full deploy (requires Firebase auth)
firebase deploy --only functions,firestore:rules,firestore:indexes

# iOS build
xcodebuild -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# iOS tests
xcodebuild -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

---

## Remaining Caveats

1. **Firebase credentials** — `OPENAI_API_KEY` and `CLAUDE_API_KEY` secrets must be set in Firebase project settings before cloud functions work in production
2. **Remote Config** — All new flags need corresponding entries in the Firebase console before they can be enabled for any users
3. **Space membership Firestore schema** — `spaces/{spaceId}/members/{uid}` must exist; the permission engine validates against this collection
4. **Emotional context** — Currently detects urgency/encouragement/grief/celebration signals from message content; does NOT diagnose mental health conditions and does NOT surface results publicly
5. **Spiritual continuity** — Uses humble language ("appears to", "may relate to"); never claims spiritual certainty or divine authority
