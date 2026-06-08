/**
 * deleteAlgoliaUser.ts — Account deletion: remove Algolia search index records
 *
 * Called by AccountDeletionService.deleteAccount() as part of the full account
 * deletion flow required by App Store Guideline 5.1.1.
 *
 * Deletes all records associated with the user from:
 *   - "users" index  (one record per user, objectID = userId)
 *   - "posts"  index (all posts authored by the user)
 *
 * The Algolia Admin API key is stored in Firebase Secret Manager and never
 * exposed to the client binary (AlgoliaConfig.writeAPIKey is intentionally empty).
 */

import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ── Algolia REST helpers ─────────────────────────────────────────────────────
// We call Algolia's REST API directly to avoid adding another npm dependency.
// The algoliasearch SDK can be added later if the codebase adopts it broadly.

const ALGOLIA_APP_ID = "182SCN7O9S";
const ALGOLIA_WRITE_KEY_SECRET = "ALGOLIA_ADMIN_KEY"; // Firebase Secret Manager key name

async function getAlgoliaAdminKey(): Promise<string> {
    // In production the key is injected via Firebase Secret Manager.
    // During local emulator development, fall back to process.env.
    const secretValue =
        process.env[ALGOLIA_WRITE_KEY_SECRET] ??
        functions.config()?.algolia?.adminkey ?? "";

    if (!secretValue) {
        throw new Error(
            "[deleteAlgoliaUser] Algolia admin key not configured. " +
            `Set the '${ALGOLIA_WRITE_KEY_SECRET}' secret in Firebase Secret Manager: ` +
            `firebase functions:secrets:set ${ALGOLIA_WRITE_KEY_SECRET}`
        );
    }
    return secretValue;
}

async function algoliaDeleteObject(
    indexName: string,
    objectID: string,
    adminKey: string
): Promise<void> {
    const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/${encodeURIComponent(indexName)}/${encodeURIComponent(objectID)}`;
    const response = await fetch(url, {
        method: "DELETE",
        headers: {
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": adminKey,
        },
    });
    if (!response.ok && response.status !== 404) {
        const body = await response.text();
        throw new Error(
            `[deleteAlgoliaUser] DELETE ${indexName}/${objectID} failed: ${response.status} ${body}`
        );
    }
}

async function algoliaDeleteByFilter(
    indexName: string,
    filterExpression: string,
    adminKey: string
): Promise<void> {
    // deleteBy — removes all records matching a filter without paging
    const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/${encodeURIComponent(indexName)}/deleteBy`;
    const response = await fetch(url, {
        method: "POST",
        headers: {
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": adminKey,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ filters: filterExpression }),
    });
    if (!response.ok) {
        const body = await response.text();
        throw new Error(
            `[deleteAlgoliaUser] deleteBy ${indexName} filters='${filterExpression}' failed: ${response.status} ${body}`
        );
    }
}

// ── Cloud Function ────────────────────────────────────────────────────────────

export const deleteAlgoliaUser = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const callerUid = context.auth.uid;
    const requestedUid = typeof data?.userId === "string" ? data.userId.trim() : "";

    if (!requestedUid) {
        throw new HttpsError("invalid-argument", "userId is required.");
    }

    // Only the account owner or an admin may delete Algolia records.
    const isAdmin = context.auth.token.admin === true;
    if (callerUid !== requestedUid && !isAdmin) {
        throw new HttpsError(
            "permission-denied",
            "You can only delete your own Algolia records."
        );
    }

    // Verify the user document is already being deleted (exists check as a guard).
    // We don't fail hard here — the caller may have already deleted the Firestore doc.
    const userSnap = await db.collection("users").doc(requestedUid).get();
    if (userSnap.exists && callerUid !== requestedUid) {
        // Only admins can delete another user's records while their doc still exists
        if (!isAdmin) {
            throw new HttpsError(
                "permission-denied",
                "User document still exists and caller is not admin."
            );
        }
    }

    let adminKey: string;
    try {
        adminKey = await getAlgoliaAdminKey();
    } catch (err) {
        // Key not configured — log and return success to avoid blocking deletion
        functions.logger.error("[deleteAlgoliaUser] Admin key unavailable — skipping Algolia delete", err);
        return { success: false, reason: "algolia_key_not_configured" };
    }

    const errors: string[] = [];

    // 1. Delete the user's own record from the "users" index
    try {
        await algoliaDeleteObject("users", requestedUid, adminKey);
        functions.logger.info(`[deleteAlgoliaUser] Deleted users/${requestedUid}`);
    } catch (err) {
        errors.push(`users record: ${String(err)}`);
        functions.logger.warn("[deleteAlgoliaUser] Failed to delete user record", err);
    }

    // 2. Delete all posts authored by the user from the "posts" index.
    // The "posts" index stores authorId as an attribute — deleteBy filters on it.
    try {
        await algoliaDeleteByFilter("posts", `authorId:${requestedUid}`, adminKey);
        functions.logger.info(`[deleteAlgoliaUser] Deleted posts for authorId=${requestedUid}`);
    } catch (err) {
        errors.push(`posts records: ${String(err)}`);
        functions.logger.warn("[deleteAlgoliaUser] Failed to delete post records", err);
    }

    if (errors.length > 0) {
        // Partial failure — log for ops investigation but don't block account deletion
        functions.logger.error("[deleteAlgoliaUser] Partial failure", { errors });
        return { success: false, errors };
    }

    return { success: true };
});
