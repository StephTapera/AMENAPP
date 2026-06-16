/**
 * algoliaUserSync.ts
 *
 * Keeps the Algolia "users" index in sync with the Firestore "users" collection.
 *
 * WHY THIS EXISTS:
 *   The default codebase comment in functions/index.js line 580 states that
 *   user/post Algolia sync is "handled by installed Firestore extension
 *   ext-firestore-algolia-search". That extension is NOT installed in firebase.json
 *   (only firestore-send-email is). This trigger closes the gap.
 *
 * Permission model:
 *   - Only adult and unclassified users are indexed (minors excluded per COPPA).
 *   - Private account users ARE indexed (they appear in search with a lock icon
 *     in the UI; the client filters follow requests appropriately).
 *   - Sensitive fields (email, phone, DOB, internalNotes) are NEVER indexed.
 *   - Suspended/disabled users are removed from the index.
 *
 * Functions:
 *   algoliaUserWriteSync — onDocumentWritten trigger on users/{userId}
 *
 * Region: us-east1 (us-central1 at quota; see CLAUDE.md §us-central1 Quota Warning)
 */

import {
    onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";

// ─── Constants ────────────────────────────────────────────────────────────────

const ALGOLIA_APP_ID      = "182SCN7O9S";
const ALGOLIA_INDEX_USERS = "users";

const algoliaAdminKey = defineSecret("ALGOLIA_ADMIN_KEY");

// ─── Algolia REST helper ───────────────────────────────────────────────────────

async function algoliaUpsert(
    objectID: string,
    record: Record<string, unknown>
): Promise<void> {
    const apiKey = algoliaAdminKey.value();
    if (!apiKey) {
        logger.warn(`[algoliaUserSync] ALGOLIA_ADMIN_KEY not set — skipping upsert ${objectID}`);
        return;
    }
    const url = `https://${ALGOLIA_APP_ID}.algolia.net/1/indexes/${encodeURIComponent(ALGOLIA_INDEX_USERS)}/${encodeURIComponent(objectID)}`;
    const res = await fetch(url, {
        method: "PUT",
        headers: {
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": apiKey,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ ...record, objectID }),
        signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok && res.status !== 200 && res.status !== 201) {
        const body = await res.text().catch(() => "unknown");
        logger.warn(`[algoliaUserSync] Algolia PUT users/${objectID} → ${res.status}: ${body}`);
    }
}

async function algoliaDelete(objectID: string): Promise<void> {
    const apiKey = algoliaAdminKey.value();
    if (!apiKey) {
        logger.warn(`[algoliaUserSync] ALGOLIA_ADMIN_KEY not set — skipping delete ${objectID}`);
        return;
    }
    const url = `https://${ALGOLIA_APP_ID}.algolia.net/1/indexes/${encodeURIComponent(ALGOLIA_INDEX_USERS)}/${encodeURIComponent(objectID)}`;
    const res = await fetch(url, {
        method: "DELETE",
        headers: {
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": apiKey,
        },
        signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok && res.status !== 200 && res.status !== 404) {
        const body = await res.text().catch(() => "unknown");
        logger.warn(`[algoliaUserSync] Algolia DELETE users/${objectID} → ${res.status}: ${body}`);
    }
}

// ─── User sync trigger ─────────────────────────────────────────────────────────

/**
 * algoliaUserWriteSync — syncs user profile changes to the Algolia "users" index.
 *
 * Fields indexed (public metadata only):
 *   displayName, username, usernameLowercase, bio, followersCount,
 *   followingCount, profileImageURL, isVerified, createdAt, authorIsPrivate, _tags.
 *
 * Fields NEVER indexed:
 *   email, phone, dateOfBirth, pushToken, stripeCustomerId, internalNotes,
 *   blockedUsers, and any field not explicitly listed above.
 *
 * Removal conditions:
 *   - User document deleted (hard delete)
 *   - User marked as suspended: true (disabled account)
 *   - User ageTier = "minor" (COPPA compliance — minors must not appear in search)
 */
export const algoliaUserWriteSync = onDocumentWritten(
    {
        document: "users/{userId}",
        secrets: [algoliaAdminKey],
        region: "us-east1",
    },
    async (event) => {
        const userId = event.params.userId;
        const after  = event.data?.after;

        // Hard deletion — remove from index
        if (!after?.exists) {
            await algoliaDelete(userId);
            logger.info(`[algoliaUserSync] Removed deleted user ${userId} from Algolia`);
            return;
        }

        const data = after.data() ?? {};

        // COPPA compliance: never index minor accounts
        const ageTier: string = (data["ageTier"] as string) ?? "";
        if (ageTier === "minor") {
            await algoliaDelete(userId);
            logger.info(`[algoliaUserSync] Removed minor user ${userId} from Algolia (ageTier=minor)`);
            return;
        }

        // Suspended accounts should not be discoverable
        if (data["suspended"] === true || data["disabled"] === true) {
            await algoliaDelete(userId);
            logger.info(`[algoliaUserSync] Removed suspended user ${userId} from Algolia`);
            return;
        }

        // Soft-delete guard: deletedAt field present and non-null
        if (data["deletedAt"] !== undefined && data["deletedAt"] !== null) {
            await algoliaDelete(userId);
            logger.info(`[algoliaUserSync] Removed soft-deleted user ${userId} from Algolia`);
            return;
        }

        // Build the searchable record — only safe public metadata
        const displayName: string = (data["displayName"] as string) ?? "";
        const username: string    = (data["username"]    as string) ?? "";

        // createdAt timestamp → epoch seconds
        const createdAtField = data["createdAt"];
        let createdAt: number = 0;
        if (createdAtField && typeof (createdAtField as { toMillis?: () => number }).toMillis === "function") {
            createdAt = (createdAtField as { toMillis: () => number }).toMillis() / 1000;
        } else if (typeof createdAtField === "number") {
            createdAt = createdAtField;
        }

        const isPrivate = (data["isPrivate"] as boolean) ?? false;

        const record: Record<string, unknown> = {
            displayName,
            username,
            usernameLowercase: username.toLowerCase(),
            bio:             (data["bio"]             as string) ?? "",
            followersCount:  (data["followersCount"]  as number) ?? 0,
            followingCount:  (data["followingCount"]  as number) ?? 0,
            profileImageURL: (data["profileImageURL"] as string) ?? "",
            isVerified:      (data["isVerified"]      as boolean) ?? false,
            createdAt,
            authorIsPrivate: isPrivate,
            _tags:           ["user"],
        };

        // Remove undefined values — Algolia rejects them
        for (const key of Object.keys(record)) {
            if (record[key] === undefined) delete record[key];
        }

        await algoliaUpsert(userId, record);
        logger.info(`[algoliaUserSync] Upserted user ${userId} to Algolia`);
    }
);
