/**
 * sessionRevocation.ts
 *
 * Callables:
 *   revokeAllSessions        — "Sign out of all devices" — revokes all refresh tokens
 *   reportAccountCompromise  — User-initiated compromise flag: revokes tokens + queues review
 *
 * Why token revocation matters:
 *   Firebase ID tokens are valid for up to 1 hour after issuance even if the
 *   password changes or the account is disabled. revokeRefreshTokens() prevents
 *   the client from obtaining a new ID token after the current one expires,
 *   effectively terminating all sessions at the next token refresh boundary.
 *
 * IMPORTANT: After calling revokeRefreshTokens(), the user's Firebase Auth
 * listener on the client will receive a sign-out event within 1 hour (at the
 * next ID token refresh). The client should immediately sign out locally after
 * calling revokeAllSessions.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

const REGION = "us-central1";

// ── Helpers ───────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

async function doRevokeAllSessions(
    uid: string,
    reason: string,
    triggeredBy: string
): Promise<void> {
    await auth.revokeRefreshTokens(uid);

    await db.collection("sessionAuditLog").add({
        uid,
        action: "revoke_all_sessions",
        reason,
        triggeredBy,
        revokedAt: FieldValue.serverTimestamp(),
    });

    // Write a sentinel the client can observe to force local sign-out.
    await db.collection("users").doc(uid).set(
        {
            lastGlobalRevocationAt: FieldValue.serverTimestamp(),
            sessionsRevokedReason: reason,
        },
        { merge: true }
    );

    logger.info("[sessionRevocation] All sessions revoked", { uid, reason, triggeredBy });
}

// ── revokeAllSessions ─────────────────────────────────────────────────────────

export const revokeAllSessions = onCall(
    { region: REGION, enforceAppCheck: true },
    async (request: CallableRequest) => {
        const userId = requireAuth(request);

        await doRevokeAllSessions(userId, "user_requested", `user:${userId}`);

        return { success: true, message: "All active sessions have been terminated." };
    }
);

// ── reportAccountCompromise ───────────────────────────────────────────────────

export const reportAccountCompromise = onCall(
    { region: REGION, enforceAppCheck: true },
    async (request: CallableRequest) => {
        const userId = requireAuth(request);

        const details =
            typeof request.data?.details === "string"
                ? request.data.details.slice(0, 500)
                : "";

        // 1. Revoke all refresh tokens immediately.
        await doRevokeAllSessions(userId, "user_reported_compromise", `user:${userId}`);

        // 2. Create a security incident record for the Trust & Safety team.
        await db.collection("securityIncidents").add({
            uid: userId,
            type: "account_compromise_report",
            details,
            status: "pending_review",
            reportedAt: FieldValue.serverTimestamp(),
            reviewedAt: null,
            reviewedBy: null,
        });

        // 3. Flag the user document so the client shows a security notice.
        await db.collection("users").doc(userId).set(
            {
                securityIncidentPending: true,
                securityIncidentReportedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
        );

        logger.warn("[sessionRevocation] Account compromise reported", { userId });

        return {
            success: true,
            message: "Your sessions have been terminated and our security team has been alerted.",
        };
    }
);

/**
 * Internal helper for other modules (e.g. accountSuspension, deletion cascade)
 * to revoke all sessions as part of their own flows.
 */
export async function revokeAllSessionsForUid(
    uid: string,
    reason: string,
    triggeredBy: string
): Promise<void> {
    try {
        await doRevokeAllSessions(uid, reason, triggeredBy);
    } catch (err) {
        // Log but do not throw — the caller's own operation should not fail due
        // to a token revocation error. The session will expire naturally.
        logger.warn("[sessionRevocation] revokeAllSessionsForUid failed", { uid, reason, err });
    }
}
