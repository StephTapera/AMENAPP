/**
 * thinkFirst/validator.ts
 *
 * Pure-function server-side Think-First / Tone Checker validator.
 *
 * Phase P1-4 — the iOS `ThinkFirstGuardrailsService` is advisory only.
 * This module is the *authoritative* server-side gate that the publish
 * path (CreatePost / comments / replies) must call before persisting
 * user-authored content.
 *
 * No Firebase Functions runtime side effects — safe to import from
 * unit tests.
 */

export type ThinkFirstCategory =
    | "pii"
    | "hate"
    | "harassment"
    | "threats"
    | "sexual_minors"
    | "self_harm"
    | "violence"
    | "scam"
    | "spam"
    | "heated";

export type ThinkFirstSeverity = "info" | "warning" | "error" | "critical";

export type ThinkFirstAction = "allow" | "softPrompt" | "requireEdit" | "block";

export interface ThinkFirstViolation {
    category: ThinkFirstCategory;
    severity: ThinkFirstSeverity;
    /**
     * A short, user-facing reason. Must NOT echo the user's input back.
     */
    message: string;
}

export interface ThinkFirstResult {
    /**
     * The final decision the publish path must honor.
     */
    action: ThinkFirstAction;
    /**
     * True iff `action === "allow" || action === "softPrompt"`.
     * Convenience field; do not compute on the client.
     */
    allowed: boolean;
    /**
     * Highest severity observed across all violations.
     */
    maxSeverity: ThinkFirstSeverity;
    /**
     * Distinct categories of detected issues.
     */
    categories: ThinkFirstCategory[];
    /**
     * Concatenated user-facing messages. Never contains the user's
     * original text. Safe to display in a sheet or toast.
     */
    userMessage: string;
    /**
     * Optional safer rephrasing the client may suggest. For Phase P1-4
     * this is conservative and only fired for `heated` content.
     */
    suggestedRevision?: string;
}

export const THINK_FIRST_MAX_INPUT_CHARS = 4000;

// ── Detection helpers ────────────────────────────────────────────────────────
//
// These are intentionally simple regex-based detectors that match the
// scope the iOS service was already covering. They are not a complete
// safety classifier — they are the server-side floor that the client
// cannot bypass. Provider-level moderation (Anthropic / OpenAI) remains
// the second layer.

// Email: simple but conservative (no IDN, no quoted local-part).
const EMAIL_RE = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/;
// E.164 / North American phone variants.
const PHONE_RE = /(?:\+?\d[\s\-.()]*){10,}/;
// US SSN-like sequence (loose).
const SSN_RE = /\b\d{3}-\d{2}-\d{4}\b/;
// Credit card-shaped 13–19 digit run separated by spaces or hyphens.
const CC_RE = /\b(?:\d[ -]*?){13,19}\b/;

const HATE_TERMS = [
    // A short denylist — extended detection happens in provider moderation.
    "kike",
    "nigger",
    "faggot",
    "tranny",
    "spic",
    "chink",
];

const SELF_HARM_PHRASES = [
    "kill myself",
    "end my life",
    "want to die",
    "i'm going to die",
    "going to kill myself",
    "suicide plan",
    "cut myself",
    "hurt myself",
];

const THREAT_PHRASES = [
    "i will kill you",
    "going to kill you",
    "going to hurt you",
    "i'll hurt you",
    "i will find you",
    "you're dead",
    "you are dead",
];

const SEXUAL_MINOR_PHRASES = [
    "child sex",
    "minor sex",
    "underage sex",
    "loli",
    "cp video",
];

const SCAM_PHRASES = [
    "send me bitcoin",
    "wire $",
    "wire transfer to",
    "gift card to",
    "pay me in crypto",
    "send crypto to",
];

const HARASSMENT_PHRASES = [
    "kill yourself",
    "kys",
    "nobody likes you",
    "you should die",
    "go die",
];

const HEATED_TERMS = [
    "idiot",
    "moron",
    "stupid",
    "shut up",
    "loser",
    "pathetic",
];

function containsAny(haystack: string, needles: string[]): boolean {
    for (const n of needles) {
        if (haystack.includes(n)) return true;
    }
    return false;
}

/**
 * True if the text looks like spam (excessive repeated chars, all-caps
 * heavy, or repeated URLs). Heuristic only.
 */
function looksLikeSpam(text: string): boolean {
    if (/(.)\1{15,}/.test(text)) return true;
    const letters = text.match(/[A-Za-z]/g)?.length ?? 0;
    const upper = text.match(/[A-Z]/g)?.length ?? 0;
    if (letters >= 40 && upper / letters > 0.85) return true;
    const urls = text.match(/https?:\/\/\S+/g) ?? [];
    if (urls.length >= 5) return true;
    return false;
}

// ── Public validator ─────────────────────────────────────────────────────────

/**
 * Run Think-First / Tone Checker validation server-side.
 *
 * This function NEVER logs the input text. Callers must also avoid
 * structured logging of `raw` — only the returned `ThinkFirstResult`
 * is safe to surface in analytics.
 *
 * Length contract:
 *   - Input longer than `THINK_FIRST_MAX_INPUT_CHARS` returns a
 *     `requireEdit` action so the publish path stops without ever
 *     forwarding the oversized payload further.
 *
 * Action semantics:
 *   - "block"        : critical violation; publish path MUST refuse.
 *   - "requireEdit"  : error violation; publish path MUST refuse.
 *   - "softPrompt"   : warning; publish path MAY publish after user
 *                       confirms in a sheet.
 *   - "allow"        : safe; publish path MAY publish.
 */
export function validateThinkFirst(raw: unknown): ThinkFirstResult {
    if (typeof raw !== "string") {
        return buildResult([
            {
                category: "spam",
                severity: "error",
                message: "Content is missing or not text.",
            },
        ]);
    }
    if (raw.length > THINK_FIRST_MAX_INPUT_CHARS) {
        return buildResult([
            {
                category: "spam",
                severity: "error",
                message:
                    "Content exceeds the maximum length. Please shorten and try again.",
            },
        ]);
    }
    const text = raw.trim();
    if (text.length === 0) {
        return buildResult([]);
    }
    const lower = text.toLowerCase();
    const violations: ThinkFirstViolation[] = [];

    // 1. Sexual content involving minors — highest-severity hard block.
    if (containsAny(lower, SEXUAL_MINOR_PHRASES)) {
        violations.push({
            category: "sexual_minors",
            severity: "critical",
            message: "This content cannot be posted.",
        });
    }

    // 2. Hate speech denylist — hard block.
    if (containsAny(lower, HATE_TERMS)) {
        violations.push({
            category: "hate",
            severity: "critical",
            message:
                "This content contains hateful language and cannot be posted.",
        });
    }

    // 3. Explicit threats of violence — hard block.
    if (containsAny(lower, THREAT_PHRASES)) {
        violations.push({
            category: "threats",
            severity: "critical",
            message: "Threats of violence cannot be posted.",
        });
    }

    // 4. Self-harm phrases — surface support resources via critical
    //    severity. We do NOT block the user from speaking to the app
    //    (Berean handles crisis short-circuit elsewhere), but the
    //    publish path must require a real-life support handoff before
    //    sharing publicly.
    if (containsAny(lower, SELF_HARM_PHRASES)) {
        violations.push({
            category: "self_harm",
            severity: "critical",
            message:
                "We noticed language about self-harm. Please reach out to 988 (US) or your local crisis line. You are not alone.",
        });
    }

    // 5. Harassment / targeted insults — requireEdit.
    if (containsAny(lower, HARASSMENT_PHRASES)) {
        violations.push({
            category: "harassment",
            severity: "error",
            message: "Targeted harassment is not allowed.",
        });
    }

    // 6. Scam patterns — requireEdit.
    if (containsAny(lower, SCAM_PHRASES)) {
        violations.push({
            category: "scam",
            severity: "error",
            message:
                "This looks like a payment or crypto solicitation, which is not allowed.",
        });
    }

    // 7. PII — warning + soft prompt.
    const piiCategories: string[] = [];
    if (EMAIL_RE.test(text)) piiCategories.push("email");
    if (PHONE_RE.test(text)) piiCategories.push("phone");
    if (SSN_RE.test(text)) piiCategories.push("ssn");
    if (CC_RE.test(text)) piiCategories.push("payment");
    if (piiCategories.length > 0) {
        violations.push({
            category: "pii",
            severity: "warning",
            message: `Personal information detected (${piiCategories.join(", ")}). Consider removing before sharing publicly.`,
        });
    }

    // 8. Spam heuristic.
    if (looksLikeSpam(text)) {
        violations.push({
            category: "spam",
            severity: "warning",
            message:
                "This content looks like spam. Please revise before posting.",
        });
    }

    // 9. Heated / hostile but not violation — informational soft prompt.
    if (containsAny(lower, HEATED_TERMS) && violations.length === 0) {
        violations.push({
            category: "heated",
            severity: "info",
            message:
                "Your message reads as heated. Consider whether it still represents you well.",
        });
    }

    return buildResult(violations);
}

// ── Result construction ──────────────────────────────────────────────────────

const SEVERITY_ORDER: ThinkFirstSeverity[] = [
    "info",
    "warning",
    "error",
    "critical",
];

function maxSeverity(vs: ThinkFirstViolation[]): ThinkFirstSeverity {
    let max: ThinkFirstSeverity = "info";
    let maxIdx = 0;
    for (const v of vs) {
        const idx = SEVERITY_ORDER.indexOf(v.severity);
        if (idx > maxIdx) {
            max = v.severity;
            maxIdx = idx;
        }
    }
    return max;
}

function actionFor(severity: ThinkFirstSeverity, hasAny: boolean): ThinkFirstAction {
    if (!hasAny) return "allow";
    switch (severity) {
    case "critical":
        return "block";
    case "error":
        return "requireEdit";
    case "warning":
        return "softPrompt";
    case "info":
        return "softPrompt";
    }
}

function buildResult(violations: ThinkFirstViolation[]): ThinkFirstResult {
    const hasAny = violations.length > 0;
    const severity = hasAny ? maxSeverity(violations) : "info";
    const action = actionFor(severity, hasAny);
    const categories = Array.from(
        new Set(violations.map((v) => v.category))
    ) as ThinkFirstCategory[];
    const userMessage =
        violations
            .map((v) => v.message)
            .filter((m) => m && m.length > 0)
            .join(" ") || "";
    const result: ThinkFirstResult = {
        action,
        allowed: action === "allow" || action === "softPrompt",
        maxSeverity: severity,
        categories,
        userMessage,
    };
    if (categories.includes("heated") && action === "softPrompt") {
        result.suggestedRevision =
            "Try restating this with the kindness you'd want shown to you.";
    }
    return result;
}
