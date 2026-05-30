// berean/repositories/ConversationRepository.ts
// Firestore read/write for berean_conversations and berean_messages.

import * as admin from "firebase-admin";
import { BereanConversation, BereanMessage } from "../models/berean";

const db = () => admin.firestore();

// Scrubs common PII patterns before persisting conversation turns.
// Berean messages can contain names, addresses, and health details typed
// by users in prayer/counsel context; storing them verbatim is unnecessary.
function scrubPII(text: string): string {
  return text
    // Email addresses
    .replace(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, "[email]")
    // SSN: 123-45-6789
    .replace(/\b\d{3}-\d{2}-\d{4}\b/g, "[ssn]")
    // Phone: (555) 123-4567 | 555-123-4567 | +1 555 123 4567
    .replace(/\b(\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/g, "[phone]");
}

export class ConversationRepository {
  // ── Conversations ────────────────────────────────────────────────────────────

  async getConversation(conversationId: string): Promise<BereanConversation | null> {
    const doc = await db().collection("berean_conversations").doc(conversationId).get();
    return doc.exists ? ({ id: doc.id, ...doc.data() } as BereanConversation) : null;
  }

  async createConversation(
    userId: string,
    conversationId: string,
    mode: BereanConversation["currentMode"] = "chat"
  ): Promise<void> {
    const now = admin.firestore.Timestamp.now();
    await db()
      .collection("berean_conversations")
      .doc(conversationId)
      .set({
        userId,
        title: "New Conversation",
        currentMode: mode,
        lastMessageAt: now,
        createdAt: now,
        updatedAt: now,
      });
  }

  async updateConversationTitle(conversationId: string, title: string): Promise<void> {
    await db()
      .collection("berean_conversations")
      .doc(conversationId)
      .update({ title, updatedAt: admin.firestore.Timestamp.now() });
  }

  async touchConversation(conversationId: string): Promise<void> {
    const now = admin.firestore.Timestamp.now();
    await db()
      .collection("berean_conversations")
      .doc(conversationId)
      .update({ lastMessageAt: now, updatedAt: now });
  }

  // ── Messages ─────────────────────────────────────────────────────────────────

  async saveMessage(messageId: string, message: Omit<BereanMessage, "id">): Promise<void> {
    const sanitized = {
      ...message,
      content: typeof (message as Record<string, unknown>).content === "string"
        ? scrubPII((message as Record<string, unknown>).content as string)
        : (message as Record<string, unknown>).content,
    };
    await db().collection("berean_messages").doc(messageId).set(sanitized);
  }

  async getRecentMessages(conversationId: string, limit = 10): Promise<BereanMessage[]> {
    const snap = await db()
      .collection("berean_messages")
      .where("conversationId", "==", conversationId)
      .orderBy("createdAt", "desc")
      .limit(limit)
      .get();
    return snap.docs
      .reverse()
      .map((d) => ({ id: d.id, ...d.data() } as BereanMessage));
  }
}

export const conversationRepository = new ConversationRepository();
