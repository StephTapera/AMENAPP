import {
    AGENT_PERSONA_MODE,
    ALWAYS_HUMAN_GATED_CAPABILITIES,
    MAX_AGENT_FANOUT,
    defaultAgentPlan,
    defaultAmbientTeammateSession,
    defaultAutoModeDecision,
    defaultCompanionConstraint,
    defaultConstitutionGovernance,
    defaultMentionInvocation,
    defaultOutcomeGrade,
    defaultSkillManifest,
    defaultUserCreatedAgentSpec,
    defaultWorkflowGraph,
    isAutoActAllowed,
} from "./agenticPrimitivesContracts";

describe("agentic primitives contracts", () => {
    it("ambient teammate defaults are fail-closed (no opt-in, boundary on)", () => {
        const s = defaultAmbientTeammateSession("s1", "u1", "feed");
        expect(s.optedIn).toBe(false);
        expect(s.grantedZones).toEqual([]);
        expect(s.triggers).toEqual([]);
        expect(s.companionBoundaryEnforced).toBe(true);
        expect(s.killSwitchHonored).toBe(true);
    });

    it("@-mention invocation defaults to unresolved (fail-closed) and parsed locally", () => {
        const m = defaultMentionInvocation("i1", "t1", "u1", "@prayer");
        expect(m.resolvedPersona).toBeNull();
        expect(m.resolvedMode).toBeNull();
        expect(m.parsedLocally).toBe(true);
        expect(m.memoryZoneIsolated).toBe(true);
    });

    it("persona->mode table is deterministic and frozen", () => {
        expect(AGENT_PERSONA_MODE.study).toBe("discern");
        expect(AGENT_PERSONA_MODE.prayer).toBe("reflect");
        expect(AGENT_PERSONA_MODE.church).toBe("ask");
        expect(AGENT_PERSONA_MODE.mentor).toBe("build");
        expect(AGENT_PERSONA_MODE.family).toBe("guard");
        expect(Object.isFrozen(AGENT_PERSONA_MODE)).toBe(true);
    });

    it("workflow graph defaults to no lead, empty nodes, disabled, capped fanout", () => {
        const g = defaultWorkflowGraph("g1", "u1");
        expect(g.leadNodeId).toBeNull();
        expect(g.nodes).toEqual([]);
        expect(g.enabled).toBe(false);
        expect(g.maxFanout).toBe(MAX_AGENT_FANOUT);
        expect(MAX_AGENT_FANOUT).toBe(3);
    });

    it("outcome grade defaults to not-passed, internal-only, never displayed", () => {
        const grade = defaultOutcomeGrade("grd1", "i1", "bibleAccuracy");
        expect(grade.passed).toBe(false);
        expect(grade.internalScore).toBe(0);
        expect(grade.neverDisplayed).toBe(true);
        expect(grade.appealable).toBe(true);
    });

    it("agent plan never auto-executes and never writes in plan mode", () => {
        const plan = defaultAgentPlan("p1", "t1", "u1");
        expect(plan.requiresConfirmation).toBe(true);
        expect(plan.writeAllowedInPlanMode).toBe(false);
        expect(plan.userConfirmed).toBe(false);
        expect(plan.plannedSources).toEqual([]);
    });

    it("auto-mode decision defaults to human-gated, no auto action", () => {
        const d = defaultAutoModeDecision("d1", "i1", "contentSafety");
        expect(d.requiresHumanReview).toBe(true);
        expect(d.autoActPermitted).toBe(false);
        expect(d.autonomousActionPermitted).toBe(false);
    });

    it("CSAM / grooming / crisis are ALWAYS human-gated regardless of verdict", () => {
        expect(ALWAYS_HUMAN_GATED_CAPABILITIES).toContain("childSafety");
        expect(ALWAYS_HUMAN_GATED_CAPABILITIES).toContain("crisis");
        expect(ALWAYS_HUMAN_GATED_CAPABILITIES).toContain("harassmentBrigading");
        // even with a clean low signal and explicit permission, gated caps never auto-act
        expect(isAutoActAllowed("childSafety", "none", true)).toBe(false);
        expect(isAutoActAllowed("crisis", "low", true)).toBe(false);
    });

    it("auto-act only when capability is non-gated, level < high, and verdict permits", () => {
        expect(isAutoActAllowed("contentSafety", "low", true)).toBe(true);
        expect(isAutoActAllowed("contentSafety", "high", true)).toBe(false);
        expect(isAutoActAllowed("contentSafety", "critical", true)).toBe(false);
        expect(isAutoActAllowed("contentSafety", "low", false)).toBe(false);
    });

    it("constitution governance forbids ad-profiling and requires boundary/citation", () => {
        const gov = defaultConstitutionGovernance();
        expect(gov.adProfilingForbidden).toBe(true);
        expect(gov.companionBoundaryRequired).toBe(true);
        expect(gov.citationGateRequired).toBe(true);
        expect(gov.memoryInspectable).toBe(true);
        expect(gov.memoryDeletable).toBe(true);
        expect(gov.maxGrantableZone).toBe("preference");
    });

    it("skill manifest defaults to disabled, no zones, no write", () => {
        const skill = defaultSkillManifest("sk1", "Study Helper");
        expect(skill.enabled).toBe(false);
        expect(skill.grantedZones).toEqual([]);
        expect(skill.writeAllowed).toBe(false);
    });

    it("companion constraint forbids parasocial pull (NON-NEGOTIABLE)", () => {
        const c = defaultCompanionConstraint();
        expect(c.parasocialForbidden).toBe(true);
        expect(c.mustRedirect).toBe(true);
        expect(c.citationGated).toBe(true);
        expect(c.minorHardened).toBe(true);
        expect(c.memoryZoneScoped).toBe(true);
        expect(c.redirectTargets.length).toBeGreaterThan(0);
    });

    it("user-created agent spec is fail-closed and carries the full companion constraint", () => {
        const spec = defaultUserCreatedAgentSpec("a1", "u1", "My Study Buddy", "study");
        expect(spec.enabled).toBe(false);
        expect(spec.published).toBe(false);
        expect(spec.writeAllowed).toBe(false);
        expect(spec.grantedZones).toEqual([]);
        expect(spec.resolvedMode).toBe(AGENT_PERSONA_MODE.study);
        expect(spec.constraint.parasocialForbidden).toBe(true);
    });
});
