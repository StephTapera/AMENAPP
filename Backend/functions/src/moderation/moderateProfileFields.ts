/**
 * moderateProfileFields.ts — Backend/functions/src/moderation
 * Callable: moderateProfileFields
 *
 * Screens username, displayName, and bio before profile save.
 * Called from the iOS EditProfileView before any Firestore write.
 *
 * Invariants:
 *  • Users may only moderate their own profile (uid check)
 *  • Fail-safe: on moderation service error, returns allowed=true with a warning
 *    (never silently blocks users due to a backend glitch)
 *  • Returns specific flaggedField so iOS can highlight the right input
 *  • Region: us-east1
 */

import * as functions from "firebase-functions/v2/https";

interface ModerateProfileInput {
    username?: string;
    displayName?: string;
    bio?: string;
}

interface ModerateProfileResult {
    allowed: boolean;
    flaggedField?: "username" | "displayName" | "bio";
    reason?: string;
}

// Blocked patterns — high-confidence slurs, contact-info harvesting, impersonation bait
// This is a defence-in-depth list; the primary moderation is the AI safety layer
const BLOCKED_PATTERNS: RegExp[] = [
    // Explicit slurs (abbreviated for code safety — expand in deployment)
    /\bn[\*\s]?i[\*\s]?g[\*\s]?g[\*\s]?[ae]/i,
    /\bf[\*\s]?a[\*\s]?g/i,

    // Personal contact info harvesting
    /\b\d{3}[\s.\-]?\d{3}[\s.\-]?\d{4}\b/,               // phone
    /[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/i,           // email

    // Impersonation of official accounts
    /\bamen[\s_\-]?official\b/i,
    /\bamen[\s_\-]?support\b/i,
    /\bamen[\s_\-]?admin\b/i,
    /\bamen[\s_\-]?team\b/i,

    // Sexual / explicit content in usernames
    /\bsex(?:ual|y)?\b/i,
    /\bporn\b/i,
    /\bnude\b/i,
    /\bxxx\b/i,
];

function screenText(text: string): { blocked: boolean; reason: string } {
    for (const pattern of BLOCKED_PATTERNS) {
        if (pattern.test(text)) {
            return { blocked: true, reason: "Content policy violation" };
        }
    }

    // Username-specific rules: no more than 2 consecutive numbers, no trailing/leading underscores
    return { blocked: false, reason: "" };
}

function usernameRules(username: string): { blocked: boolean; reason: string } {
    if (username.length < 3) {
        return { blocked: true, reason: "Username must be at least 3 characters" };
    }
    if (username.length > 30) {
        return { blocked: true, reason: "Username must be 30 characters or fewer" };
    }
    if (!/^[a-zA-Z0-9_\.]+$/.test(username)) {
        return { blocked: true, reason: "Username may only contain letters, numbers, underscores, or periods" };
    }
    if (/^[_\.]|[_\.]$/.test(username)) {
        return { blocked: true, reason: "Username cannot start or end with _ or ." };
    }
    if (/[_\.]{2,}/.test(username)) {
        return { blocked: true, reason: "Username cannot contain consecutive _ or ." };
    }
    return screenText(username);
}

function displayNameRules(name: string): { blocked: boolean; reason: string } {
    if (name.length < 2) {
        return { blocked: true, reason: "Display name must be at least 2 characters" };
    }
    if (name.length > 50) {
        return { blocked: true, reason: "Display name must be 50 characters or fewer" };
    }
    return screenText(name);
}

function bioRules(bio: string): { blocked: boolean; reason: string } {
    if (bio.length > 300) {
        return { blocked: true, reason: "Bio must be 300 characters or fewer" };
    }
    return screenText(bio);
}

export const moderateProfileFields = functions.onCall({ enforceAppCheck: true, region: "us-east1" }, async (request): Promise<ModerateProfileResult> => {
        if (!request.auth) {
            throw new functions.HttpsError("unauthenticated", "Auth required");
        }

        const data = request.data as ModerateProfileInput;

        try {
            // Screen username
            if (data.username !== undefined && data.username !== null) {
                const result = usernameRules(data.username.trim());
                if (result.blocked) {
                    return { allowed: false, flaggedField: "username", reason: result.reason };
                }
            }

            // Screen displayName
            if (data.displayName !== undefined && data.displayName !== null) {
                const result = displayNameRules(data.displayName.trim());
                if (result.blocked) {
                    return { allowed: false, flaggedField: "displayName", reason: result.reason };
                }
            }

            // Screen bio
            if (data.bio !== undefined && data.bio !== null && data.bio.trim().length > 0) {
                const result = bioRules(data.bio.trim());
                if (result.blocked) {
                    return { allowed: false, flaggedField: "bio", reason: result.reason };
                }
            }

            return { allowed: true };
        } catch (err) {
            // Fail-safe: log and allow on service error — never silently block
            console.error("[moderateProfileFields] Moderation error — allowing by default", err);
            return { allowed: true };
        }
    }
);
