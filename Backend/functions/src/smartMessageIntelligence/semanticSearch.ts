import * as admin from "firebase-admin";

const db = admin.firestore();
const VECTOR_TOP_K = 40;
const VECTOR_FIELD = "embedding";

export interface SemanticSearchResult {
  id: string;
  sourceType: string;
  title: string;
  snippet: string;
  score: number;
  path: string;
}

type SemanticSourceType =
  | "message"
  | "summary"
  | "studySession"
  | "prayerRequest"
  | "scripture"
  | "knowledgeNode";

interface VectorEmbeddingResponse {
  embedding: number[];
  model?: string;
}

interface VectorSearchHit {
  id: string;
  score: number;
  metadata?: Record<string, unknown>;
}

interface VectorSearchResponse {
  results: VectorSearchHit[];
}

type VectorProvider = "firestore" | "external" | "disabled";

export function tokenize(value: string): string[] {
  return Array.from(new Set(
    value.toLowerCase().split(/[^a-z0-9]+/).filter((token) => token.length > 2)
  )).slice(0, 20);
}

export async function keywordSearchSpace(spaceId: string, query: string): Promise<SemanticSearchResult[]> {
  const tokens = tokenize(query);
  if (!tokens.length) return [];
  const snap = await db.collection("spaces").doc(spaceId)
    .collection("semanticIndex").doc("items")
    .collection("items")
    .where("tokens", "array-contains-any", tokens.slice(0, 10))
    .limit(40)
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data();
    const itemTokens = Array.isArray(data.tokens) ? data.tokens.map(String) : [];
    const score = tokens.filter((token) => itemTokens.includes(token)).length / Math.max(tokens.length, 1);
    return {
      id: doc.id,
      sourceType: String(data.sourceType ?? "message"),
      title: String(data.title ?? "Result"),
      snippet: String(data.snippet ?? ""),
      score,
      path: doc.ref.path,
    };
  }).sort((a, b) => b.score - a.score);
}

export function vectorSearchEnabled(): boolean {
  if (process.env.SMART_MESSAGE_VECTOR_ENABLED !== "true") return false;
  return vectorProvider() !== "disabled";
}

function vectorProvider(): VectorProvider {
  if (process.env.SMART_MESSAGE_VECTOR_ENABLED !== "true") return "disabled";
  if (process.env.SMART_MESSAGE_VECTOR_PROVIDER === "firestore") return "firestore";
  if (process.env.SMART_MESSAGE_VECTOR_PROVIDER === "external") {
    return process.env.SMART_MESSAGE_VECTOR_API_URL && process.env.SMART_MESSAGE_VECTOR_API_KEY ? "external" : "disabled";
  }
  if (process.env.SMART_MESSAGE_VECTOR_API_URL && process.env.SMART_MESSAGE_VECTOR_API_KEY) return "external";
  return "firestore";
}

function vectorBaseURL(): string {
  return String(process.env.SMART_MESSAGE_VECTOR_API_URL ?? "").replace(/\/+$/, "");
}

function vectorHeaders(): Record<string, string> {
  return {
    "Authorization": `Bearer ${process.env.SMART_MESSAGE_VECTOR_API_KEY}`,
    "Content-Type": "application/json",
  };
}

function validateEmbedding(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  const embedding = value
    .map((item) => typeof item === "number" && Number.isFinite(item) ? item : undefined)
    .filter((item): item is number => typeof item === "number");
  return embedding.length >= 64 ? embedding.slice(0, 4096) : [];
}

async function fetchEmbedding(text: string, sourceType: SemanticSourceType, purpose: "document" | "query" = "document"): Promise<VectorEmbeddingResponse | null> {
  if (!vectorSearchEnabled()) return null;
  if (vectorProvider() === "firestore") return fetchVertexEmbedding(text, purpose);
  const response = await fetch(`${vectorBaseURL()}/embed`, {
    method: "POST",
    headers: vectorHeaders(),
    body: JSON.stringify({
      text: text.slice(0, 8000),
      inputType: sourceType,
      domain: "amen_smart_message",
    }),
  });
  if (!response.ok) return null;
  const body = await response.json() as Record<string, unknown>;
  const embedding = validateEmbedding(body.embedding);
  if (!embedding.length) return null;
  return { embedding, model: typeof body.model === "string" ? body.model : undefined };
}

function projectId(): string | undefined {
  return process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? process.env.FIREBASE_CONFIG?.match(/"projectId"\s*:\s*"([^"]+)"/)?.[1];
}

async function metadataAccessToken(): Promise<string | null> {
  try {
    const response = await fetch("http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token", {
      headers: { "Metadata-Flavor": "Google" },
    });
    if (!response.ok) return null;
    const body = await response.json() as Record<string, unknown>;
    return typeof body.access_token === "string" ? body.access_token : null;
  } catch {
    return null;
  }
}

async function fetchVertexEmbedding(text: string, purpose: "document" | "query"): Promise<VectorEmbeddingResponse | null> {
  const token = await metadataAccessToken();
  const activeProjectId = projectId();
  if (!token || !activeProjectId) return null;
  const location = process.env.VERTEX_AI_LOCATION ?? "us-central1";
  const model = process.env.VERTEX_AI_EMBEDDING_MODEL ?? "text-embedding-005";
  const outputDimensionality = Number(process.env.SMART_MESSAGE_VECTOR_DIMENSIONS ?? "");
  const taskType = purpose === "query" ? "RETRIEVAL_QUERY" : "RETRIEVAL_DOCUMENT";
  const parameters: Record<string, number> = {};
  if (Number.isFinite(outputDimensionality) && outputDimensionality > 0) {
    parameters.outputDimensionality = outputDimensionality;
  }
  try {
    const response = await fetch(`https://${location}-aiplatform.googleapis.com/v1/projects/${activeProjectId}/locations/${location}/publishers/google/models/${model}:predict`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        instances: [{ content: text.slice(0, 8000), task_type: taskType }],
        parameters,
      }),
    });
    if (!response.ok) return null;
    const body = await response.json() as Record<string, unknown>;
    const predictions = Array.isArray(body.predictions) ? body.predictions : [];
    const first = predictions[0] as Record<string, unknown> | undefined;
    const embeddings = first?.embeddings as Record<string, unknown> | undefined;
    const embedding = validateEmbedding(embeddings?.values);
    return embedding.length ? { embedding, model } : null;
  } catch {
    return null;
  }
}

async function upsertVector(input: {
  spaceId: string;
  itemId: string;
  sourceType: SemanticSourceType;
  text: string;
  title: string;
  snippet: string;
  path: string;
  topics: string[];
  scriptures: string[];
}): Promise<{ indexed: boolean; model?: string }> {
  const embedded = await fetchEmbedding(input.text, input.sourceType);
  if (!embedded) return { indexed: false };

  if (vectorProvider() === "firestore") {
    const vectorValue = vectorFieldValue(embedded.embedding);
    if (!vectorValue) return { indexed: false, model: embedded.model };
    await db.collection("spaces").doc(input.spaceId)
      .collection("semanticIndex").doc("items")
      .collection("items").doc(input.itemId)
      .set({ [VECTOR_FIELD]: vectorValue }, { merge: true });
    return { indexed: true, model: embedded.model };
  }

  const response = await fetch(`${vectorBaseURL()}/upsert`, {
    method: "POST",
    headers: vectorHeaders(),
    body: JSON.stringify({
      namespace: `spaces/${input.spaceId}`,
      id: input.itemId,
      vector: embedded.embedding,
      metadata: {
        sourceType: input.sourceType,
        title: input.title,
        snippet: input.snippet,
        path: input.path,
        topics: input.topics.slice(0, 20),
        scriptures: input.scriptures.slice(0, 20),
      },
    }),
  });
  return { indexed: response.ok, model: embedded.model };
}

function vectorFieldValue(embedding: number[]): unknown | null {
  const fieldValue = admin.firestore.FieldValue as unknown as { vector?: (values: number[]) => unknown };
  return typeof fieldValue.vector === "function" ? fieldValue.vector(embedding) : null;
}

export async function vectorSearchSpace(spaceId: string, query: string): Promise<SemanticSearchResult[] | null> {
  const embedded = await fetchEmbedding(query, "message", "query");
  if (!embedded) return null;

  if (vectorProvider() === "firestore") {
    const queryVector = vectorFieldValue(embedded.embedding);
    if (!queryVector) return null;
    const collection = db.collection("spaces").doc(spaceId)
      .collection("semanticIndex").doc("items")
      .collection("items") as unknown as {
        findNearest: (options: Record<string, unknown>) => { get: () => Promise<FirebaseFirestore.QuerySnapshot> };
      };
    try {
      const snap = await collection.findNearest({
        vectorField: VECTOR_FIELD,
        queryVector,
        limit: VECTOR_TOP_K,
        distanceMeasure: "COSINE",
        distanceResultField: "vectorDistance",
      }).get();
      return snap.docs.map((doc) => {
        const data = doc.data();
        const distance = typeof data.vectorDistance === "number" ? data.vectorDistance : 1;
        return {
          id: doc.id,
          sourceType: String(data.sourceType ?? "message"),
          title: String(data.title ?? "Result"),
          snippet: String(data.snippet ?? ""),
          score: Math.max(0, Math.min(1, 1 - distance)),
          path: doc.ref.path,
        };
      });
    } catch {
      return null;
    }
  }

  const response = await fetch(`${vectorBaseURL()}/search`, {
    method: "POST",
    headers: vectorHeaders(),
    body: JSON.stringify({
      namespace: `spaces/${spaceId}`,
      vector: embedded.embedding,
      topK: VECTOR_TOP_K,
    }),
  });
  if (!response.ok) return null;
  const body = await response.json() as VectorSearchResponse;
  if (!Array.isArray(body.results)) return null;
  return body.results.map((hit) => ({
    id: String(hit.id),
    sourceType: String(hit.metadata?.sourceType ?? "message"),
    title: String(hit.metadata?.title ?? "Result"),
    snippet: String(hit.metadata?.snippet ?? ""),
    score: typeof hit.score === "number" ? hit.score : 0,
    path: String(hit.metadata?.path ?? ""),
  }));
}

export async function indexSemanticItem(input: {
  spaceId: string;
  itemId: string;
  sourceType: SemanticSourceType;
  threadId?: string;
  sourceId: string;
  title: string;
  text: string;
  topics?: string[];
  scriptures?: string[];
  path?: string;
}): Promise<void> {
  const topics = input.topics ?? [];
  const scriptures = input.scriptures ?? [];
  const tokens = tokenize(`${input.text} ${topics.join(" ")} ${scriptures.join(" ")}`);
  if (!tokens.length) return;
  const ref = db.collection("spaces").doc(input.spaceId)
    .collection("semanticIndex").doc("items")
    .collection("items").doc(input.itemId);
  const path = input.path ?? ref.path;
  const snippet = input.text.slice(0, 240);
  const vector = await upsertVector({
    spaceId: input.spaceId,
    itemId: input.itemId,
    sourceType: input.sourceType,
    text: input.text,
    title: input.title,
    snippet,
    path,
    topics,
    scriptures,
  });
  await ref.set({
    sourceType: input.sourceType,
    sourceId: input.sourceId,
    threadId: input.threadId ?? null,
    title: input.title,
    snippet,
    tokens,
    topics,
    scriptures,
    vectorIndexed: vector.indexed,
    vectorModel: vector.model ?? null,
    generatedBy: "smartMessageIntelligence",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

export async function indexMessageForFallback(
  spaceId: string,
  threadId: string,
  messageId: string,
  text: string,
  topics: string[],
  scriptures: string[]
): Promise<void> {
  await indexSemanticItem({
    spaceId,
    itemId: messageId,
    sourceType: "message",
    threadId,
    sourceId: messageId,
    title: scriptures[0] ?? topics[0] ?? "Message",
    text,
    topics,
    scriptures,
  });
}
