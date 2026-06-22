/**
 * algoliaWorkSync.ts
 *
 * Keeps the Algolia catalog_works and catalog_creators indexes in sync with
 * Firestore. These indexes back the searchCatalog callable in catalogSearch.ts.
 *
 * WHY THIS EXISTS:
 *   catalogSearch.ts queries Algolia indexes named "catalog_works" and
 *   "catalog_creators". Before this file existed, no Firestore trigger
 *   populated those indexes — the Algolia search path always fell through
 *   to Pinecone/Firestore because the indexes were empty.
 *
 * Permission model:
 *   catalog_works  — only indexes works with reviewState="published" AND
 *                    visibility="public". Followers-only/private/deleted works
 *                    are NEVER indexed (Algolia cannot enforce per-user ACL).
 *   catalog_creators — indexes verified creator profiles (public metadata only).
 *                      No private fields (email, phone, internalNotes) are indexed.
 *
 * Functions:
 *   algoliaWorkWriteSync     — onDocumentWritten trigger on works/{workId}
 *   algoliaCreatorWriteSync  — onDocumentWritten trigger on catalogCreators/{creatorId}
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
const ALGOLIA_INDEX_WORKS    = "catalog_works";
const ALGOLIA_INDEX_CREATORS = "catalog_creators";

const algoliaAdminKey = defineSecret("ALGOLIA_ADMIN_KEY");

// ─── Algolia REST helper ───────────────────────────────────────────────────────

async function algoliaUpsert(
    indexName: string,
    objectID: string,
    record: Record<string, unknown>
): Promise<void> {
    const apiKey = algoliaAdminKey.value();
    if (!apiKey) {
        logger.warn(`[algoliaWorkSync] ALGOLIA_ADMIN_KEY not set — skipping upsert to ${indexName}/${objectID}`);
        return;
    }
    const url = `https://${ALGOLIA_APP_ID}.algolia.net/1/indexes/${encodeURIComponent(indexName)}/${encodeURIComponent(objectID)}`;
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
        logger.warn(`[algoliaWorkSync] Algolia PUT ${indexName}/${objectID} → ${res.status}: ${body}`);
    }
}

async function algoliaDelete(indexName: string, objectID: string): Promise<void> {
    const apiKey = algoliaAdminKey.value();
    if (!apiKey) {
        logger.warn(`[algoliaWorkSync] ALGOLIA_ADMIN_KEY not set — skipping delete from ${indexName}/${objectID}`);
        return;
    }
    const url = `https://${ALGOLIA_APP_ID}.algolia.net/1/indexes/${encodeURIComponent(indexName)}/${encodeURIComponent(objectID)}`;
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
        logger.warn(`[algoliaWorkSync] Algolia DELETE ${indexName}/${objectID} → ${res.status}: ${body}`);
    }
}

// ─── Works sync ───────────────────────────────────────────────────────────────

/**
 * Syncs a single work document to/from the catalog_works Algolia index.
 *
 * Index rule:
 *   - Only reviewState="published" AND visibility="public" works are indexed.
 *   - Any change that moves a work OUT of that state removes it from the index.
 *   - Deleted works (deletedAt field set or document deleted) are removed.
 *
 * Fields indexed: workId, creatorId, creatorName, title, type, topics,
 *   coverUrl, publishedAt, visibility, reviewState.
 * Fields NOT indexed: articleText, captions, links (too large / not needed for search).
 */
export const algoliaWorkWriteSync = onDocumentWritten(
    {
        document: "works/{workId}",
        secrets: [algoliaAdminKey],
        region: "us-east1",
    },
    async (event) => {
        const workId = event.params.workId;
        const after  = event.data?.after;

        // Deletion — hard delete or soft delete both remove from index
        if (!after?.exists) {
            await algoliaDelete(ALGOLIA_INDEX_WORKS, workId);
            logger.info(`[algoliaWorkSync] Removed deleted work ${workId} from ${ALGOLIA_INDEX_WORKS}`);
            return;
        }

        const data = after.data() ?? {};

        // Soft-delete guard: deletedAt field present and non-null
        if (data["deletedAt"] !== undefined && data["deletedAt"] !== null) {
            await algoliaDelete(ALGOLIA_INDEX_WORKS, workId);
            logger.info(`[algoliaWorkSync] Removed soft-deleted work ${workId} from ${ALGOLIA_INDEX_WORKS}`);
            return;
        }

        const reviewState: string = (data["reviewState"] as string) ?? "";
        const visibility:  string = (data["visibility"]  as string) ?? "";

        // PERMISSION GATE: only public + published works are discoverable via Algolia.
        // Followers-only and private works cannot be filtered in Algolia at query time
        // because Algolia does not support per-user ACL for these tiers.
        if (reviewState !== "published" || visibility !== "public") {
            // If a previously-indexed work changed state, remove it
            await algoliaDelete(ALGOLIA_INDEX_WORKS, workId);
            logger.info(
                `[algoliaWorkSync] Removed non-public/non-published work ${workId} ` +
                `(reviewState=${reviewState}, visibility=${visibility})`
            );
            return;
        }

        // Build the searchable record — only safe public metadata
        const publishedAtField = data["publishedAt"];
        let publishedAt: number | undefined;
        if (publishedAtField && typeof (publishedAtField as { toMillis?: () => number }).toMillis === "function") {
            publishedAt = (publishedAtField as { toMillis: () => number }).toMillis();
        }

        const record: Record<string, unknown> = {
            workId,
            creatorId:   (data["creatorId"]   as string) ?? "",
            creatorName: (data["creatorName"]  as string) ?? "",
            title:       (data["title"]        as string) ?? "",
            type:        (data["type"]         as string) ?? "article",
            topics:      (data["topics"]       as string[]) ?? [],
            coverUrl:    (data["coverUrl"]     as string | undefined),
            publishedAt,
            visibility:  "public",   // invariant: only public works reach this point
            reviewState: "published", // invariant
        };

        // Remove undefined values — Algolia rejects them
        for (const key of Object.keys(record)) {
            if (record[key] === undefined) {
                delete record[key];
            }
        }

        await algoliaUpsert(ALGOLIA_INDEX_WORKS, workId, record);
        logger.info(`[algoliaWorkSync] Upserted work ${workId} to ${ALGOLIA_INDEX_WORKS}`);
    }
);

// ─── Creator profile sync ─────────────────────────────────────────────────────

/**
 * Syncs a catalogCreator document to/from the catalog_creators Algolia index.
 *
 * Privacy rules:
 *   - Only the following fields are indexed: displayName, badge, verified,
 *     workCount, topics, avatarUrl, entityType, bio.
 *   - Internal fields (email, internalNotes, stripeCustomerId, etc.) are
 *     NEVER included in the Algolia record.
 *   - Soft-deleted creators (deletedAt set) are removed from the index.
 *
 * The objectID in Algolia equals the Firestore document ID (creatorId).
 */
export const algoliaCreatorWriteSync = onDocumentWritten(
    {
        document: "catalogCreators/{creatorId}",
        secrets: [algoliaAdminKey],
        region: "us-east1",
    },
    async (event) => {
        const creatorId = event.params.creatorId;
        const after     = event.data?.after;

        // Hard deletion
        if (!after?.exists) {
            await algoliaDelete(ALGOLIA_INDEX_CREATORS, creatorId);
            logger.info(`[algoliaWorkSync] Removed deleted creator ${creatorId} from ${ALGOLIA_INDEX_CREATORS}`);
            return;
        }

        const data = after.data() ?? {};

        // Soft-delete guard
        if (data["deletedAt"] !== undefined && data["deletedAt"] !== null) {
            await algoliaDelete(ALGOLIA_INDEX_CREATORS, creatorId);
            logger.info(`[algoliaWorkSync] Removed soft-deleted creator ${creatorId} from ${ALGOLIA_INDEX_CREATORS}`);
            return;
        }

        // Build the searchable record — only safe public metadata
        // displayNameLower stored for case-insensitive prefix fallback queries
        const displayName: string = (data["displayName"] as string) ?? "";
        const record: Record<string, unknown> = {
            id:              creatorId,
            displayName,
            displayNameLower: displayName.toLowerCase(),
            badge:           data["badge"]       as string | undefined,
            verified:        (data["verified"]   as boolean) ?? false,
            workCount:       (data["workCount"]  as number)  ?? 0,
            topics:          (data["topics"]     as string[]) ?? [],
            avatarUrl:       data["avatarUrl"]   as string | undefined,
            entityType:      (data["entityType"] as string) ?? "person",
            bio:             (data["bio"]        as string) ?? "",
        };

        // Remove undefined values
        for (const key of Object.keys(record)) {
            if (record[key] === undefined) {
                delete record[key];
            }
        }

        await algoliaUpsert(ALGOLIA_INDEX_CREATORS, creatorId, record);
        logger.info(`[algoliaWorkSync] Upserted creator ${creatorId} to ${ALGOLIA_INDEX_CREATORS}`);
    }
);
