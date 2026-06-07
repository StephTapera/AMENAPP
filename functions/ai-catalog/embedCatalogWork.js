/**
 * embedCatalogWork.js — AI Catalog Embedding Pipeline
 *
 * Embedding pipeline for catalog Works. When a creator's work is approved or
 * published, we embed its text content into Pinecone (namespace:
 * `creator-catalog-{creatorId}`) and index it in Algolia (`catalog_works`).
 *
 * Exports (Firebase Functions v1 onCall + Firestore triggers):
 *   embedWork          — onCall: manually trigger embedding for a single work
 *   onWorkApproved     — Firestore trigger: fires on reviewState → 'approved'/'published'
 *   removeWorkEmbedding — internal helper (also exported for reuse by other CFs)
 *   SYSTEM_PROMPTS     — consumed by askCreatorQuery.js
 *
 * Security:
 *   - embedWork requires authenticated caller; server verifies creatorId ownership
 *   - Only reviewState 'approved' or 'published' works are embedded
 *   - Deleted works are skipped / cleaned up
 *
 * Dependencies already in the project (mlClients.js):
 *   openaiEmbed(text) → float[]
 *   pineconeUpsert(namespace, [{id, values, metadata}])
 *   pineconeDelete(namespace, [id])
 *
 * Algolia: lazy-required (algoliasearch package, same as algoliaSync.js).
 */

"use strict";

const functions = require("firebase-functions");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin     = require("firebase-admin");
const logger    = require("firebase-functions/logger");

const { openaiEmbed, pineconeUpsert, pineconeDelete } = require("../mlClients");

// ── Algolia lazy init ─────────────────────────────────────────────────────────
// Separate catalog index — never overwrite the existing "posts" index.
const ALGOLIA_CATALOG_INDEX = "catalog_works";

let _algoliaIndex = null;
function getCatalogAlgoliaIndex() {
  if (_algoliaIndex) return _algoliaIndex;
  const algoliasearch = require("algoliasearch");
  const appId  = process.env.ALGOLIA_APP_ID  || "";
  const apiKey = process.env.ALGOLIA_ADMIN_API_KEY || "";
  const client = algoliasearch(appId, apiKey);
  _algoliaIndex = client.initIndex(ALGOLIA_CATALOG_INDEX);
  return _algoliaIndex;
}

// ── Pinecone namespace helper ─────────────────────────────────────────────────
function catalogNamespace(creatorId) {
  return `creator-catalog-${creatorId}`;
}

// ── Embedding text builder ─────────────────────────────────────────────────────
/**
 * Builds a plain-text representation of a work suitable for embedding.
 * Deliberately excludes URLs and links — semantic text only.
 */
function buildEmbeddingText(work) {
  const parts = [];
  if (work.title)       parts.push(work.title.trim());
  if (work.subtitle)    parts.push(work.subtitle.trim());
  if (work.description) parts.push(work.description.trim());
  // topics may be an array of strings or objects with a .name field
  if (Array.isArray(work.topics)) {
    const topicLabels = work.topics.map((t) =>
      typeof t === "string" ? t : (t.name || t.label || "")
    ).filter(Boolean);
    if (topicLabels.length) parts.push(topicLabels.join(", "));
  }
  return parts.join("\n\n");
}

// ── Core embed logic (shared between onCall + trigger) ────────────────────────
/**
 * Embeds a single work into Pinecone + Algolia.
 * Resolves the work from Firestore if only workId is provided.
 *
 * @param {string} workId
 * @param {FirebaseFirestore.DocumentData | null} workData — pass null to re-fetch
 * @returns {Promise<{success: boolean, workId: string}>}
 */
async function _embedWorkInternal(workId, workData = null) {
  const db = admin.firestore();

  // Fetch if not provided
  if (!workData) {
    const snap = await db.collection("works").doc(workId).get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", `Work ${workId} not found.`);
    }
    workData = snap.data();
  }

  // Guard: only embed approved/published, non-deleted works
  const state = workData.reviewState;
  if (state !== "approved" && state !== "published") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Work ${workId} has reviewState '${state}'; only 'approved' or 'published' works are embedded.`
    );
  }
  if (workData.deletedAt) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Work ${workId} is soft-deleted and cannot be embedded.`
    );
  }

  const creatorId = workData.creatorId;
  if (!creatorId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `Work ${workId} is missing creatorId.`
    );
  }

  // Build embedding input text
  const text = buildEmbeddingText(workData);
  if (!text.trim()) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `Work ${workId} has no embeddable text content.`
    );
  }

  // Generate embedding vector via OpenAI text-embedding-3-small
  logger.info("[embedCatalog] Generating embedding", { workId, creatorId });
  const vector = await openaiEmbed(text);

  // Metadata stored alongside vector in Pinecone
  const metadata = {
    workId,
    creatorId,
    title:       workData.title        || "",
    type:        workData.type         || "unknown",
    reviewState: workData.reviewState  || "published",
    visibility:  workData.visibility   || "public",
    topics:      Array.isArray(workData.topics)
                   ? workData.topics.map((t) => (typeof t === "string" ? t : (t.name || "")))
                   : [],
    sourceUrl:   (workData.links && workData.links[0]?.url) || workData.sourceUrl || "",
    publishedAt: workData.publishedAt
                   ? (workData.publishedAt.toDate
                       ? workData.publishedAt.toDate().toISOString()
                       : String(workData.publishedAt))
                   : "",
  };

  const namespace = catalogNamespace(creatorId);

  // Upsert to Pinecone
  await pineconeUpsert(namespace, [{ id: workId, values: vector, metadata }]);
  logger.info("[embedCatalog] Pinecone upsert complete", { workId, namespace });

  // Index to Algolia catalog_works
  try {
    const algoliaIndex = getCatalogAlgoliaIndex();
    await algoliaIndex.saveObject({
      objectID:    workId,
      creatorId,
      title:       workData.title       || "",
      description: workData.description || "",
      type:        workData.type        || "unknown",
      topics:      metadata.topics,
      visibility:  workData.visibility  || "public",
      reviewState: workData.reviewState || "published",
      publishedAt: metadata.publishedAt,
      coverUrl:    workData.coverUrl    || "",
    });
    logger.info("[embedCatalog] Algolia index updated", { workId });
  } catch (algoliaErr) {
    // Algolia failure is non-fatal — log and continue
    logger.warn("[embedCatalog] Algolia index failed (non-fatal)", { workId, err: algoliaErr.message });
  }

  // Update work doc with embeddingRef
  await db.collection("works").doc(workId).update({
    embeddingRef: {
      namespace,
      vectorId:   workId,
      embeddedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  });

  return { success: true, workId };
}

// ── removeWorkEmbedding ───────────────────────────────────────────────────────
/**
 * Deletes a work's vector from Pinecone and removes it from Algolia.
 * Called when a work is soft-deleted or reverted to draft.
 *
 * @param {string} workId
 * @param {string} creatorId
 */
async function removeWorkEmbedding(workId, creatorId) {
  if (!workId || !creatorId) {
    logger.warn("[embedCatalog] removeWorkEmbedding: missing workId or creatorId", { workId, creatorId });
    return;
  }

  const namespace = catalogNamespace(creatorId);

  // Delete from Pinecone
  try {
    await pineconeDelete(namespace, [workId]);
    logger.info("[embedCatalog] Pinecone vector deleted", { workId, namespace });
  } catch (err) {
    logger.warn("[embedCatalog] Pinecone delete failed (non-fatal)", { workId, err: err.message });
  }

  // Delete from Algolia
  try {
    const algoliaIndex = getCatalogAlgoliaIndex();
    await algoliaIndex.deleteObject(workId);
    logger.info("[embedCatalog] Algolia object deleted", { workId });
  } catch (err) {
    logger.warn("[embedCatalog] Algolia delete failed (non-fatal)", { workId, err: err.message });
  }

  // Clear embeddingRef on work doc
  try {
    const db = admin.firestore();
    await db.collection("works").doc(workId).update({
      embeddingRef: admin.firestore.FieldValue.delete(),
    });
  } catch (err) {
    logger.warn("[embedCatalog] Clearing embeddingRef failed", { workId, err: err.message });
  }
}

// ── embedWork — onCall CF ─────────────────────────────────────────────────────
/**
 * Manually trigger embedding for a single work.
 *
 * Request: { workId: string }
 * Response: { success: true, workId: string }
 *
 * Auth required. The caller must either be the work's creator or have admin claim.
 */
exports.embedWork = functions.https.onCall(async (data, context) => {
  // Auth gate
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }

  const { workId } = data || {};
  if (!workId || typeof workId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "workId is required.");
  }

  const db   = admin.firestore();
  const snap = await db.collection("works").doc(workId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", `Work ${workId} not found.`);
  }
  const workData = snap.data();

  // Ownership check: caller must be creator or admin
  const isAdmin   = context.auth.token?.admin === true;
  const isCreator = workData.creatorId === context.auth.uid;
  if (!isAdmin && !isCreator) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "You can only embed your own works."
    );
  }

  return _embedWorkInternal(workId, workData);
});

// ── onWorkApproved — Firestore trigger ───────────────────────────────────────
/**
 * Automatically embeds a work when its reviewState transitions to
 * 'approved' or 'published'. Also triggers topic graph update via
 * topicClusterEngine (imported lazily to avoid circular deps).
 */
exports.onWorkApproved = onDocumentUpdated("works/{workId}", async (event) => {
    const before = event.data?.before.data() || {};
    const after  = event.data?.after.data()  || {};

    const workId = event.params.workId;

    const targetStates = ["approved", "published"];
    const wasTarget    = targetStates.includes(before.reviewState);
    const isTarget     = targetStates.includes(after.reviewState);

    // Only fire on transition INTO an approved/published state
    if (!isTarget) return null;
    // If it was already in a target state and still is (e.g. title update),
    // still re-embed to keep the vector fresh.

    // If soft-deleted, run removal instead
    if (after.deletedAt) {
      logger.info("[onWorkApproved] Work deleted — removing embedding", { workId });
      await removeWorkEmbedding(workId, after.creatorId);
      return null;
    }

    // Embed
    try {
      await _embedWorkInternal(workId, after);
    } catch (err) {
      logger.error("[onWorkApproved] Embedding failed", { workId, err: err.message });
      // Non-fatal at trigger level — don't retry infinitely
    }

    return null;
  });

// ── Export removeWorkEmbedding for use by other CFs ──────────────────────────
exports.removeWorkEmbedding = removeWorkEmbedding;

// ── SYSTEM_PROMPTS ────────────────────────────────────────────────────────────
/**
 * System prompt templates used by askCreatorQuery.js via the callModel router.
 * The {citations}, {creatorName}, and {question} placeholders are replaced at
 * query time.
 *
 * RULES in this prompt are NON-NEGOTIABLE and must not be altered by callers.
 */
const SYSTEM_PROMPTS = {
  catalog_qa: `You are answering questions about a creator's published work.

RULES (NEVER VIOLATE):
1. Only answer from the provided source citations below.
2. If no relevant citation exists, respond: "I can only answer from {creatorName}'s published catalog. No matching source was found for this question."
3. Never fabricate quotes, opinions, or beliefs not found in the citations.
4. Label your answer mode: "creator_said" if you are directly quoting or referencing a specific work, "ai_summary" if you are paraphrasing across multiple works.
5. Every claim must have a citation with workId and snippet.
6. Never reveal private, draft, or unpublished content.

Citations:
{citations}

Creator: {creatorName}
Question: {question}`,
};

module.exports.SYSTEM_PROMPTS = SYSTEM_PROMPTS;
