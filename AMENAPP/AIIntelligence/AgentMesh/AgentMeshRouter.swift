// AgentMeshRouter.swift
// AMENAPP — Berean Tag-an-Agent Mesh (Feature B), Wave 1.
//
// Pure deterministic table router. No network, no model call. Resolves the
// local (no-network) @-mention tags in a query into a single lead + bounded
// fanout of AgentPersonas, each of which maps to an existing BereanMode via the
// frozen AGENT_PERSONA_MODE table (AM-5). The mesh never broadens scope on its
// own: when the flag is OFF or the routing basis is indeterminate, the router
// returns the fail-closed route ([] fanout — the lead answers alone, AM-4).
//
// Flag guard: gated on AMENFeatureFlags.shared.bereanAgentMesh (RC
// "berean_agent_mesh_enabled", default OFF). Fail-closed: flag OFF => no fanout.

import Foundation

enum AgentMeshRouter {

    /// Parses the explicit @-mention tags in `query` into AgentPersonas.
    /// Pure local string scan — no network, deterministic, order-preserving,
    /// de-duplicated. Unknown tags are ignored (never model-guessed, AM-5/AM-6).
    static func parseTags(in query: String) -> [AgentPersona] {
        let lower = query.lowercased()
        var seen = Set<AgentPersona>()
        var ordered: [AgentPersona] = []

        // Scan for "@<persona>" tokens in textual order.
        for token in lower.split(whereSeparator: { !($0 == "@" || $0.isLetter) }) {
            guard token.first == "@" else { continue }
            let name = String(token.dropFirst())
            guard let persona = AgentPersona(rawValue: name) else { continue }
            if seen.insert(persona).inserted {
                ordered.append(persona)
            }
        }
        return ordered
    }

    /// Builds the route for an invocation. Deterministic table lookup only.
    ///
    /// - Returns the fail-closed route (empty fanout) when the mesh flag is OFF,
    ///   when no valid tag is present, or when the basis is otherwise
    ///   indeterminate. Otherwise returns a single-lead route with the fanout
    ///   truncated to MAX_AGENT_FANOUT (AM-4) and cycle-guarded against repeats.
    @MainActor
    static func route(invocationId: String,
                      query: String,
                      flagEnabled: Bool = AMENFeatureFlags.shared.bereanAgentMesh) -> AgentRoute {
        // Fail-closed: flag OFF => lead answers alone, never broadens scope.
        guard flagEnabled else {
            return AgentMeshContract.failClosedRoute(invocationId: invocationId)
        }
        return route(invocationId: invocationId, query: query, ignoringFlag: ())
    }

    /// Pure routing core, independent of the flag (used by the flag-gated entry
    /// point above and by deterministic tests). Cycle-guarded + fanout-clamped.
    static func route(invocationId: String, query: String, ignoringFlag: Void) -> AgentRoute {
        let tags = parseTags(in: query)

        // No explicit tag => indeterminate basis => fail-closed lead-only route.
        guard !tags.isEmpty else {
            return AgentMeshContract.failClosedRoute(invocationId: invocationId)
        }

        // Cycle guard: a persona is visited at most once (de-dup already applied
        // in parseTags, but we keep the visited list explicit for audit).
        var visited: [AgentPersona] = []
        for persona in tags where !visited.contains(persona) {
            visited.append(persona)
        }

        // AM-4: truncate to the contract ceiling, preserving order.
        let fanout = AgentMeshContract.clampFanout(visited)

        return AgentRoute(
            invocationId: invocationId,
            leadPersona: "lead",
            fanout: fanout,
            maxFanout: MAX_AGENT_FANOUT,
            cycleGuardVisited: visited,
            routingBasis: .explicitTag
        )
    }

    /// Builds the per-persona invocations a route fans out to. Each carries the
    /// deterministic resolvedMode (AM-5) and the inherited depth (never escalated).
    static func invocations(for route: AgentRoute,
                            threadId: String,
                            uid: String,
                            query: String,
                            depth: BereanDepth,
                            createdAtUTC: TimeInterval = Date().timeIntervalSince1970) -> [AgentInvocation] {
        route.fanout.map { persona in
            AgentInvocation(
                invocationId: UUID().uuidString,
                threadId: threadId,
                uid: uid,
                rawTag: "@\(persona.rawValue)",
                persona: persona,
                resolvedMode: persona.resolvedMode,
                depth: depth,
                query: query,
                isLeadRouterFanout: true,
                parentInvocationId: route.invocationId,
                createdAtUTC: createdAtUTC
            )
        }
    }
}
