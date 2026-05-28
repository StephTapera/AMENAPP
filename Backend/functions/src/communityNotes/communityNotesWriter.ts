// communityNotesWriter.ts
// Gen2 Firestore trigger: onDocumentWritten for communityNotes/{noteId}
// Responsibilities:
//   • On delete  → purge from Algolia + Pinecone
//   • On write   → content-hash guard to skip function-owned field updates
//   • If content changed → derive excerpt, scriptureRefs, scriptureRefStrings, scriptureKeys
//   • If indexable → Algolia upsert + OpenAI embed + Pinecone upsert
//   • If not indexable → purge both search indexes
//   • Write derived fields back with merge:true (loop-safe)

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as crypto from "crypto";
import { parseScripture, buildExcerpt } from "./scriptureParser";

if (!getApps().length) initializeApp();
const db = getFirestore();

const ALGOLIA_APP_ID   = defineSecret("ALGOLIA_APP_ID");
const ALGOLIA_ADMIN_KEY = defineSecret("ALGOLIA_ADMIN_KEY");
const PINECONE_API_KEY  = defineSecret("PINECONE_API_KEY");
const OPENAI_API_KEY    = defineSecret("OPENAI_API_KEY");

const ALGOLIA_INDEX       = "community_notes";
const PINECONE_INDEX_HOST = process.env.PINECONE_INDEX_HOST ?? "";
const PINECONE_NAMESPACE  = "community_notes";
const EMBEDDING_MODEL     = "text-embedding-3-small";

// ─── Types ────────────────────────────────────────────────────────────────────

interface NoteData {
  title?: string;
  body?: string;
  category?: string;
  tags?: string[];
  visibility?: string;
  moderationStatus?: string;
  authorId?: string;
  authorName?: string;
  authorHandle?: string;
  authorInitial?: string;
  authorColor?: string;
  likeCount?: number;
  commentCount?: number;
  saveCount?: number;
  createdAt?: FirebaseFirestore.Timestamp;
  [key: string]: unknown;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * SHA-1 hash of the user-editable fields that affect search/indexing.
 * Used to skip trigger re-runs caused by our own derived-field writes.
 */
function contentHash(d: NoteData): string {
  const raw = [
    d.title ?? "",
    d.body ?? "",
    d.category ?? "",
    (d.tags ?? []).join(","),
    d.visibility ?? "",
    d.moderationStatus ?? "",
  ].join("|");
  return crypto.createHash("sha1").update(raw).digest("hex");
}

/**
 * A note is indexable when it is public and approved.
 */
function isIndexable(d: NoteData): boolean {
  return d.visibility === "public" && d.moderationStatus === "approved";
}

/**
 * Fetch an embedding vector from OpenAI.
 * Input text is sliced to 8000 characters to stay within token budget.
 */
async function getEmbedding(text: string, apiKey: string): Promise<number[]> {
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input: text.slice(0, 8000),
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenAI embeddings error ${response.status}: ${err}`);
  }
  const json = (await response.json()) as { data: Array<{ embedding: number[] }> };
  return json.data[0].embedding;
}

// ─── Algolia ──────────────────────────────────────────────────────────────────

async function algoliaUpsert(
  noteId: string,
  record: Record<string, unknown>,
  appId: string,
  adminKey: string
): Promise<void> {
  const url = `https://${appId}.algolia.net/1/indexes/${ALGOLIA_INDEX}/${encodeURIComponent(noteId)}`;
  const response = await fetch(url, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      "X-Algolia-Application-Id": appId,
      "X-Algolia-API-Key": adminKey,
    },
    body: JSON.stringify({ ...record, objectID: noteId }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Algolia upsert error ${response.status}: ${err}`);
  }
}

async function algoliaDelete(
  noteId: string,
  appId: string,
  adminKey: string
): Promise<void> {
  const url = `https://${appId}.algolia.net/1/indexes/${ALGOLIA_INDEX}/${encodeURIComponent(noteId)}`;
  const response = await fetch(url, {
    method: "DELETE",
    headers: {
      "X-Algolia-Application-Id": appId,
      "X-Algolia-API-Key": adminKey,
    },
  });
  // 404 is acceptable — the record may never have been indexed
  if (!response.ok && response.status !== 404) {
    const err = await response.text();
    throw new Error(`Algolia delete error ${response.status}: ${err}`);
  }
}

// ─── Pinecone ─────────────────────────────────────────────────────────────────

async function pineconeUpsert(
  noteId: string,
  vector: number[],
  metadata: Record<string, unknown>,
  apiKey: string
): Promise<void> {
  const url = `${PINECONE_INDEX_HOST}/vectors/upsert`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Api-Key": apiKey,
    },
    body: JSON.stringify({
      vectors: [{ id: noteId, values: vector, metadata }],
      namespace: PINECONE_NAMESPACE,
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Pinecone upsert error ${response.status}: ${err}`);
  }
}

async function pineconeDelete(noteId: string, apiKey: string): Promise<void> {
  const url = `${PINECONE_INDEX_HOST}/vectors/delete`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Api-Key": apiKey,
    },
    body: JSON.stringify({ ids: [noteId], namespace: PINECONE_NAMESPACE }),
  });
  if (!response.ok && response.status !== 404) {
    const err = await response.text();
    throw new Error(`Pinecone delete error ${response.status}: ${err}`);
  }
}

// ─── Trigger ──────────────────────────────────────────────────────────────────

export const onCommunityNoteWritten = onDocumentWritten(
  {
    document: "communityNotes/{noteId}",
    secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_KEY, PINECONE_API_KEY, OPENAI_API_KEY],
  },
  async (event) => {
    const noteId = event.params.noteId;
    const algoliaAppId   = ALGOLIA_APP_ID.value();
    const algoliaKey     = ALGOLIA_ADMIN_KEY.value();
    const pineconeKey    = PINECONE_API_KEY.value();
    const openaiKey      = OPENAI_API_KEY.value();

    // ── Delete path ──────────────────────────────────────────────────────────
    if (!event.data?.after?.exists) {
      await Promise.allSettled([
        algoliaDelete(noteId, algoliaAppId, algoliaKey),
        pineconeDelete(noteId, pineconeKey),
      ]);
      return;
    }

    const after  = event.data.after.data() as NoteData;
    const before = event.data.before?.exists
      ? (event.data.before.data() as NoteData)
      : null;

    const hashAfter  = contentHash(after);
    const hashBefore = before ? contentHash(before) : null;

    // ── Loop-safety guard ────────────────────────────────────────────────────
    // If only function-owned fields changed (indexedToAlgolia, indexedToPinecone,
    // searchSyncedAt, excerpt, scriptureRefs, etc.) the hash is identical — skip.
    const contentChanged = hashAfter !== hashBefore;
    if (!contentChanged) return;

    // ── Derive fields from new content ───────────────────────────────────────
    const body = after.body ?? "";
    const excerpt = buildExcerpt(body);
    const { scriptureRefs, scriptureRefStrings, scriptureKeys } = parseScripture(
      `${after.title ?? ""} ${body}`
    );

    const shouldIndex = isIndexable(after);
    const docRef = db.doc(`communityNotes/${noteId}`);

    if (shouldIndex) {
      // Build Algolia record
      const algoliaRecord: Record<string, unknown> = {
        title:               after.title ?? "",
        excerpt,
        category:            after.category ?? "",
        tags:                after.tags ?? [],
        authorId:            after.authorId ?? "",
        authorName:          after.authorName ?? "",
        authorHandle:        after.authorHandle ?? "",
        authorInitial:       after.authorInitial ?? "",
        authorColor:         after.authorColor ?? "",
        scriptureRefStrings,
        scriptureKeys,
        likeCount:           after.likeCount ?? 0,
        commentCount:        after.commentCount ?? 0,
        saveCount:           after.saveCount ?? 0,
        visibility:          after.visibility ?? "",
        moderationStatus:    after.moderationStatus ?? "",
        _tags:               scriptureKeys,
      };

      // Compose embedding input: title + excerpt + scripture ref strings
      const embedInput = [
        after.title ?? "",
        excerpt,
        ...scriptureRefStrings,
        ...(after.tags ?? []),
      ]
        .join(" ")
        .trim();

      // Fire Algolia + OpenAI in parallel, then Pinecone with the vector
      const [, vector] = await Promise.all([
        algoliaUpsert(noteId, algoliaRecord, algoliaAppId, algoliaKey),
        getEmbedding(embedInput, openaiKey),
      ] as const);

      const pineconeMetadata: Record<string, unknown> = {
        noteId,
        title:               after.title ?? "",
        category:            after.category ?? "",
        authorId:            after.authorId ?? "",
        visibility:          after.visibility ?? "",
        moderationStatus:    after.moderationStatus ?? "",
        scriptureKeys,
      };
      await pineconeUpsert(noteId, vector, pineconeMetadata, pineconeKey);

      // Write derived fields back — merge:true so we don't stomp other fields
      await docRef.set(
        {
          excerpt,
          scriptureRefs,
          scriptureRefStrings,
          scriptureKeys,
          contentHash: hashAfter,
          indexedToAlgolia:  true,
          indexedToPinecone: true,
          searchSyncedAt:    FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      // Purge from both indexes
      await Promise.allSettled([
        algoliaDelete(noteId, algoliaAppId, algoliaKey),
        pineconeDelete(noteId, pineconeKey),
      ]);

      await docRef.set(
        {
          excerpt,
          scriptureRefs,
          scriptureRefStrings,
          scriptureKeys,
          contentHash: hashAfter,
          indexedToAlgolia:  false,
          indexedToPinecone: false,
          searchSyncedAt:    FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  }
);
