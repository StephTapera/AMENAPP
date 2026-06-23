// AgenticPrimitivesContracts.swift
// AMENAPP — Berean "Borrow & Smarten" agentic layer (Wave 0, §8.1)
//
// Swift mirror of Backend/functions/src/berean/agenticPrimitivesContracts.ts.
// TypeScript is the source of truth — this file matches it field-for-field with
// NO behavior divergence. Contract-only: routing/enforcement land in later waves.
//
// Reused existing types (do NOT redefine them here):
//   - BereanMode             (BereanMultilingualContracts.swift)
//   - BereanDepth            (BereanSpiritualIntelligenceContracts.swift)
//   - PrivacyCoreZone        (BereanSpiritualIntelligenceContracts.swift)
//   - MemoryField            (BereanSpiritualIntelligenceContracts.swift)
//   - IntentProposal         (BereanSpiritualIntelligenceContracts.swift)
//   - SafetyCapabilityKind   (ModerationMeshContracts.swift)
//   - SafetySignalLevel      (ModerationMeshContracts.swift)
//   - AdvisoryAction         (ModerationMeshContracts.swift)
//   - AdvisoryVerdict        (ModerationMeshContracts.swift)
//   - ReceiptSourceType      (TrustTransparencyContracts.swift)
//
// Every spec/decision/session has a fail-closed default. Grades/scores are
// INTERNAL ONLY and never displayed. Auto-mode CSAM/grooming/crisis is always
// human-gated. CompanionConstraint.parasocialForbidden is always true.

import Foundation

// MARK: - 1. Ambient teammate (Claude Tag)

enum AmbientSurface: String, Codable, CaseIterable, Sendable {
    case feed
    case post
    case comments
    case dm
    case prayerRoom
    case churchNotes
    case study
    case profile
}

enum AmbientTriggerKind: String, Codable, CaseIterable, Sendable {
    case explicitInvite   // user tapped the tag — always allowed
    case dwellSignal      // coarse, consented dwell on a surface
    case scriptureContext // a scripture reference surfaced nearby
    case distressSignal   // routes to redirect, never to attachment
}

struct AmbientTeammateSession: Codable, Identifiable, Sendable {
    var id: String { sessionId }
    let sessionId: String
    let uid: String
    let surface: AmbientSurface
    let mode: BereanMode          // posture carried with the teammate
    let depth: BereanDepth        // never escalated by the teammate
    let grantedZones: [PrivacyCoreZone] // subset of the caller's zones
    let triggers: [AmbientTriggerKind]
    let optedIn: Bool             // false => no ambient presence at all
    let companionBoundaryEnforced: Bool // always true when surfacing
    let killSwitchHonored: Bool
    let createdAtUTC: TimeInterval

    /// Fail-closed: no opt-in, no zones, no triggers, boundary enforced, kill honored.
    static func failClosed(sessionId: String, uid: String, surface: AmbientSurface) -> AmbientTeammateSession {
        AmbientTeammateSession(
            sessionId: sessionId,
            uid: uid,
            surface: surface,
            mode: .guard,
            depth: .quick,
            grantedZones: [],
            triggers: [],
            optedIn: false,
            companionBoundaryEnforced: true,
            killSwitchHonored: true,
            createdAtUTC: 0
        )
    }
}

// MARK: - 2. @-mention-to-invoke

enum AgentPersona: String, Codable, CaseIterable, Sendable {
    case study
    case prayer
    case church
    case mentor
    case family

    /// Deterministic table — never model-guessed. Mirrors AGENT_PERSONA_MODE.
    var resolvedMode: BereanMode {
        switch self {
        case .study:  return .discern
        case .prayer: return .reflect
        case .church: return .ask
        case .mentor: return .build
        case .family: return .guard
        }
    }
}

struct AgentRegistryEntry: Codable, Sendable {
    let persona: AgentPersona
    let resolvedMode: BereanMode    // persona.resolvedMode
    let displayLabel: String
    let grantableZones: [PrivacyCoreZone] // ceiling of what may ever be granted
    let writeAllowed: Bool          // false default; family/guard NEVER writes
    let citationGated: Bool         // always true — no node bypasses the gate
    let companionBoundaryEnforced: Bool // always true
    let enabled: Bool               // always false in this build (flags OFF)
}

struct MentionInvocation: Codable, Identifiable, Sendable {
    var id: String { invocationId }
    let invocationId: String
    let threadId: String
    let uid: String
    let rawMention: String          // exactly what the user typed, e.g. "@prayer"
    let resolvedPersona: AgentPersona? // nil => unparseable
    let resolvedMode: BereanMode?      // nil when persona nil (fail-closed)
    let depth: BereanDepth          // carried from IntentSwitch; never escalated
    let parsedLocally: Bool         // true — no network parse
    let memoryZoneIsolated: Bool    // true — child zones subset of caller
    let createdAtUTC: TimeInterval

    /// Fail-closed: unresolved mention, no persona, no mode, default depth, isolated.
    static func failClosed(invocationId: String, threadId: String, uid: String, rawMention: String) -> MentionInvocation {
        MentionInvocation(
            invocationId: invocationId,
            threadId: threadId,
            uid: uid,
            rawMention: rawMention,
            resolvedPersona: nil,
            resolvedMode: nil,
            depth: .quick,
            parsedLocally: true,
            memoryZoneIsolated: true,
            createdAtUTC: 0
        )
    }
}

// MARK: - 3. Subagents + dynamic workflows

enum AgentNodeKind: String, Codable, CaseIterable, Sendable {
    case leadRouter
    case personaNode
    case graderNode
    case citationNode
}

struct AgentNode: Codable, Identifiable, Sendable {
    var id: String { nodeId }
    let nodeId: String
    let kind: AgentNodeKind
    let persona: AgentPersona?      // nil for non-persona nodes (lead/grader)
    let mode: BereanMode?
    let grantedZones: [PrivacyCoreZone] // subset of parent zones (monotone)
    let readableFields: [MemoryField]   // explicit allow-list, no wildcard
    let writeAllowed: Bool              // false default
    let boundaryEnforced: Bool          // always true
    /// Structurally impossible to bypass review — always false.
    let bypassesReview: Bool
}

struct WorkflowGraph: Codable, Identifiable, Sendable {
    var id: String { graphId }
    let graphId: String
    let uid: String
    let leadNodeId: String?         // nil => no lead resolved (fail-closed: empty fanout)
    let nodes: [AgentNode]
    let maxFanout: Int              // <= 3; >3 truncates
    let cycleGuardVisited: [AgentPersona]
    let enabled: Bool               // always false in this build

    static let maxAgentFanout = 3

    /// Fail-closed: no lead, no nodes, fanout truncated to ceiling, disabled.
    static func failClosed(graphId: String, uid: String) -> WorkflowGraph {
        WorkflowGraph(
            graphId: graphId,
            uid: uid,
            leadNodeId: nil,
            nodes: [],
            maxFanout: maxAgentFanout,
            cycleGuardVisited: [],
            enabled: false
        )
    }
}

// MARK: - 4. Performance-outcomes grader (INTERNAL ONLY — never displayed)

enum GradeDimension: String, Codable, CaseIterable, Sendable {
    case bibleAccuracy
    case safety
    case theologicalNeutrality
    case citationIntegrity
}

struct OutcomeGrade: Codable, Identifiable, Sendable {
    var id: String { gradeId }
    let gradeId: String
    let invocationId: String
    let dimension: GradeDimension
    let passed: Bool                // the only gate that routing reads
    let internalScore: Double       // [0,1] — INTERNAL ONLY, never displayed
    let neverDisplayed: Bool        // always true — honesty marker
    let appealable: Bool            // always true
    let evidenceRefs: [String]      // eval-suite locators, not user-facing
    let gradedAtUTC: TimeInterval

    /// Fail-closed: not passed, zero internal score, appealable, never displayed.
    static func failClosed(gradeId: String, invocationId: String, dimension: GradeDimension) -> OutcomeGrade {
        OutcomeGrade(
            gradeId: gradeId,
            invocationId: invocationId,
            dimension: dimension,
            passed: false,
            internalScore: 0,
            neverDisplayed: true,
            appealable: true,
            evidenceRefs: [],
            gradedAtUTC: 0
        )
    }
}

// MARK: - 5. Plan mode (no write in plan mode)

struct PlannedSource: Codable, Identifiable, Sendable {
    var id: String { sourceId }
    let sourceId: String
    let type: ReceiptSourceType
    let locator: String             // verse ref / chunk id / URL
}

struct AgentPlan: Codable, Identifiable, Sendable {
    var id: String { planId }
    let planId: String
    let threadId: String
    let uid: String
    let proposedMode: BereanMode
    let proposedDepth: BereanDepth
    let plannedSources: [PlannedSource]
    let plannedSubagents: [AgentPersona]
    let requiresConfirmation: Bool  // always true — plan never auto-executes
    let writeAllowedInPlanMode: Bool // always false — no writes while planning
    let userConfirmed: Bool         // false default
    let createdAtUTC: TimeInterval

    /// Fail-closed: unconfirmed, confirmation required, no writes, no sources.
    static func failClosed(planId: String, threadId: String, uid: String) -> AgentPlan {
        AgentPlan(
            planId: planId,
            threadId: threadId,
            uid: uid,
            proposedMode: .ask,
            proposedDepth: .study,
            plannedSources: [],
            plannedSubagents: [],
            requiresConfirmation: true,
            writeAllowedInPlanMode: false,
            userConfirmed: false,
            createdAtUTC: 0
        )
    }
}

// MARK: - 6. Auto-mode risk classifier (CSAM/grooming/crisis ALWAYS human-gated)

struct AutoModeDecision: Codable, Identifiable, Sendable {
    var id: String { decisionId }
    let decisionId: String
    let invocationId: String
    let capability: SafetyCapabilityKind
    let signalLevel: SafetySignalLevel
    let recommendedAction: AdvisoryAction
    let autonomousActionPermitted: Bool // mirror of AdvisoryVerdict
    let requiresHumanReview: Bool        // true for any gated capability/level
    let autoActPermitted: Bool           // final gate — false unless ALL safe
    let reason: String                   // INTERNAL ONLY
    let decidedAtUTC: TimeInterval

    /// Capabilities that can never be auto-resolved — always route to a human.
    static let alwaysHumanGatedCapabilities: [SafetyCapabilityKind] =
        [.childSafety, .crisis, .harassmentBrigading]

    /// Deterministic gate: auto-act only when the capability is not always-gated,
    /// the level is below high, and the verdict explicitly permits autonomy.
    static func isAutoActAllowed(
        capability: SafetyCapabilityKind,
        signalLevel: SafetySignalLevel,
        autonomousActionPermitted: Bool
    ) -> Bool {
        if alwaysHumanGatedCapabilities.contains(capability) { return false }
        if signalLevel >= .high { return false }
        return autonomousActionPermitted
    }

    /// Fail-closed: human review required, no auto action.
    static func failClosed(decisionId: String, invocationId: String, capability: SafetyCapabilityKind) -> AutoModeDecision {
        AutoModeDecision(
            decisionId: decisionId,
            invocationId: invocationId,
            capability: capability,
            signalLevel: .critical,
            recommendedAction: .holdForHumanReview,
            autonomousActionPermitted: false,
            requiresHumanReview: true,
            autoActPermitted: false,
            reason: "fail_closed_default",
            decidedAtUTC: 0
        )
    }
}

// MARK: - 7. Skills / plugins / CLAUDE.md / memory

struct ConstitutionGovernance: Codable, Sendable {
    let version: String             // CLAUDE.md analogue version stamp
    let companionBoundaryRequired: Bool // always true
    let citationGateRequired: Bool      // always true
    let maxGrantableZone: PrivacyCoreZone // ceiling for any registered skill
    let allowedWriteFields: [MemoryField] // explicit allow-list, no wildcard
    let adProfilingForbidden: Bool      // always true — memory is never ad-profiling
    let memoryInspectable: Bool         // always true
    let memoryDeletable: Bool           // always true

    static func failClosed() -> ConstitutionGovernance {
        ConstitutionGovernance(
            version: "0",
            companionBoundaryRequired: true,
            citationGateRequired: true,
            maxGrantableZone: .preference, // most-restrictive default
            allowedWriteFields: [],
            adProfilingForbidden: true,
            memoryInspectable: true,
            memoryDeletable: true
        )
    }
}

struct SkillManifest: Codable, Identifiable, Sendable {
    var id: String { skillId }
    let skillId: String
    let displayLabel: String
    let persona: AgentPersona?
    let grantedZones: [PrivacyCoreZone] // subset of governance ceiling
    let readableFields: [MemoryField]
    let writeAllowed: Bool          // false default
    let governance: ConstitutionGovernance
    let enabled: Bool               // always false in this build

    /// Fail-closed: no zones, no write, disabled, restrictive governance.
    static func failClosed(skillId: String, displayLabel: String) -> SkillManifest {
        SkillManifest(
            skillId: skillId,
            displayLabel: displayLabel,
            persona: nil,
            grantedZones: [],
            readableFields: [],
            writeAllowed: false,
            governance: .failClosed(),
            enabled: false
        )
    }
}

// MARK: - 8. In-app user-created AIs (Hard Companion Boundary)

enum CompanionRedirectTarget: String, Codable, CaseIterable, Sendable {
    case scripture
    case prayer
    case people
    case embodiedChurch = "embodied_church"
    case god
}

struct CompanionConstraint: Codable, Sendable {
    let parasocialForbidden: Bool   // always true — NON-NEGOTIABLE
    let mustRedirect: Bool          // always true — every reply redirects outward
    let redirectTargets: [CompanionRedirectTarget] // non-empty allow-list
    let citationGated: Bool         // always true
    let minorHardened: Bool         // always true — extra guard for minors
    let memoryZoneScoped: Bool      // always true
    let maxGrantableZone: PrivacyCoreZone // ceiling

    static func failClosed() -> CompanionConstraint {
        CompanionConstraint(
            parasocialForbidden: true,
            mustRedirect: true,
            redirectTargets: [.scripture, .prayer, .people, .embodiedChurch, .god],
            citationGated: true,
            minorHardened: true,
            memoryZoneScoped: true,
            maxGrantableZone: .preference
        )
    }
}

struct UserCreatedAgentSpec: Codable, Identifiable, Sendable {
    var id: String { agentId }
    let agentId: String
    let ownerUid: String
    let displayLabel: String
    let basePersona: AgentPersona   // creation is constrained to existing personas
    let resolvedMode: BereanMode    // basePersona.resolvedMode
    let grantedZones: [PrivacyCoreZone] // subset of constraint ceiling
    let readableFields: [MemoryField]
    let writeAllowed: Bool          // false default
    let constraint: CompanionConstraint // always present, never relaxable
    let published: Bool             // false default
    let enabled: Bool               // always false in this build
    let createdAtUTC: TimeInterval

    /// Fail-closed: unpublished, disabled, no zones/writes, full companion constraint.
    static func failClosed(agentId: String, ownerUid: String, displayLabel: String, basePersona: AgentPersona) -> UserCreatedAgentSpec {
        UserCreatedAgentSpec(
            agentId: agentId,
            ownerUid: ownerUid,
            displayLabel: displayLabel,
            basePersona: basePersona,
            resolvedMode: basePersona.resolvedMode,
            grantedZones: [],
            readableFields: [],
            writeAllowed: false,
            constraint: .failClosed(),
            published: false,
            enabled: false,
            createdAtUTC: 0
        )
    }
}
