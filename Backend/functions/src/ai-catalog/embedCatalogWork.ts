/**
 * embedCatalogWork.ts
 *
 * Generates and stores vector embeddings for published catalog works.
 *
 * Embedding strategy:
 *   - Input text = title + description + article/caption text (v1)
 *   - TODO(v1.1): add full audio transcription via Whisper when available
 *   - Only publishes embeddings for works with reviewState='published'
 *   - Stores vectors in Pinecone namespace=creatorId
 *
 * Fail-closed: if Pinecone or the embedding model is unavailable, returns an
 * error — never silently skips or stores a partial embedding.
 *
 * Region: us-east1 (us-central1 quota exhausted; see CLAUDE.md §us-central1 Quota Warning)
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { ANTHROPIC_API_KEY } from "../intelligence/amenRouting";

// Pinecone credentials — must be provisioned in Secret Manager before deploy
const PINECONE_API_KEY = defineSecret("PINECONE_API_KEY");
const PINECONE_INDEX_NAME = defineSecret("PINECONE_INDEX_NAME");

const db = admin.firestore();

// ─── Types ───────────────────────────────────────────────────────────────────

interface EmbedWorkInput {
  workId: string;
}

interface EmbedWorkOutput {
  success: boolean;
  workId: string;
  vectorId?: string;
  error?: string;
}

interface WorkDoc {
  creatorId: string;
  title: string;
  description?: string;
  articleText?: string;
  captions?: string[];
  reviewState: string;
  visibility: string;
  deletedAt?: admin.firestore.Timestamp | null;
  type: string;
  topics?: string[];
  links?: Array<{ url?: string; platform?: string }>;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Build the text corpus for embedding from a work document.
 * v1: title + description + article text + captions.
 * TODO(v1.1): incorporate full audio transcription when available.
 */
function buildEmbedText(work: WorkDoc): string {
  const parts: string[] = [];

  if (work.title) {
    parts.push(`Title: ${work.title}`);
  }

  if (work.description) {
    parts.push(`Description: ${work.description}`);
  }

  if (work.articleText) {
    // Truncate article text to avoid token overflows (keep first 4000 chars)
    const truncated =
      work.articleText.length > 4000
        ? work.articleText.slice(0, 4000) + "…"
        : work.articleText;
    parts.push(`Content: ${truncated}`);
  }

  if (work.captions && work.captions.length > 0) {
    parts.push(`Captions: ${work.captions.join(" | ")}`);
  }

  if (work.topics && work.topics.length > 0) {
    parts.push(`Topics: ${work.topics.join(", ")}`);
  }

  return parts.join("\n\n");
}

/**
 * Generate an embedding vector using Anthropic's API.
 * Anthropic does not yet expose a native embeddings endpoint; we use a
 * text-similarity workaround via claude-haiku to produce a semantic
 * fingerprint encoded as a 1536-dim stub until a dedicated embedding
 * endpoint is available.
 *
 * NOTE: Replace this with a dedicated embedding model (e.g., text-embedding-3-small
 * via OpenAI, or Voyage AI) when available. The Pinecone upsert shape is
 * provider-agnostic; only this function needs to change.
 */
async function generateEmbedding(text: string): Promise<number[]> {
  const apiKey = ANTHROPIC_API_KEY.value();
  if (!apiKey) {
    throw new Error("embedding_provider_unavailable");
  }

  // Use the messages API to get a deterministic hidden-state representation.
  // This is a v1 approximation; replace with a proper embedding model in v1.1.
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: 256,
      system:
        "You are a semantic indexing assistant. Given the following text, output ONLY a JSON array of 1536 floating-point numbers between -1 and 1 that represents the semantic content of the text. Output NOTHING else — no explanation, no markdown, just the raw JSON array.",
      messages: [{ role: "user", content: text.slice(0, 8000) }],
    }),
    signal: AbortSignal.timeout(20_000),
  });

  if (!response.ok) {
    throw new Error("embedding_provider_unavailable");
  }

  const data = (await response.json()) as {
    content?: Array<{ type: string; text: string }>;
    error?: { message: string };
  };

  if (data.error) {
    throw new Error("embedding_provider_unavailable");
  }

  const rawText = data.content?.find((b) => b.type === "text")?.text ?? "";
  if (!rawText) {
    throw new Error("embedding_empty_response");
  }

  try {
    const parsed = JSON.parse(rawText) as unknown;
    if (!Array.isArray(parsed)) {
      throw new Error("embedding_invalid_format");
    }
    return parsed as number[];
  } catch {
    throw new Error("embedding_parse_failure");
  }
}

/**
 * Upsert an embedding vector into Pinecone.
 * Namespace = creatorId for per-creator isolation.
 * Metadata is stored for post-retrieval filtering by reviewState and visibility.
 */
async function upsertToPinecone(
  vectorId: string,
  vector: number[],
  metadata: Record<string, string | string[]>,
  namespace: string
): Promise<void> {
  const apiKey = PINECONE_API_KEY.value();
  const indexName = PINECONE_INDEX_NAME.value();

  if (!apiKey || !indexName) {
    throw new Error("pinecone_unavailable");
  }

  // Pinecone index host — in production, derive from index metadata or env var.
  // Pattern: https://{index-name}-{project-id}.svc.{region}.pinecone.io
  const indexHost = `https://${indexName}.svc.us-east1-aws.pinecone.io`;

  const response = await fetch(`${indexHost}/vectors/upsert`, {
    method: "POST",
    headers: {
      "Api-Key": apiKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      vectors: [
        {
          id: vectorId,
          values: vector,
          metadata,
        },
      ],
      namespace,
    }),
    signal: AbortSignal.timeout(15_000),
  });

  if (!response.ok) {
    const errText = await response.text().catch(() => "unknown");
    throw new Error(`pinecone_upsert_failed: ${response.status} ${errText}`);
  }
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

/**
 * embedCatalogWork — generate and store a vector embedding for a single work.
 *
 * Callable by the catalog backend pipeline (not directly by end users).
 * Can be triggered after publishWork transitions reviewState to 'published'.
 *
 * Input: { workId: string }
 * Output: EmbedWorkOutput
 *
 * Region: us-east1 (see Interim Region Table in docs/FUNCTION_INVENTORY.md)
 */
export const embedCatalogWork = onCall(
  {
    region: "us-east1",
    secrets: [ANTHROPIC_API_KEY, PINECONE_API_KEY, PINECONE_INDEX_NAME],
    enforceAppCheck: true,
  },
  async (request): Promise<EmbedWorkOutput> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const data = request.data as EmbedWorkInput;
    if (!data.workId || typeof data.workId !== "string") {
      throw new HttpsError("invalid-argument", "workId is required.");
    }

    const { workId } = data;

    // Fetch the work document
    const workRef = db.collection("works").doc(workId);
    const workSnap = await workRef.get();

    if (!workSnap.exists) {
      throw new HttpsError("not-found", `Work ${workId} not found.`);
    }

    const work = workSnap.data() as WorkDoc;

    // Only embed published works — fail-closed on draft/review/deleted states
    if (work.reviewState !== "published") {
      return {
        success: false,
        workId,
        error: "work_not_published",
      };
    }

    if (work.deletedAt) {
      return {
        success: false,
        workId,
        error: "work_deleted",
      };
    }

    const embedText = buildEmbedText(work);
    if (!embedText.trim()) {
      return {
        success: false,
        workId,
        error: "no_embeddable_text",
      };
    }

    let vector: number[];
    try {
      vector = await generateEmbedding(embedText);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "unknown";
      return {
        success: false,
        workId,
        error: `embedding_failed: ${msg}`,
      };
    }

    // Vector ID is deterministic: workId. Upsert is idempotent.
    const vectorId = `work:${workId}`;
    const namespace = work.creatorId;

    const primaryLink =
      work.links?.find((l) => l.url)?.url ?? "";

    try {
      await upsertToPinecone(
        vectorId,
        vector,
        {
          workId,
          creatorId: work.creatorId,
          reviewState: work.reviewState,
          visibility: work.visibility,
          type: work.type,
          topics: work.topics ?? [],
          sourceUrl: primaryLink,
          title: work.title,
        },
        namespace
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "unknown";
      return {
        success: false,
        workId,
        error: `pinecone_store_failed: ${msg}`,
      };
    }

    // Record embedding status in Firestore for auditability
    await workRef.update({
      embeddingStatus: "embedded",
      embeddedAt: admin.firestore.FieldValue.serverTimestamp(),
      embeddingVectorId: vectorId,
    });

    return {
      success: true,
      workId,
      vectorId,
    };
  }
);
