/**
 * amenLiveCallable.js
 * AMEN App — Amen Live callable Cloud Functions
 *
 * Exports three v2 onCall functions:
 *
 *   startAmenLiveSession  — pastor/admin only; creates a live session
 *   endAmenLiveSession    — pastor/admin only; marks session inactive
 *   recordLiveAction      — any authenticated user; logs banner action
 *
 * Add to functions/index.js:
 *   const { startAmenLiveSession, endAmenLiveSession, recordLiveAction }
 *       = require('./intelligence/amenLiveCallable');
 *   exports.startAmenLiveSession = startAmenLiveSession;
 *   exports.endAmenLiveSession   = endAmenLiveSession;
 *   exports.recordLiveAction     = recordLiveAction;
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { startLiveSession, endLiveSession } = require("./amenLive");

const REGION = "us-central1";

// ── Role helper ───────────────────────────────────────────────────────────────

/**
 * Verify the caller has the pastor or admin custom claim.
 * Throws HttpsError('permission-denied') if not.
 *
 * @param {object} request - onCall request object
 */
function requirePastorOrAdmin(request) {
    const claims = request.auth?.token ?? {};
    if (!claims.pastor && !claims.admin) {
        throw new HttpsError(
            "permission-denied",
            "Only pastors and admins can manage live sessions."
        );
    }
}

// ── startAmenLiveSession ──────────────────────────────────────────────────────

/**
 * Start a new Amen Live session.
 *
 * Auth:  required; caller must have pastor or admin custom claim
 *
 * Request data:
 *   {
 *     title:                    string   (required)
 *     subtitle?:                string
 *     type:                     string   AmenLiveType rawValue (required)
 *     hostId:                   string   (required)
 *     hostName:                 string   (required)
 *     backingEntityId:          string   (required)
 *     backingEntityKind:        string   "CHURCH" | "EVENT" | "ORG" (required)
 *     actionLabel:              string   (required)
 *     actionHandler:            string   CF callable name (required)
 *     actionTarget:             string   (required)
 *     scheduledDurationMinutes?: number
 *   }
 *
 * Response: { sessionId: string }
 */
exports.startAmenLiveSession = onCall({ region: REGION }, async (request) => {
    // ── Auth guard ────────────────────────────────────────────────────────────
    if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Must be signed in to start a live session."
        );
    }
    requirePastorOrAdmin(request);

    const db = getFirestore();

    try {
        const sessionId = await startLiveSession(request.data ?? {}, db);
        return { sessionId };
    } catch (err) {
        if (err instanceof HttpsError) throw err;
        console.error("[startAmenLiveSession] Error:", err);
        // Surface validation errors (from amenLive.js) as invalid-argument
        throw new HttpsError(
            "invalid-argument",
            err.message ?? "Failed to start live session."
        );
    }
});

// ── endAmenLiveSession ────────────────────────────────────────────────────────

/**
 * End an active Amen Live session.
 *
 * Auth:  required; caller must have pastor or admin custom claim
 *
 * Request data:
 *   { sessionId: string }
 *
 * Response: { success: true }
 */
exports.endAmenLiveSession = onCall({ region: REGION }, async (request) => {
    // ── Auth guard ────────────────────────────────────────────────────────────
    if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Must be signed in to end a live session."
        );
    }
    requirePastorOrAdmin(request);

    const { sessionId } = request.data ?? {};

    if (!sessionId || typeof sessionId !== "string" || sessionId.trim() === "") {
        throw new HttpsError(
            "invalid-argument",
            "sessionId must be a non-empty string."
        );
    }

    const db = getFirestore();

    try {
        await endLiveSession(sessionId.trim(), db);
        return { success: true };
    } catch (err) {
        if (err instanceof HttpsError) throw err;
        console.error("[endAmenLiveSession] Error:", err);
        throw new HttpsError(
            "not-found",
            err.message ?? "Failed to end live session."
        );
    }
});

// ── recordLiveAction ──────────────────────────────────────────────────────────

/**
 * Record a user's action on an Amen Live banner (e.g. tapping the action button).
 *
 * Auth:  required (any authenticated user)
 *
 * Request data:
 *   {
 *     sessionId: string   (required)
 *     action:    string   (required, e.g. "joined", "prayed", "rsvped")
 *     targetId:  string   (required)
 *   }
 *
 * Response: { recorded: true }
 *
 * Write target: intelligence_actions/{userId}/actions/{actionId}
 *
 * Formation invariants:
 *   - NO counts, NO metrics written to the action document
 *   - Action document is append-only (no updates to existing actions)
 */
exports.recordLiveAction = onCall({ region: REGION }, async (request) => {
    // ── Auth guard ────────────────────────────────────────────────────────────
    if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Must be signed in to record a live action."
        );
    }

    const uid = request.auth.uid;
    const { sessionId, action, targetId } = request.data ?? {};

    // ── Input validation ──────────────────────────────────────────────────────
    if (!sessionId || typeof sessionId !== "string" || sessionId.trim() === "") {
        throw new HttpsError("invalid-argument", "sessionId is required.");
    }
    if (!action || typeof action !== "string" || action.trim() === "") {
        throw new HttpsError("invalid-argument", "action is required.");
    }
    if (!targetId || typeof targetId !== "string" || targetId.trim() === "") {
        throw new HttpsError("invalid-argument", "targetId is required.");
    }

    const db = getFirestore();

    // ── Write action document ─────────────────────────────────────────────────
    // Path: intelligence_actions/{userId}/actions/{auto-id}
    // This subcollection structure keeps user action data under the user's path
    // and is consistent with other intelligence action writes in the codebase.
    try {
        await db
            .collection("intelligence_actions")
            .doc(uid)
            .collection("actions")
            .add({
                sessionId:   sessionId.trim(),
                action:      action.trim(),
                targetId:    targetId.trim(),
                recordedAt:  FieldValue.serverTimestamp(),
                // Formation invariants — deliberately absent:
                // NO counts, NO metrics, NO engagement signals
            });

        return { recorded: true };
    } catch (err) {
        if (err instanceof HttpsError) throw err;
        console.error("[recordLiveAction] Error:", err);
        throw new HttpsError(
            "internal",
            "Failed to record live action. Please try again."
        );
    }
});
