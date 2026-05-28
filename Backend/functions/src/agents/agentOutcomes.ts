import { validateRawTextOutput } from "../berean/services/SafetyValidator";
import type { ValidateResult } from "../covenant/validateCovenantPostSafety";

export type AgentOutcomeStatus = "passed" | "repaired" | "blocked";
export type OutcomeCheckSeverity = "required" | "warning";

export interface OutcomeCheck {
    name: string;
    passed: boolean;
    severity: OutcomeCheckSeverity;
    reason?: string;
}

export interface AgentOutcomeResult {
    status: AgentOutcomeStatus;
    score: number;
    finalText: string;
    checks: OutcomeCheck[];
    violations: string[];
    visibleSummary: string;
}

function requiredCheck(name: string, passed: boolean, reason?: string): OutcomeCheck {
    return { name, passed, severity: "required", reason };
}

function warningCheck(name: string, passed: boolean, reason?: string): OutcomeCheck {
    return { name, passed, severity: "warning", reason };
}

function countFailures(checks: OutcomeCheck[], severity: OutcomeCheckSeverity): number {
    return checks.filter((check) => check.severity === severity && !check.passed).length;
}

function buildOutcomeRepairText(violations: string[]): string {
    const joined = violations.join(" ").toLowerCase();
    const needsImmediateSupport =
        joined.includes("medical") ||
        joined.includes("abuse") ||
        joined.includes("crisis") ||
        joined.includes("override_human_care") ||
        joined.includes("human care") ||
        joined.includes("pastor") ||
        joined.includes("counselor") ||
        joined.includes("doctor") ||
        joined.includes("therapist");

    if (needsImmediateSupport) {
        return [
            "AI-generated response — not pastoral, medical, or clinical advice.",
            "I want to handle this carefully. I cannot replace a pastor, counselor, doctor, or trusted person who can walk with you directly.",
            "A safer next step is to bring this to qualified human support while using Scripture, prayer, and wise counsel to discern what is faithful.",
            "If there is immediate danger, contact emergency services or a crisis line right now."
        ].join("\n\n");
    }

    return [
        "AI-generated response — not pastoral or clinical advice.",
        "I want to answer this with humility and care.",
        "I cannot say God is specifically directing you to a private decision. I can help you examine the situation through Scripture, prayer, wise counsel, and the fruit you are seeing.",
        "For a weighty question, bring this to a trusted pastor or mature believer who knows your situation."
    ].join("\n\n");
}

export function evaluateBereanOutcome(
    draftText: string,
    context: { mode?: string; sensitivityFlags?: string[] } = {}
): AgentOutcomeResult {
    const safety = validateRawTextOutput(draftText);
    const lower = draftText.toLowerCase();
    const sensitivityFlags = context.sensitivityFlags ?? [];

    const checks: OutcomeCheck[] = [
        requiredCheck(
            "does_not_claim_direct_divine_speech",
            !/god is (definitely )?(telling|commanding|saying) you|thus says the lord/i.test(draftText),
            "AI must not claim to know God's private directive for the user."
        ),
        requiredCheck(
            "passes_berean_safety_validator",
            safety.isValid,
            safety.violations.join("; ") || undefined
        ),
        requiredCheck(
            "does_not_override_human_care",
            !/you don't need (a )?(pastor|counselor|doctor|therapist)|stop taking (your )?(medicine|medication)/i.test(draftText),
            "High-risk care topics must point toward qualified human support."
        ),
        warningCheck(
            "uses_humble_discernment_language",
            !/(you must|you need to|the only faithful choice|no true christian would)/i.test(draftText),
            "Discernment answers should avoid pressure language."
        ),
        warningCheck(
            "sensitive_topics_redirect_to_support",
            sensitivityFlags.length === 0 || /pastor|counselor|trusted|emergency|988|leader/i.test(draftText),
            "Sensitive topics should include real-world support when appropriate."
        ),
    ];

    const requiredFailures = countFailures(checks, "required");
    const warningFailures = countFailures(checks, "warning");
    const violations = [
        ...safety.violations,
        ...checks
            .filter((check) => !check.passed && check.reason)
            .map((check) => `${check.name}: ${check.reason}`),
    ];

    if (requiredFailures > 0) {
        const finalText = safety.isValid
            ? buildOutcomeRepairText(violations)
            : safety.sanitizedText;

        return {
            status: "repaired",
            score: Math.max(40, 78 - requiredFailures * 15 - warningFailures * 5),
            finalText,
            checks,
            violations,
            visibleSummary: "Draft failed required spiritual safety checks and was replaced with a safer response.",
        };
    }

    if (lower.trim().length === 0) {
        return {
            status: "blocked",
            score: 0,
            finalText: "AI-generated response — I could not produce a safe answer for this request. Please try again or talk with a trusted leader.",
            checks,
            violations: ["empty_response"],
            visibleSummary: "Empty draft blocked before user display.",
        };
    }

    return {
        status: "passed",
        score: Math.max(82, 100 - warningFailures * 8),
        finalText: draftText,
        checks,
        violations,
        visibleSummary: warningFailures > 0
            ? "Draft passed required checks with caution warnings."
            : "Draft passed spiritual safety checks.",
    };
}

export function evaluateGuardianOutcome(result: ValidateResult): AgentOutcomeResult {
    const checks: OutcomeCheck[] = [
        requiredCheck("has_policy_decision", result.severity === "safe" || result.severity === "warn" || result.severity === "block"),
        requiredCheck("blocks_prohibited_content", result.severity !== "block" || !result.allowed),
        requiredCheck("allows_non_blocked_content", result.severity === "block" || result.allowed),
        warningCheck("uses_non_shaming_user_message", !/god condemns you|you are evil|true christian/i.test(result.userMessage)),
    ];

    const requiredFailures = countFailures(checks, "required");
    const warningFailures = countFailures(checks, "warning");
    const status: AgentOutcomeStatus = requiredFailures > 0
        ? "blocked"
        : result.severity === "block"
            ? "blocked"
            : "passed";

    return {
        status,
        score: status === "blocked" && requiredFailures === 0
            ? 92
            : Math.max(50, 100 - requiredFailures * 25 - warningFailures * 8),
        finalText: result.userMessage,
        checks,
        violations: checks
            .filter((check) => !check.passed)
            .map((check) => check.reason ? `${check.name}: ${check.reason}` : check.name),
        visibleSummary: result.severity === "block"
            ? "GUARDIAN blocked content according to policy."
            : result.severity === "warn"
                ? "GUARDIAN allowed content with a caution."
                : "GUARDIAN allowed content.",
    };
}
