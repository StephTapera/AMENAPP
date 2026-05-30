/**
 * orgAlgoliaSync.ts
 *
 * Cloud Function: `algolia_syncOrg`
 *
 * Syncs org stub records from the Firestore `organizations` collection to
 * the Algolia `organizations` index.
 *
 * Two modes:
 *   1. Single-org sync: { orgId: string }
 *      Reads one org from Firestore and upserts to Algolia.
 *
 *   2. Bulk sync: { bulkSync: true, limit?: number }
 *      Queries organizations where searchIndexed == false (max 500 per call).
 *      Upserts each to Algolia, then sets searchIndexed = true on success.
 *
 * Algolia record shape (NEVER includes billing or claimedBy):
 *   {
 *     objectID, name, normalizedName, type, source, claimStatus,
 *     city, state, zip, _geoloc: { lat, lng }, modules, schemaVersion
 *   }
 *
 * Security: Admin-only callable.
 *
 * Index privacy:
 *   Only claimStatus values: unclaimed, claimed, verified are indexed.
 *   "pending" and "rejected" orgs are NOT indexed.
 *   Billing data is NEVER included in Algolia records.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";
import { isOrgSeedEnabled } from "./orgImportUtils";

const REGION = "us-central1";
const db = admin.firestore();

const ALGOLIA_APP_ID = "182SCN7O9S";
const algoliaAdminKey = defineSecret("ALGOLIA_ADMIN_KEY");

const INDEXABLE_CLAIM_STATUSES = new Set(["unclaimed", "claimed", "verified"]);
const MAX_BULK_LIMIT = 500;

// ─── Algolia record shape ─────────────────────────────────────────────────────

interface AlgoliaOrgRecord {
    objectID: string;
    name: string;
    normalizedName: string;
    type: string;
    source: string;
    claimStatus: string;
    city: string;
    state: string;
    zip: string;
    /** Algolia geo field — present only when org has coordinates. */
    _geoloc?: { lat: number; lng: number };
    modules: string[];
    schemaVersion: number;
    // NOTE: billing and claimedBy are intentionally omitted
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

export const algolia_syncOrg = onCall(
    {
        region: REGION,
        timeoutSeconds: 300,
        memory: "256MiB",
        secrets: [algoliaAdminKey],
    },
    async (request) => {
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required.");
        }

        const flags = await isOrgSeedEnabled();
        if (!flags.orgPlatform) {
            logger.warn("[algolia_syncOrg] orgPlatformEnabled flag is off — returning early");
            return { skipped: true, reason: "orgPlatformEnabled flag is off" };
        }

        const data = request.data as
            | { orgId: string; bulkSync?: never }
            | { bulkSync: true; limit?: number; orgId?: never };

        const apiKey = algoliaAdminKey.value();
        if (!apiKey) {
            throw new HttpsError("failed-precondition", "ALGOLIA_ADMIN_KEY secret is not set.");
        }

        if (data.bulkSync === true) {
            return await runBulkSync(apiKey, data.limit);
        }

        if (data.orgId) {
            return await runSingleSync(apiKey, data.orgId);
        }

        throw new HttpsError("invalid-argument", "Provide either orgId or bulkSync: true");
    }
);

// ─── Single-org sync ──────────────────────────────────────────────────────────

async function runSingleSync(
    apiKey: string,
    orgId: string
): Promise<{ synced: number; skipped: number }> {
    const docSnap = await db.collection("organizations").doc(orgId).get();
    if (!docSnap.exists) {
        throw new HttpsError("not-found", `Organization ${orgId} not found.`);
    }

    const record = toAlgoliaRecord(orgId, docSnap.data() as Record<string, unknown>);
    if (!record) {
        logger.info(`[algolia_syncOrg] Skipping org ${orgId} — claimStatus not indexable`);
        return { synced: 0, skipped: 1 };
    }

    await algoliaUpsert(apiKey, record);

    // Mark as indexed
    await db.collection("organizations").doc(orgId).update({
        searchIndexed: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[algolia_syncOrg] Synced org ${orgId}`);
    return { synced: 1, skipped: 0 };
}

// ─── Bulk sync ────────────────────────────────────────────────────────────────

async function runBulkSync(
    apiKey: string,
    limitArg?: number
): Promise<{ synced: number; skipped: number; errorCount: number }> {
    const limit = Math.min(limitArg ?? MAX_BULK_LIMIT, MAX_BULK_LIMIT);

    const snap = await db
        .collection("organizations")
        .where("searchIndexed", "==", false)
        .limit(limit)
        .get();

    logger.info(`[algolia_syncOrg] Bulk sync — ${snap.docs.length} unindexed orgs`);

    let synced = 0;
    let skipped = 0;
    let errorCount = 0;

    // Algolia batch upsert (saveObjects) — up to 1000 per call
    const records: AlgoliaOrgRecord[] = [];
    const docRefs: string[] = [];

    for (const docSnap of snap.docs) {
        const record = toAlgoliaRecord(docSnap.id, docSnap.data() as Record<string, unknown>);
        if (!record) {
            skipped++;
            continue;
        }
        records.push(record);
        docRefs.push(docSnap.id);
    }

    if (records.length > 0) {
        try {
            await algoliaBatchUpsert(apiKey, records);

            // Mark all synced docs as indexed in a Firestore batch
            // Firestore batch limit is 500; records.length is already <= MAX_BULK_LIMIT (500)
            const batch = db.batch();
            for (const docId of docRefs) {
                batch.update(db.collection("organizations").doc(docId), {
                    searchIndexed: true,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            await batch.commit();
            synced = records.length;
        } catch (err) {
            logger.error("[algolia_syncOrg] Bulk upsert failed", { err });
            errorCount++;
        }
    }

    logger.info(`[algolia_syncOrg] Bulk sync done — synced=${synced}, skipped=${skipped}, errors=${errorCount}`);
    return { synced, skipped, errorCount };
}

// ─── Algolia Record Builder ───────────────────────────────────────────────────

function toAlgoliaRecord(
    orgId: string,
    data: Record<string, unknown>
): AlgoliaOrgRecord | null {
    const claimStatus = data.claimStatus as string | undefined;

    // Only index orgs with appropriate claim status
    if (!claimStatus || !INDEXABLE_CLAIM_STATUSES.has(claimStatus)) {
        return null;
    }

    const geo = data.geo as { latitude: number; longitude: number } | null | undefined;

    const record: AlgoliaOrgRecord = {
        objectID: orgId,
        name: (data.name as string) ?? "",
        normalizedName: (data.normalizedName as string) ?? "",
        type: (data.type as string) ?? "",
        source: (data.source as string) ?? "",
        claimStatus,
        city: (data.city as string) ?? "",
        state: (data.state as string) ?? "",
        zip: (data.zip as string) ?? "",
        modules: (data.modules as string[]) ?? [],
        schemaVersion: (data.schemaVersion as number) ?? 1,
        // billing and claimedBy intentionally OMITTED
    };

    if (geo?.latitude != null && geo?.longitude != null) {
        record._geoloc = { lat: geo.latitude, lng: geo.longitude };
    }

    return record;
}

// ─── Algolia HTTP Helpers ─────────────────────────────────────────────────────

async function algoliaUpsert(apiKey: string, record: AlgoliaOrgRecord): Promise<void> {
    const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/organizations/${encodeURIComponent(record.objectID)}`;
    const response = await fetch(url, {
        method: "PUT",
        headers: {
            "Content-Type": "application/json",
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": apiKey,
        },
        body: JSON.stringify(record),
    });

    if (!response.ok) {
        const body = await response.text().catch(() => "");
        throw new Error(`Algolia PUT failed: ${response.status} ${body}`);
    }
}

async function algoliaBatchUpsert(apiKey: string, records: AlgoliaOrgRecord[]): Promise<void> {
    const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/organizations/batch`;
    const body = {
        requests: records.map((r) => ({
            action: "updateObject",
            body: r,
        })),
    };

    const response = await fetch(url, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": apiKey,
        },
        body: JSON.stringify(body),
    });

    if (!response.ok) {
        const respBody = await response.text().catch(() => "");
        throw new Error(`Algolia batch failed: ${response.status} ${respBody}`);
    }
}
