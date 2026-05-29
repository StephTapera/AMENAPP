/**
 * sensitiveActionGate.ts
 *
 * Callable: requireRecentAuth
 *
 * Gate that protects sensitive account operations (email change, password change,
 * account deletion, 2FA disable) by verifying the user authenticated RECENTLY —
 * not just that they hold a valid session.
 *
 * HOW IT WORKS:
 *   Firebase ID tokens carry an `auth_time` claim (seconds since epoch) set
 *   at the moment the user signed in. A stale session may have a valid token
 *   but an old `auth_time` — this gate enforces a recency window.
 *
 *   1. Client calls requireRecentAuth({ action }) just before a sensitive op.
 *   2. This function reads request.auth.token.auth_time from the verified ID
 *      token (cannot be forged — it's set by Firebase Auth at sign-in time).
 *   3. If auth_time is within MAX_AUTH_AGE_SECONDS (5 minutes by default),
 *      a short-lived grant is written to Firestore at:
 *        sensitiveActionGrants/{uid}_{action}
 *      The grant expires in GRANT_TTL_SECONDS (5 minutes).
 *   4. The downstream callable (e.g. initiateEmailChange) calls
 *      consumeSensitiveActionGrant(uid, action) to verify and consume the grant
 *      before proceeding.
 *
 * CLIENT FLOW:
 *   if (requiresReauth) {
 *     // Present re-authentication UI (sign-in prompt or Face ID)
 *     await reauthenticate()
 *     // Force-refresh the ID token to pick up updated auth_time
 *     await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
 *   }
 *   await requireRecentAuth({ action: "delete_account" })
 *   await userAccountDeletionCascade({})
 *
 * SUPPORTED ACTIONS:
 *   "delete_account" | "change_email" | "change_password" | "disable_2fa"
 *   | "link_payment" | "export_data"
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = "us-central1";
const MAX_AUTH_AGE_SECONDS = 5 * 60;      // must have signed in within 5 minutes
const GRANT_TTL_SECONDS = 5 * 60;         // grant valid for 5 minutes after issue

const SUPPORTED_ACTIONS = new Set([
    "delete_account",
    "change_email",
    "change_password",
    "disable_2fa",
    "link_payment",
    "export_data",
]);

// ── Helpers ───────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

function grantDocId(uid: string, action: string): string {
    return `${uid}_${action}`;
}

// ── requireRecentAuth ─────────────────────────────────────────────────────────

export const requireRecentAuth = onCall(
    { region: REGION, enforceAppCheck: true },
    async (request: CallableRequest) => {
        const userId = requireAuth(request);

        const action = typeof request.data?.action === "string"
            ? request.data.action
            : "";

        if (!SUPPORTED_ACTIONS.has(action)) {
            throw new HttpsError(
                "invalid-argument",
                `Unsupported sensitive action: "${action}". Allowed: ${[...SUPPORTED_ACTIONS].join(", ")}.`
            );
        }

        // auth_time is in the Firebase ID token payload — seconds since epoch.
        // It is set by Firebase Auth at sign-in time and cannot be forged.
        const authTimeSeconds: number = (request.auth!.token as { auth_time?: number }).auth_time ?? 0;
        const nowSeconds = Math.floor(Date.now() / 1000);
        const authAgeSeconds = nowSeconds - authTimeSeconds;

        if (authAgeSeconds > MAX_AUTH_AGE_SECONDS) {
            logger.info("[sensitiveActionGate] Stale session — re-auth required", {
                userId,
                action,
                authAgeSeconds,
            });
            return {
                granted: false,
                requiresReauth: true,
                authAgeSeconds,
                maxAllowedAgeSeconds: MAX_AUTH_AGE_SECONDS,
                message: "Please sign in again before performing this action.",
            };
        }

        // Auth is fresh — issue a single-use grant.
        const grantId = grantDocId(userId, action);
        const expiresAtMs = Date.now() + GRANT_TTL_SECONDS * 1000;

        await db.collection("sensitiveActionGrants").doc(grantId).set({
            uid: userId,
            action,
            issuedAt: FieldValue.serverTimestamp(),
            expiresAtMs,
            consumed: false,
        });

        logger.info("[sensitiveActionGate] Grant issued", {
            userId,
            action,
            authAgeSeconds,
            expiresAtMs,
        });

        return {
            granted: true,
            requiresReauth: false,
            authAgeSeconds,
            grantExpiresInSeconds: GRANT_TTL_SECONDS,
        };
    }
);

// ── consumeSensitiveActionGrant ───────────────────────────────────────────────

/**
 * Called by downstream callables before performing a sensitive operation.
 * Throws HttpsError("permission-denied") if no valid unconsumed grant exists.
 * Atomically marks the grant as consumed so it cannot be reused.
 */
export async function consumeSensitiveActionGrant(
    uid: string,
    action: string
): Promise<void> {
    const grantRef = db.collection("sensitiveActionGrants").doc(grantDocId(uid, action));

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(grantRef);

        if (!snap.exists) {
            throw new HttpsError(
                "permission-denied",
                "Re-authentication required. Please sign in again and retry."
            );
        }

        const data = snap.data()!;

        if (data.consumed === true) {
            throw new HttpsError(
                "permission-denied",
                "This authorization grant has already been used."
            );
        }

        if (Date.now() > (data.expiresAtMs as number)) {
            throw new HttpsError(
                "permission-denied",
                "Authorization grant expired. Please sign in again and retry."
            );
        }

        if (data.uid !== uid || data.action !== action) {
            throw new HttpsError(
                "permission-denied",
                "Authorization grant mismatch."
            );
        }

        // Consume the grant atomically.
        tx.update(grantRef, { consumed: true, consumedAt: FieldValue.serverTimestamp() });
    });

    logger.info("[sensitiveActionGate] Grant consumed", { uid, action });
}
