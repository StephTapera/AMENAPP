/**
 * AMEN Semantic Search Service — Cloud Run (Node.js / TypeScript)
 *
 * POST /embed
 *   Body: { postId, content }
 *   Generates a Vertex AI text-embedding-004 vector and stores it in Firestore.
 *   Called by Cloud Functions on post creation.
 *
 * POST /search
 *   Body: { query, limit?, minSimilarity? }
 *   Returns: { results: [{ postId, score }] }
 *   Embeds the query text, then finds top-K similar posts via cosine similarity
 *   over the postEmbeddings collection (all stored as 768-dim float arrays).
 *
 * Deploy:
 *   gcloud run deploy amen-search \
 *     --source . --region us-central1 \
 *     --set-env-vars PROJECT_ID=<your-project-id> \
 *     --no-allow-unauthenticated
 */

import express, { Request, Response } from "express";
import { VertexAI } from "@google-cloud/vertexai";
import * as admin from "firebase-admin";

const app = express();
app.use(express.json({ limit: "256kb" }));

// ─── Firebase Admin ───────────────────────────────────────────────────────────

admin.initializeApp();
const db = admin.firestore();

// ─── Vertex AI Embeddings ─────────────────────────────────────────────────────

const PROJECT_ID = process.env.PROJECT_ID ?? "";
const LOCATION = process.env.LOCATION ?? "us-central1";
const EMBEDDING_MODEL = "text-embedding-004";   // 768 dimensions
const EMBEDDING_DIMS = 768;

const vertexAI = new VertexAI({ project: PROJECT_ID, location: LOCATION });
const embeddingModel = vertexAI.getGenerativeModel({ model: EMBEDDING_MODEL });

async function getEmbedding(text: string): Promise<number[]> {
  // The Vertex AI embedding API is separate from the generative model API.
  // We call the prediction endpoint directly via the REST interface.
  const { PredictionServiceClient } = await import("@google-cloud/aiplatform");
  const client = new PredictionServiceClient({
    apiEndpoint: `${LOCATION}-aiplatform.googleapis.com`,
  });

  const endpoint = `projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models/${EMBEDDING_MODEL}`;

  const predictResult = await client.predict({
    endpoint,
    instances: [
      { structValue: { fields: { content: { stringValue: text.slice(0, 3000) } } } },
    ],
    parameters: undefined,
  });
  const response = Array.isArray(predictResult) ? predictResult[0] : predictResult;

  const embeddings = response.predictions?.[0]?.structValue?.fields?.embeddings;
  const values = embeddings?.structValue?.fields?.values?.listValue?.values;

  if (!values?.length) {
    throw new Error("No embedding returned from Vertex AI");
  }

  return values.map((v: { numberValue?: number | null }) => v.numberValue ?? 0);
}

// ─── Cosine similarity ────────────────────────────────────────────────────────

function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) return 0;
  let dot = 0, magA = 0, magB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }
  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  return denom === 0 ? 0 : dot / denom;
}

// ─── Routes ───────────────────────────────────────────────────────────────────

/**
 * POST /embed  — store embedding for a new post
 * Body: { postId: string, content: string }
 */
app.post("/embed", async (req: Request, res: Response) => {
  const { postId, content } = req.body as { postId?: string; content?: string };

  if (!postId || !content) {
    res.status(400).json({ error: "postId and content required" });
    return;
  }

  try {
    // Skip if already exists
    const existing = await db.collection("postEmbeddings").doc(postId).get();
    if (existing.exists) {
      res.json({ status: "exists" });
      return;
    }

    const embedding = await getEmbedding(content);

    await db.collection("postEmbeddings").doc(postId).set({
      postId,
      embedding,
      content: content.slice(0, 200),
      modelVersion: EMBEDDING_MODEL,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ status: "stored", dimensions: embedding.length });
  } catch (err) {
    console.error("embed error:", err);
    res.status(500).json({ error: String(err) });
  }
});

/**
 * POST /embed-query  — return an embedding vector for arbitrary text (no storage)
 * Body: { content: string }
 * Returns: { embedding: number[] }
 * Used by the iOS client's SemanticSearchService.generateEmbedding() fallback path.
 */
app.post("/embed-query", async (req: Request, res: Response) => {
  const { content } = req.body as { content?: string };

  if (!content?.trim()) {
    res.status(400).json({ error: "content required" });
    return;
  }

  try {
    const embedding = await getEmbedding(content);
    res.json({ embedding });
  } catch (err) {
    console.error("embed-query error:", err);
    res.status(500).json({ error: String(err) });
  }
});

/**
 * POST /search  — semantic search over stored embeddings
 * Body: { query: string, limit?: number, minSimilarity?: number }
 * Returns: { results: [{ postId, score }] }
 */
app.post("/search", async (req: Request, res: Response) => {
  const {
    query,
    limit = 20,
    minSimilarity = 0.55,
  } = req.body as {
    query?: string;
    limit?: number;
    minSimilarity?: number;
  };

  if (!query?.trim()) {
    res.status(400).json({ error: "query required" });
    return;
  }

  try {
    // 1. Embed the query
    const queryEmbedding = await getEmbedding(query);

    // 2. Fetch all stored embeddings (up to 2000 — use Vertex AI Vector Search for scale)
    const snapshot = await db.collection("postEmbeddings").limit(2000).get();

    // 3. Score
    const scored: Array<{ postId: string; score: number }> = [];
    for (const doc of snapshot.docs) {
      const data = doc.data() as { postId: string; embedding: number[] };
      if (!data.embedding?.length) continue;
      const score = cosineSimilarity(queryEmbedding, data.embedding);
      if (score >= minSimilarity) {
        scored.push({ postId: data.postId, score });
      }
    }

    // 4. Sort and trim
    scored.sort((a, b) => b.score - a.score);
    const results = scored.slice(0, limit);

    res.json({ results });
  } catch (err) {
    console.error("search error:", err);
    res.status(500).json({ error: String(err) });
  }
});

app.get("/health", (_req, res) => res.json({ status: "ok" }));

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT ?? "8080", 10);
app.listen(PORT, () => console.log(`Semantic search service on :${PORT}`));
