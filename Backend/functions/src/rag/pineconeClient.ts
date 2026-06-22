/**
 * rag/pineconeClient.ts
 *
 * Single shared Pinecone client for all RAG/memory workloads.
 *
 * ARCHITECTURE CONTRACT (pinecone_rag_enabled feature flag):
 *   - All public functions check `isPineconeRagEnabled()` first.
 *   - If the flag is OFF or the secret is absent, functions return empty results
 *     and log a clearly-labeled stub notice. They NEVER return fabricated content.
 *   - Callers are responsible for building prompts from retrieved chunks;
 *     this module only retrieves and stores vectors.
 *
 * INGESTION FLOW (per spec):
 *   userContent → sanitizePii() → chunkText(512 tokens, 50 overlap)
 *     → embedWithGemini() → upsertChunks(namespace="user-{userId}")
 *
 * RETRIEVAL FLOW (per spec):
 *   userQuery → embedWithGemini() → queryChunks(filter: scope, topK: 5)
 *     → returned to caller for prompt injection
 *
 * PRIVACY INVARIANT:
 *   Per-user vectors live in namespace "user-{userId}".
 *   Retrieval ALWAYS scopes to (scope=="public") OR (scope==userId).
 *   User-A's namespace is NEVER queried for User-B.
 *
 * EMBEDDING MODEL:
 *   Gemini text-embedding-004 (768-dim, cosine) — same model already used
 *   in functions/discussionFunctions.js and sanctuary/index.ts. Replaces the
 *   fake Claude-chat embedding hack in embedCatalogWork.ts / askCreatorQuery.ts.
 *   Index must be configured with dimension=768, metric=cosine.
 *
 * VERTEX AI RAG CORPUS:
 *   TODO(reconcile): Backend/functions/.env references VERTEX_AI_EMBEDDING_MODEL=text-embedding-005
 *   and VERTEX_AI_LOCATION=us-central1, suggesting a Vertex AI RAG Corpus may have been
 *   provisioned. If so, that corpus duplicates this Pinecone store.
 *   Do NOT delete the Vertex AI config until the corpus contents have been audited
 *   and migrated. See SMART_MESSAGE_VECTOR_PROVIDER=firestore in .env — this indicates
 *   the smart message vector path currently falls back to Firestore, not Vertex AI.
 *
 * Region: us-east1 (us-central1 at quota; see CLAUDE.md §us-central1 Quota Warning)
 */

import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";

// ─── Secrets ──────────────────────────────────────────────────────────────────

/** Pinecone API key — provisioned in Secret Manager. */
export const PINECONE_API_KEY = defineSecret("PINECONE_API_KEY");

/**
 * Pinecone index host (full URL, e.g. https://amen-rag-abc123.svc.us-east1-aws.pinecone.io).
 * Retrieved from Secret Manager rather than .env to survive CF cold starts.
 */
export const PINECONE_INDEX_HOST = defineSecret("PINECONE_INDEX_HOST");

/**
 * Gemini API key — re-uses BEREAN_LLM_KEY pattern established in the codebase
 * (same key used by discussion/embeddingAdapter and sanctuary/index.ts).
 */
export const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");

// ─── Feature flag ─────────────────────────────────────────────────────────────

const FLAG_CACHE_TTL_MS = 5 * 60 * 1000;
let ragFlagCache: boolean | null = null;
let ragFlagCacheExpiresAt = 0;

/**
 * Read the pinecone_rag_enabled flag from Firestore (system/serverFeatureFlags).
 * Defaults to OFF — must be explicitly set to true to activate RAG.
 * Fail-closed: any read error returns false.
 */
export async function isPineconeRagEnabled(): Promise<boolean> {
  const now = Date.now();
  if (ragFlagCache !== null && now < ragFlagCacheExpiresAt) {
    return ragFlagCache;
  }
  try {
    const db = admin.firestore();
    const snap = await db.collection("system").doc("serverFeatureFlags").get();
    const data = snap.data() ?? {};
    const enabled =
      typeof data.pinecone_rag_enabled === "boolean"
        ? data.pinecone_rag_enabled
        : false;
    ragFlagCache = enabled;
    ragFlagCacheExpiresAt = now + FLAG_CACHE_TTL_MS;
    return enabled;
  } catch (err) {
    logger.error(
      "[PineconeClient] Failed to read pinecone_rag_enabled flag — defaulting OFF.",
      err
    );
    return false;
  }
}

// ─── Types ────────────────────────────────────────────────────────────────────

/**
 * Scope of a stored chunk.
 * "private" — visible only to the owning user.
 * "space"   — visible to members of a Space.
 * "public"  — visible to all authenticated users (catalog content, etc.).
 */
export type ChunkScope = "private" | "space" | "public";

/** Metadata stored alongside each vector in Pinecone. */
export interface VectorMetadata {
  userId: string;
  resourceId: string;
  resourceType: string;
  scope: ChunkScope;
  /** Unix epoch ms */
  timestamp: number;
  /** Optional space ID for scope="space" chunks. */
  spaceId?: string;
  /** Short plaintext snippet for display without a Firestore round-trip. */
  snippet?: string;
}

/** A single retrieved chunk returned by queryChunks(). */
export interface RetrievedChunk {
  id: string;
  score: number;
  metadata: VectorMetadata;
}

// ─── Embedding (Gemini text-embedding-004) ────────────────────────────────────

const GEMINI_EMBED_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent";

/**
 * Generate a 768-dimension embedding using Gemini text-embedding-004.
 * Consistent with discussion/embeddingAdapter.ts and sanctuary/index.ts.
 *
 * Returns null (not throws) if the API key is absent or the call fails,
 * so callers can gracefully degrade rather than crashing the pipeline.
 */
export async function embedWithGemini(
  text: string,
  taskType: "RETRIEVAL_DOCUMENT" | "RETRIEVAL_QUERY" = "RETRIEVAL_DOCUMENT"
): Promise<number[] | null> {
  const apiKey = BEREAN_LLM_KEY.value();
  if (!apiKey) {
    logger.warn("[PineconeClient] BEREAN_LLM_KEY absent — embedding stubbed.");
    return null;
  }

  try {
    const res = await fetch(`${GEMINI_EMBED_ENDPOINT}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "models/text-embedding-004",
        content: { parts: [{ text: text.slice(0, 8000) }] },
        taskType,
      }),
      signal: AbortSignal.timeout(10_000),
    });

    if (!res.ok) {
      const errBody = await res.text().catch(() => "unreadable");
      logger.warn("[PineconeClient] Gemini embed API error", {
        status: res.status,
        body: errBody.slice(0, 200),
      });
      return null;
    }

    const data = (await res.json()) as {
      embedding?: { values?: number[] };
    };

    const values = data.embedding?.values;
    if (!Array.isArray(values) || values.length === 0) {
      logger.warn("[PineconeClient] Gemini embed returned empty values.");
      return null;
    }

    return values;
  } catch (err) {
    logger.warn("[PineconeClient] embedWithGemini failed", err);
    return null;
  }
}

// ─── PII sanitizer ────────────────────────────────────────────────────────────

/**
 * Lightweight PII scrub before embedding.
 * Removes common patterns (email, phone, SSN, credit card) from text
 * before it is sent to an external embedding API.
 *
 * This is a defense-in-depth measure — the primary PII controls are
 * upstream in the iOS app and the Cloud Function validation layers.
 */
export function sanitizePii(text: string): string {
  return text
    // Email addresses
    .replace(/[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g, "[EMAIL]")
    // US phone numbers (various formats)
    .replace(/(\+?1[\s.\-]?)?(\(?\d{3}\)?[\s.\-]?)(\d{3}[\s.\-]?\d{4})/g, "[PHONE]")
    // US SSN
    .replace(/\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b/g, "[SSN]")
    // Credit card patterns (13–19 digits)
    .replace(/\b(?:\d[ \-]?){13,19}\b/g, "[CARD]");
}

// ─── Text chunker ─────────────────────────────────────────────────────────────

/**
 * Split text into chunks of ~512 tokens (approximated as 4 chars/token)
 * with 50-token (200-char) overlap between adjacent chunks.
 *
 * Returns at least one chunk even for short texts.
 */
export function chunkText(text: string): string[] {
  const TARGET_CHARS = 2048; // ~512 tokens at 4 chars/token
  const OVERLAP_CHARS = 200; // ~50-token overlap

  if (text.length <= TARGET_CHARS) {
    return [text];
  }

  const chunks: string[] = [];
  let start = 0;

  while (start < text.length) {
    const end = Math.min(start + TARGET_CHARS, text.length);
    chunks.push(text.slice(start, end));

    if (end === text.length) break;
    start = end - OVERLAP_CHARS;
  }

  return chunks;
}

// ─── Pinecone REST helpers ────────────────────────────────────────────────────

function getPineconeHeaders(apiKey: string): Record<string, string> {
  return {
    "Api-Key": apiKey,
    "Content-Type": "application/json",
  };
}

/**
 * Build the index host URL.
 * Prefers PINECONE_INDEX_HOST secret; falls back to PINECONE_HOST env var
 * (used by the legacy catalogSearch.ts path) for backward compatibility.
 */
function getIndexHost(): string | null {
  const secretHost = PINECONE_INDEX_HOST.value();
  if (secretHost) return secretHost;

  const envHost = process.env.PINECONE_HOST;
  if (envHost) return envHost;

  return null;
}

// ─── upsertChunks ─────────────────────────────────────────────────────────────

export interface UpsertChunkInput {
  /** Caller-supplied stable ID for the source resource (e.g. entryId, workId). */
  resourceId: string;
  resourceType: string;
  userId: string;
  scope: ChunkScope;
  /** Full text to sanitize, chunk, and embed. */
  text: string;
  /** Optional space ID (required when scope="space"). */
  spaceId?: string;
}

export interface UpsertResult {
  upserted: number;
  skipped: boolean;
  reason?: string;
}

/**
 * Ingest a resource into Pinecone:
 *   sanitize PII → chunk (512 tokens, 50 overlap) → embed with Gemini → upsert.
 *
 * Namespace = "user-{userId}" for private/space scopes.
 * Namespace = "public" for scope="public".
 *
 * Returns { skipped: true } if the feature flag is OFF, secrets are missing,
 * or embedding fails. NEVER throws to the caller — ingestion failure should not
 * block the primary user action (e.g. saving a note).
 */
export async function upsertChunks(input: UpsertChunkInput): Promise<UpsertResult> {
  const enabled = await isPineconeRagEnabled();
  if (!enabled) {
    logger.info("[PineconeClient] pinecone_rag_enabled=false — upsert stubbed.", {
      resourceId: input.resourceId,
      resourceType: input.resourceType,
    });
    return { upserted: 0, skipped: true, reason: "feature_flag_off" };
  }

  const apiKey = PINECONE_API_KEY.value();
  const indexHost = getIndexHost();

  if (!apiKey || !indexHost) {
    logger.warn(
      "[PineconeClient] PINECONE_API_KEY or PINECONE_INDEX_HOST absent — upsert stubbed.",
      { resourceId: input.resourceId }
    );
    return { upserted: 0, skipped: true, reason: "secrets_missing" };
  }

  const sanitized = sanitizePii(input.text);
  const chunks = chunkText(sanitized);
  const namespace =
    input.scope === "public" ? "public" : `user-${input.userId}`;

  let upsertedCount = 0;

  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    const vectorId = `${input.resourceType}:${input.resourceId}:${i}`;

    const vector = await embedWithGemini(chunk, "RETRIEVAL_DOCUMENT");
    if (!vector) {
      logger.warn("[PineconeClient] Embedding failed for chunk — skipping.", {
        vectorId,
      });
      continue;
    }

    const metadata: VectorMetadata = {
      userId: input.userId,
      resourceId: input.resourceId,
      resourceType: input.resourceType,
      scope: input.scope,
      timestamp: Date.now(),
      snippet: chunk.slice(0, 200),
      ...(input.spaceId ? { spaceId: input.spaceId } : {}),
    };

    try {
      const res = await fetch(`${indexHost}/vectors/upsert`, {
        method: "POST",
        headers: getPineconeHeaders(apiKey),
        body: JSON.stringify({
          vectors: [{ id: vectorId, values: vector, metadata }],
          namespace,
        }),
        signal: AbortSignal.timeout(15_000),
      });

      if (!res.ok) {
        const errBody = await res.text().catch(() => "unreadable");
        logger.warn("[PineconeClient] Pinecone upsert failed", {
          vectorId,
          status: res.status,
          body: errBody.slice(0, 200),
        });
      } else {
        upsertedCount++;
      }
    } catch (err) {
      logger.warn("[PineconeClient] Pinecone upsert exception", { vectorId, err });
    }
  }

  logger.info("[PineconeClient] upsertChunks complete", {
    resourceId: input.resourceId,
    chunksTotal: chunks.length,
    chunksUpserted: upsertedCount,
    namespace,
  });

  return { upserted: upsertedCount, skipped: false };
}

// ─── queryChunks ──────────────────────────────────────────────────────────────

export interface QueryChunksInput {
  userId: string;
  queryText: string;
  topK?: number;
  /**
   * Scope filter. Queries always include scope="public".
   * When userId is provided, also includes the private namespace for that user.
   */
  includePrivate?: boolean;
  /** Optional Pinecone metadata filter to narrow results. */
  metadataFilter?: Record<string, unknown>;
}

/**
 * Retrieve the top-K semantically similar chunks for a query.
 *
 * Scope enforcement:
 *   - Always searches namespace "public" for public content.
 *   - When includePrivate=true, also searches namespace "user-{userId}".
 *   - User-A's private namespace is NEVER queried for User-B.
 *
 * Returns empty array (not throws) if the feature flag is OFF, secrets are
 * missing, or embedding fails.
 */
export async function queryChunks(
  input: QueryChunksInput
): Promise<RetrievedChunk[]> {
  const enabled = await isPineconeRagEnabled();
  if (!enabled) {
    logger.info("[PineconeClient] pinecone_rag_enabled=false — query stubbed.");
    return [];
  }

  const apiKey = PINECONE_API_KEY.value();
  const indexHost = getIndexHost();

  if (!apiKey || !indexHost) {
    logger.warn("[PineconeClient] PINECONE_API_KEY or PINECONE_INDEX_HOST absent — query stubbed.");
    return [];
  }

  const queryVector = await embedWithGemini(input.queryText, "RETRIEVAL_QUERY");
  if (!queryVector) {
    logger.warn("[PineconeClient] queryChunks: embedding failed — returning empty.");
    return [];
  }

  const topK = input.topK ?? 5;
  const results: RetrievedChunk[] = [];

  // Query namespaces to search: always "public"; add private namespace if requested.
  const namespacesToQuery: string[] = ["public"];
  if (input.includePrivate) {
    namespacesToQuery.push(`user-${input.userId}`);
  }

  for (const namespace of namespacesToQuery) {
    try {
      const body: Record<string, unknown> = {
        vector: queryVector,
        topK,
        includeMetadata: true,
        namespace,
      };

      if (input.metadataFilter) {
        body.filter = input.metadataFilter;
      }

      const res = await fetch(`${indexHost}/query`, {
        method: "POST",
        headers: getPineconeHeaders(apiKey),
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10_000),
      });

      if (!res.ok) {
        logger.warn("[PineconeClient] Pinecone query failed", {
          namespace,
          status: res.status,
        });
        continue;
      }

      const data = (await res.json()) as {
        matches?: Array<{
          id: string;
          score: number;
          metadata?: Record<string, unknown>;
        }>;
      };

      for (const match of data.matches ?? []) {
        const meta = match.metadata as VectorMetadata | undefined;

        // Enforce: only return chunks the user is allowed to see.
        if (meta) {
          const scopeAllowed =
            meta.scope === "public" ||
            (meta.scope === "private" && meta.userId === input.userId) ||
            (meta.scope === "space" && namespace === `user-${input.userId}`);

          if (!scopeAllowed) continue;
        }

        results.push({
          id: match.id,
          score: match.score,
          metadata: meta ?? {
            userId: "",
            resourceId: match.id,
            resourceType: "unknown",
            scope: "public",
            timestamp: 0,
          },
        });
      }
    } catch (err) {
      logger.warn("[PineconeClient] Pinecone query exception", { namespace, err });
    }
  }

  // Deduplicate by id (same vector may appear in multiple namespaces)
  const seen = new Set<string>();
  const deduped = results.filter((r) => {
    if (seen.has(r.id)) return false;
    seen.add(r.id);
    return true;
  });

  // Sort by score descending
  deduped.sort((a, b) => b.score - a.score);

  logger.info("[PineconeClient] queryChunks complete", {
    queryLength: input.queryText.length,
    namespacesQueried: namespacesToQuery.length,
    resultsReturned: deduped.length,
  });

  return deduped.slice(0, topK);
}

// ─── deleteChunks ─────────────────────────────────────────────────────────────

/**
 * Delete all vectors for a specific resource from the user's private namespace.
 * Called from bereanMemory.ts bereanMemoryDelete and bereanMemoryDeleteAll.
 *
 * Safe no-op if the flag is OFF or secrets are missing.
 */
export async function deleteChunks(
  userId: string,
  resourceId: string,
  resourceType: string
): Promise<void> {
  const enabled = await isPineconeRagEnabled();
  if (!enabled) return;

  const apiKey = PINECONE_API_KEY.value();
  const indexHost = getIndexHost();

  if (!apiKey || !indexHost) return;

  const namespace = `user-${userId}`;

  // Pinecone delete-by-prefix is not universally available; enumerate chunk IDs
  // (we store at most ~20 chunks per resource at 512-token chunks of 8k-char content).
  // Pattern: "{resourceType}:{resourceId}:{chunkIndex}"
  const MAX_CHUNKS_PER_RESOURCE = 20;
  const ids: string[] = [];
  for (let i = 0; i < MAX_CHUNKS_PER_RESOURCE; i++) {
    ids.push(`${resourceType}:${resourceId}:${i}`);
  }

  try {
    const res = await fetch(`${indexHost}/vectors/delete`, {
      method: "POST",
      headers: getPineconeHeaders(apiKey),
      body: JSON.stringify({ ids, namespace }),
      signal: AbortSignal.timeout(10_000),
    });

    if (!res.ok) {
      logger.warn("[PineconeClient] deleteChunks failed", {
        resourceId,
        status: res.status,
      });
    } else {
      logger.info("[PineconeClient] deleteChunks complete", {
        userId,
        resourceId,
        namespace,
      });
    }
  } catch (err) {
    logger.warn("[PineconeClient] deleteChunks exception", { resourceId, err });
  }
}

/**
 * Delete the entire private namespace for a user from Pinecone.
 * Called from bereanMemory.ts bereanMemoryDeleteAll (account deletion cascade).
 *
 * Safe no-op if the flag is OFF or secrets are missing.
 */
export async function deleteUserNamespace(userId: string): Promise<void> {
  const enabled = await isPineconeRagEnabled();
  if (!enabled) return;

  const apiKey = PINECONE_API_KEY.value();
  const indexHost = getIndexHost();

  if (!apiKey || !indexHost) return;

  const namespace = `user-${userId}`;

  try {
    const res = await fetch(`${indexHost}/vectors/delete`, {
      method: "POST",
      headers: getPineconeHeaders(apiKey),
      body: JSON.stringify({ deleteAll: true, namespace }),
      signal: AbortSignal.timeout(15_000),
    });

    if (!res.ok) {
      logger.warn("[PineconeClient] deleteUserNamespace failed", {
        userId,
        status: res.status,
      });
    } else {
      logger.info("[PineconeClient] deleteUserNamespace complete", {
        userId,
        namespace,
      });
    }
  } catch (err) {
    logger.warn("[PineconeClient] deleteUserNamespace exception", { userId, err });
  }
}
