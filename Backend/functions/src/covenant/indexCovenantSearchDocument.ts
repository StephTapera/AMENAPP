import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

// indexCovenantSearchDocument / deleteCovenantSearchDocument
// Firestore triggers that sync Covenant content to the search provider (Algolia/Typesense placeholder).
// Search results respect permissions — isLocked flag is written to the search index
// so the client can show locked content with a paywall prompt vs. hide it entirely.
//
// Production: replace searchIndex.saveObject/deleteObject with real Algolia/Typesense calls.

async function syncToSearchIndex(id: string, payload: Record<string, unknown> | null): Promise<void> {
    // PLACEHOLDER: Replace with Algolia or Typesense SDK call.
    // Example Algolia:
    //   const client = algoliasearch(ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY);
    //   const index = client.initIndex(ALGOLIA_INDEX_NAME);
    //   if (payload) await index.saveObject({ objectID: id, ...payload });
    //   else await index.deleteObject(id);
    console.log(`[SearchIndex] ${payload ? "Upsert" : "Delete"} document ${id}`);
}

// Trigger: when a covenant post is created/updated/deleted
export const indexCovenantPost = onDocumentWritten(
    { document: "covenants/{covenantId}/posts/{postId}", region: "us-central1" },
    async (event) => {
        const { covenantId, postId } = event.params;
        const after = event.data?.after;

        if (!after?.exists) {
            // Deletion
            await syncToSearchIndex(`post_${covenantId}_${postId}`, null);
            return;
        }

        const data = after.data() ?? {};
        await syncToSearchIndex(`post_${covenantId}_${postId}`, {
            type: "posts",
            covenantId,
            title: data.title ?? data.body?.slice(0, 120) ?? "",
            subtitle: data.authorDisplayName,
            isLocked: data.isLocked ?? false,
            createdAt: data.createdAt?.toMillis() ?? 0,
        });
    }
);

// searchCovenantDocuments callable — routes to search provider
export const searchCovenantDocuments = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }

        const { query, scope, covenantId } = request.data;
        if (!query?.trim()) {
            throw new HttpsError("invalid-argument", "query is required.");
        }

        // PLACEHOLDER: Implement actual Algolia/Typesense search here.
        // Filter by covenantId, scope, and user's membership status.
        // Never return documents the user cannot access without a paywall flag.
        const hits: Array<{
            id: string;
            type: string;
            title: string;
            subtitle?: string;
            isLocked: boolean;
        }> = [];

        return { hits };
    }
);
