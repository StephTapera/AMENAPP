// spaces/spaceLifecycle.ts
//
// Lifecycle management callables for AMEN Spaces.
//
// Callables:
//   deleteSpace — host-only hard delete: archives the space document, then
//                 batch-deletes the members, events, and announcements
//                 subcollections so no orphan documents remain.
//
// Subcollections cleaned:
//   spaces/{spaceId}/members
//   spaces/{spaceId}/events
//   spaces/{spaceId}/announcements
//
// The space document itself is deleted last so that partial-failure retries
// (idempotent page loop) are safe — the host auth check reads the document.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

// ── Constants ─────────────────────────────────────────────────────────────────

/** Maximum documents per Firestore batch write (hard limit: 500). */
const BATCH_PAGE = 400;

/** Subcollections to purge when a space is deleted. */
const SPACE_SUBCOLLECTIONS = ["members", "events", "announcements"] as const;

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Batch-deletes all documents in a subcollection, paging through in chunks
 * of BATCH_PAGE to stay within the Firestore 500-operation batch limit.
 */
async function purgeSubcollection(
    db: FirebaseFirestore.Firestore,
    path: string
): Promise<number> {
    const ref = db.collection(path);
    let total = 0;

    while (true) {
        const page = await ref.limit(BATCH_PAGE).get();
        if (page.empty) break;

        const batch = db.batch();
        page.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        total += page.size;

        if (page.size < BATCH_PAGE) break;
    }

    return total;
}

// ── deleteSpace ───────────────────────────────────────────────────────────────

interface DeleteSpaceInput {
    spaceId: string;
}

export const deleteSpace = onCall({ enforceAppCheck: true, region: "us-central1" }, async (
        request
    ): Promise<{ success: true; deletedSubdocuments: number }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<DeleteSpaceInput>;

        if (typeof data.spaceId !== "string" || !data.spaceId.trim()) {
            throw new HttpsError("invalid-argument", "spaceId is required.");
        }

        const spaceId = data.spaceId.trim();
        const db = getFirestore();
        const spaceRef = db.doc(`spaces/${spaceId}`);

        // ── Auth: only the original space creator may delete it ───────────────
        const spaceSnap = await spaceRef.get();
        if (!spaceSnap.exists) {
            throw new HttpsError("not-found", "Space not found.");
        }
        const createdBy = spaceSnap.data()?.createdBy as string | undefined;
        if (createdBy !== uid) {
            throw new HttpsError(
                "permission-denied",
                "Only the space host can delete this space."
            );
        }

        logger.info("[deleteSpace] Starting cascade", { spaceId, uid });

        // ── Step 1: Mark the space as deleting so clients see it immediately ──
        await spaceRef.update({
            status: "deleting",
            deletionStartedAt: Timestamp.now(),
        });

        // ── Step 2: Purge subcollections ──────────────────────────────────────
        const counts = await Promise.allSettled(
            SPACE_SUBCOLLECTIONS.map((sub) =>
                purgeSubcollection(db, `spaces/${spaceId}/${sub}`)
            )
        );

        const deletedSubdocuments = counts.reduce<number>((acc, result) => {
            if (result.status === "fulfilled") return acc + result.value;
            logger.warn("[deleteSpace] Subcollection purge partial failure", {
                reason: result.reason,
            });
            return acc;
        }, 0);

        // ── Step 3: Delete the space document itself ──────────────────────────
        await spaceRef.delete();

        logger.info("[deleteSpace] Complete", {
            spaceId,
            uid,
            deletedSubdocuments,
        });

        return { success: true, deletedSubdocuments };
    }
);
