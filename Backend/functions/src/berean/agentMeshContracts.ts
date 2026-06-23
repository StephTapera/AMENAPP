/**
 * agentMeshContracts.ts — Berean Tag-an-Agent Mesh, Wave 0 contracts (source of truth).
 *
 * NOT a parallel stack (AM-5). Each "agent" is an existing BereanMode wearing a
 * persona label, routed through the SAME bereanConstitutionalPipeline callable,
 * SAME grader (constitutionalReview.ts), SAME BereanCitationGate, SAME
 * zone-classified BereanMemoryStore.
 *
 * Reuse over redefine: AgentPersona, AGENT_PERSONA_MODE, BereanMode, BereanDepth,
 * PrivacyCoreZone, and MemoryField are the canonical vocabulary already frozen in
 * agenticPrimitivesContracts.ts (the §8.1 agentic layer). We import them here so
 * the mesh shares one persona table with the rest of the agentic layer. This file
 * adds only the genuinely new mesh-routing/verdict types.
 *
 * Mirrored field-for-field by
 * AMENAPP/AIIntelligence/AgentMesh/BereanAgentMeshContracts.swift.
 *
 * Flag: bereanAgentMesh (Remote Config key "berean_agent_mesh_enabled", default OFF).
 *
 * Invariants:
 *   AM-1  Reply surfaces ONLY iff grader && citation && companionBoundary all pass
 *         (fail-closed: any false / indeterminate => degraded response).
 *   AM-2  Memory scope narrows monotonically: child zones ⊆ parent zones.
 *   AM-3  Ambient nudges are opt-in only — false optedIn => zero nudges, no soft default.
 *   AM-4  Single lead, maxFanout = 3, cycle-guarded.
 *   AM-5  No new model/pipeline stack — personas map to existing BereanModes.
 *   AM-6  The companion boundary is a structural check, never model judgment.
 *
 * TypeScript is source of truth. No runtime behavior beyond the deterministic
 * helpers; later waves consume these contracts.
 */

import type {
  AgentPersona,
  BereanMode,
  BereanDepth,
  PrivacyCoreZone,
  MemoryField,
} from "./agenticPrimitivesContracts";
import { AGENT_PERSONA_MODE } from "./agenticPrimitivesContracts";

export type { AgentPersona, BereanMode, BereanDepth, PrivacyCoreZone, MemoryField };
export { AGENT_PERSONA_MODE };

/** Max personas a single lead may fan out to (AM-4). >3 is a contract violation. */
export const MAX_AGENT_FANOUT = 3;

// ---------------------------------------------------------------------------
// Invocation
// ---------------------------------------------------------------------------

export interface AgentInvocation {
  invocationId: string;
  threadId: string;
  uid: string;
  rawTag: string;                  // exactly what the user typed, e.g. "@prayer"
  persona: AgentPersona;           // deterministic table lookup, never model-guessed
  resolvedMode: BereanMode;        // AGENT_PERSONA_MODE[persona]; redundant-by-design for audit
  depth: BereanDepth;              // carried from IntentSwitch; never escalated by the agent
  query: string;
  isLeadRouterFanout: boolean;
  parentInvocationId: string | null;
  createdAtUTC: number;
}

// ---------------------------------------------------------------------------
// Route (AM-4: single lead, maxFanout=3, cycle-guarded)
// ---------------------------------------------------------------------------

export interface AgentRoute {
  invocationId: string;
  leadPersona: "lead";
  fanout: AgentPersona[];
  maxFanout: 3;                    // >3 is a contract violation -> truncate
  cycleGuardVisited: AgentPersona[];
  routingBasis: "explicit_tag" | "intent_proposal" | "default_lead";
  // fail-closed: flag off OR basis indeterminate -> [] (lead answers alone, never broadens scope)
}

// ---------------------------------------------------------------------------
// Memory scope (AM-2: monotone narrowing)
// ---------------------------------------------------------------------------

export interface AgentMemoryScope {
  invocationId: string;
  uid: string;
  grantedZones: PrivacyCoreZone[];   // subset of caller's zones; high/sensitive => per-turn opt-in
  readableFields: MemoryField[];     // explicit allow-list, no wildcard
  writeAllowed: boolean;             // false default; family/guard NEVER writes
  crossPersonaShareAllowed: boolean; // false => prayerHistory can't leak into study fanout
  inheritedFromInvocationId: string | null; // AM-2: child zones ⊆ parent zones (monotone)
}

// ---------------------------------------------------------------------------
// Ambient nudge policy (AM-3: opt-in only, mandatory redirect target)
// ---------------------------------------------------------------------------

export interface AmbientNudgePolicy {
  uid: string;
  optedIn: boolean;     // AM-3: false => zero nudges (no soft default)
  maxPerDay: number;
  quietHoursLocal: [number, number];
  redirectTarget: "scripture" | "prayer" | "people" | "embodied_church"; // MANDATORY
  lastNudgeAtUTC: number | null;
  killSwitchHonored: true;
}

// ---------------------------------------------------------------------------
// Reply verdict (AM-1: fail-closed three-gate)
// ---------------------------------------------------------------------------

export interface AgentReplyVerdict {
  invocationId: string;
  persona: AgentPersona;
  graderPassed: boolean;             // constitutionalReview.ts rubric
  citationGatePassed: boolean;       // BereanCitationGate
  companionBoundaryPassed: boolean;  // deterministic redirect check
  // AM-1 fail-closed: reply surfaces ONLY iff all three pass; else degraded response
  blockedReason: "grader" | "citation" | "companion_boundary" | null;
}

// ---------------------------------------------------------------------------
// Deterministic helpers (pure — no network, no model call).
// ---------------------------------------------------------------------------

/** AM-5: deterministic persona → mode lookup. Never model-guessed. */
export function resolveModeForPersona(persona: AgentPersona): BereanMode {
  return AGENT_PERSONA_MODE[persona];
}

/** AM-4: truncate fanout to the contract ceiling, preserving order. */
export function clampFanout(personas: AgentPersona[]): AgentPersona[] {
  return personas.slice(0, MAX_AGENT_FANOUT);
}

/** AM-1: the reply may surface only iff all three gates passed. */
export function maySurface(verdict: AgentReplyVerdict): boolean {
  return (
    verdict.graderPassed &&
    verdict.citationGatePassed &&
    verdict.companionBoundaryPassed
  );
}

/** AM-2: child zones must be a subset of parent zones (monotone narrowing). */
export function isMonotoneNarrowing(
  parentZones: PrivacyCoreZone[],
  childZones: PrivacyCoreZone[]
): boolean {
  const parent = new Set(parentZones);
  return childZones.every((z) => parent.has(z));
}

/** AM-3: a nudge may fire only when explicitly opted in. */
export function nudgesPermitted(policy: AmbientNudgePolicy): boolean {
  return policy.optedIn === true;
}

/** Fail-closed route: flag off OR basis indeterminate -> lead answers alone. */
export function failClosedRoute(invocationId: string): AgentRoute {
  return {
    invocationId,
    leadPersona: "lead",
    fanout: [],
    maxFanout: MAX_AGENT_FANOUT,
    cycleGuardVisited: [],
    routingBasis: "default_lead",
  };
}

// ---------------------------------------------------------------------------
// Invariant registry (asserted by the eval suite + Swift mirror).
// ---------------------------------------------------------------------------

export interface AgentMeshInvariants {
  readonly noNewStack: true;            // AM-5
  readonly singleLead: true;            // AM-4
  readonly maxFanout: 3;                // AM-4
  readonly cycleGuarded: true;          // AM-4
  readonly failClosedReply: true;       // AM-1
  readonly monotoneMemory: true;        // AM-2
  readonly nudgesOptInOnly: true;       // AM-3
  readonly boundaryIsStructural: true;  // AM-6
}

export const AGENT_MESH_INVARIANTS: Readonly<AgentMeshInvariants> = Object.freeze({
  noNewStack: true,
  singleLead: true,
  maxFanout: 3,
  cycleGuarded: true,
  failClosedReply: true,
  monotoneMemory: true,
  nudgesOptInOnly: true,
  boundaryIsStructural: true,
});
