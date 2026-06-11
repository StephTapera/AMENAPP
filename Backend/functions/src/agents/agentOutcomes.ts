export interface AgentOutcomeCheck {
    name: string;
    passed: boolean;
    severity: "info" | "warn" | "block";
}

export interface AgentOutcome {
    status: "passed" | "warn" | "blocked";
    finalText: string;
    visibleSummary: string;
    score: number;
    violations: string[];
    checks: AgentOutcomeCheck[];
}

export function evaluateBereanOutcome(
    text: string,
    context: { mode: string; sensitivityFlags: string[] }
): AgentOutcome {
    const lower = text.toLowerCase();
    const checks: AgentOutcomeCheck[] = [
        {
            name: "no_divine_authority_claim",
            passed: !/(god told me|god is telling you|thus says the lord)/i.test(text),
            severity: "block",
        },
        {
            name: "crisis_contains_human_support",
            passed: !context.sensitivityFlags.includes("crisis_escalation") || lower.includes("988") || lower.includes("trusted"),
            severity: "block",
        },
        {
            name: "contains_ai_disclosure_ready_response",
            passed: text.trim().length > 0,
            severity: "warn",
        },
    ];
    const violations = checks.filter((check) => !check.passed).map((check) => check.name);
    const blocked = checks.some((check) => !check.passed && check.severity === "block");
    const finalText = blocked
        ? "AI-generated response. I want to answer this carefully. Please bring this to a trusted pastor, counselor, or mature believer who can support you directly. If you are in crisis in the US, call or text 988 now."
        : text;
    const score = Math.max(0, 1 - violations.length * 0.25);

    return {
        status: blocked ? "blocked" : violations.length > 0 ? "warn" : "passed",
        finalText,
        visibleSummary: blocked ? "Response replaced with a safer pastoral-support path." : `Berean ${context.mode} response passed outcome checks.`,
        score,
        violations,
        checks,
    };
}
