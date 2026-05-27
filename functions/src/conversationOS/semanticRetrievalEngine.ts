// semanticRetrievalEngine.ts
// AMEN Conversation OS — Semantic Retrieval Engine
//
// Retrieves semantically relevant messages for compression and summarization.
// Abstraction supports: keyword fallback (staging), Firestore vector search,
// and future integration with Pinecone / pgvector / Vertex AI Vector Search.
// Never retrieves from inaccessible spaces — always permission-validated upstream.

import * as admin from "firebase-admin";
import { RawMessage, ConversationOSSurface } from "./types";

const db = admin.firestore();

// MARK: - Retrieve Messages for Summarization

export async function retrieveMessagesForWindow(
  spaceId: string,
  threadId: string | undefined,
  surface: ConversationOSSurface,
  windowStart: Date,
  windowEnd: Date,
  limit = 200
): Promise<RawMessage[]> {
  try {
    const collectionPath = getMessageCollectionPath(surface, spaceId, threadId);

    const snapshot = await db
      .collection(collectionPath)
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(windowStart))
      .where("timestamp", "<=", admin.firestore.Timestamp.fromDate(windowEnd))
      .orderBy("timestamp", "asc")
      .limit(limit)
      .get();

    return snapshot.docs.map(docToRawMessage).filter(Boolean) as RawMessage[];
  } catch (err) {
    console.error("retrieveMessagesForWindow error:", err);
    return [];
  }
}

// MARK: - Retrieve Unread Messages Since Last Visit

export async function retrieveUnreadMessages(
  spaceId: String,
  threadId: string | undefined,
  surface: ConversationOSSurface,
  lastVisitedAt: Date,
  limit = 150
): Promise<RawMessage[]> {
  return retrieveMessagesForWindow(
    spaceId as string, threadId, surface,
    lastVisitedAt, new Date(), limit
  );
}

// MARK: - Retrieve High-Signal Messages (ranked by engagement)

export async function retrieveHighSignalMessages(
  spaceId: string,
  threadId: string | undefined,
  surface: ConversationOSSurface,
  limit = 50
): Promise<RawMessage[]> {
  try {
    const collectionPath = getMessageCollectionPath(surface, spaceId, threadId);

    // Get messages with highest reaction + reply counts
    const snapshot = await db
      .collection(collectionPath)
      .orderBy("reactionCount", "desc")
      .limit(limit)
      .get();

    return snapshot.docs.map(docToRawMessage).filter(Boolean) as RawMessage[];
  } catch {
    return [];
  }
}

// MARK: - Keyword-Based Retrieval (fallback for staging/dev)

export async function retrieveByKeywords(
  spaceId: string,
  threadId: string | undefined,
  surface: ConversationOSSurface,
  keywords: string[],
  limit = 50
): Promise<RawMessage[]> {
  if (keywords.length === 0) return [];

  try {
    // Firestore doesn't support full-text search natively.
    // We query using searchKeywords array-contains-any if the data model supports it.
    const collectionPath = getMessageCollectionPath(surface, spaceId, threadId);
    const searchableKeywords = keywords.map((k) => k.toLowerCase()).slice(0, 10);

    const snapshot = await db
      .collection(collectionPath)
      .where("searchKeywords", "array-contains-any", searchableKeywords)
      .orderBy("timestamp", "desc")
      .limit(limit)
      .get();

    return snapshot.docs.map(docToRawMessage).filter(Boolean) as RawMessage[];
  } catch {
    return [];
  }
}

// MARK: - Retrieve Thread Messages

export async function retrieveThreadMessages(
  threadId: string,
  limit = 100
): Promise<RawMessage[]> {
  try {
    const snapshot = await db
      .collection("messages")
      .where("threadId", "==", threadId)
      .orderBy("timestamp", "asc")
      .limit(limit)
      .get();

    return snapshot.docs.map(docToRawMessage).filter(Boolean) as RawMessage[];
  } catch {
    return [];
  }
}

// MARK: - Collection Path Resolution

function getMessageCollectionPath(
  surface: ConversationOSSurface,
  spaceId: string,
  threadId?: string
): string {
  switch (surface) {
    case "amen_spaces":
    case "church_discussion":
    case "org_hub":
    case "creator_community":
    case "classroom_discussion":
    case "prayer_room":
    case "leadership_room":
    case "event_chat":
      // Space-scoped messages
      return threadId
        ? `spaces/${spaceId}/threads/${threadId}/messages`
        : `spaces/${spaceId}/messages`;

    case "group_messages":
    case "direct_messages":
      // Conversation-scoped messages
      return `conversations/${spaceId}/messages`;

    case "berean_study":
      return `spaces/${spaceId}/messages`;

    case "media_comments":
      return `posts/${spaceId}/comments`;

    case "admin_channel":
      return `spaces/${spaceId}/messages`;

    default:
      return `spaces/${spaceId}/messages`;
  }
}

// MARK: - Document → RawMessage

function docToRawMessage(doc: admin.firestore.QueryDocumentSnapshot): RawMessage | null {
  const data = doc.data();
  if (!data.text && !data.body && !data.content) return null;

  const text: string = data.text ?? data.body ?? data.content ?? "";
  if (!text.trim()) return null;

  return {
    id: doc.id,
    senderId: data.senderId ?? data.uid ?? data.authorId ?? "",
    senderDisplayName: data.senderDisplayName ?? data.displayName ?? data.authorName ?? "Unknown",
    text,
    timestamp: data.timestamp ?? data.createdAt ?? admin.firestore.Timestamp.now(),
    threadId: data.threadId ?? "",
    reactionCount: data.reactionCount ?? data.reactions?.length ?? 0,
    replyCount: data.replyCount ?? data.replies?.length ?? 0,
    tags: data.semanticTags ?? data.tags ?? [],
    isEdited: data.isEdited ?? false,
  };
}

// MARK: - Rank Messages by Signal

export function rankMessagesBySignal(messages: RawMessage[]): RawMessage[] {
  return [...messages].sort((a, b) => {
    const scoreA = a.reactionCount * 2 + a.replyCount * 1.5 + (a.tags?.length ?? 0);
    const scoreB = b.reactionCount * 2 + b.replyCount * 1.5 + (b.tags?.length ?? 0);
    return scoreB - scoreA;
  });
}

// MARK: - Embedding Abstraction (future: Pinecone / pgvector / Vertex)

export interface EmbeddingProvider {
  embed(text: string): Promise<number[]>;
  search(embedding: number[], topK: number): Promise<string[]>; // Returns message IDs
}

// Stub implementation — replace with real vector DB when available
export class FirestoreFallbackEmbeddingProvider implements EmbeddingProvider {
  async embed(_text: string): Promise<number[]> {
    // Staging fallback: no real embeddings
    return [];
  }

  async search(_embedding: number[], _topK: number): Promise<string[]> {
    // Staging fallback: return empty (keyword search is used instead)
    return [];
  }
}
