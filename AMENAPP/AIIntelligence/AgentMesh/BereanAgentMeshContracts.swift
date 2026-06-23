// BereanAgentMeshContracts.swift
// AMENAPP — Berean Tag-an-Agent Mesh (Feature B), Wave 0 contracts.
//
// Swift mirror of Backend/functions/src/berean/agentMeshContracts.ts.
// TypeScript is source of truth; keep these field-for-field. Add no behavior here
// beyond the deterministic helpers; later waves consume these contracts.
//
// NOT a parallel stack (AM-5): each "agent" is an existing BereanMode wearing a
// persona label, routed through the SAME bereanConstitutionalPipeline callable,
// SAME grader, SAME BereanCitationGate, SAME zone-classified BereanMemoryStore.
//
// Reused upstream types (do NOT redefine — read their files):
//   - AgentPersona (+ .resolvedMode)  → AIIntelligence/AgenticPrimitivesContracts.swift
//   - BereanMode                      → BereanOS/BereanMultilingualContracts.swift
//   - BereanDepth                     → AIIntelligence/BereanSpiritualIntelligenceContracts.swift
//   - PrivacyCoreZone                 → AIIntelligence/BereanSpiritualIntelligenceContracts.swift
//   - MemoryField                     → AIIntelligence/BereanSpiritualIntelligenceContracts.swift
//   - CitationVerdict                 → AIIntelligence/BereanSpiritualIntelligenceContracts.swift
//
// AgentPersona and its deterministic persona→mode table already live in
// AgenticPrimitivesContracts.swift (the §8.1 agentic layer). The mesh shares that
// one persona table; this file only adds the new mesh-routing/verdict types.
//
// Flag: bereanAgentMesh (Remote Config key "berean_agent_mesh_enabled", default OFF).

import Foundation

// MARK: - Fanout ceiling (AM-4)

/// Max personas a single lead may fan out to. >3 is a contract violation.
/// Mirrors MAX_AGENT_FANOUT in agentMeshContracts.ts.
let MAX_AGENT_FANOUT = 3

// MARK: - Agent Invocation

struct AgentInvocation: Codable, Identifiable, Sendable {
    /// `id` is the invocation identifier.
    var id: String { invocationId }
    let invocationId: String
    let threadId: String
    let uid: String
    /// Exactly what the user typed, e.g. "@prayer".
    let rawTag: String
    /// Deterministic table lookup, never model-guessed.
    let persona: AgentPersona
    /// persona.resolvedMode; redundant-by-design for audit.
    let resolvedMode: BereanMode
    /// Carried from IntentSwitch; never escalated by the agent.
    let depth: BereanDepth
    let query: String
    let isLeadRouterFanout: Bool
    let parentInvocationId: String?
    let createdAtUTC: TimeInterval
}

// MARK: - Agent Route (AM-4)

/// Routing basis for a fanout decision. Mirrors the TS union.
enum AgentRoutingBasis: String, Codable, Sendable {
    case explicitTag     = "explicit_tag"
    case intentProposal  = "intent_proposal"
    case defaultLead     = "default_lead"
}

struct AgentRoute: Codable, Sendable {
    let invocationId: String
    /// Always the single lead. Mirrors the TS literal "lead".
    let leadPersona: String
    let fanout: [AgentPersona]
    /// >3 is a contract violation -> truncate. Mirrors the TS literal 3.
    let maxFanout: Int
    let cycleGuardVisited: [AgentPersona]
    let routingBasis: AgentRoutingBasis
    // fail-closed: flag off OR basis indeterminate -> [] (lead answers alone).
}

// MARK: - Agent Memory Scope (AM-2)

struct AgentMemoryScope: Codable, Sendable {
    let invocationId: String
    let uid: String
    /// Subset of caller's zones; high/sensitive => per-turn opt-in.
    let grantedZones: [PrivacyCoreZone]
    /// Explicit allow-list, no wildcard.
    let readableFields: [MemoryField]
    /// false default; family/guard NEVER writes.
    let writeAllowed: Bool
    /// false => prayerHistory can't leak into study fanout.
    let crossPersonaShareAllowed: Bool
    /// AM-2: child zones ⊆ parent zones (monotone).
    let inheritedFromInvocationId: String?
}

// MARK: - Ambient Nudge Policy (AM-3)

enum AmbientNudgeRedirectTarget: String, Codable, Sendable {
    case scripture       = "scripture"
    case prayer          = "prayer"
    case people          = "people"
    case embodiedChurch  = "embodied_church"
}

struct AmbientNudgePolicy: Codable, Sendable {
    let uid: String
    /// AM-3: false => zero nudges (no soft default).
    let optedIn: Bool
    let maxPerDay: Int
    /// [startHourLocal, endHourLocal].
    let quietHoursLocal: [Int]
    /// MANDATORY redirect target.
    let redirectTarget: AmbientNudgeRedirectTarget
    let lastNudgeAtUTC: TimeInterval?
    /// Always true (mirror of the TS literal `true`).
    let killSwitchHonored: Bool
}

// MARK: - Agent Reply Verdict (AM-1)

enum AgentBlockedReason: String, Codable, Sendable {
    case grader            = "grader"
    case citation          = "citation"
    case companionBoundary = "companion_boundary"
}

struct AgentReplyVerdict: Codable, Sendable {
    let invocationId: String
    let persona: AgentPersona
    /// constitutionalReview rubric.
    let graderPassed: Bool
    /// BereanCitationGate.
    let citationGatePassed: Bool
    /// Deterministic redirect check (CompanionBoundaryEnforcer).
    let companionBoundaryPassed: Bool
    /// AM-1 fail-closed: reply surfaces ONLY iff all three pass; else degraded.
    let blockedReason: AgentBlockedReason?

    /// AM-1: the reply may surface only iff all three gates passed.
    var maySurface: Bool {
        graderPassed && citationGatePassed && companionBoundaryPassed
    }
}

// MARK: - Deterministic helpers (pure — no network, no model call)

enum AgentMeshContract {
    /// AM-5: deterministic persona → mode lookup (delegates to the shared table).
    static func resolveMode(for persona: AgentPersona) -> BereanMode {
        persona.resolvedMode
    }

    /// AM-4: truncate fanout to the contract ceiling, preserving order.
    static func clampFanout(_ personas: [AgentPersona]) -> [AgentPersona] {
        Array(personas.prefix(MAX_AGENT_FANOUT))
    }

    /// AM-2: child zones must be a subset of parent zones (monotone narrowing).
    static func isMonotoneNarrowing(parentZones: [PrivacyCoreZone],
                                    childZones: [PrivacyCoreZone]) -> Bool {
        let parent = Set(parentZones)
        return childZones.allSatisfy { parent.contains($0) }
    }

    /// AM-3: a nudge may fire only when explicitly opted in.
    static func nudgesPermitted(_ policy: AmbientNudgePolicy) -> Bool {
        policy.optedIn
    }

    /// Fail-closed route: flag off OR basis indeterminate -> lead answers alone.
    static func failClosedRoute(invocationId: String) -> AgentRoute {
        AgentRoute(
            invocationId: invocationId,
            leadPersona: "lead",
            fanout: [],
            maxFanout: MAX_AGENT_FANOUT,
            cycleGuardVisited: [],
            routingBasis: .defaultLead
        )
    }
}

// MARK: - Invariant Registry

/// Asserted by the companionBoundary eval suite + the deterministic enforcers.
struct AgentMeshInvariants: Codable, Sendable {
    let noNewStack: Bool           // AM-5
    let singleLead: Bool           // AM-4
    let maxFanout: Int             // AM-4
    let cycleGuarded: Bool         // AM-4
    let failClosedReply: Bool      // AM-1
    let monotoneMemory: Bool       // AM-2
    let nudgesOptInOnly: Bool      // AM-3
    let boundaryIsStructural: Bool // AM-6

    static let frozen = AgentMeshInvariants(
        noNewStack: true,
        singleLead: true,
        maxFanout: 3,
        cycleGuarded: true,
        failClosedReply: true,
        monotoneMemory: true,
        nudgesOptInOnly: true,
        boundaryIsStructural: true
    )
}
