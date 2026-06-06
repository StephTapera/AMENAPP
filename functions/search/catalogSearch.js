/**
 * catalogSearch.js
 * Agent G — Universal Catalog Search (ADDITIVE ONLY)
 *
 * Exports (all onCall, auth required):
 *   - searchCatalog        — full-text + semantic + Firestore fallback search
 *   - searchCreators       — people & organizations (never raw URLs)
 *   - getTopicSuggestions  — partial-query topic completions
 *
 * Internal (called by other CFs):
 *   - indexCreatorForSearch — upsert creator profile into Algolia catalog_creators
 *
 * Result invariant: returns PEOPLE + ORGANIZATIONS as primary type, never raw URLs.
 * Privacy invariant: only reviewState:published AND visibility:public works are returned.
 * Rate limit: 60 searches / user / hour (RTDB window counter).
 */

"use strict";

const functions = require("firebase-functions");
const admin     = require("firebase-admin");

// admin is already initialized in index.js — do not call initializeApp() again.
const db = admin.firestore();

// ── SECRET RESOLUTION ─────────────────────────────────────────────────────────

const secretCache = {};

async function getSecret(name) {
  if (secretCache[name]) return secretCache[name];
  if (process.env[name]) {
    secretCache[name] = process.env[name];
    return secretCache[name];
  }
  try {
    const { SecretManagerServiceClient } = require("@google-cloud/secret-manager");
    const client    = new SecretManagerServiceClient();
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    const [version] = await client.accessSecretVersion({
      name: `projects/${projectId}/secrets/${name}/versions/latest`,
    });
    const value = version.payload.data.toString("utf8");
    secretCache[name] = value;
    return value;
  } catch (err) {
    console.error(`[SecretManager] Failed to fetch "${name}":`, err.message);
    return null;
  }
}

// ── RATE LIMITER ──────────────────────────────────────────────────────────────
// 60 searches / user / hour using RTDB sliding-window counter.

const SEARCH_RATE_LIMIT = 60;
const RATE_WINDOW_MS    = 60 * 60 * 1000; // 1 hour

async function checkSearchRateLimit(userId) {
  const key = `rateLimits/${userId}_catalogSearch`;
  const ref = admin.database().ref(key);
  const snap = await ref.get();
  const data = snap.val() || { count: 0, resetAt: 0 };
  const now  = Date.now();

  if (now > data.resetAt) {
    await ref.set({ count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (data.count >= SEARCH_RATE_LIMIT) {
    return false;
  }
  await ref.update({ count: data.count + 1 });
  return true;
}

// ── ALGOLIA HELPERS ───────────────────────────────────────────────────────────

async function getAlgoliaCreds() {
  const [appId, adminKey, searchKey] = await Promise.all([
    getSecret("ALGOLIA_APP_ID"),
    getSecret("ALGOLIA_ADMIN_API_KEY"),
    getSecret("ALGOLIA_SEARCH_KEY"),
  ]);
  return { appId, adminKey, searchKey };
}

/**
 * Query an Algolia index via REST (no SDK — matches project style).
 * @param {string} indexName
 * @param {string} query
 * @param {object} opts — hitsPerPage, filters, attributesToRetrieve, facetFilters
 * @returns {Promise<{hits: Array, nbHits: number}>}
 */
async function algoliaQuery(indexName, query, opts = {}) {
  const { appId, adminKey } = await getAlgoliaCreds();
  if (!appId || !adminKey) throw new Error("Algolia credentials unavailable");

  const url = `https://${appId}-dsn.algolia.net/1/indexes/${encodeURIComponent(indexName)}/query`;

  const body = {
    query,
    hitsPerPage: opts.hitsPerPage ?? 20,
    ...(opts.filters && { filters: opts.filters }),
    ...(opts.attributesToRetrieve && { attributesToRetrieve: opts.attributesToRetrieve }),
    ...(opts.facetFilters && { facetFilters: opts.facetFilters }),
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Algolia-Application-Id": appId,
      "X-Algolia-API-Key": adminKey,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`Algolia ${res.status}: ${errText.slice(0, 200)}`);
  }
  return res.json();
}

/**
 * Upsert a record into an Algolia index via REST saveObject.
 */
async function algoliaUpsert(indexName, record) {
  const { appId, adminKey } = await getAlgoliaCreds();
  if (!appId || !adminKey) throw new Error("Algolia credentials unavailable");

  const url = `https://${appId}.algolia.net/1/indexes/${encodeURIComponent(indexName)}/${encodeURIComponent(record.objectID)}`;

  const res = await fetch(url, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      "X-Algolia-Application-Id": appId,
      "X-Algolia-API-Key": adminKey,
    },
    body: JSON.stringify(record),
    signal: AbortSignal.timeout(8000),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => "");
    throw new Error(`Algolia upsert ${res.status}: ${errText.slice(0, 200)}`);
  }
  return res.json();
}

// ── PINECONE HELPERS ──────────────────────────────────────────────────────────

async function generateEmbedding(text) {
  const apiKey = await getSecret("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY unavailable");

  const res = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model: "text-embedding-3-small", input: text }),
    signal: AbortSignal.timeout(10000),
  });

  if (!res.ok) throw new Error(`OpenAI embeddings ${res.status}`);
  const data = await res.json();
  return data.data?.[0]?.embedding ?? null;
}

async function getPineconeHost() {
  const host = process.env.PINECONE_HOST || await getSecret("PINECONE_HOST");
  return host;
}

/**
 * Query a Pinecone namespace and return catalog work IDs from metadata.
 * Returns [] gracefully if namespace doesn't exist or has no data.
 */
async function queryPineconeForWorks(namespace, vector) {
  const host   = await getPineconeHost();
  const apiKey = await getSecret("PINECONE_API_KEY");
  if (!host || !apiKey) return [];

  try {
    const res = await fetch(`https://${host}/query`, {
      method: "POST",
      headers: {
        "Api-Key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        vector,
        topK: 10,
        namespace,
        includeMetadata: true,
      }),
      signal: AbortSignal.timeout(5000),
    });

    if (!res.ok) return [];
    const data = await res.json();
    // metadata expected: { workId, creatorId, title, type, topics, coverUrl, publishedAt }
    return (data.matches ?? [])
      .filter((m) => m.metadata?.workId)
      .map((m) => m.metadata);
  } catch (err) {
    console.warn(`[Pinecone] Query failed for namespace "${namespace}":`, err.message);
    return [];
  }
}

// ── RESULT BUILDERS ───────────────────────────────────────────────────────────

/**
 * Group work hits (from Algolia or Pinecone) by creatorId → creator cards.
 * Fetches creator profile from Firestore for each distinct creatorId.
 */
async function buildCreatorCards(workHits) {
  // Deduplicate by creatorId
  const byCreator = new Map();
  for (const hit of workHits) {
    const cid = hit.creatorId;
    if (!cid) continue;
    if (!byCreator.has(cid)) byCreator.set(cid, []);
    byCreator.get(cid).push(hit);
  }

  const creatorIds = [...byCreator.keys()];
  if (!creatorIds.length) return { creators: [], works: [] };

  // Batch-fetch user profiles (max 10 at once for Firestore)
  const chunks   = [];
  for (let i = 0; i < creatorIds.length; i += 10) {
    chunks.push(creatorIds.slice(i, i + 10));
  }

  const profileDocs = new Map();
  for (const chunk of chunks) {
    const snaps = await Promise.all(chunk.map((id) => db.collection("users").doc(id).get()));
    for (const snap of snaps) {
      if (snap.exists) profileDocs.set(snap.id, snap.data());
    }
  }

  const creators = [];
  const works    = [];

  for (const [cid, hits] of byCreator.entries()) {
    const profile = profileDocs.get(cid) ?? {};
    creators.push({
      id: cid,
      displayName:  profile.displayName ?? profile.username ?? "Creator",
      bio:          profile.bio ?? "",
      badge:        profile.verificationBadge ?? null,
      verified:     profile.verified ?? false,
      workCount:    profile.workCount ?? hits.length,
      topics:       profile.topics ?? [],
      avatarUrl:    profile.avatarUrl ?? profile.photoURL ?? null,
      entityType:   profile.entityType ?? "person",   // "person" | "organization"
    });

    for (const hit of hits) {
      works.push({
        workId:      hit.objectID ?? hit.workId,
        creatorId:   cid,
        title:       hit.title ?? "",
        type:        hit.type ?? "article",
        topics:      hit.topics ?? [],
        coverUrl:    hit.coverUrl ?? null,
        publishedAt: hit.publishedAt ?? null,
        creatorName: profile.displayName ?? profile.username ?? "",
      });
    }
  }

  return { creators, works };
}

// ── FIRESTORE FALLBACK ────────────────────────────────────────────────────────

async function firestoreTitlePrefixFallback(query, limit) {
  const end = query + "";
  const snap = await db.collection("catalog_works")
    .where("visibility", "==", "public")
    .where("reviewState", "==", "published")
    .where("title", ">=", query)
    .where("title", "<=", end)
    .orderBy("title")
    .limit(limit)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      objectID:    doc.id,
      workId:      doc.id,
      creatorId:   d.creatorId ?? "",
      title:       d.title ?? "",
      type:        d.type ?? "article",
      topics:      d.topics ?? [],
      coverUrl:    d.coverUrl ?? null,
      publishedAt: d.publishedAt?.toMillis() ?? null,
    };
  });
}

// ── TOPIC SUGGESTIONS DATA ────────────────────────────────────────────────────

const PREDEFINED_TOPICS = [
  "Leadership", "Prayer", "Marriage", "AI", "Startups", "Faith", "Finance", "Health",
  "Relationships", "Creativity", "Scripture", "Justice", "Worship", "Education",
  "Business", "Parenting", "Mental Health", "Community", "Social Justice", "Technology",
  "Discipleship", "Evangelism", "Church", "Family", "Serving", "Missions",
  "Theology", "Apologetics", "Counseling", "Devotional",
];

function topicId(name) {
  return name.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
}

// ═════════════════════════════════════════════════════════════════════════════
// CF: searchCatalog
// ═════════════════════════════════════════════════════════════════════════════

exports.searchCatalog = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = context.auth.uid;

  // Rate limit: 60/hr/user
  const allowed = await checkSearchRateLimit(uid);
  if (!allowed) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Search rate limit reached. Please wait before searching again."
    );
  }

  const query      = (data.query ?? "").trim();
  const workType   = data.type ?? null;
  const creatorId  = data.creatorId ?? null;
  const topic      = data.topic ?? null;
  const limit      = Math.min(data.limit ?? 20, 50);

  if (!query || query.length < 2) {
    return { creators: [], works: [], topics: [] };
  }

  // Build Algolia filter — only published public works
  let filters = "reviewState:published AND visibility:public";
  if (workType)  filters += ` AND type:${workType}`;
  if (creatorId) filters += ` AND creatorId:${creatorId}`;
  if (topic)     filters += ` AND topics:${topic}`;

  let workHits = [];
  let source   = "algolia";

  // ── Primary: Algolia keyword search ──────────────────────────────────────
  try {
    const result = await algoliaQuery("catalog_works", query, {
      hitsPerPage: limit,
      filters,
      attributesToRetrieve: [
        "objectID", "creatorId", "title", "type",
        "topics", "coverUrl", "publishedAt",
      ],
    });
    workHits = result.hits ?? [];
    console.log(`[searchCatalog] Algolia returned ${workHits.length} hits for "${query}"`);
  } catch (err) {
    console.warn("[searchCatalog] Algolia failed:", err.message);
  }

  // ── Semantic fallback: Pinecone (only if Algolia returned < 3 results) ────
  if (workHits.length < 3 && query.length > 5) {
    source = "pinecone";
    try {
      const vector = await generateEmbedding(query);
      if (vector) {
        // If a specific creator is requested, use their namespace; else global
        const namespace = creatorId
          ? `creator-catalog-${creatorId}`
          : "catalog-global";

        const pineconeHits = await queryPineconeForWorks(namespace, vector);
        // Merge without duplicates
        const existingIds = new Set(workHits.map((h) => h.objectID ?? h.workId));
        for (const hit of pineconeHits) {
          if (!existingIds.has(hit.workId)) {
            workHits.push({ objectID: hit.workId, ...hit });
            existingIds.add(hit.workId);
          }
        }
        console.log(`[searchCatalog] After Pinecone (${namespace}): ${workHits.length} total hits`);
      }
    } catch (err) {
      console.warn("[searchCatalog] Pinecone fallback failed:", err.message);
    }
  }

  // ── Firestore fallback: title prefix query ────────────────────────────────
  if (workHits.length === 0) {
    source = "firestore";
    try {
      const fsHits = await firestoreTitlePrefixFallback(query, limit);
      workHits = fsHits;
      console.log(`[searchCatalog] Firestore fallback: ${workHits.length} hits`);
    } catch (err) {
      console.warn("[searchCatalog] Firestore fallback failed:", err.message);
    }
  }

  // ── Group results by creator ──────────────────────────────────────────────
  const { creators, works } = await buildCreatorCards(workHits);

  // ── Topic suggestions from query ──────────────────────────────────────────
  const qLower = query.toLowerCase();
  const matchedTopics = PREDEFINED_TOPICS
    .filter((t) => t.toLowerCase().includes(qLower))
    .slice(0, 5)
    .map((t) => ({
      topicId:      topicId(t),
      topicName:    t,
      workCount:    0,
      creatorCount: 0,
    }));

  console.log(`[searchCatalog] uid=${uid} query="${query}" source=${source} creators=${creators.length} works=${works.length}`);

  return { creators, works, topics: matchedTopics };
});

// ═════════════════════════════════════════════════════════════════════════════
// CF: searchCreators
// ═════════════════════════════════════════════════════════════════════════════

exports.searchCreators = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = context.auth.uid;

  const allowed = await checkSearchRateLimit(uid);
  if (!allowed) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Search rate limit reached."
    );
  }

  const query = (data.query ?? "").trim();
  const limit = Math.min(data.limit ?? 20, 50);

  if (!query || query.length < 2) {
    return { creators: [] };
  }

  const creatorMap = new Map(); // userId → profileData

  // ── Step 1: Algolia catalog_works — find distinct creatorIds matching query ─
  let algoliaCreatorIds = [];
  try {
    const result = await algoliaQuery("catalog_works", query, {
      hitsPerPage: 50,
      filters: "reviewState:published AND visibility:public",
      attributesToRetrieve: ["creatorId"],
    });
    const hits = result.hits ?? [];
    const seen = new Set();
    for (const hit of hits) {
      if (hit.creatorId && !seen.has(hit.creatorId)) {
        seen.add(hit.creatorId);
        algoliaCreatorIds.push(hit.creatorId);
      }
    }
  } catch (err) {
    console.warn("[searchCreators] Algolia catalog_works failed:", err.message);
  }

  // ── Step 2: Algolia catalog_creators index (creator displayName/bio) ───────
  try {
    const result = await algoliaQuery("catalog_creators", query, {
      hitsPerPage: limit,
      attributesToRetrieve: [
        "objectID", "displayName", "bio", "verified",
        "badge", "workCount", "topics", "entityType",
      ],
    });
    for (const hit of result.hits ?? []) {
      if (!creatorMap.has(hit.objectID)) {
        creatorMap.set(hit.objectID, hit);
      }
    }
  } catch (err) {
    console.warn("[searchCreators] Algolia catalog_creators failed:", err.message);
  }

  // ── Step 3: Firestore displayName prefix match (fallback) ─────────────────
  try {
    const qEnd = query + "";
    const snap = await db.collection("users")
      .where("displayName", ">=", query)
      .where("displayName", "<=", qEnd)
      .limit(limit)
      .get();
    for (const doc of snap.docs) {
      if (!creatorMap.has(doc.id)) {
        creatorMap.set(doc.id, { objectID: doc.id, ...doc.data() });
      }
    }
  } catch (err) {
    console.warn("[searchCreators] Firestore displayName fallback failed:", err.message);
  }

  // Fetch Firestore profiles for Algolia catalog_works creatorIds not yet loaded
  for (const cid of algoliaCreatorIds) {
    if (!creatorMap.has(cid)) {
      try {
        const snap = await db.collection("users").doc(cid).get();
        if (snap.exists) creatorMap.set(cid, { objectID: cid, ...snap.data() });
      } catch (_) {}
    }
  }

  // Fetch work counts for each creator
  const enrichedCreators = await Promise.all(
    [...creatorMap.values()].slice(0, limit).map(async (profile) => {
      const id = profile.objectID ?? profile.id;
      let workCount = profile.workCount ?? 0;
      if (!workCount) {
        try {
          const snap = await db.collection("catalog_works")
            .where("creatorId", "==", id)
            .where("reviewState", "==", "published")
            .where("visibility", "==", "public")
            .limit(1)
            .get();
          workCount = snap.size;
        } catch (_) {}
      }

      return {
        id,
        displayName: profile.displayName ?? profile.username ?? "Creator",
        bio:         (profile.bio ?? "").slice(0, 200),
        badge:       profile.verificationBadge ?? profile.badge ?? null,
        verified:    profile.verified ?? false,
        workCount,
        topics:      profile.topics ?? [],
        avatarUrl:   profile.avatarUrl ?? profile.photoURL ?? null,
        // Primary type: PERSON or ORGANIZATION — never a raw URL
        entityType:  profile.entityType ?? "person",
      };
    })
  );

  console.log(`[searchCreators] uid=${uid} query="${query}" found=${enrichedCreators.length}`);
  return { creators: enrichedCreators };
});

// ═════════════════════════════════════════════════════════════════════════════
// CF: getTopicSuggestions
// ═════════════════════════════════════════════════════════════════════════════

exports.getTopicSuggestions = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in required.");
  }

  const query  = (data.query ?? "").trim().toLowerCase();
  const limit  = Math.min(data.limit ?? 10, 20);

  // Match against predefined topic list
  const predefinedMatches = PREDEFINED_TOPICS
    .filter((t) => t.toLowerCase().startsWith(query) || t.toLowerCase().includes(query))
    .slice(0, limit);

  // Also query KnowledgeNodes collection for creator-defined topics
  let firestoreTopics = [];
  if (query.length >= 2) {
    try {
      const end  = query + "";
      const snap = await db.collection("knowledgeNodes")
        .where("topic", ">=", query)
        .where("topic", "<=", end)
        .limit(limit)
        .get();

      const topicAgg = new Map();
      for (const doc of snap.docs) {
        const d = doc.data();
        const t = d.topic ?? "";
        if (!t) continue;
        const key = topicId(t);
        if (!topicAgg.has(key)) {
          topicAgg.set(key, { topicId: key, topicName: t, workCount: 0, creatorCount: 0 });
        }
        const entry = topicAgg.get(key);
        entry.workCount    += d.workCount ?? 0;
        entry.creatorCount += 1;
      }
      firestoreTopics = [...topicAgg.values()];
    } catch (err) {
      console.warn("[getTopicSuggestions] Firestore query failed:", err.message);
    }
  }

  // Merge: predefined + Firestore, deduplicated
  const seen   = new Set(firestoreTopics.map((t) => t.topicId));
  const merged = [...firestoreTopics];

  for (const name of predefinedMatches) {
    const key = topicId(name);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push({ topicId: key, topicName: name, workCount: 0, creatorCount: 0 });
    }
  }

  return { topics: merged.slice(0, limit) };
});

// ═════════════════════════════════════════════════════════════════════════════
// INTERNAL: indexCreatorForSearch
// Called when a creator profile updates — upserts into Algolia catalog_creators.
// ═════════════════════════════════════════════════════════════════════════════

async function indexCreatorForSearch(userId, profileData) {
  const record = {
    objectID:     userId,
    displayName:  profileData.displayName ?? profileData.username ?? "",
    bio:          (profileData.bio ?? "").slice(0, 500),
    verified:     profileData.verified ?? false,
    badge:        profileData.verificationBadge ?? null,
    workCount:    profileData.workCount ?? 0,
    topics:       profileData.topics ?? [],
    entityType:   profileData.entityType ?? "person",
    avatarUrl:    profileData.avatarUrl ?? profileData.photoURL ?? null,
    updatedAt:    Date.now(),
  };

  try {
    await algoliaUpsert("catalog_creators", record);
    console.log(`[indexCreatorForSearch] Indexed userId=${userId} into catalog_creators`);
  } catch (err) {
    console.error(`[indexCreatorForSearch] Failed for userId=${userId}:`, err.message);
    throw err;
  }
}

exports.indexCreatorForSearch = indexCreatorForSearch;
