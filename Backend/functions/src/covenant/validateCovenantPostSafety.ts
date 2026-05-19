import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

// validateCovenantPostSafety
//
// P1-5: Real server-authoritative tone / safety check for the Covenant post
// composer. Replaces the client-side Task.sleep stub. Used by:
//   - AmenCovenantPostComposerView before Submit is enabled
//   - createCovenantPost / createCovenantMessage (if they re-validate server-side)
//   - any future composer that posts into a Covenant
//
// Contract:
//   Input:
//     - text:  string (required, 1..MAX_LEN chars)
//     - kind:  "post" | "message" | "comment" (optional, default "post")
//   Output:
//     - allowed:          boolean  // whether publish is permitted
//     - severity:         "safe" | "warn" | "block"
//     - categories:       string[] // matched category tags (no raw text)
//     - userMessage:      string   // safe to show in UI
//     - suggestedRevision?: string // (currently empty — reserved)
//
// Server-side rules (initial heuristic version):
//   block:
//     - Empty / whitespace-only
//     - Over MAX_LEN characters (24,000)
//     - Contains explicit hate / harassment slur tokens
//     - Contains financial-manipulation prosperity-gospel scam patterns
//   warn:
//     - All-caps for > 60% of long messages (perceived shouting)
//     - Repeated punctuation runs (!!!!! ?????)
//     - Excess link density (> 3 URLs in <140 chars)
//   safe:
//     - All other content
//
// Logging never includes the raw post text — only categories + lengths.

interface ValidateInput {
    text: string;
    kind?: "post" | "message" | "comment";
}

export type ValidateSeverity = "safe" | "warn" | "block";

export interface ValidateResult {
    allowed: boolean;
    severity: ValidateSeverity;
    categories: string[];
    userMessage: string;
    suggestedRevision?: string;
}

const MAX_LEN = 24_000;

// Financial manipulation regex mirrors submitCovenantReport patterns so
// the composer can warn pre-publish on the same shape moderators react to.
const FINANCIAL_MANIPULATION_PATTERNS: RegExp[] = [
    /seed\s*(faith)?\s*gift/i,
    /miracle\s+money/i,
    /sow\s+\$\d+/i,
    /god\s+told\s+me\s+you\s+need\s+to\s+give/i,
    /unlock\s+your\s+blessing.*give/i,
    /prophetic\s+pledge/i,
];

// Coarse slur / hate token list. Real production should use a managed
// classifier — this is a conservative initial baseline so the composer
// cannot ship a permissive heuristic by mistake.
const HATE_TOKENS: RegExp[] = [
    /\bn[i1]gg[ae3]r\b/i,
    /\bf[a4]gg[o0]t\b/i,
    /\bk[i1]ke\b/i,
    /\bsp[i1]c\b/i,
    /\btr[a4]nn[i1]e\b/i,
];

// Exported for unit testing.
export function evaluatePostSafety(text: string): ValidateResult {
    const trimmed = text.trim();

    if (trimmed.length === 0) {
        return {
            allowed: false,
            severity: "block",
            categories: ["empty"],
            userMessage: "Add something to say before posting.",
        };
    }
    if (trimmed.length > MAX_LEN) {
        return {
            allowed: false,
            severity: "block",
            categories: ["too_long"],
            userMessage: `Posts are limited to ${MAX_LEN.toLocaleString()} characters.`,
        };
    }

    const categories: string[] = [];

    for (const pattern of HATE_TOKENS) {
        if (pattern.test(trimmed)) {
            categories.push("hate_speech");
            break;
        }
    }

    for (const pattern of FINANCIAL_MANIPULATION_PATTERNS) {
        if (pattern.test(trimmed)) {
            categories.push("financial_manipulation");
            break;
        }
    }

    if (categories.length > 0) {
        return {
            allowed: false,
            severity: "block",
            categories,
            userMessage: "This post can't be published because it appears to contain prohibited content. Please revise and try again.",
        };
    }

    // Warn-level heuristics
    const warnCategories: string[] = [];

    if (trimmed.length >= 80) {
        const letters = trimmed.replace(/[^A-Za-z]/g, "");
        if (letters.length >= 40) {
            const upper = letters.replace(/[^A-Z]/g, "").length;
            if (upper / letters.length > 0.6) {
                warnCategories.push("all_caps");
            }
        }
    }

    if (/[!?]{4,}/.test(trimmed)) {
        warnCategories.push("excess_punctuation");
    }

    const urlCount = (trimmed.match(/https?:\/\/\S+/g) ?? []).length;
    if (urlCount >= 4 && trimmed.length < 280) {
        warnCategories.push("link_density");
    }

    if (warnCategories.length > 0) {
        return {
            allowed: true,            // warn does not block publish
            severity: "warn",
            categories: warnCategories,
            userMessage: "Heads up — this post might come across stronger than you intend. You can still publish.",
        };
    }

    return {
        allowed: true,
        severity: "safe",
        categories: [],
        userMessage: "",
    };
}

// ── Core handler (exported for unit testing) ──────────────────────────────────

export async function validateCovenantPostSafetyHandler(
    uid: string | null,
    appCheckPresent: boolean,
    data: Partial<ValidateInput>
): Promise<ValidateResult> {
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    if (!appCheckPresent) throw new HttpsError("failed-precondition", "App Check required.");

    const text = typeof data.text === "string" ? data.text : "";
    if (text.length === 0) {
        throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > MAX_LEN) {
        // Even before rate-limiting we reject grossly oversized payloads.
        throw new HttpsError("invalid-argument", `text exceeds maximum length (${MAX_LEN}).`);
    }
    const kind = (data.kind ?? "post") as ValidateInput["kind"];
    if (kind !== "post" && kind !== "message" && kind !== "comment") {
        throw new HttpsError("invalid-argument", "kind must be post, message, or comment.");
    }

    await enforceRateLimit(uid, [
        RATE_LIMITS.COMMUNITY_TONE_CHECK_PER_MINUTE,
        RATE_LIMITS.COMMUNITY_TONE_CHECK_PER_DAY,
    ]);

    const result = evaluatePostSafety(text);

    // Safe structured logging — NO raw post text.
    logger.info("[validateCovenantPostSafety] evaluated", {
        uid,
        kind,
        textLength: text.length,
        severity: result.severity,
        categories: result.categories,
        allowed: result.allowed,
    });

    return result;
}

// ── Cloud Function wrapper ────────────────────────────────────────────────────

export const validateCovenantPostSafety = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        return validateCovenantPostSafetyHandler(
            request.auth?.uid ?? null,
            request.app != null,
            (request.data ?? {}) as Partial<ValidateInput>
        );
    }
);

// Used by admin.firestore() references in future expansion; silence unused.
void admin;
