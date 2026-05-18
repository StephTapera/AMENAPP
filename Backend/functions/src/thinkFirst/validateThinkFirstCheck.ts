/**
 * validateThinkFirstCheck.ts
 *
 * Phase P1-4 — server-authoritative Think-First / Tone Checker callable.
 *
 * The iOS `ThinkFirstGuardrailsService` performs an advisory client
 * check before showing a sheet. This callable is the authoritative
 * server-side gate that the publish path (CreatePost / comments /
 * replies) must call before persisting any user-authored content. The
 * publish path MUST refuse to write when this returns
 * `action: "block" | "requireEdit"`.
 *
 * Contracts:
 *   - Auth required (HttpsError "unauthenticated" otherwise).
 *   - App Check required (HttpsError "unauthenticated" if missing).
 *   - Input length cap of 4000 chars enforced via the validator.
 *   - Per-user rate limit (AI_PER_MINUTE / AI_PER_DAY) shared with
 *     other AI callables.
 *   - NEVER logs the raw input text. Only the structured result is
 *     surfaced in analytics-safe logs.
 */

import { HttpsError, onCall } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import {
    validateThinkFirst,
    THINK_FIRST_MAX_INPUT_CHARS,
    type ThinkFirstResult,
} from "./validator";

interface ValidateThinkFirstRequest {
    text?: unknown;
    /**
     * Where in the app the check is being run. Free-form short label;
     * used only for analytics-safe logging.
     */
    surface?: unknown;
}

export const validateThinkFirstCheck = onCall(
    {
        timeoutSeconds: 10,
        memory: "256MiB",
        enforceAppCheck: true,
    },
    async (request): Promise<ThinkFirstResult> => {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Sign in required to use the safety check."
            );
        }
        if (!request.app) {
            throw new HttpsError(
                "unauthenticated",
                "App Check attestation required."
            );
        }

        const uid = request.auth.uid;
        await enforceRateLimit(uid, [
            RATE_LIMITS.AI_PER_MINUTE,
            RATE_LIMITS.AI_PER_DAY,
        ]);

        const data = (request.data ?? {}) as ValidateThinkFirstRequest;

        // Up-front validation so we never log oversized payloads.
        if (typeof data.text !== "string") {
            throw new HttpsError(
                "invalid-argument",
                "`text` must be a string."
            );
        }
        if (data.text.length > THINK_FIRST_MAX_INPUT_CHARS) {
            throw new HttpsError(
                "invalid-argument",
                `Content exceeds the ${THINK_FIRST_MAX_INPUT_CHARS}-character limit.`
            );
        }

        const result = validateThinkFirst(data.text);

        // Analytics-safe log. NEVER include `data.text` here.
        const surface =
            typeof data.surface === "string" && data.surface.length <= 64
                ? data.surface
                : "unknown";
        console.info("think_first_check_completed", {
            uid,
            surface,
            action: result.action,
            maxSeverity: result.maxSeverity,
            categories: result.categories,
        });

        return result;
    }
);
