// engagement.ts
// Counter triggers for communityNotes engagement + searchCommunityNotes callable.
//
// Counter triggers:
//   likes/{likeId}       → communityNotes/{noteId}.likeCount    ± 1
//   comments/{commentId} → communityNotes/{noteId}.commentCount ± 1
//   amenReactions/{id}   → comments/{cid}.amenCount             ± 1
//   saves/{saveId}       → communityNotes/{noteId}.saveCount    ± 1
//   follows/{followId}   → users/{uid}.followingCount           ± 1
//                        → users/{targetUid}.followerCount      ± 1
//
// searchCommunityNotes callable:
//   Hybrid (keyword + semantic) search with RRF merge over Algolia + Pinecone.
//   Hydrates top-20 results from Firestore and filters to public/approved docs.

import {
  onDocumentCreated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

if (!getApps().length) initializeApp();
const db = getFirestore();

const ALGOLIA_APP_ID    = defineSecret("ALGOLIA_APP_ID");
const ALGOLIA_ADMIN_KEY = defineSecret("ALGOLIA_ADMIN_KEY");
const PINECONE_API_KEY  = defineSecret("PINECONE_API_KEY");
const OPENAI_API_KEY    = defineSecret("OPENAI_API_KEY");

const ALGOLIA_INDEX       = "community_notes";
const PINECONE_INDEX_HOST = process.env.PINECONE_INDEX_HOST ?? "";
const PINECONE_NAMESPACE  = "community_notes";
const EMBEDDING_MODEL     = "text-embedding-3-small";

// ─── Types ────────────────────────────────────────────────────────────────────

interface SearchParams {
  query: string;
  category?: string;
  scriptureKey?: string;
  mode?: "hybrid" | "keyword" | "semantic";
}

interface SearchResult {
  id: string;
  title: string;
  excerpt: string;
  category: string;
  authorName: string;
  authorHandle: string;
  authorInitial: string;
  authorColor: string;
  scriptureRefStrings: string[];
  tags: string[];
  likeCount: number;
  commentCount: number;
  saveCount: number;
}

// ─── Utility ──────────────────────────────────────────────────────────────────

async function getEmbedding(text: string, apiKey: string): Promise<number[]> {
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model: EMBEDDING_MODEL, input: text.slice(0, 8000) }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenAI embeddings error ${response.status}: ${err}`);
  }
  const json = (await response.json()) as { data: Array<{ embedding: number[] }> };
  return json.data[0].embedding;
}

// ─── Counter triggers — likes ─────────────────────────────────────────────────

export const onLikeCreated = onDocumentCreated(
  "communityNotes/{noteId}/likes/{likeId}",
  async (event) => {
    const { noteId } = event.params;
    await db.doc(`communityNotes/${noteId}`).update({
      likeCount: FieldValue.increment(1),
    });
  }
);

export const onLikeDeleted = onDocumentDeleted(
  "communityNotes/{noteId}/likes/{likeId}",
  async (event) => {
    const { noteId } = event.params;
    await db.doc(`communityNotes/${noteId}`).update({
      likeCount: FieldValue.increment(-1),
    });
  }
);

// ─── Counter triggers — comments ──────────────────────────────────────────────

export const onCommentCreated = onDocumentCreated(
  "communityNotes/{noteId}/comments/{commentId}",
  async (event) => {
    const { noteId } = event.params;
    await db.doc(`communityNotes/${noteId}`).update({
      commentCount: FieldValue.increment(1),
    });
  }
);

export const onCommentDeleted = onDocumentDeleted(
  "communityNotes/{noteId}/comments/{commentId}",
  async (event) => {
    const { noteId } = event.params;
    await db.doc(`communityNotes/${noteId}`).update({
      commentCount: FieldValue.increment(-1),
    });
  }
);

// ─── Counter triggers — amen reactions on comments ───────────────────────────

export const onAmenCreated = onDocumentCreated(
  "comments/{cid}/amenReactions/{amenId}",
  async (event) => {
    const { cid } = event.params;
    await db.doc(`comments/${cid}`).update({
      amenCount: FieldValue.increment(1),
    });
  }
);

export const onAmenDeleted = onDocumentDeleted(
  "comments/{cid}/amenReactions/{amenId}",
  async (event) => {
    const { cid } = event.params;
    await db.doc(`comments/${cid}`).update({
      amenCount: FieldValue.increment(-1),
    });
  }
);

// ─── Counter triggers — saves ─────────────────────────────────────────────────

export const onSaveCreated = onDocumentCreated(
  "communityNotes/{noteId}/saves/{saveId}",
  async (event) => {
    const { noteId } = event.params;
    await db.doc(`communityNotes/${noteId}`).update({
      saveCount: FieldValue.increment(1),
    });
  }
);

export const onSaveDeleted = onDocumentDeleted(
  "communityNotes/{noteId}/saves/{saveId}",
  async (event) => {
    const { noteId } = event.params;
    await db.doc(`communityNotes/${noteId}`).update({
      saveCount: FieldValue.increment(-1),
    });
  }
);

// ─── Counter triggers — follows ───────────────────────────────────────────────
// Document path: users/{uid}/following/{targetUid}

export const onFollowCreated = onDocumentCreated(
  "users/{uid}/following/{targetUid}",
  async (event) => {
    const { uid, targetUid } = event.params;
    await Promise.all([
      db.doc(`users/${uid}`).update({ followingCount: FieldValue.increment(1) }),
      db.doc(`users/${targetUid}`).update({ followerCount: FieldValue.increment(1) }),
    ]);
  }
);

export const onFollowDeleted = onDocumentDeleted(
  "users/{uid}/following/{targetUid}",
  async (event) => {
    const { uid, targetUid } = event.params;
    await Promise.all([
      db.doc(`users/${uid}`).update({ followingCount: FieldValue.increment(-1) }),
      db.doc(`users/${targetUid}`).update({ followerCount: FieldValue.increment(-1) }),
    ]);
  }
);

// ─── searchCommunityNotes callable ────────────────────────────────────────────

export const searchCommunityNotes = onCall<SearchParams>(
  {
    secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_KEY, PINECONE_API_KEY, OPENAI_API_KEY],
  },
  async (request) => {
    // Auth required
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required to search notes.");
    }

    const { query, category, scriptureKey, mode = "hybrid" } = request.data;

    if (!query || typeof query !== "string" || query.trim().length === 0) {
      throw new HttpsError("invalid-argument", "query is required.");
    }

    const algoliaAppId   = ALGOLIA_APP_ID.value();
    const algoliaKey     = ALGOLIA_ADMIN_KEY.value();
    const pineconeKey    = PINECONE_API_KEY.value();
    const openaiKey      = OPENAI_API_KEY.value();

    // RRF score accumulator: noteId -> score
    const rrfScores = new Map<string, number>();
    // keyword rank list (Algolia objectIDs in order)
    const keywordIds: string[] = [];
    // semantic rank list (Pinecone match IDs in order)
    const semanticIds: string[] = [];

    // ── Algolia keyword search ──────────────────────────────────────────────
    if (mode === "hybrid" || mode === "keyword") {
      const algoliaUrl = `https://${algoliaAppId}-dsn.algolia.net/1/indexes/${ALGOLIA_INDEX}/query`;
      const algoliaBody: Record<string, unknown> = {
        query,
        hitsPerPage: 40,
        attributesToRetrieve: ["objectID"],
      };
      if (category) {
        algoliaBody.filters = `category:${category}`;
      }
      if (scriptureKey) {
        // scriptureKeys are stored as _tags in Algolia
        algoliaBody.tagFilters = [[scriptureKey]];
      }
      const algoliaResponse = await fetch(algoliaUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Algolia-Application-Id": algoliaAppId,
          "X-Algolia-API-Key": algoliaKey,
        },
        body: JSON.stringify(algoliaBody),
      });
      if (algoliaResponse.ok) {
        const data = (await algoliaResponse.json()) as {
          hits: Array<{ objectID: string }>;
        };
        for (const hit of data.hits) {
          keywordIds.push(hit.objectID);
        }
      }
    }

    // ── Pinecone semantic search ────────────────────────────────────────────
    if (mode === "hybrid" || mode === "semantic") {
      try {
        const vector = await getEmbedding(query, openaiKey);
        const pineconeUrl = `${PINECONE_INDEX_HOST}/query`;
        const pineconeFilter: Record<string, unknown> = {
          visibility:       { $eq: "public" },
          moderationStatus: { $eq: "approved" },
        };
        if (category) {
          pineconeFilter.category = { $eq: category };
        }
        if (scriptureKey) {
          pineconeFilter.scriptureKeys = { $in: [scriptureKey] };
        }
        const pineconeResponse = await fetch(pineconeUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Api-Key": pineconeKey,
          },
          body: JSON.stringify({
            vector,
            topK: 40,
            namespace: PINECONE_NAMESPACE,
            filter: pineconeFilter,
            includeMetadata: false,
          }),
        });
        if (pineconeResponse.ok) {
          const data = (await pineconeResponse.json()) as {
            matches: Array<{ id: string }>;
          };
          for (const match of data.matches) {
            semanticIds.push(match.id);
          }
        }
      } catch {
        // Semantic search failure is non-fatal; fall back to keyword results
      }
    }

    // ── Reciprocal Rank Fusion ──────────────────────────────────────────────
    // score[id] += 1 / (60 + rank + 1)  for each list the id appears in
    const applyRRF = (ids: string[]) => {
      ids.forEach((id, rank) => {
        const contribution = 1 / (60 + rank + 1);
        rrfScores.set(id, (rrfScores.get(id) ?? 0) + contribution);
      });
    };
    applyRRF(keywordIds);
    applyRRF(semanticIds);

    // Sort by descending RRF score
    const ranked = Array.from(rrfScores.entries())
      .sort((a, b) => b[1] - a[1])
      .map(([id]) => id)
      .slice(0, 20);

    if (ranked.length === 0) {
      return { results: [] };
    }

    // ── Hydrate from Firestore ──────────────────────────────────────────────
    const docRefs = ranked.map((id) => db.doc(`communityNotes/${id}`));
    const snapshots = await db.getAll(...docRefs);

    const results: SearchResult[] = [];
    for (const snap of snapshots) {
      if (!snap.exists) continue;
      const d = snap.data() as Record<string, unknown>;
      // Post-hydration visibility + moderation filter
      if (d.visibility !== "public" || d.moderationStatus !== "approved") continue;

      results.push({
        id:                   snap.id,
        title:                (d.title as string | undefined)         ?? "",
        excerpt:              (d.excerpt as string | undefined)       ?? "",
        category:             (d.category as string | undefined)      ?? "",
        authorName:           (d.authorName as string | undefined)    ?? "",
        authorHandle:         (d.authorHandle as string | undefined)  ?? "",
        authorInitial:        (d.authorInitial as string | undefined) ?? "",
        authorColor:          (d.authorColor as string | undefined)   ?? "",
        scriptureRefStrings:  (d.scriptureRefStrings as string[] | undefined) ?? [],
        tags:                 (d.tags as string[] | undefined)        ?? [],
        likeCount:            (d.likeCount as number | undefined)     ?? 0,
        commentCount:         (d.commentCount as number | undefined)  ?? 0,
        saveCount:            (d.saveCount as number | undefined)     ?? 0,
      });
    }

    return { results };
  }
);
