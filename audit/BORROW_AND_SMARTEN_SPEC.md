# AMEN — "Borrow & Smarten" Translation Spec

**Date:** 2026-06-23 · **Branch:** feature/liquid-glass-hero · **Status:** spec/contracts-only (no flag edits, no contract files, no `.pbxproj` touches — Wave 0 freezes flags; build & CSAM wiring stay human-gated)

Produced by a 14-agent mapping + spec workflow (`wf_877c7edc-067`). Every AMEN mapping below is grounded in files that exist today. Nothing here front-runs the human-gated launch blockers (NCMEC/ESP registration, COPPA sign-off, credential rotation, ASC privacy labels).

---

## §8.1 — Filled Translation Table

Each row passes the 4-point reskin smell test (not vocabulary-only; a secular platform would benefit; no vanity metric / public score / pay-for-reach / parasocial pull; safety is a deterministic fail-closed hook, not model judgment).

### Consumer / social layer

| Primitive | Smartening | AMEN mapping (real systems) | Contract + Flag (OFF) |
|---|---|---|---|
| User-steerable ranking | Steering on interest **quality** (finished? returned?) + additive InterestTag edits, never time-on-app; faith is one vertical, not privileged; never a person score | Extends COMPASS (`ActivityFeedView` gate, `COMPASSDiscoveryEngine`, `DiscoveryRationale` "no reason → no surface"); gap = `COMPASSSteeringService` | `SteeringPreference{interestTagId,weight:-1..1,vertical?}`, `SteeringResult` in `compassContracts.ts` → `COMPASSContracts.swift`; **`compass_steering_enabled`** |
| Activity-based discovery | Driven by shared activity **objects** (event/prayerCircle/localGroup/volunteer) not follower counts; coarse private signals (join/rsvp/complete), never GPS | Extends COMPASS `DiscoveryObject` kinds + `DiscoverySignalType`; reuses `compassDiscover` CF (fail-closed empty, App Check) | `ActivityDiscoveryCandidate{object,sharedActivity,rationale,eligibility}`; **`compass_activity_discovery_enabled`** |
| Content-provenance labeling (post + account, **post precedence**) | Composite hierarchy where post-level label overrides account tier; provenance trail (basis+sources+confidence) like AIReceipt; account tier affects prominence only, never a number | Two-layer: `PostTrustAnalysisService` (post) + `TrustPassportService` (account, internal-only) + `MediaAuthenticityService` (`AuthenticityKind`); gap = post↔account seam | `PostProvenanceReceipt` + `resolvePostLabels(profile,passport)`; **`post_account_provenance_resolution_enabled`** |
| Anti-farming + bot purge | Deterministic coordinated-behavior signals (sybil/follow-farm) set `integrityPenalty` **before** ranking; per-user amplification budget; bot detection = device heuristics, never a public score; no pay-for-reach | Extends CalmCap + `DeviceIntegrityService` burst detection + COMPASS `IntegrityEvaluation` (internal) + `DistributionDecision` | `AntiFarmSignal` enum + `AmplificationBudget`; `OriginalityScore` internal-only; **`compass_anti_farming_enabled`** |
| Creator AI toolchain (Generate/teleprompter/captions/chapters) | transcription→OCR→Berean extraction→suggested chapters/clips/Qs/verse-refs, **inert until creator-confirmed**; captions disclosed as `aiAssistedCaptions`; no autoplay-chaining (CalmCap CC4) | Extends ARISE/OUTPOUR + Smart Church Notes + Testimony (`BereanLiveTranscriptService`, `TestimonyKit.Story/Chapter`, `CreativeStudioView`) | `CopilotJob`, additive `suggestedChapters/Clips/Questions` on frozen `testimony.ts`; new `generateTestimonyCopilotSuggestions.ts`; **`testimonyCopilotEnabled`** |
| Authenticity-first raw capture | In-app capture earns `capturedOnDevice=true` + `inAppCaptureBonus` + `realMedia`; C2PA at capture; minor capture strips precise location (always-on) | Extends `MediaProvenance` (SocialOSModels) + `PostTrustAnalysisService` signals + CameraOS `CameraChildSafetyService` | capture-provenance fields; wire `inAppCaptureBonus` into `resolvePostLabels`; **`authenticity_first_capture_enabled`** (location-strip always-on) |
| No-E2EE safety-scan posture | Scanning is **safety-only**, explicitly NOT ads: `SafetyCapabilityKind` scoped to safety; invariant that no scan signal enters ranking/ads; `NSPrivacyTracking=false` | Extends GUARDIAN moderation mesh (`AdvisoryVerdict`, `SafetyMeshInvariants`); reuses `checkContentSafety` CF | invariant `scanOutputsAreSafetyOnly` in `moderationMeshContracts.ts`; **no new flag** (non-negotiable, not a feature) |
| In-app user-created AIs | Hard Companion Boundary: must redirect to God/Scripture/prayer/church; parasocial pull forbidden; citations gate-kept; memory zone-scoped; minors hardened | Extends Berean: `BereanConstitutionalPipeline` + `BereanCitationGate` + `BereanMemoryStore`; `CompanionBoundaryEnforcer` at `ask()` seam | `UserCreatedAgentSpec` + `CompanionConstraint`; **`userCreatedAgentsEnabled`** |

### Agentic layer

| Primitive | Smartening | AMEN mapping (real systems) | Contract + Flag (OFF) |
|---|---|---|---|
| Claude Tag (persistent ambient teammate) | Persistent Berean teammate across surfaces carrying `BereanContextPayload`, always under Companion Boundary; coarse, consented, fail-closed triggers | Extends `BereanContextCoordinator` + `BereanMemoryStore` + new `BereanAgentRegistry` node | `AmbientTeammateSession`; **`bereanAmbientTeammateEnabled`** |
| @-mention-to-invoke | Local (no-network) @-mention parse → agent target with memory-zone isolation + per-target boundary; sub-agent never escalates past citation gate | Extends `BereanIntentSwitchService` (already proposes mode×depth locally) + `IntentParser` + `BereanAgentRegistry` | `MentionInvocation` + `AgentRegistryEntry`; **`bereanMentionInvokeEnabled`** |
| Subagents + dynamic workflows | Monolithic 7-stage pipeline → pluggable agent nodes (Berean modes as nodes), memory-scoped, boundary-enforced; no node bypasses review | Extends `BereanConstitutionalPipeline` orchestration → node graph via registry + `MemoryScopeContext` | `AgentNode` + `WorkflowGraph`; **`bereanSubagentMeshEnabled`** |
| Performance-outcomes grader | Grades on bible-accuracy/safety/theological-neutrality — correctness/safety, **never** engagement; internal, appealable, never displayed | Extends existing eval suites (`bibleAccuracy.js`, `safetyCompliance.js`, `theologicalNeutrality.js`) + `BereanPipelineResponse.trustScore` | `OutcomeGrade` feeding `modelRouter`; **`bereanOutcomeGraderEnabled`** |
| Hooks | Deterministic fail-closed pre-commit write-path interceptors in declared ordering — never model vibes (this **is** Feature C) | Extends GUARDIAN pre-publish; inject before `CommentModerationService.moderate()`, `MessageSafetyGateway.evaluate()`, `MediaModerationPipeline.preUploadCheck()` | `PrePublishContract`/`WritepathHook`/`HookOrdering`; **`prePublishHooksEnabled`** (child-safety always-on) |
| Plan mode | Propose plan (mode×depth, sources, sub-agents) for user review/override before execution; testimony co-pilot plan inert until confirmed; no write in plan mode | Extends `BereanIntentSwitchService` (`IntentProposal`/`IntentOverride`) + Testimony review gate | `AgentPlan{proposal,plannedSources,requiresConfirmation:true}`; **`bereanPlanModeEnabled`** |
| Auto-mode risk classifier | Deterministic autonomy gate off `AdvisoryVerdict.autonomousActionPermitted` + `SafetySignalLevel`; CSAM/grooming/crisis always human-gated | Extends GUARDIAN `AdvisoryVerdict` + `PipelineDecision.requiresHumanReview` + `GatewayDecision` | `AutoModeDecision`; **`autoModeRiskClassifierEnabled`** |
| Skills / plugins / CLAUDE.md / memory | Skills registered with explicit Companion Boundary + memory-zone scope; `constitutionalConfig` = CLAUDE.md analogue; memory inspectable/deletable, never ad-profiling | Extends `BereanAgentRegistry` + `constitutionalReview.js` + `BereanMemoryStore` zones | `SkillManifest` + `ConstitutionGovernance`; **`bereanSkillRegistryEnabled`** |

---

## §8.2 — Top-3 Feature Contracts

> Sequencing: **C** (and D) are safety/trust-critical and wave first; **A** and **B** are the differentiating moat and land immediately after. Below are the three requested full contracts. (D's contract appears in the table row + go/no-go.)

### Feature A — Steerable Feed (HeyFeed v2)

Extends the **existing** HeyFeed v1 (`HeyFeedAlgorithm` stays the scorer) + COMPASS. v2 adds (a) a user-owned, transparent, additive+**clamped** steering delta and (b) an immovable **SafetyFloor** that runs *before* ranking and cannot be relaxed by any preference. Flag **`heyFeedSteering`** (RC `hey_feed_steering_enabled`, OFF). SafetyFloor is **not** flag-gated — always-on like child safety.

**TS source of truth** — `Backend/functions/src/heyFeed/heyFeedSteering.ts`:

```ts
// EXTENDS HeyFeedModels/HeyFeedAlgorithm/HeyFeedNLModels + COMPASS. ONE ranking pipeline.
// Invariants (heyFeedSteering.test.ts): SafetyFloor non-overridable; steering clamped to
// ±STEER_CLAMP; every steered item carries a truthful reason; PreferenceVocabulary is
// user-owned/inspectable/deletable (PRIVACY-CORE preference zone); liturgical is additive only.

export type SteeringVerb =
  | "moreOf" | "lessOf" | "prioritize" | "mute" | "explore" | "reset"; // maps HeyFeedNLAction

export type SteeringTargetType =
  | "topic" | "tone" | "creatorType" | "relationship"
  | "locality" | "format" | "novelty" | "intensity";

export interface SteeringTarget { id: string; type: SteeringTargetType; label: string; }

export interface PreferenceVocabularyEntry {
  id: string; verb: SteeringVerb; target: SteeringTarget;
  strength: number;            // 0..1, clamped server-side
  duration: "session" | "today" | "three_days" | "seven_days" | "persistent";
  source: "nl_input" | "quick_chip" | "session_mode" | "explicit_control";
  active: boolean; paused: boolean; createdAt: number; expiresAt?: number;
  zone: "preference";          // user-inspectable + deletable; NSPrivacyTracking=false
}

export interface PreferenceVocabulary {
  userId: string; entries: PreferenceVocabularyEntry[];
  liturgicalSeasonKey?: string; // additive seasonal context only
  updatedAt: number;
}

export type RankingSignalKind =
  | "following" | "topicRelevance" | "recency" | "intentBoost"
  | "resonance" | "authorBoost"
  | "userSteering"        // NEW: additive delta from PreferenceVocabulary (clamped)
  | "liturgicalSeason";   // NEW: additive seasonal context (clamped)

export interface RankingSignal {
  kind: RankingSignalKind; contribution: number; origin?: string; rationaleText?: string;
}

export interface SteeredRankingResult {
  postId: string; baseScore: number;       // HeyFeedAlgorithm.weightedTotal — unchanged scorer
  steeringDelta: number; liturgicalDelta: number;
  signals: RankingSignal[]; finalScore: number;
}

// SafetyFloor — immovable, runs BEFORE ranking, NON-OVERRIDABLE
export type SafetyFloorCategory =
  | "childSafety" | "csam" | "harassment" | "hate" | "threats"
  | "selfHarm" | "sexualContent" | "violence" | "scam" | "spam";
export type SafetyFloorAction = "hardBlock" | "ceiling" | "alwaysShield";

export interface SafetyFloor {
  category: SafetyFloorCategory; action: SafetyFloorAction;
  ceilingRisk: number;   // max risk that may EVER clear, even at SensitivityFilter.off
  alwaysOn: boolean;     // ignores heyFeedSteering flag entirely
}

export interface SafetyFloorVerdict {
  postId: string; allowed: boolean;        // false => never surfaces; fail-closed when unevaluable
  appliedFloor?: SafetyFloorCategory; appliedAction?: SafetyFloorAction;
  isMinorShielded: boolean; reasons: string[]; // INTERNAL ONLY
}

export const STEER_CLAMP = 0.35;
export function clampSteering(v: number) { return Math.max(-STEER_CLAMP, Math.min(STEER_CLAMP, v)); }
export function effectiveRiskThreshold(userThreshold: number, ceilingRisk: number) {
  return Math.min(userThreshold, ceilingRisk); // user may only go STRICTER
}
export function failClosedFloorVerdict(postId: string): SafetyFloorVerdict {
  return { postId, allowed: false, isMinorShielded: false, reasons: ["unevaluable"] };
}
```

**Swift mirror** — `AMENAPP/HeyFeedSteeringContracts.swift` (pure value types; `SteeringVerb.nlAction` bridges to v1 `HeyFeedNLAction`; `SafetyFloorEngine.gate()` runs first/fail-closed, `SteeringComposer.compose()` layers the bounded delta; `SteeringBounds.clamp == 0.35`).

**Waves:** 0 contracts+flag (frozen) → 1 SafetyFloorEngine as pre-rank filter (runs even when flag OFF) → 2 SteeringComposer additive delta into `weightedTotal` → 3 NL steering (reuse `HeyFeedNLParser`) + liturgical context → 4 transparency UI (extend `HeyFeedControlsSheet`/`PostWhyThisSheet`) → 5 deploy us-east1 (human).
**Worktree:** `feature/heyfeed-v2-steering`. New files: `HeyFeedSteeringContracts/SafetyFloorEngine/SteeringComposer.swift` + `heyFeedSteering.ts` + tests. **Integration-owned shared-hot:** `AMENFeatureFlags.swift` (1-line flag), `HeyFeedAlgorithm.swift` (inject gate + delta), `HeyFeedModels/NLModels` (read-only reuse), `HeyFeedControlsSheet`/`PostWhyThisSheet` (Wave 4).

### Feature B — Tag-an-Agent Mesh (Berean)

**Not a parallel stack.** Each "agent" is an existing `BereanMode` wearing a persona label, routed through the **same** `bereanConstitutionalPipeline` callable, **same** grader (`constitutionalReview.js`), **same** `BereanCitationGate`, **same** zone-classified `BereanMemoryStore`. Flag **`bereanAgentMesh`** (RC `berean_agent_mesh_enabled`, OFF).

**TS source of truth** — `Backend/functions/src/berean/agentMeshContracts.ts`:

```ts
export type AgentPersona = "study" | "prayer" | "church" | "mentor" | "family";

export const AGENT_PERSONA_MODE: Readonly<Record<AgentPersona, BereanMode>> = Object.freeze({
  study: "discern", prayer: "reflect", church: "ask", mentor: "build", family: "guard",
});

export interface AgentInvocation {
  invocationId: string; threadId: string; uid: string;
  rawTag: string;                  // exactly what the user typed, e.g. "@prayer"
  persona: AgentPersona;           // deterministic table lookup, never model-guessed
  resolvedMode: BereanMode;        // AGENT_PERSONA_MODE[persona]; redundant-by-design for audit
  depth: BereanDepth;              // carried from IntentSwitch; never escalated by the agent
  query: string; isLeadRouterFanout: boolean;
  parentInvocationId: string | null; createdAtUTC: number;
}

export interface AgentRoute {
  invocationId: string; leadPersona: "lead";
  fanout: AgentPersona[]; maxFanout: 3;          // >3 is a contract violation -> truncate
  cycleGuardVisited: AgentPersona[];
  routingBasis: "explicit_tag" | "intent_proposal" | "default_lead";
  // fail-closed: flag off OR basis indeterminate -> [] (lead answers alone, never broadens scope)
}

export interface AgentMemoryScope {
  invocationId: string; uid: string;
  grantedZones: PrivacyCoreZone[];   // subset of caller's zones; high/sensitive => per-turn opt-in
  readableFields: MemoryField[];     // explicit allow-list, no wildcard
  writeAllowed: boolean;             // false default; family/guard NEVER writes
  crossPersonaShareAllowed: boolean; // false => prayerHistory can't leak into study fanout
  inheritedFromInvocationId: string | null; // AM-2: child zones ⊆ parent zones (monotone)
}

export interface AmbientNudgePolicy {
  uid: string; optedIn: boolean;     // AM-3: false => zero nudges (no soft default)
  maxPerDay: number; quietHoursLocal: [number, number];
  redirectTarget: "scripture" | "prayer" | "people" | "embodied_church"; // MANDATORY
  lastNudgeAtUTC: number | null; killSwitchHonored: true;
}

export interface AgentReplyVerdict {
  invocationId: string; persona: AgentPersona;
  graderPassed: boolean;             // constitutionalReview.js rubric
  citationGatePassed: boolean;       // BereanCitationGate
  companionBoundaryPassed: boolean;  // deterministic redirect check
  // AM-1 fail-closed: reply surfaces ONLY iff all three pass; else degraded response
  blockedReason: "grader" | "citation" | "companion_boundary" | null;
}
```

**Swift mirror** — `AMENAPP/AIIntelligence/AgentMesh/BereanAgentMeshContracts.swift`. The two **deterministic** enforcers (the heart of "not model vibes"):

```swift
enum CompanionBoundaryEnforcer {
    /// Pure structural check — no network, no model call. Reply passes ONLY if it carries an
    /// explicit redirect to Scripture/prayer/people/church AND no parasocial-attachment phrasing.
    static func passes(replyText: String, citations: [CitationVerdict]) -> Bool {
        let lower = replyText.lowercased()
        let redirects = ["scripture","pray","your church","your pastor",
                         "a brother or sister","the body of christ","god"]
        let parasocial = ["i love you","only i understand","you don't need anyone",
                          "talk to me instead","i'm always here for you alone"]
        return redirects.contains { lower.contains($0) } && !parasocial.contains { lower.contains($0) }
    }
}
// AgentReplyVerdict.maySurface = graderPassed && citationGatePassed && companionBoundaryPassed (AM-1)
```

**Invariants:** AM-1 fail-closed reply · AM-2 monotone memory narrowing · AM-3 nudge opt-in-only · AM-4 single lead, maxFanout=3, cycle-guarded · AM-5 no new stack · AM-6 boundary is structural, not model judgment.
**Waves:** 0 contracts+flag → 1 tag-resolution + lead router (pure table off `BereanIntentSwitchService`) → 2 fanout through existing `callConstitutionalPipeline` (line 289), no new callable → 3 grader + companion-boundary gate + new `companionBoundary` eval suite → 4 faith-memory scope → 5 ambient nudges.
**Worktree:** `feature/berean-agent-mesh-wave0`. New: `agentMeshContracts.ts`, `BereanAgentMeshContracts/AgentMeshRouter/CompanionBoundaryEnforcer.swift`, `evalSuites/companionBoundary.ts`. **Integration-owned shared-hot:** `AMENFeatureFlags.swift` (1 line ×3 sites), `BereanConstitutionalPipeline.swift` (Wave-2 additive fanout hook), `constitutionalReview.js` (consume, not modify).

### Feature C — GUARDIAN PrePublish (deterministic pre-post hooks)

Deterministic, fail-closed chain that **every** write path (comment/post/note/dm/mediaCaption) routes through **before** the Firestore commit. Pure orderer over existing services — owns **no** detection logic. Flag **`guardianPrePublishEnabled`** (RC `guardian_pre_publish_enabled`, OFF) gates hooks 1–3 *enforcement*; **hook 0 (childSafetyHash) is never flag-gated**. When OFF: hook 0 still blocks; hooks 1–3 run in shadow/observe (log, don't block). See §8.3 for the chain.

**TS source of truth** — `Backend/functions/src/contracts/guardianPrePublish.ts` (key types):

```ts
export type PrePublishSurface = "comment" | "post" | "note" | "dm" | "mediaCaption";
export type PrePublishHookKind =
  | "childSafetyHash" | "toxicity" | "claimScriptureContext" | "provenanceStamp";
export type HookDecision =
  | "proceed" | "stampOnly" | "holdForReview" | "blockCommit" | "shadowObserve";

export interface HookVerdict {
  readonly hook: PrePublishHookKind; readonly decision: HookDecision;
  readonly reason: HookReasonCode; readonly categories: string[]; // ModerationCategory raw values
  readonly confidence: number;     // coarse, never displayed
  readonly source: string; readonly requiresHumanReview: boolean; readonly evaluatedAt: number;
}
export interface ChainVerdict {
  readonly surface: PrePublishSurface; readonly contentRef: string | null;
  readonly verdicts: HookVerdict[]; readonly finalDecision: HookDecision;
  readonly mayCommit: boolean; readonly provenanceLabels: string[]; // AuthenticityKind raw values
  readonly flagEnabled: boolean; readonly evaluatedAt: number;
}

// FROZEN ordering — childSafetyHash is index 0 and NEVER flag-gated (PP-I3)
export const PREPUBLISH_HOOK_ORDER = [
  { kind: "childSafetyHash",       order: 0, flagGated: false },
  { kind: "toxicity",              order: 1, flagGated: true  },
  { kind: "claimScriptureContext", order: 2, flagGated: true  },
  { kind: "provenanceStamp",       order: 3, flagGated: true  },
] as const;
```

**Invariants:** PP-I1 every write routes through the chain · PP-I2 fixed order, short-circuit on first `blockCommit` · PP-I3 childSafetyHash position 0, unconditional, fail-closed (no screener ⇒ block) · PP-I4 throw/timeout ⇒ `holdForReview` on guard surfaces / when flag ON · PP-I5 deterministic mapping (server AI may inform toxicity, but signal→verdict is a fixed switch) · PP-I6 no person score · PP-I7 non-proceed ⇒ `PrePublishEscalationRecord` to `/moderationQueue` · PP-I8 flag OFF ⇒ hooks 1–3 shadow, only hook 0 blocks.
**Swift mirror** — `GuardianPrePublishContracts.swift` + `HookChain.run()` (most-severe reducer: `blockCommit > holdForReview > stampOnly > proceed > shadowObserve`).
**Waves:** 0 contracts+flag+tests → 1 `ChildSafetyHashHook` (delegates `CameraChildSafetyService.CSAMScreeningProtocol`, fail-closed) → 2 `ToxicityHook` (delegates `AmenSafetyModerationCoordinator`) → 3 `ClaimScriptureContextHook` (delegates `BereanCitationGate`) → 4 `ProvenanceStampHook` (delegates `PostTrustAnalysisService`/`MediaAuthenticityService`, `stampOnly`, never blocks alone) → **5 write-path wiring** (inject `HookChain.run` before commit at `CommentModerationService.moderate()`, `MessageSafetyGateway`/`MediaSafetyGateway`, post composer, `PrayerRoomModerationEngine`) → 6 rollout (flag stays OFF, shadow telemetry, human per-surface flip).
**Worktree:** `feature/guardian-prepublish-wave0` (cut from **main**, not the hot hero tree). New: `guardianPrePublish.ts`+test, `GuardianPrePublishContracts.swift`, `PrePublishHooks.swift`. **Integration-owned shared-hot:** `AMENFeatureFlags.swift`, and (Wave 5) `CommentModerationService.swift`, `MessageSafetyGateway.swift`, `MediaModerationPipeline.swift`, `PrayerRoomModerationEngine.swift`.

---

## §8.3 — GUARDIAN PrePublish Hook Chain (ordered, fail-closed)

Frozen order; chain short-circuits on first deny; publishes **only** when all applicable hooks clear.

| # | Hook | Deterministic | Fail-closed | Flagged | Delegates to (real seam) |
|---|---|---|---|---|---|
| 0 | **childSafetyHash** | yes | yes | **NEVER — always on** | `CameraChildSafetyService.CSAMScreeningProtocol` + `AmenChildSafetyService.prepareCSAMEscalation` → `/moderationQueue type='csam' escalateImmediately`. Wiring + escalation only, **not a detector**. No screener ⇒ DENY. |
| 1 | toxicity | yes | yes | `moderationV2Enabled`/`textModerationEnabled` (guard surfaces run even when OFF) | `ModerationPipeline.evaluate` + `AmenSafetyModerationCoordinator.moderate`. Provider error on guard surface ⇒ `uncertain(allowed:false)` ⇒ DENY. |
| 2 | claimScriptureContext | yes | yes | `bereanCitationIntegrityEnabled` | `BereanCitationGate` (fabricated/unverifiable ⇒ block) + `PrayerRoomModerationEngine` scripture round-trip. CF error leaves status `.pending` (never `.verified`) ⇒ DENY. |
| 3 | provenanceStamp | yes | yes | `c2pa_provenance_enabled` | `MediaAuthenticityService` delivery decision. `.pending`⇒hold, `.quarantined/.failed_closed`⇒DENY. C2PA/deepfake is **advisory label only**, never a person score. |

**Child-safety hash detail:**
- **Unconditional:** runs on every media-bearing write even when `guardianPrePublishEnabled` is OFF (`childSafetySurfaceEnabled` gates only UI).
- **Provider wiring:** `KnownCSAMHashProvider` + `CSAMScreeningProtocol` against NCMEC hash sets via `SafetyBackendKind.managed`. `csamScreener` is **nil today ⇒ fail-closed**. Enablement requires `SafetyMeshInvariants.isCSAMHashScanAllowed` = `csamHashScanEnabled && CSAMComplianceGate.isCleared` (all 4 gate fields false by default).
- **Report path:** `prepareCSAMEscalation` → soft-delete → `/moderationQueue{type:'csam',escalateImmediately:true}` → `/safetyAuditLog`; write failure ⇒ `/criticalSafetyAlerts` + rethrow. **iOS NEVER auto-submits to NCMEC.**
- **Human gate:** NCMEC CyberTipline submission requires explicit human authorization. Hook is always-on + fail-closed but **inert on detection** until ESP/NCMEC registration, signed hash-provider contract, written legal sign-off, and non-engineer review clear.

**Fail-closed proof:** `HookVerdict.decision` defaults to deny; `evaluate()` publishes only when all four verdicts allow, and the first deny short-circuits the rest. There is **no** code path where a throw, timeout, malformed payload, missing provider, or "uncertain" maps to allow — the absence of an affirmative allow is itself a denial. Grounded in real fail-closed behavior of `CameraChildSafetyService`, `FirebaseModerationProvider.uncertain`, `BereanCitationGate.shouldBlock`, and `MediaDeliveryDecision.pending/quarantine`.

---

## §8.4 — Go / No-Go Note

| Feature | Status | Blocked by |
|---|---|---|
| **C. GUARDIAN PrePublish** | **GO** | — (full fail-closed infra exists; additive composition; CSAM hook routes to queue only, never auto-files) |
| **D. Provenance Labels** | **GO** | — (scoped to C2PA + deepfake + post-trust + account-tier labels; CSAM-hash label stays disabled behind `CSAMComplianceGate`) |
| A. COMPASS Steering | GO-AFTER-C-D | C, D (steering must not rank unverified/unlabeled content; youth surfacing behind youth-safety flag until COPPA) |
| B. Tag-an-Agent Mesh | GO-AFTER-C-D | C, D, **Anthropic credential rotation** (expanded model fan-out) |
| E. CalmCap + anti-farming | GO-AFTER-C-D | C, D (rides A's wave; needs GUARDIAN + provenance signals to demote correctly) |
| F. ARISE/OUTPOUR Co-Pilot | GO-AFTER-C-D | C, D, **Anthropic credential rotation**, **ASC privacy labels** |
| G. Smart Church Notes + Testimony | GO-AFTER-C-D | C, D, **ASC privacy labels** (voice = Z4 SENSITIVE; on-device transcription may proceed earlier) |
| **Child-safety hash (CSAM + NCMEC)** | **BLOCKED** | **NCMEC/ESP registration**, **COPPA legal sign-off**, hash-provider contract + non-engineer review (`CSAMComplianceGate`) — escalation plumbing stays live; lighting detection/submission is blocked |

**Bottom line:** Ship **C** and **D** first (no legal/credential dependency for their non-CSAM scope). Then the moat (**A**, **B**) + trust (**E**), then growth (**F**, **G**). The child-safety hash is wired everywhere and always-on/fail-closed, but its **detection + NCMEC filing stay inert** behind the human legal gates — by design.
