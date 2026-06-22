import { SpeechClient } from "@google-cloud/speech";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

const REGION = "us-central1";
const TRANSCRIPT_NAMESPACE = "sanctuary-transcripts";
const REACTION_BUCKETS = 100;
const ROOM_DRIFT_TOLERANCE_MS = 1500;

const BEREAN_LLM_KEY = defineSecret("BEREAN_LLM_KEY");
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const API_BIBLE_KEY = defineSecret("API_BIBLE_KEY");
const PINECONE_API_KEY = defineSecret("PINECONE_API_KEY");
const PINECONE_HOST = defineSecret("PINECONE_HOST");

const db = getFirestore();
let speechClient: SpeechClient | undefined;

type TranscriptStatus = "pending" | "processing" | "ready" | "failed";
type ScriptureAnchorSource = "ai" | "creator" | "community";
type WatchRoomState = "playing" | "paused" | "prayer";
type SacredReactionType = "amen" | "convicted" | "encouraged" | "need_prayer" | "studying_this" | "saved";

interface TranscriptWord {
  word: string;
  startMs: number;
  endMs: number;
}

interface TranscriptChunk {
  id: string;
  text: string;
  startMs: number;
  endMs: number;
  words: TranscriptWord[];
  embeddingRef?: string;
}

interface ScriptureAnchor {
  verseRef: string;
  timestampMs: number;
  confidence: number;
  source: ScriptureAnchorSource;
}

interface SanctuaryUserRef {
  uid: string;
  displayName?: string | null;
  avatarURL?: string | null;
}

interface SacredReaction {
  type: SacredReactionType;
  timestampMs: number;
  userRef?: SanctuaryUserRef;
}

interface WatchRoomSyncOp {
  type: "join" | "leave" | "play" | "pause" | "prayer" | "seek";
  member?: SanctuaryUserRef;
  uid?: string;
  playheadMs?: number;
}

interface SanctuarySearchScope {
  visibility: "mine" | "community" | "public";
  contentTypes?: string[];
  verseRefs?: string[];
  creatorIds?: string[];
}

interface SanctuarySearchResult {
  videoId: string;
  timestampMs: number;
  title?: string;
  snippet: string;
  verseRefs: string[];
  score: number;
}

const BOOK_MAP: Record<string, string> = {
  genesis: "GEN",
  gen: "GEN",
  exodus: "EXO",
  exo: "EXO",
  leviticus: "LEV",
  lev: "LEV",
  numbers: "NUM",
  num: "NUM",
  deuteronomy: "DEU",
  deu: "DEU",
  joshua: "JOS",
  jos: "JOS",
  judges: "JDG",
  jdg: "JDG",
  ruth: "RUT",
  psalms: "PSA",
  psalm: "PSA",
  psa: "PSA",
  ps: "PSA",
  proverbs: "PRO",
  prov: "PRO",
  ecclesiastes: "ECC",
  isaiah: "ISA",
  isa: "ISA",
  jeremiah: "JER",
  jer: "JER",
  ezekiel: "EZK",
  daniel: "DAN",
  dan: "DAN",
  matthew: "MAT",
  matt: "MAT",
  mark: "MRK",
  luke: "LUK",
  john: "JHN",
  jn: "JHN",
  acts: "ACT",
  romans: "ROM",
  rom: "ROM",
  galatians: "GAL",
  ephesians: "EPH",
  philippians: "PHP",
  colossians: "COL",
  hebrews: "HEB",
  james: "JAS",
  revelation: "REV",
  rev: "REV",
};

const NUMBERED_BOOK_MAP: Record<string, string> = {
  "1 samuel": "1SA",
  "2 samuel": "2SA",
  "1 kings": "1KI",
  "2 kings": "2KI",
  "1 chronicles": "1CH",
  "2 chronicles": "2CH",
  "1 corinthians": "1CO",
  "2 corinthians": "2CO",
  "1 thessalonians": "1TH",
  "2 thessalonians": "2TH",
  "1 timothy": "1TI",
  "2 timothy": "2TI",
  "1 peter": "1PE",
  "2 peter": "2PE",
  "1 john": "1JN",
  "2 john": "2JN",
  "3 john": "3JN",
};

function requireAuth(request: { auth?: { uid?: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  return uid;
}

function requireString(value: unknown, field: string, maxLength = 512): string {
  const text = String(value ?? "").trim();
  if (!text) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  if (text.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return text;
}

function getSpeechClient(): SpeechClient {
  if (!speechClient) {
    speechClient = new SpeechClient();
  }
  return speechClient;
}

function durationToMs(value: { seconds?: number | string; nanos?: number } | null | undefined): number {
  if (!value) {
    return 0;
  }
  return Math.round(Number(value.seconds ?? 0) * 1000 + Number(value.nanos ?? 0) / 1_000_000);
}

function sanitizeIdPart(value: string): string {
  return value.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 160);
}

function anchorId(anchor: ScriptureAnchor): string {
  return `${sanitizeIdPart(anchor.verseRef)}_${anchor.timestampMs}_${anchor.source}`;
}

function normalizeBook(rawBook: string): string | undefined {
  const lower = rawBook.toLowerCase().replace(/\s+/g, " ").trim();
  return NUMBERED_BOOK_MAP[lower] ?? BOOK_MAP[lower] ?? BOOK_MAP[lower.replace(/^[123]\s+/, "")];
}

export function detectScriptureReferences(text: string, timestampMs = 0): ScriptureAnchor[] {
  const anchors: ScriptureAnchor[] = [];
  const seen = new Set<string>();
  const regex = /\b((?:[123]\s+)?[A-Za-z]+)\s+(\d{1,3}):(\d{1,3})(?:-(\d{1,3}))?\b/g;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(text)) !== null) {
    const osisBook = normalizeBook(match[1]);
    if (!osisBook) {
      continue;
    }
    const chapter = Number(match[2]);
    const startVerse = Number(match[3]);
    const endVerse = match[4] ? Number(match[4]) : undefined;
    if (chapter < 1 || startVerse < 1 || (endVerse !== undefined && endVerse < startVerse)) {
      continue;
    }

    const verseRef = endVerse ? `${osisBook}.${chapter}.${startVerse}-${osisBook}.${chapter}.${endVerse}` : `${osisBook}.${chapter}.${startVerse}`;
    if (seen.has(verseRef)) {
      continue;
    }
    seen.add(verseRef);
    anchors.push({ verseRef, timestampMs, confidence: 0.96, source: "ai" });
  }

  return anchors;
}

export function computeReactionDensity(
  reactions: Array<{ timestampMs: number }>,
  durationMs: number,
  bucketCount = REACTION_BUCKETS
): number[] {
  const buckets = Array.from({ length: bucketCount }, () => 0);
  if (durationMs <= 0 || bucketCount <= 0) {
    return buckets;
  }

  for (const reaction of reactions) {
    const clamped = Math.min(Math.max(reaction.timestampMs, 0), durationMs);
    const index = Math.min(bucketCount - 1, Math.floor((clamped / durationMs) * bucketCount));
    buckets[index] += 1;
  }

  const max = Math.max(...buckets, 0);
  if (max === 0) {
    return buckets;
  }
  return buckets.map((count) => Math.round((count / max) * 1000) / 1000);
}

export function applyRoomOperation(room: any, op: WatchRoomSyncOp, uid: string, serverTimeMs: number): any {
  const memberOrbs = Array.isArray(room.memberOrbs) ? [...room.memberOrbs] : [];
  const playheadMs = typeof op.playheadMs === "number" ? Math.max(0, Math.round(op.playheadMs)) : Math.max(0, Number(room.playheadMs ?? 0));

  switch (op.type) {
    case "join": {
      const member = op.member ?? { uid };
      if (!memberOrbs.some((existing: SanctuaryUserRef) => existing.uid === member.uid)) {
        memberOrbs.push(member);
      }
      return { ...room, memberOrbs, lastSyncedAtMs: serverTimeMs };
    }
    case "leave":
      return { ...room, memberOrbs: memberOrbs.filter((member: SanctuaryUserRef) => member.uid !== (op.uid ?? uid)), lastSyncedAtMs: serverTimeMs };
    case "play":
      return { ...room, playheadMs, state: "playing" as WatchRoomState, lastSyncedAtMs: serverTimeMs };
    case "pause":
      return { ...room, playheadMs, state: "paused" as WatchRoomState, lastSyncedAtMs: serverTimeMs };
    case "prayer":
      return { ...room, playheadMs, state: "prayer" as WatchRoomState, lastSyncedAtMs: serverTimeMs };
    case "seek":
      return { ...room, playheadMs, lastSyncedAtMs: serverTimeMs };
    default:
      throw new HttpsError("invalid-argument", "Unsupported room sync op.");
  }
}

async function writeJourneyInteraction(uid: string, interaction: any): Promise<void> {
  const nodeId = `${sanitizeIdPart(interaction.videoRef)}_${new Date().toISOString().slice(0, 10)}`;
  const nodeRef = db.collection("journeyNodes").doc(uid).collection("nodes").doc(nodeId);
  await nodeRef.set(
    {
      id: nodeId,
      videoRef: interaction.videoRef,
      interactions: FieldValue.arrayUnion(interaction),
      themeEmbeddingRef: interaction.themeEmbeddingRef ?? `pending:${interaction.videoRef}`,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function fetchTranscriptChunks(videoId: string): Promise<TranscriptChunk[]> {
  const snap = await db.collection("livingVideos").doc(videoId).collection("transcriptChunks").orderBy("startMs").limit(400).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<TranscriptChunk, "id">) }));
}

async function embedText(text: string): Promise<number[] | null> {
  const key = BEREAN_LLM_KEY.value();
  if (!key) {
    return null;
  }
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${key}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content: { parts: [{ text: text.slice(0, 6000) }] } }),
  });
  if (!response.ok) {
    throw new Error(`Embedding provider returned HTTP ${response.status}`);
  }
  const json = (await response.json()) as { embedding?: { values?: number[] } };
  return json.embedding?.values ?? null;
}

async function pineconeUpsert(namespace: string, vectors: Array<{ id: string; values: number[]; metadata: Record<string, unknown> }>): Promise<void> {
  const apiKey = PINECONE_API_KEY.value();
  const host = PINECONE_HOST.value();
  if (!apiKey || !host || vectors.length === 0) {
    return;
  }

  const response = await fetch(`https://${host}/vectors/upsert`, {
    method: "POST",
    headers: {
      "Api-Key": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ namespace, vectors }),
  });
  if (!response.ok) {
    throw new Error(`Pinecone upsert returned HTTP ${response.status}`);
  }
}

async function pineconeQuery(namespace: string, vector: number[], topK = 12): Promise<Array<{ id: string; score: number }>> {
  const apiKey = PINECONE_API_KEY.value();
  const host = PINECONE_HOST.value();
  if (!apiKey || !host) {
    return [];
  }

  const response = await fetch(`https://${host}/query`, {
    method: "POST",
    headers: {
      "Api-Key": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ namespace, vector, topK, includeMetadata: false }),
  });
  if (!response.ok) {
    throw new Error(`Pinecone query returned HTTP ${response.status}`);
  }
  const json = (await response.json()) as { matches?: Array<{ id: string; score?: number }> };
  return (json.matches ?? []).map((match) => ({ id: match.id, score: match.score ?? 0 }));
}

async function callAnthropic(system: string, prompt: string, maxTokens = 900): Promise<string> {
  const apiKey = ANTHROPIC_API_KEY.value();
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "ANTHROPIC_API_KEY is not configured.");
  }

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
      "x-api-key": apiKey,
    },
    body: JSON.stringify({
      model: "claude-3-5-haiku-latest",
      max_tokens: maxTokens,
      temperature: 0.2,
      system,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic returned HTTP ${response.status}`);
  }
  const json = (await response.json()) as { content?: Array<{ type: string; text?: string }> };
  return (json.content ?? []).map((part) => part.text ?? "").join("\n").trim();
}

async function resolveVerseWithApiBible(verseRef: string): Promise<{ verseRef: string; text?: string; provider: "apiBible" | "unresolved" }> {
  const key = API_BIBLE_KEY.value();
  if (!key) {
    return { verseRef, provider: "unresolved" };
  }
  const bibleId = process.env.API_BIBLE_ID || "de4e12af7f28f599-02";
  const response = await fetch(`https://api.scripture.api.bible/v1/bibles/${bibleId}/passages/${encodeURIComponent(verseRef)}`, {
    headers: { "api-key": key },
  });
  if (!response.ok) {
    return { verseRef, provider: "unresolved" };
  }
  const json = (await response.json()) as { data?: { content?: string } };
  return { verseRef, text: json.data?.content?.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim(), provider: "apiBible" };
}

async function indexTranscriptChunks(videoId: string, chunks: TranscriptChunk[]): Promise<void> {
  const vectors: Array<{ id: string; values: number[]; metadata: Record<string, unknown> }> = [];
  for (const chunk of chunks) {
    const embedding = await embedText(chunk.text);
    if (!embedding) {
      continue;
    }
    const vectorId = `${videoId}::${chunk.id}`;
    vectors.push({
      id: vectorId,
      values: embedding,
      metadata: { videoId, chunkId: chunk.id, startMs: chunk.startMs, endMs: chunk.endMs },
    });
  }
  await pineconeUpsert(TRANSCRIPT_NAMESPACE, vectors);
}

async function persistTranscript(videoId: string, chunks: TranscriptChunk[]): Promise<void> {
  const videoRef = db.collection("livingVideos").doc(videoId);
  const batch = db.batch();
  chunks.forEach((chunk) => {
    batch.set(videoRef.collection("transcriptChunks").doc(chunk.id), {
      ...chunk,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  batch.set(
    videoRef,
    {
      transcriptStatus: "ready" as TranscriptStatus,
      transcriptChunkCount: chunks.length,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await batch.commit();
}

async function transcribeGsUri(videoId: string, mediaURL: string): Promise<TranscriptChunk[]> {
  const [operation] = await getSpeechClient().longRunningRecognize({
    audio: { uri: mediaURL },
    config: {
      languageCode: "en-US",
      enableAutomaticPunctuation: true,
      enableWordTimeOffsets: true,
      model: "latest_long",
    },
  });
  const [result] = await operation.promise();
  const words: TranscriptWord[] = [];
  for (const item of result.results ?? []) {
    const alternative = item.alternatives?.[0];
    for (const wordInfo of alternative?.words ?? []) {
      words.push({
        word: wordInfo.word ?? "",
        startMs: durationToMs(wordInfo.startTime as any),
        endMs: durationToMs(wordInfo.endTime as any),
      });
    }
  }

  const chunks: TranscriptChunk[] = [];
  for (let i = 0; i < words.length; i += 120) {
    const slice = words.slice(i, i + 120);
    if (slice.length === 0) {
      continue;
    }
    const chunkIndex = Math.floor(i / 120);
    chunks.push({
      id: `chunk_${String(chunkIndex).padStart(4, "0")}`,
      text: slice.map((word) => word.word).join(" "),
      startMs: slice[0].startMs,
      endMs: slice[slice.length - 1].endMs,
      words: slice,
      embeddingRef: `${TRANSCRIPT_NAMESPACE}/${videoId}_chunk_${String(chunkIndex).padStart(4, "0")}`,
    });
  }
  return chunks;
}

export const sanctuaryTranscribe = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 540, memory: "1GiB", secrets: [BEREAN_LLM_KEY, PINECONE_API_KEY, PINECONE_HOST] },
  async (request) => {
    requireAuth(request);
    const videoId = requireString(request.data?.videoId, "videoId");
    const videoRef = db.collection("livingVideos").doc(videoId);
    const snap = await videoRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Living video not found.");
    }
    const mediaURL = String(snap.data()?.mediaURL ?? "");
    if (!mediaURL.startsWith("gs://")) {
      await videoRef.set({ transcriptStatus: "failed", transcriptError: "media_url_must_be_gs_uri", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      throw new HttpsError("failed-precondition", "Transcription requires a gs:// Cloud Storage media URL.");
    }

    await videoRef.set({ transcriptStatus: "processing", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    try {
      const chunks = await transcribeGsUri(videoId, mediaURL);
      await persistTranscript(videoId, chunks);
      await indexTranscriptChunks(videoId, chunks);
      return { videoId, transcriptDocPath: `livingVideos/${videoId}/transcriptChunks`, status: "ready" as TranscriptStatus };
    } catch (error) {
      logger.error("sanctuaryTranscribe failed", { videoId, error });
      await videoRef.set({ transcriptStatus: "failed", transcriptError: String((error as Error).message ?? error), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      throw new HttpsError("internal", "Transcription failed.");
    }
  }
);

export const sanctuaryAnchorScripture = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 180, secrets: [ANTHROPIC_API_KEY, API_BIBLE_KEY] },
  async (request) => {
    requireAuth(request);
    const videoId = requireString(request.data?.videoId, "videoId");
    const chunks = await fetchTranscriptChunks(videoId);
    if (chunks.length === 0) {
      throw new HttpsError("failed-precondition", "Transcript must be ready before scripture anchoring.");
    }

    const anchorMap = new Map<string, ScriptureAnchor>();
    chunks.forEach((chunk) => {
      detectScriptureReferences(chunk.text, chunk.startMs).forEach((anchor) => anchorMap.set(anchor.verseRef, anchor));
    });

    if (ANTHROPIC_API_KEY.value()) {
      const sample = chunks.map((chunk) => `[${chunk.startMs}ms] ${chunk.text}`).join("\n").slice(0, 18000);
      const raw = await callAnthropic(
        "You detect explicit and paraphrased Scripture references. Return only JSON array items with verseRef OSIS, timestampMs, confidence 0..1.",
        sample,
        1200
      );
      try {
        const parsed = JSON.parse(raw.replace(/^```json\s*/i, "").replace(/```$/i, "")) as Array<Partial<ScriptureAnchor>>;
        parsed.forEach((candidate) => {
          if (typeof candidate.verseRef === "string" && typeof candidate.timestampMs === "number") {
            anchorMap.set(candidate.verseRef, {
              verseRef: candidate.verseRef,
              timestampMs: Math.max(0, Math.round(candidate.timestampMs)),
              confidence: Math.min(1, Math.max(0, Number(candidate.confidence ?? 0.7))),
              source: "ai",
            });
          }
        });
      } catch (error) {
        logger.warn("sanctuaryAnchorScripture: semantic JSON parse failed; keeping explicit anchors", { videoId, error });
      }
    }

    const anchors = Array.from(anchorMap.values()).sort((a, b) => a.timestampMs - b.timestampMs);
    const videoRef = db.collection("livingVideos").doc(videoId);
    const batch = db.batch();
    for (const anchor of anchors) {
      const resolved = await resolveVerseWithApiBible(anchor.verseRef);
      batch.set(videoRef.collection("anchors").doc(anchorId(anchor)), {
        ...anchor,
        resolvedText: resolved.text ?? null,
        provider: resolved.provider,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    batch.set(videoRef, { scriptureAnchors: anchors, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await batch.commit();
    return { videoId, anchors };
  }
);

export const sanctuarySearch = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 60, secrets: [BEREAN_LLM_KEY, PINECONE_API_KEY, PINECONE_HOST] },
  async (request) => {
    const uid = requireAuth(request);
    const query = requireString(request.data?.query, "query", 300);
    const scope = (request.data?.scope ?? { visibility: "mine" }) as SanctuarySearchScope;
    const terms = query.toLowerCase().split(/\W+/).filter((term) => term.length > 2);

    const results = new Map<string, SanctuarySearchResult>();
    const videoSnap = await db.collection("livingVideos").limit(50).get();
    for (const videoDoc of videoSnap.docs) {
      const video = videoDoc.data();
      if (scope.visibility === "mine" && video.ownerUid !== uid) {
        continue;
      }
      if (scope.contentTypes?.length && !scope.contentTypes.includes(video.contentType)) {
        continue;
      }
      const chunkSnap = await videoDoc.ref.collection("transcriptChunks").orderBy("startMs").limit(200).get();
      for (const chunkDoc of chunkSnap.docs) {
        const chunk = chunkDoc.data() as TranscriptChunk;
        const text = String(chunk.text ?? "");
        const lower = text.toLowerCase();
        const hits = terms.filter((term) => lower.includes(term)).length;
        if (hits === 0) {
          continue;
        }
        results.set(`${videoDoc.id}_${chunkDoc.id}`, {
          videoId: videoDoc.id,
          timestampMs: Number(chunk.startMs ?? 0),
          title: video.title,
          snippet: text.slice(0, 260),
          verseRefs: (video.scriptureAnchors ?? []).map((anchor: ScriptureAnchor) => anchor.verseRef),
          score: hits / terms.length,
        });
      }
    }

    const embedding = await embedText(query);
    if (embedding) {
      const matches = await pineconeQuery(TRANSCRIPT_NAMESPACE, embedding, 12);
      for (const match of matches) {
        const [videoId, chunkId] = match.id.split("::");
        if (!videoId || !chunkId) {
          continue;
        }
        const chunkSnap = await db.collection("livingVideos").doc(videoId).collection("transcriptChunks").doc(chunkId).get();
        if (chunkSnap.exists) {
          const chunk = chunkSnap.data() as TranscriptChunk;
          results.set(match.id, {
            videoId,
            timestampMs: Number(chunk.startMs ?? 0),
            snippet: String(chunk.text ?? "").slice(0, 260),
            verseRefs: [],
            score: Math.max(match.score, results.get(match.id)?.score ?? 0),
          });
        }
      }
    }

    const sorted = Array.from(results.values()).sort((a, b) => b.score - a.score).slice(0, 20);
    await writeJourneyInteraction(uid, { id: `search_${Date.now()}`, type: "search", videoRef: sorted[0]?.videoId ?? "global", createdAt: new Date().toISOString(), metadata: { query } });
    return { results: sorted };
  }
);

export const sanctuaryReact = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request);
    const videoId = requireString(request.data?.videoId, "videoId");
    const reaction = request.data?.reaction as SacredReaction;
    if (!reaction || !["amen", "convicted", "encouraged", "need_prayer", "studying_this", "saved"].includes(reaction.type)) {
      throw new HttpsError("invalid-argument", "Valid reaction is required.");
    }
    const timestampMs = Math.max(0, Math.round(Number(reaction.timestampMs ?? 0)));
    const minuteBucket = Math.floor(Date.now() / 60000);
    const rateRef = db.collection("_rateLimits").doc(`sanctuaryReact_${uid}_${videoId}_${minuteBucket}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(rateRef);
      const count = Number(snap.data()?.count ?? 0);
      if (count >= 20) {
        throw new HttpsError("resource-exhausted", "Too many reactions for this video.");
      }
      tx.set(rateRef, { count: count + 1, ttl: Timestamp.fromMillis(Date.now() + 90 * 60 * 1000) }, { merge: true });
    });

    const reactionRef = db.collection("livingVideos").doc(videoId).collection("reactions").doc(`${uid}_${reaction.type}_${timestampMs}`);
    await reactionRef.set({
      type: reaction.type,
      timestampMs,
      userRef: { ...(reaction.userRef ?? {}), uid },
      createdAt: FieldValue.serverTimestamp(),
    });
    const field = await recomputeReactionField(videoId);
    await writeJourneyInteraction(uid, { id: `reaction_${Date.now()}`, type: "reaction", videoRef: videoId, timestampMs, createdAt: new Date().toISOString(), metadata: { reactionType: reaction.type } });
    return { accepted: true, bucketIndex: Math.min(REACTION_BUCKETS - 1, Math.floor((timestampMs / Math.max(field.durationMs, 1)) * REACTION_BUCKETS)) };
  }
);

async function recomputeReactionField(videoId: string): Promise<{ durationMs: number; buckets: number[] }> {
  const videoRef = db.collection("livingVideos").doc(videoId);
  const videoSnap = await videoRef.get();
  const durationMs = Math.max(1, Number(videoSnap.data()?.durationMs ?? videoSnap.data()?.mediaDurationMs ?? 1));
  const reactionSnap = await videoRef.collection("reactions").limit(5000).get();
  const reactions = reactionSnap.docs.map((doc) => ({ timestampMs: Number(doc.data().timestampMs ?? 0) }));
  const buckets = computeReactionDensity(reactions, durationMs);
  await videoRef.collection("reactionFields").doc("current").set({
    videoId,
    buckets,
    bucketDurationMs: Math.ceil(durationMs / REACTION_BUCKETS),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { durationMs, buckets };
}

export const sanctuaryReactionField = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    requireAuth(request);
    const videoId = requireString(request.data?.videoId, "videoId");
    const snap = await db.collection("livingVideos").doc(videoId).collection("reactionFields").doc("current").get();
    if (snap.exists) {
      return snap.data();
    }
    const field = await recomputeReactionField(videoId);
    return { videoId, buckets: field.buckets, bucketDurationMs: Math.ceil(field.durationMs / REACTION_BUCKETS), updatedAt: new Date().toISOString() };
  }
);

export const sanctuaryRoomSync = onCall(
  { region: REGION, enforceAppCheck: true, timeoutSeconds: 30 },
  async (request) => {
    const uid = requireAuth(request);
    const roomId = requireString(request.data?.roomId, "roomId");
    const op = request.data?.op as WatchRoomSyncOp;
    if (!op?.type) {
      throw new HttpsError("invalid-argument", "room sync op is required.");
    }
    const roomRef = db.collection("watchRooms").doc(roomId);
    const serverTimeMs = Date.now();
    let room: any;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(roomRef);
      const current = snap.exists ? snap.data()! : { id: roomId, hostRef: { uid }, memberOrbs: [], playheadMs: 0, state: "paused" };
      room = applyRoomOperation(current, op, uid, serverTimeMs);
      tx.set(roomRef, { ...room, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      tx.set(roomRef.collection("events").doc(), { op, uid, serverTimeMs, createdAt: FieldValue.serverTimestamp() });
    });
    const correctionMs = typeof op.playheadMs === "number" ? Math.round(Number(room.playheadMs ?? 0) - op.playheadMs) : 0;
    return { room, serverTimeMs, correctionMs: Math.abs(correctionMs) > ROOM_DRIFT_TOLERANCE_MS ? correctionMs : 0 };
  }
);

export const sanctuaryAskMoment = onRequest(
  { region: REGION, timeoutSeconds: 180, cors: true, secrets: [ANTHROPIC_API_KEY] },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("POST required");
      return;
    }

    try {
      const authHeader = String(request.header("authorization") ?? "");
      const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
      const decoded = await getAuth().verifyIdToken(idToken);
      const appCheckToken = request.header("x-firebase-appcheck");
      if (appCheckToken) {
        await getAppCheck().verifyToken(appCheckToken);
      }

      const videoId = requireString(request.body?.videoId, "videoId");
      const timestampMs = Math.max(0, Math.round(Number(request.body?.timestampMs ?? 0)));
      const question = requireString(request.body?.question, "question", 1000);
      const chunks = await fetchTranscriptChunks(videoId);
      const nearby = chunks.filter((chunk) => Math.abs(chunk.startMs - timestampMs) < 120000).map((chunk) => chunk.text).join("\n").slice(0, 9000);
      const anchorsSnap = await db.collection("livingVideos").doc(videoId).collection("anchors").limit(40).get();
      const anchors = anchorsSnap.docs.map((doc) => doc.data());
      const answer = await callAnthropic(
        "You are Berean. Answer only from the supplied video moment, transcript, and Scripture anchors. Include concise citations.",
        JSON.stringify({ question, timestampMs, transcript: nearby, anchors }),
        1000
      );

      await writeJourneyInteraction(decoded.uid, { id: `question_${Date.now()}`, type: "question", videoRef: videoId, timestampMs, createdAt: new Date().toISOString(), metadata: { question } });

      response.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      response.write(`event: citations\ndata: ${JSON.stringify({ anchors })}\n\n`);
      for (const sentence of answer.split(/(?<=[.!?])\s+/).filter(Boolean)) {
        response.write(`event: chunk\ndata: ${JSON.stringify({ text: sentence })}\n\n`);
      }
      response.write(`event: done\ndata: ${JSON.stringify({ ok: true })}\n\n`);
      response.end();
    } catch (error) {
      logger.error("sanctuaryAskMoment failed", error);
      response.status(500).json({ error: "ask_moment_failed" });
    }
  }
);

export const sanctuaryWeeklyDigest = onSchedule(
  { region: REGION, schedule: "every monday 08:00", timeZone: "America/Chicago" },
  async () => {
    const since = Timestamp.fromMillis(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const videos = await db.collection("livingVideos").where("updatedAt", ">=", since).limit(500).get();
    const byCreator = new Map<string, { videoIds: string[]; reactionCount: number; questionCount: number }>();

    for (const videoDoc of videos.docs) {
      const ownerUid = String(videoDoc.data().ownerUid ?? "");
      if (!ownerUid) {
        continue;
      }
      const current = byCreator.get(ownerUid) ?? { videoIds: [], reactionCount: 0, questionCount: 0 };
      current.videoIds.push(videoDoc.id);
      const reactions = await videoDoc.ref.collection("reactions").count().get();
      current.reactionCount += reactions.data().count;
      byCreator.set(ownerUid, current);
    }

    const batch = db.batch();
    for (const [creatorId, digest] of byCreator.entries()) {
      const ref = db.collection("creatorWeeklyDigests").doc(`${creatorId}_${new Date().toISOString().slice(0, 10)}`);
      batch.set(ref, {
        creatorId,
        weekStart: since,
        sanctuary: digest,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    logger.info("sanctuaryWeeklyDigest completed", { digestsWritten: byCreator.size });
  }
);
