// embeddingAdapter.ts — Embedding adapter for duplicate detection

import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";

const EMBEDDING_KEY_SECRET = defineSecret("EMBEDDING_KEY");

// ── Constants ─────────────────────────────────────────────────────────────────

const EMBEDDING_DIM = 768;
const MOCK_VECTOR: number[] = Array(EMBEDDING_DIM).fill(0);

// ── embedText ─────────────────────────────────────────────────────────────────

/**
 * Embeds the given text using Gemini text-embedding-004.
 * Returns a 768-dimensional float vector.
 * Falls back to an all-zeros mock vector when EMBEDDING_KEY is unset or a
 * network error occurs.
 */
export async function embedText(text: string): Promise<number[]> {
  const key = EMBEDDING_KEY_SECRET.value() ?? "";

  if (!key) {
    logger.info("embeddingAdapter: EMBEDDING_KEY not set — returning mock vector.");
    return MOCK_VECTOR;
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${key}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "models/text-embedding-004",
        content: { parts: [{ text }] },
      }),
    });

    if (!response.ok) {
      logger.warn(`embeddingAdapter: Embedding API returned HTTP ${response.status} — returning mock vector.`);
      return MOCK_VECTOR;
    }

    const json = (await response.json()) as {
      embedding?: { values?: number[] };
    };

    const values = json?.embedding?.values;

    if (!Array.isArray(values) || values.length !== EMBEDDING_DIM) {
      logger.warn("embeddingAdapter: Unexpected embedding shape — returning mock vector.", {
        receivedLength: values?.length ?? "none",
      });
      return MOCK_VECTOR;
    }

    logger.info("embeddingAdapter: Embedding retrieved successfully.", { dim: values.length });
    return values;
  } catch (err) {
    logger.warn("embeddingAdapter: Network error calling embedding API — returning mock vector.", {
      err: String(err),
    });
    return MOCK_VECTOR;
  }
}

// ── cosineSimilarity ──────────────────────────────────────────────────────────

/**
 * Computes cosine similarity between two equal-length vectors.
 * Returns a value in [-1, 1].  Returns 0 for zero-magnitude vectors.
 */
export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 0;

  let dot = 0;
  let magA = 0;
  let magB = 0;

  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }

  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  if (denom === 0) return 0;

  return dot / denom;
}
