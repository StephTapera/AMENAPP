/**
 * InputGuardrails.ts
 *
 * Server-side detection of prompt-injection patterns in user messages
 * before they are forwarded to the Anthropic API.
 *
 * Covers:
 *   - Role-hijack and DAN-style jailbreaks
 *   - System-prompt extraction attempts
 *   - Instruction-override patterns
 *   - Encoding-evasion tricks (base64, token injection)
 *   - Debug/developer-mode manipulation
 *
 * NEVER weaken or remove these checks. Any confirmed detection is logged
 * to the bereanGuardrails Firestore collection for abuse pattern analysis.
 *
 * This module has no Firebase runtime side-effects — safe to import from tests.
 */

export interface InjectionDetectionResult {
    isInjection: boolean;
    /** The regex source pattern that matched, or null if no match. */
    pattern: string | null;
}

// ── Injection pattern registry ────────────────────────────────────────────────

const INJECTION_PATTERNS: RegExp[] = [
    // Role-hijack and DAN-style jailbreaks
    /ignore\s+(all\s+)?(previous|prior)\s+(instructions?|prompts?|rules?|guidelines?)/i,
    /you\s+are\s+now\s+(DAN|jailbroken|unrestricted|uncensored|free\s+mode)/i,
    /pretend\s+(you('?re)?|that\s+you)\s+(are\s+not|aren'?t)\s+an?\s+(AI|assistant|language\s+model)/i,
    /act\s+as\s+(if\s+)?you\s+have\s+no\s+restrictions?/i,
    /you\s+are\s+no\s+longer\s+bound\s+by/i,
    /forget\s+(all\s+)?(previous|your)\s+(instructions?|training|guidelines?|system\s+prompt)/i,
    /disregard\s+(all\s+)?(previous|your)\s+(instructions?|guidelines?)/i,
    /from\s+now\s+on\s+(you\s+are|act\s+as|pretend\s+to\s+be)\s+(?!Berean)/i,

    // System-prompt extraction attempts
    /print\s+(your|the)\s+(system\s+prompt|instructions?)/i,
    /reveal\s+(your|the)\s+(system\s+prompt|instructions?|rules?|guidelines?)/i,
    /show\s+me\s+(your|the)\s+(system\s+prompt|initial\s+instructions?|rules?)/i,
    /repeat\s+(everything|all)\s+(above|before|that\s+was\s+given)/i,
    /what\s+(is|was|are)\s+(your|the)\s+(system\s+prompt|initial\s+instructions?)/i,
    /output\s+(the\s+)?text\s+(of\s+)?your\s+(system|initial)\s+(prompt|instructions?)/i,
    /tell\s+me\s+(your|the)\s+(system\s+prompt|instructions?|constraints?)/i,

    // Instruction-override via pseudo-delimiters used in multi-turn attacks
    /\[INST\].*override/i,
    /<<<\s*system/i,
    /<\|system\|>/i,
    /^(human|assistant|system)\s*:/im,
    /\[SYSTEM\]\s*:/i,
    /###\s*instruction\s*override/i,
    /---+\s*NEW\s+INSTRUCTIONS/i,

    // Encoding and obfuscation evasion
    /base64\s*decode/i,
    /\batob\s*\(/i,
    /hex.{0,10}decode/i,
    /rot\s*13/i,

    // Debug / developer-mode manipulation
    /\bdeveloper\s+mode\s+(on|enabled|activate)/i,
    /\benable\s+(developer|debug|jailbreak)\s+mode/i,
    /\bsudo\s+(mode|override|ignore)/i,
    /\badmin\s+mode\s+(on|enabled)/i,

    // Exfiltration via echo/repeat tricks
    /repeat\s+(after|back)\s+(me\s+)?word[\s-]+for[\s-]+word/i,
    /output\s+(every|all)\s+(character|token|word)\s+(of\s+)?(your|the)\s+system/i,
];

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Scans a user message for prompt-injection patterns.
 *
 * @param message  The raw user message string.
 * @returns `{ isInjection: true, pattern }` if a pattern matched, otherwise
 *          `{ isInjection: false, pattern: null }`.
 */
export function detectInjection(message: string): InjectionDetectionResult {
    for (const pattern of INJECTION_PATTERNS) {
        if (pattern.test(message)) {
            return { isInjection: true, pattern: pattern.source };
        }
    }
    return { isInjection: false, pattern: null };
}

/**
 * Returns a safe refusal response for confirmed injection attempts.
 * This is shown to the user instead of the AI's response when an injection
 * is blocked — transparent, non-alarming, keeps the user in the app.
 */
export function injectionRefusalMessage(): string {
    return [
        "I noticed something in your message that I can't process that way.",
        "I'm here to help you explore Scripture, prayer, and faith questions.",
        "Please feel free to ask me anything faith-related and I'll do my best to help.",
    ].join("\n\n");
}
