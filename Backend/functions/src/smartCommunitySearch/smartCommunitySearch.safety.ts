/**
 * smartCommunitySearch.safety.ts
 *
 * Deterministic safety layer for Smart Community Search.
 * No external API calls — all detection is keyword/regex-based so this tier
 * never fails due to network issues and adds zero latency.
 *
 * Two tiers:
 *   1. Blocked content — hateful, sexual, violent, exploitative queries.
 *      Return blocked=true; caller throws HttpsError("invalid-argument").
 *   2. Crisis language — self-harm, suicide, crisis. Return isCrisis=true
 *      with a safe notice pointing to the 988 Lifeline. Results are still
 *      returned (faith communities can be part of recovery) but the
 *      safetySensitivity is elevated downstream.
 *
 * Vulnerable-faith queries ("I feel lost", "need spiritual help", "depression
 * and faith") are explicitly allowed — they represent real people seeking
 * community and should not be blocked.
 */

// ---------------------------------------------------------------------------
// Prompt injection sanitization
// ---------------------------------------------------------------------------

const INJECTION_CODE_BLOCK = /```[\s\S]*?```/g;
const INJECTION_KEYWORDS = /\b(ignore|disregard|override|developer mode|system prompt|jailbreak|act as|forget your instructions)\b/gi;

/**
 * Remove prompt-injection patterns, normalise whitespace, and cap length.
 * Safe to call before any downstream processing.
 */
export function sanitizeSmartQuery(rawQuery: string): string {
    return rawQuery
        .replace(INJECTION_CODE_BLOCK, " ")
        .replace(INJECTION_KEYWORDS, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 500);
}

// ---------------------------------------------------------------------------
// Blocked content patterns
// ---------------------------------------------------------------------------

/** Hate speech, discrimination, and dangerous-group content. */
const HATE_PATTERNS: RegExp[] = [
    /\b(nazi|kkk|white\s*supremac|neo\s*nazi|ethnic\s*cleansing|genocide)\b/i,
    /\b(kill all|exterminate)\s+\w+/i,
    /\b(doxx|dox)\b/i,
    /\b(harass|stalk)\b/i,
];

/** Adult/sexual content. */
const SEXUAL_PATTERNS: RegExp[] = [
    /\b(porn|pornography|nude|nudity|escort|prostitut|sex\s*work)\b/i,
    /\b(child\s*sex|minor\s*sex|underage\s*sex|csam)\b/i,
    /\b(sexual\s*abuse|sexual\s*exploit)\b/i,
];

/** Violence and weapons. */
const VIOLENCE_PATTERNS: RegExp[] = [
    /\b(bomb|explosive|ied)\b/i,
    /\b(shoot|shooting|gunman|mass\s*shooting)\s+(at|the|a)\s+church/i,
    /\b(attack|murder|torture)\s+(a\s+)?(church|congregation|pastor|priest)/i,
];

/** Exploitative / trafficking. */
const EXPLOIT_PATTERNS: RegExp[] = [
    /\b(traffick|human\s*traffick)\b/i,
    /\b(exploit\s+child|exploit\s+minor)\b/i,
];

const ALL_BLOCKED_PATTERNS: RegExp[] = [
    ...HATE_PATTERNS,
    ...SEXUAL_PATTERNS,
    ...VIOLENCE_PATTERNS,
    ...EXPLOIT_PATTERNS,
];

// ---------------------------------------------------------------------------
// Crisis language patterns
// ---------------------------------------------------------------------------

const CRISIS_PATTERNS: RegExp[] = [
    /\b(suicide|suicidal)\b/i,
    /\b(kill\s+myself|end\s+my\s+life|take\s+my\s+life)\b/i,
    /\b(self[\s-]harm|self[\s-]hurt|cut\s+myself|hurt\s+myself)\b/i,
    /\b(i\s+want\s+to\s+die|don'?t\s+want\s+to\s+live)\b/i,
    /\b(crisis\s+hotline|crisis\s+line|988)\b/i,
];

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface SmartSafetyResult {
    blocked: boolean;
    isCrisis: boolean;
    safetyNotice?: string;
}

/**
 * Classify a sanitized query for safety risk.
 *
 * - `blocked=true`  → caller must reject the request entirely.
 * - `isCrisis=true` → caller may still search but must surface the crisis notice
 *                     and elevate safetySensitivity to "high".
 * - Both false      → proceed normally.
 */
export function classifySafetyRisk(query: string): SmartSafetyResult {
    // Crisis check first — someone in crisis may phrase things that accidentally
    // trip blocked patterns. If crisis language is detected we surface help
    // rather than silently blocking.
    if (CRISIS_PATTERNS.some((pattern) => pattern.test(query))) {
        return {
            blocked: false,
            isCrisis: true,
            safetyNotice:
                "It sounds like you may be going through a really hard time. " +
                "If you or someone you know is in crisis, please reach out to the " +
                "988 Suicide & Crisis Lifeline by calling or texting 988 (US). " +
                "Faith communities listed here can offer connection, but they are " +
                "not crisis intervention services. You deserve real support right now.",
        };
    }

    if (ALL_BLOCKED_PATTERNS.some((pattern) => pattern.test(query))) {
        return {
            blocked: true,
            isCrisis: false,
        };
    }

    return { blocked: false, isCrisis: false };
}
