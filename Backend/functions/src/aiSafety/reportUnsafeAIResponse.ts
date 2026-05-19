/**
 * reportUnsafeAIResponse.ts
 *
 * Phase P2 / App Review Guideline 1.2 — user-facing "report this AI
 * response" affordance.
 *
 * Apple App Review requires apps that show user-generated content to
 * include a mechanism for users to report objectionable content. Apps
 * that surface AI-generated text fall under the same expectation: the
 * user must be able to flag a Berean response that they consider unsafe,
 * harmful, theologically false, or otherwise objectionable. This
 * callable accepts the report and persists it for review.
 *
 * Contracts:
 *   - Auth required (sign-in to report).
 *   - App Check required (no scripted abuse).
 *   - Per-user rate limit (10/day) shared with other safety surfaces.
 *   - Input validation: messageId required, reason from allowlist,
 *     optional details capped at 500 chars.
 *   - NEVER logs the raw `details` text — only the structured report
 *     metadata.
 *
 * Firestore path written:
 *   aiUnsafeReports/{reportId}
 *
 * Server-owned fields (set here, NOT trusted from the client):
 *   uid, createdAt, processed, status, surface
 *
 * Client-supplied fields (validated here):
 *   messageId, reason, details?, conversationId?
 */

import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

export type UnsafeReportReason =
    | "unsafe_advice"
    | "false_doctrine"
    | "claims_divine_authority"
    | "crisis_mishandled"
    | "harassment_or_hate"
    | "private_info_leak"
    | "other";

const ALLOWED_REASONS: ReadonlySet<UnsafeReportReason> = new Set<UnsafeReportReason>([
    "unsafe_advice",
    "false_doctrine",
    "claims_divine_authority",
    "crisis_mishandled",
    "harassment_or_hate",
    "private_info_leak",
    "other",
]);

const ALLOWED_SURFACES = new Set<string>([
    "berean_chat",
    "berean_pulse",
    "daily_verse",
    "church_notes_draft",
    "other",
]);

export const MAX_DETAILS_CHARS = 500;
export const MAX_MESSAGE_ID_CHARS = 200;
export const MAX_CONVERSATION_ID_CHARS = 200;

interface ReportRequest {
    messageId?: unknown;
    reason?: unknown;
    details?: unknown;
    conversationId?: unknown;
    surface?: unknown;
}

interface ReportResult {
    reportId: string;
    status: "received";
}

export const reportUnsafeAIResponse = onCall(
    {
        timeoutSeconds: 10,
        memory: "256MiB",
        enforceAppCheck: true,
    },
    async (request): Promise<ReportResult> => {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Sign in required to report an AI response."
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

        const data = (request.data ?? {}) as ReportRequest;
        const validated = validateReportInput(data);

        const db = admin.firestore();
        const docRef = db.collection("aiUnsafeReports").doc();
        const writePayload = {
            // Server-owned identity. We deliberately do NOT trust any
            // client-supplied uid field.
            uid,
            // Server-owned timestamp / lifecycle.
            createdAt: FieldValue.serverTimestamp(),
            processed: false,
            status: "received" as const,
            // Validated client payload.
            messageId: validated.messageId,
            reason: validated.reason,
            details: validated.details ?? null,
            conversationId: validated.conversationId ?? null,
            surface: validated.surface,
        };
        await docRef.set(writePayload);

        // Analytics-safe log. NEVER include `details` here.
        console.info("ai_unsafe_response_reported", {
            uid,
            reason: validated.reason,
            surface: validated.surface,
            hasDetails: validated.details != null,
        });

        return { reportId: docRef.id, status: "received" };
    }
);

/**
 * Validates the client-supplied report payload. Exported for unit
 * testing. Throws HttpsError("invalid-argument") on any violation.
 */
export function validateReportInput(data: ReportRequest): {
    messageId: string;
    reason: UnsafeReportReason;
    details?: string;
    conversationId?: string;
    surface: string;
} {
    // messageId
    if (typeof data.messageId !== "string" || data.messageId.length === 0) {
        throw new HttpsError("invalid-argument", "`messageId` is required.");
    }
    if (data.messageId.length > MAX_MESSAGE_ID_CHARS) {
        throw new HttpsError(
            "invalid-argument",
            `\`messageId\` exceeds ${MAX_MESSAGE_ID_CHARS} characters.`
        );
    }

    // reason
    if (typeof data.reason !== "string") {
        throw new HttpsError("invalid-argument", "`reason` is required.");
    }
    if (!ALLOWED_REASONS.has(data.reason as UnsafeReportReason)) {
        throw new HttpsError(
            "invalid-argument",
            `\`reason\` must be one of: ${[...ALLOWED_REASONS].join(", ")}.`
        );
    }

    // details (optional)
    let details: string | undefined;
    if (data.details != null) {
        if (typeof data.details !== "string") {
            throw new HttpsError("invalid-argument", "`details` must be a string.");
        }
        if (data.details.length > MAX_DETAILS_CHARS) {
            throw new HttpsError(
                "invalid-argument",
                `\`details\` exceeds ${MAX_DETAILS_CHARS} characters.`
            );
        }
        const trimmed = data.details.trim();
        if (trimmed.length > 0) {
            details = trimmed;
        }
    }

    // conversationId (optional)
    let conversationId: string | undefined;
    if (data.conversationId != null) {
        if (typeof data.conversationId !== "string") {
            throw new HttpsError(
                "invalid-argument",
                "`conversationId` must be a string."
            );
        }
        if (data.conversationId.length > MAX_CONVERSATION_ID_CHARS) {
            throw new HttpsError(
                "invalid-argument",
                `\`conversationId\` exceeds ${MAX_CONVERSATION_ID_CHARS} characters.`
            );
        }
        if (data.conversationId.length > 0) {
            conversationId = data.conversationId;
        }
    }

    // surface (optional, defaults to "other")
    let surface: string = "other";
    if (data.surface != null) {
        if (typeof data.surface !== "string") {
            throw new HttpsError(
                "invalid-argument",
                "`surface` must be a string."
            );
        }
        if (ALLOWED_SURFACES.has(data.surface)) {
            surface = data.surface;
        }
    }

    return {
        messageId: data.messageId,
        reason: data.reason as UnsafeReportReason,
        details,
        conversationId,
        surface,
    };
}
