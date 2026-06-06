/**
 * topicClusterEngine.js — KnowledgeNode Topic Graph Population
 *
 * Responsible for extracting topics from catalog works (Phase 1: keyword/regex
 * matching — no AI cost) and maintaining the KnowledgeNode graph in Firestore.
 *
 * KnowledgeNode schema (Firestore: knowledgeNodes/{nodeId}):
 *   { id, creatorId, topic, workRefs: [workId], parentId: null }
 *   nodeId = `{creatorId}_{topicSlug}`
 *
 * Exports:
 *   extractTopicsFromWork(work)   — pure function, returns string[]
 *   updateKnowledgeNodes          — onCall CF: rebuild graph for a creatorId
 *   onWorkPublished               — Firestore trigger on works/{workId} update
 */

"use strict";

const functions = require("firebase-functions");
const admin     = require("firebase-admin");
const logger    = require("firebase-functions/logger");

// ── Predefined topic taxonomy ─────────────────────────────────────────────────
// Checked against title + description + work.topics via lowercase keyword match.
// Order matters for determinism; more specific phrases listed before generic ones.
const TOPIC_TAXONOMY = [
  // Faith & Theology
  "Scripture",
  "Theology",
  "Doctrine",
  "Apologetics",
  "Church History",
  "Hermeneutics",
  "Evangelism",
  "Missions",
  "Discipleship",
  "Worship",
  "Prayer",
  "Fasting",
  "Faith",
  "Grace",
  "Salvation",
  "Sanctification",
  "Holy Spirit",
  "Trinity",
  "Baptism",
  "Communion",
  // Life & Relationships
  "Marriage",
  "Parenting",
  "Family",
  "Relationships",
  "Dating",
  "Singleness",
  "Sexuality",
  "Gender",
  "Men",
  "Women",
  // Justice & Society
  "Justice",
  "Race",
  "Politics",
  "Culture",
  "Ethics",
  "Human Trafficking",
  "Immigration",
  "Poverty",
  "Activism",
  // Personal Growth
  "Mental Health",
  "Anxiety",
  "Depression",
  "Trauma",
  "Healing",
  "Identity",
  "Purpose",
  "Grief",
  "Forgiveness",
  "Habits",
  "Creativity",
  "Education",
  "Calling",
  "Vocation",
  // Professional & Innovation
  "Leadership",
  "Entrepreneurship",
  "Startups",
  "Business",
  "Finance",
  "Economics",
  "Technology",
  "AI",
  "Innovation",
  "Management",
  "Career",
  // Health & Body
  "Health",
  "Fitness",
  "Nutrition",
  "Wellness",
  // Media & Arts
  "Music",
  "Film",
  "Literature",
  "Art",
  "Preaching",
  "Storytelling",
  // Other
  "Community",
  "Church",
  "Youth",
  "Generosity",
  "Stewardship",
];

// ── Keyword → canonical topic map ─────────────────────────────────────────────
// Extra keyword aliases that map back to taxonomy entries.
const KEYWORD_ALIASES = {
  "bible":       "Scripture",
  "verse":       "Scripture",
  "passage":     "Scripture",
  "sermon":      "Preaching",
  "pastor":      "Preaching",
  "preach":      "Preaching",
  "god":         "Faith",
  "jesus":       "Faith",
  "christ":      "Faith",
  "christian":   "Faith",
  "startup":     "Startups",
  "founder":     "Entrepreneurship",
  "entrepreneur":"Entrepreneurship",
  "invest":      "Finance",
  "money":       "Finance",
  "wealth":      "Finance",
  "tech":        "Technology",
  "artificial intelligence": "AI",
  "machine learning": "AI",
  "anxiety":     "Mental Health",
  "depression":  "Mental Health",
  "trauma":      "Mental Health",
  "leader":      "Leadership",
  "management":  "Leadership",
  "marriage":    "Marriage",
  "husband":     "Marriage",
  "wife":        "Marriage",
  "couple":      "Marriage",
  "parent":      "Parenting",
  "children":    "Parenting",
  "kids":        "Parenting",
  "race":        "Race",
  "racism":      "Race",
  "justice":     "Justice",
  "worship":     "Worship",
  "praise":      "Worship",
  "prayer":      "Prayer",
  "pray":        "Prayer",
};

// ── slugify helper ─────────────────────────────────────────────────────────────
function slugify(topic) {
  return topic
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");
}

// ── extractTopicsFromWork ─────────────────────────────────────────────────────
/**
 * Phase 1: keyword matching — no AI cost.
 *
 * Strategy:
 *   1. Start with topics explicitly attached to the work (work.topics array).
 *   2. Scan title + description against TOPIC_TAXONOMY (case-insensitive).
 *   3. Scan title + description against KEYWORD_ALIASES.
 *
 * @param {object} work — Firestore document data for a catalog work
 * @returns {string[]} — deduplicated canonical topic strings
 */
function extractTopicsFromWork(work) {
  const found = new Set();

  // 1. Work's explicit topics field
  if (Array.isArray(work.topics)) {
    work.topics.forEach((t) => {
      const label = typeof t === "string" ? t : (t.name || t.label || "");
      if (label) found.add(label.trim());
    });
  }

  // Build a single searchable text blob from title + description
  const textBlob = [
    work.title       || "",
    work.subtitle    || "",
    work.description || "",
  ].join(" ").toLowerCase();

  // 2. Scan against full taxonomy entries
  for (const topic of TOPIC_TAXONOMY) {
    if (textBlob.includes(topic.toLowerCase())) {
      found.add(topic);
    }
  }

  // 3. Scan against keyword aliases
  for (const [keyword, canonical] of Object.entries(KEYWORD_ALIASES)) {
    if (textBlob.includes(keyword)) {
      found.add(canonical);
    }
  }

  return Array.from(found);
}

// ── _rebuildNodesForCreator — core logic ──────────────────────────────────────
/**
 * Queries all approved+published works for a creator, extracts topics from
 * each, and batch-writes KnowledgeNode docs.
 *
 * KnowledgeNode upsert is merge-based: workRefs are accumulated across runs.
 *
 * @param {string} creatorId
 * @returns {Promise<{nodesUpdated: number}>}
 */
async function _rebuildNodesForCreator(creatorId) {
  const db = admin.firestore();

  // Query all approved + published works for this creator
  const worksSnap = await db.collection("works")
    .where("creatorId", "==", creatorId)
    .where("reviewState", "in", ["approved", "published"])
    .get();

  if (worksSnap.empty) {
    logger.info("[topicCluster] No qualifying works found", { creatorId });
    return { nodesUpdated: 0 };
  }

  // Accumulate topic → workIds mapping
  const topicWorkMap = {};   // topic → Set<workId>

  worksSnap.forEach((doc) => {
    const work   = doc.data();
    const workId = doc.id;
    // Skip deleted
    if (work.deletedAt) return;

    const topics = extractTopicsFromWork(work);
    topics.forEach((topic) => {
      if (!topicWorkMap[topic]) topicWorkMap[topic] = new Set();
      topicWorkMap[topic].add(workId);
    });
  });

  const topicEntries = Object.entries(topicWorkMap);
  if (!topicEntries.length) {
    logger.info("[topicCluster] No topics extracted for creator", { creatorId });
    return { nodesUpdated: 0 };
  }

  // Batch write KnowledgeNodes — Firestore max 500 ops per batch
  const MAX_BATCH = 500;
  let batchCount = 0;
  let batch      = db.batch();
  let opsInBatch = 0;

  for (const [topic, workIds] of topicEntries) {
    const nodeId  = `${creatorId}_${slugify(topic)}`;
    const nodeRef = db.collection("knowledgeNodes").doc(nodeId);

    const nodeData = {
      id:        nodeId,
      creatorId,
      topic,
      workRefs:  Array.from(workIds),
      parentId:  null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    batch.set(nodeRef, nodeData, { merge: true });
    opsInBatch++;

    if (opsInBatch >= MAX_BATCH) {
      await batch.commit();
      batchCount += opsInBatch;
      batch       = db.batch();
      opsInBatch  = 0;
    }
  }

  // Commit any remaining ops
  if (opsInBatch > 0) {
    await batch.commit();
    batchCount += opsInBatch;
  }

  logger.info("[topicCluster] KnowledgeNodes updated", { creatorId, nodesUpdated: batchCount });
  return { nodesUpdated: batchCount };
}

// ── updateKnowledgeNodes — onCall CF ─────────────────────────────────────────
/**
 * Manually rebuild the KnowledgeNode graph for a creator.
 *
 * Request: { creatorId: string }
 * Response: { success: true, creatorId, nodesUpdated: number }
 *
 * Auth required. Caller must be the creator or an admin.
 */
exports.updateKnowledgeNodes = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }

  const { creatorId } = data || {};
  if (!creatorId || typeof creatorId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "creatorId is required.");
  }

  const isAdmin   = context.auth.token?.admin === true;
  const isSelf    = context.auth.uid === creatorId;
  if (!isAdmin && !isSelf) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "You can only update KnowledgeNodes for your own creator profile."
    );
  }

  const result = await _rebuildNodesForCreator(creatorId);
  return { success: true, creatorId, ...result };
});

// ── onWorkPublished — Firestore trigger ───────────────────────────────────────
/**
 * Fires whenever a work document is updated. When reviewState transitions to
 * 'published', rebuild KnowledgeNodes for that creator.
 */
exports.onWorkPublished = functions.firestore
  .document("works/{workId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after  = change.after.data()  || {};

    // Only care about transitions to 'published'
    if (after.reviewState !== "published") return null;
    if (before.reviewState === "published") return null;   // already published, skip

    const creatorId = after.creatorId;
    if (!creatorId) {
      logger.warn("[onWorkPublished] Work missing creatorId", { workId: context.params.workId });
      return null;
    }

    // Extract topics for this specific work (lightweight; full rebuild also runs)
    const topics = extractTopicsFromWork(after);
    logger.info("[onWorkPublished] Topics extracted", {
      workId: context.params.workId,
      creatorId,
      topics,
    });

    // Rebuild the full KnowledgeNode graph for this creator
    try {
      await _rebuildNodesForCreator(creatorId);
    } catch (err) {
      logger.error("[onWorkPublished] KnowledgeNode rebuild failed", {
        creatorId,
        err: err.message,
      });
    }

    return null;
  });

// ── Export pure function for testing + reuse ──────────────────────────────────
module.exports.extractTopicsFromWork = extractTopicsFromWork;
