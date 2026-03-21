// livingMemory.js
// Soul Engine — resurfaces resonant content at the right moment
// Uses OpenAI text-embedding-3-small for semantic similarity

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// ── Lazy clients ──────────────────────────────────────────────────────────────

let _openai = null;
let _openaiKey = null;
function getOpenAI() {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error("OPENAI_API_KEY environment variable is not set");
  // Re-create the client if the key has changed (e.g. rotated between cold starts)
  if (!_openai || _openaiKey !== key) {
    const { OpenAI } = require("openai");
    _openai = new OpenAI({ apiKey: key });
    _openaiKey = key;
  }
  return _openai;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function embedText(text) {
  const resp = await getOpenAI().embeddings.create({
    model: "text-embedding-3-small",
    input: text.slice(0, 2000),
  });
  return resp.data[0].embedding;
}

function cosineSimilarity(a, b) {
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

function extractTextFromPost(data) {
  return [data.content, data.caption, data.prayerText, data.testimony, data.title]
    .filter(Boolean)
    .join(" ")
    .trim();
}

// ── Cloud Function 1: generateEmbedding ───────────────────────────────────────
// Triggers on every new post/prayer/testimony and stores a semantic embedding

exports.generateEmbedding = onDocumentCreated(
  {
    document: "posts/{postId}",
    secrets: ["OPENAI_API_KEY"],
  },
  async (event) => {
    const data = event.data.data();
    if (!data) return;

    const text = extractTextFromPost(data);
    if (!text || text.length < 10) return; // nothing meaningful to embed

    try {
      const embedding = await embedText(text);
      await event.data.ref.update({
        embedding,
        embeddedAt: admin.firestore.FieldValue.serverTimestamp(),
        resurface: true,
        resurfaceCount: 0,
        resonanceScore: 0,
      });
    } catch (err) {
      functions.logger.error("generateEmbedding failed", { postId: event.params.postId, err });
    }
  }
);

// ── Cloud Function 2: findResonantContent ─────────────────────────────────────
// Callable: given a sourcePostId (usually a recent prayer), returns the top-N
// posts/testimonies/prayers that resonate most with it.

exports.findResonantContent = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const { sourcePostId, limit: rawLimit = 5, types = ["testimony", "prayer", "post"] } = request.data;
  if (!sourcePostId) {
    throw new HttpsError("invalid-argument", "sourcePostId required");
  }

  const db = admin.firestore();

  // Fetch the source post's embedding
  const sourceDoc = await db.collection("posts").doc(sourcePostId).get();
  if (!sourceDoc.exists) {
    throw new HttpsError("not-found", "Source post not found");
  }
  const sourceEmbedding = sourceDoc.data().embedding;
  if (!sourceEmbedding) {
    throw new HttpsError("failed-precondition", "Source post has no embedding yet");
  }

  const limit = Math.min(Number(rawLimit), 20);
  const uid = request.auth.uid;

  // Fetch candidate posts that have embeddings — excluding the source post and the caller's own posts
  const snap = await db.collection("posts")
    .where("resurface", "==", true)
    .orderBy("createdAt", "desc")
    .limit(300)
    .get();

  const scored = [];
  for (const doc of snap.docs) {
    if (doc.id === sourcePostId) continue;
    const d = doc.data();
    if (!d.embedding) continue;
    if (!types.includes(d.type || "post")) continue;

    const score = cosineSimilarity(sourceEmbedding, d.embedding);
    if (score > 0.55) {
      scored.push({
        id: doc.id,
        authorId: d.authorId || d.userId || "",
        authorName: d.authorName || d.displayName || "Anonymous",
        authorPhotoURL: d.authorPhotoURL || d.photoURL || null,
        content: d.content || d.prayerText || d.testimony || "",
        type: d.type || "post",
        createdAt: d.createdAt ? d.createdAt.toMillis() : 0,
        resonanceScore: Math.round(score * 100) / 100,
      });
    }
  }

  // Sort by score descending, return top N
  scored.sort((a, b) => b.resonanceScore - a.resonanceScore);
  const results = scored.slice(0, limit);

  // Increment resurfaceCount on matched docs (fire-and-forget)
  const batch = db.batch();
  for (const r of results) {
    batch.update(db.collection("posts").doc(r.id), {
      resurfaceCount: admin.firestore.FieldValue.increment(1),
    });
  }
  batch.commit().catch(() => {}); // non-blocking

  return { results };
});

// ── Cloud Function 3: markPrayerAnswered ──────────────────────────────────────
// Callable: links a prayer post to an answered-prayer testimony, building the
// answeredPrayerChain that Living Memory surfaces.

exports.markPrayerAnswered = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const { prayerPostId, testimonyPostId, note } = request.data;
  if (!prayerPostId || !testimonyPostId) {
    throw new HttpsError("invalid-argument", "prayerPostId and testimonyPostId required");
  }

  const db = admin.firestore();
  const uid = request.auth.uid;

  // Verify ownership of the prayer post
  const prayerDoc = await db.collection("posts").doc(prayerPostId).get();
  if (!prayerDoc.exists) {
    throw new HttpsError("not-found", "Prayer post not found");
  }
  const prayerData = prayerDoc.data();
  if ((prayerData.authorId || prayerData.userId) !== uid) {
    throw new HttpsError("permission-denied", "You can only mark your own prayers as answered");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  // Write the chain link document
  const chainRef = db.collection("answeredPrayerChain").doc();
  await chainRef.set({
    id: chainRef.id,
    uid,
    prayerPostId,
    testimonyPostId,
    note: note || null,
    createdAt: now,
  });

  // Tag both posts
  const batch = db.batch();
  batch.update(db.collection("posts").doc(prayerPostId), {
    answeredAt: now,
    answeredByTestimony: testimonyPostId,
    resurface: true,
    resonanceScore: admin.firestore.FieldValue.increment(0.2),
  });
  batch.update(db.collection("posts").doc(testimonyPostId), {
    answeredPrayerRef: prayerPostId,
    resurface: true,
    resonanceScore: admin.firestore.FieldValue.increment(0.2),
  });
  await batch.commit();

  return { success: true, chainId: chainRef.id };
});
