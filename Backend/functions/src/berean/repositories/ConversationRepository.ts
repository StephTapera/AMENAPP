// berean/repositories/ConversationRepository.ts
// Firestore read/write for berean_conversations and berean_messages.

import * as admin from "firebase-admin";
import { BereanConversation, BereanMessage } from "../models/berean";

const db = () => admin.firestore();

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
    await db().collection("berean_messages").doc(messageId).set(message);
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
