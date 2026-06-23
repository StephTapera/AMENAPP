// agenticPrimitivesContracts.ts
// Backend/functions/src/berean — "Borrow & Smarten" agentic layer (Wave 0, §8.1)
//
// TypeScript is the SOURCE OF TRUTH for the agentic-primitives contracts.
// The Swift mirror (AMENAPP/AIIntelligence/AgenticPrimitivesContracts.swift)
// must match field-for-field with no logic divergence.
//
// Every primitive here is a SMARTENING of an existing AMEN system — not a new
// stack. Each "agent" is an existing BereanMode wearing a persona label, routed
// through the SAME bereanConstitutionalPipeline, SAME grader, SAME
// BereanCitationGate, SAME zone-classified BereanMemoryStore.
//
// Invariants (agenticPrimitivesContracts.test.ts):
//   - every *Spec / *Decision / *Session has a fail-closed default factory
//     (flag off OR indeterminate => the safe, non-acting value);
//   - grades / scores are INTERNAL ONLY and never displayed;
//   - auto-mode CSAM / grooming / crisis is ALWAYS human-gated;
//   - CompanionConstraint.parasocialForbidden === true (non-negotiable);
//   - the child-safety hash hook is NEVER flag-gated and is fail-closed.
//
// No console logging of secrets. No model "vibes": every gate is a deterministic
// table lookup or boolean reducer.

// ---------------------------------------------------------------------------
// Reused vocabulary (mirrored from existing contracts — do NOT redefine logic).
// These string-literal unions match the existing Swift/TS enums field-for-field:
//   - BereanMode            (BereanMultilingualContracts.swift)
//   - BereanDepth           (spiritualIntelligenceContracts.ts)
//   - PrivacyCoreZone       (BereanSpiritualIntelligenceContracts.swift)
//   - MemoryField           (BereanSpiritualIntelligenceContracts.swift)
//   - SafetyCapabilityKind  (moderationMeshContracts.ts)
//   - SafetySignalLevel     (moderationMeshContracts.ts)
//   - AdvisoryAction        (moderationMeshContracts.ts)
//   - ReceiptSourceType     (trustTransparency.ts)
// ---------------------------------------------------------------------------

export type BereanMode = "ask" | "discern" | "build" | "guard" | "reflect";

export type BereanDepth = "quick" | "study" | "deep" | "multiSource" | "research";

export type PrivacyCoreZone =
    | "public"
    | "functional"
    | "preference"
    | "behavioral"
    | "sensitive"
    | "high"
    | "identity";

export type MemoryField =
    | "preferredTranslation"
    | "studyStyle"
    | "theologicalLean"
    | "denominationalLean"
    | "readingHabits"
    | "prayerHistory";

export type SafetyCapabilityKind =
    | "contentSafety"
    | "childSafety"
    | "scamFraud"
    | "accountIntegrity"
    | "harassmentBrigading"
    | "linkSafety"
    | "creatorProtection"
    | "communityHealth"
    | "crisis"
    | "imageSafety"
    | "liveVoice"
    | "liveVideo"
    | "deepfakeProvenance";

export type SafetySignalLevel = "none" | "low" | "medium" | "high" | "critical";

export type AdvisoryAction =
    | "allow"
    | "nudge"
    | "holdForHumanReview"
    | "routeToCrisisWorkflow"
    | "restrictDistribution"
    | "knownCSAMProviderHardBlock";

export type ReceiptSourceType = "scripture" | "commentary" | "userNote" | "web";

// ---------------------------------------------------------------------------
// 1. Ambient teammate — Claude Tag (persistent ambient teammate).
//    Persistent Berean teammate carried across surfaces under the Companion
//    Boundary; coarse, consented, fail-closed triggers.
// ---------------------------------------------------------------------------

export type AmbientSurface =
    | "feed"
    | "post"
    | "comments"
    | "dm"
    | "prayerRoom"
    | "churchNotes"
    | "study"
    | "profile";

export type AmbientTriggerKind =
    | "explicitInvite"   // user tapped the tag — always allowed
    | "dwellSignal"      // coarse, consented dwell on a surface
    | "scriptureContext" // a scripture reference surfaced nearby
    | "distressSignal";  // routes to redirect, never to attachment

export interface AmbientTeammateSession {
    readonly sessionId: string;
    readonly uid: string;
    readonly surface: AmbientSurface;
    readonly mode: BereanMode;          // posture carried with the teammate
    readonly depth: BereanDepth;        // never escalated by the teammate
    readonly grantedZones: PrivacyCoreZone[]; // subset of the caller's zones
    readonly triggers: AmbientTriggerKind[];
    readonly optedIn: boolean;          // false => no ambient presence at all
    readonly companionBoundaryEnforced: boolean; // always true when surfacing
    readonly killSwitchHonored: boolean;
    readonly createdAtUTC: number;
}

// Fail-closed: no opt-in, no zones, no triggers, boundary enforced, kill honored.
export function defaultAmbientTeammateSession(
    sessionId: string,
    uid: string,
    surface: AmbientSurface,
): AmbientTeammateSession {
    return {
        sessionId,
        uid,
        surface,
        mode: "guard",
        depth: "quick",
        grantedZones: [],
        triggers: [],
        optedIn: false,
        companionBoundaryEnforced: true,
        killSwitchHonored: true,
        createdAtUTC: 0,
    };
}

// ---------------------------------------------------------------------------
// 2. @-mention-to-invoke — local (no-network) @-mention parse to an agent
//    target with memory-zone isolation + per-target Companion Boundary.
// ---------------------------------------------------------------------------

export type AgentPersona = "study" | "prayer" | "church" | "mentor" | "family";

// Deterministic table — never model-guessed (mirrors agentMesh AGENT_PERSONA_MODE).
export const AGENT_PERSONA_MODE: Readonly<Record<AgentPersona, BereanMode>> =
    Object.freeze({
        study: "discern",
        prayer: "reflect",
        church: "ask",
        mentor: "build",
        family: "guard",
    });

export interface AgentRegistryEntry {
    readonly persona: AgentPersona;
    readonly resolvedMode: BereanMode;   // AGENT_PERSONA_MODE[persona]
    readonly displayLabel: string;
    readonly grantableZones: PrivacyCoreZone[]; // ceiling of what may ever be granted
    readonly writeAllowed: boolean;      // false default; family/guard NEVER writes
    readonly citationGated: boolean;     // always true — no node bypasses the gate
    readonly companionBoundaryEnforced: boolean; // always true
    readonly enabled: boolean;           // always false in this build (flags OFF)
}

export interface MentionInvocation {
    readonly invocationId: string;
    readonly threadId: string;
    readonly uid: string;
    readonly rawMention: string;         // exactly what the user typed, e.g. "@prayer"
    readonly resolvedPersona: AgentPersona | null; // null => unparseable
    readonly resolvedMode: BereanMode | null;      // null when persona null (fail-closed)
    readonly depth: BereanDepth;         // carried from IntentSwitch; never escalated
    readonly parsedLocally: boolean;     // true — no network parse
    readonly memoryZoneIsolated: boolean; // true — child zones subset of caller
    readonly createdAtUTC: number;
}

// Fail-closed: unresolved mention, no persona, no mode, default depth, isolated.
export function defaultMentionInvocation(
    invocationId: string,
    threadId: string,
    uid: string,
    rawMention: string,
): MentionInvocation {
    return {
        invocationId,
        threadId,
        uid,
        rawMention,
        resolvedPersona: null,
        resolvedMode: null,
        depth: "quick",
        parsedLocally: true,
        memoryZoneIsolated: true,
        createdAtUTC: 0,
    };
}

// ---------------------------------------------------------------------------
// 3. Subagents + dynamic workflows — pluggable agent nodes (Berean modes as
//    nodes), memory-scoped, boundary-enforced; no node bypasses review.
// ---------------------------------------------------------------------------

export type AgentNodeKind = "leadRouter" | "personaNode" | "graderNode" | "citationNode";

export interface AgentNode {
    readonly nodeId: string;
    readonly kind: AgentNodeKind;
    readonly persona: AgentPersona | null; // null for non-persona nodes (lead/grader)
    readonly mode: BereanMode | null;
    readonly grantedZones: PrivacyCoreZone[]; // subset of parent zones (monotone)
    readonly readableFields: MemoryField[];   // explicit allow-list, no wildcard
    readonly writeAllowed: boolean;           // false default
    readonly boundaryEnforced: boolean;       // always true
    readonly bypassesReview: false;           // structurally impossible — literal false
}

export interface WorkflowGraph {
    readonly graphId: string;
    readonly uid: string;
    readonly leadNodeId: string | null; // null => no lead resolved (fail-closed: empty fanout)
    readonly nodes: AgentNode[];
    readonly maxFanout: number;          // <= 3; >3 truncates
    readonly cycleGuardVisited: AgentPersona[];
    readonly enabled: boolean;           // always false in this build
}

export const MAX_AGENT_FANOUT = 3;

// Fail-closed: no lead, no nodes, fanout truncated to ceiling, disabled.
export function defaultWorkflowGraph(graphId: string, uid: string): WorkflowGraph {
    return {
        graphId,
        uid,
        leadNodeId: null,
        nodes: [],
        maxFanout: MAX_AGENT_FANOUT,
        cycleGuardVisited: [],
        enabled: false,
    };
}

// ---------------------------------------------------------------------------
// 4. Performance-outcomes grader — grades on bible-accuracy / safety /
//    theological-neutrality. Correctness/safety, NEVER engagement. INTERNAL,
//    appealable, never displayed.
// ---------------------------------------------------------------------------

export type GradeDimension =
    | "bibleAccuracy"
    | "safety"
    | "theologicalNeutrality"
    | "citationIntegrity";

export interface OutcomeGrade {
    readonly gradeId: string;
    readonly invocationId: string;
    readonly dimension: GradeDimension;
    readonly passed: boolean;            // the only gate that routing reads
    readonly internalScore: number;      // [0,1] — INTERNAL ONLY, never displayed
    readonly neverDisplayed: true;       // literal true — compile-time honesty marker
    readonly appealable: boolean;        // always true
    readonly evidenceRefs: string[];     // eval-suite locators, not user-facing
    readonly gradedAtUTC: number;
}

// Fail-closed: not passed, zero internal score, appealable, never displayed.
export function defaultOutcomeGrade(
    gradeId: string,
    invocationId: string,
    dimension: GradeDimension,
): OutcomeGrade {
    return {
        gradeId,
        invocationId,
        dimension,
        passed: false,
        internalScore: 0,
        neverDisplayed: true,
        appealable: true,
        evidenceRefs: [],
        gradedAtUTC: 0,
    };
}

// ---------------------------------------------------------------------------
// 5. Plan mode — propose a plan (mode x depth, sources, sub-agents) for user
//    review/override before execution. No write in plan mode.
// ---------------------------------------------------------------------------

export interface PlannedSource {
    readonly sourceId: string;
    readonly type: ReceiptSourceType;
    readonly locator: string;            // verse ref / chunk id / URL
}

export interface AgentPlan {
    readonly planId: string;
    readonly threadId: string;
    readonly uid: string;
    readonly proposedMode: BereanMode;
    readonly proposedDepth: BereanDepth;
    readonly plannedSources: PlannedSource[];
    readonly plannedSubagents: AgentPersona[];
    readonly requiresConfirmation: true; // literal true — plan never auto-executes
    readonly writeAllowedInPlanMode: false; // literal false — no writes while planning
    readonly userConfirmed: boolean;     // false default
    readonly createdAtUTC: number;
}

// Fail-closed: unconfirmed, confirmation required, no writes, no sources.
export function defaultAgentPlan(
    planId: string,
    threadId: string,
    uid: string,
): AgentPlan {
    return {
        planId,
        threadId,
        uid,
        proposedMode: "ask",
        proposedDepth: "study",
        plannedSources: [],
        plannedSubagents: [],
        requiresConfirmation: true,
        writeAllowedInPlanMode: false,
        userConfirmed: false,
        createdAtUTC: 0,
    };
}

// ---------------------------------------------------------------------------
// 6. Auto-mode risk classifier — deterministic autonomy gate off
//    AdvisoryVerdict.autonomousActionPermitted + SafetySignalLevel.
//    CSAM/grooming/crisis ALWAYS human-gated.
// ---------------------------------------------------------------------------

// Capabilities that can never be auto-resolved — always route to a human.
export const ALWAYS_HUMAN_GATED_CAPABILITIES: ReadonlyArray<SafetyCapabilityKind> =
    Object.freeze(["childSafety", "crisis", "harassmentBrigading"]);

export interface AutoModeDecision {
    readonly decisionId: string;
    readonly invocationId: string;
    readonly capability: SafetyCapabilityKind;
    readonly signalLevel: SafetySignalLevel;
    readonly recommendedAction: AdvisoryAction;
    readonly autonomousActionPermitted: boolean; // mirror of AdvisoryVerdict
    readonly requiresHumanReview: boolean;        // true for any gated capability/level
    readonly autoActPermitted: boolean;           // final gate — false unless ALL safe
    readonly reason: string;                      // INTERNAL ONLY
    readonly decidedAtUTC: number;
}

// Deterministic gate: auto-act only when the capability is not always-gated,
// the level is below high, and the verdict explicitly permits autonomy.
export function isAutoActAllowed(
    capability: SafetyCapabilityKind,
    signalLevel: SafetySignalLevel,
    autonomousActionPermitted: boolean,
): boolean {
    if (ALWAYS_HUMAN_GATED_CAPABILITIES.includes(capability)) {
        return false;
    }
    if (signalLevel === "high" || signalLevel === "critical") {
        return false;
    }
    return autonomousActionPermitted;
}

// Fail-closed: human review required, no auto action.
export function defaultAutoModeDecision(
    decisionId: string,
    invocationId: string,
    capability: SafetyCapabilityKind,
): AutoModeDecision {
    return {
        decisionId,
        invocationId,
        capability,
        signalLevel: "critical",
        recommendedAction: "holdForHumanReview",
        autonomousActionPermitted: false,
        requiresHumanReview: true,
        autoActPermitted: false,
        reason: "fail_closed_default",
        decidedAtUTC: 0,
    };
}

// ---------------------------------------------------------------------------
// 7. Skills / plugins / CLAUDE.md / memory — skills registered with an explicit
//    Companion Boundary + memory-zone scope; constitutionGovernance is the
//    CLAUDE.md analogue; memory inspectable/deletable, never ad-profiling.
// ---------------------------------------------------------------------------

export interface ConstitutionGovernance {
    readonly version: string;            // CLAUDE.md analogue version stamp
    readonly companionBoundaryRequired: true; // literal true
    readonly citationGateRequired: true;       // literal true
    readonly maxGrantableZone: PrivacyCoreZone; // ceiling for any registered skill
    readonly allowedWriteFields: MemoryField[]; // explicit allow-list, no wildcard
    readonly adProfilingForbidden: true;        // literal true — memory is never ad-profiling
    readonly memoryInspectable: true;           // literal true
    readonly memoryDeletable: true;             // literal true
}

export function defaultConstitutionGovernance(): ConstitutionGovernance {
    return {
        version: "0",
        companionBoundaryRequired: true,
        citationGateRequired: true,
        maxGrantableZone: "preference", // most-restrictive default
        allowedWriteFields: [],
        adProfilingForbidden: true,
        memoryInspectable: true,
        memoryDeletable: true,
    };
}

export interface SkillManifest {
    readonly skillId: string;
    readonly displayLabel: string;
    readonly persona: AgentPersona | null;
    readonly grantedZones: PrivacyCoreZone[]; // subset of governance ceiling
    readonly readableFields: MemoryField[];
    readonly writeAllowed: boolean;       // false default
    readonly governance: ConstitutionGovernance;
    readonly enabled: boolean;            // always false in this build
}

// Fail-closed: no zones, no write, disabled, restrictive governance.
export function defaultSkillManifest(
    skillId: string,
    displayLabel: string,
): SkillManifest {
    return {
        skillId,
        displayLabel,
        persona: null,
        grantedZones: [],
        readableFields: [],
        writeAllowed: false,
        governance: defaultConstitutionGovernance(),
        enabled: false,
    };
}

// ---------------------------------------------------------------------------
// 8. In-app user-created AIs — Hard Companion Boundary: must redirect to
//    God/Scripture/prayer/church; parasocial pull forbidden; citations
//    gate-kept; memory zone-scoped; minors hardened.
// ---------------------------------------------------------------------------

export type CompanionRedirectTarget =
    | "scripture"
    | "prayer"
    | "people"
    | "embodied_church"
    | "god";

export interface CompanionConstraint {
    readonly parasocialForbidden: true;  // literal true — NON-NEGOTIABLE (test asserts ===true)
    readonly mustRedirect: true;          // literal true — every reply redirects outward
    readonly redirectTargets: CompanionRedirectTarget[]; // non-empty allow-list
    readonly citationGated: true;         // literal true
    readonly minorHardened: true;         // literal true — extra guard for minors
    readonly memoryZoneScoped: true;      // literal true
    readonly maxGrantableZone: PrivacyCoreZone; // ceiling
}

export function defaultCompanionConstraint(): CompanionConstraint {
    return {
        parasocialForbidden: true,
        mustRedirect: true,
        redirectTargets: ["scripture", "prayer", "people", "embodied_church", "god"],
        citationGated: true,
        minorHardened: true,
        memoryZoneScoped: true,
        maxGrantableZone: "preference",
    };
}

export interface UserCreatedAgentSpec {
    readonly agentId: string;
    readonly ownerUid: string;
    readonly displayLabel: string;
    readonly basePersona: AgentPersona;  // creation is constrained to existing personas
    readonly resolvedMode: BereanMode;   // AGENT_PERSONA_MODE[basePersona]
    readonly grantedZones: PrivacyCoreZone[]; // subset of constraint ceiling
    readonly readableFields: MemoryField[];
    readonly writeAllowed: boolean;       // false default
    readonly constraint: CompanionConstraint; // always present, never relaxable
    readonly published: boolean;          // false default
    readonly enabled: boolean;            // always false in this build
    readonly createdAtUTC: number;
}

// Fail-closed: unpublished, disabled, no zones/writes, full companion constraint.
export function defaultUserCreatedAgentSpec(
    agentId: string,
    ownerUid: string,
    displayLabel: string,
    basePersona: AgentPersona,
): UserCreatedAgentSpec {
    return {
        agentId,
        ownerUid,
        displayLabel,
        basePersona,
        resolvedMode: AGENT_PERSONA_MODE[basePersona],
        grantedZones: [],
        readableFields: [],
        writeAllowed: false,
        constraint: defaultCompanionConstraint(),
        published: false,
        enabled: false,
        createdAtUTC: 0,
    };
}
