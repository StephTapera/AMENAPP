import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { SmartDiscussionInsight, SmartMessageAction } from "./types";
import { detectScriptures } from "./scriptureDetection";
import { detectPrayerRequests } from "./prayerDetection";
import { extractTopics } from "./topicExtraction";
import { stableId } from "./validators";

const db = admin.firestore();

export function buildExtractiveDiscussionInsight(messages: string[]): SmartDiscussionInsight {
  const text = messages.join("\n").slice(0, 12000);
  const sentences = text
    .split(/(?<=[.!?])\s+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean);
  const questions = sentences.filter((sentence) => sentence.endsWith("?")).slice(0, 6);
  const actionItems = sentences.filter((sentence) => /\b(?:will|can someone|i'll|we should|please)\b/i.test(sentence)).slice(0, 6);
  const scriptures = detectScriptures(text).map((entity) => entity.normalizedValue);
  const prayerRequests = detectPrayerRequests(text).map((entity) => entity.sourceText);
  const topics = extractTopics(text).map((entity) => entity.normalizedValue);
  const keyTakeaways = sentences
    .filter((sentence) => sentence.length > 35 && !sentence.endsWith("?"))
    .slice(0, 5);

  const summary = keyTakeaways.length
    ? keyTakeaways.slice(0, 2).join(" ")
    : "No substantial discussion content was available to summarize.";

  const suggestedNextActions: SmartMessageAction[] = [
    {
      id: stableId("action", [summary, "startStudyMode"]),
      title: "Start Study",
      subtitle: scriptures[0] ?? topics[0] ?? "Create a study session",
      iconSystemName: "book.closed",
      actionType: "startStudyMode",
      payload: { scriptures, topics },
      requiresConfirmation: true,
      privacyLevel: "space",
    },
    {
      id: stableId("action", [summary, "askBerean"]),
      title: "Ask Berean",
      subtitle: "Explore this discussion",
      iconSystemName: "sparkles",
      actionType: "askBerean",
      payload: { summary },
      requiresConfirmation: false,
      privacyLevel: "private",
    },
  ];

  return {
    summary,
    keyTakeaways,
    scriptures: Array.from(new Set(scriptures)).slice(0, 12),
    prayerRequests: Array.from(new Set(prayerRequests)).slice(0, 8),
    topics: Array.from(new Set(topics)).slice(0, 12),
    actionItems,
    unresolvedQuestions: questions,
    suggestedNextActions,
  };
}

export async function loadThreadMessageTexts(
  spaceId: string,
  threadId: string,
  messageIds?: unknown
): Promise<string[]> {
  const base = db.collection("spaces").doc(spaceId).collection("smartThreads").doc(threadId).collection("messages");
  if (Array.isArray(messageIds) && messageIds.length > 0) {
    const snaps = await Promise.all(
      messageIds.slice(0, 80).map((id) => base.doc(String(id)).get())
    );
    return snaps
      .map((snap) => String(snap.data()?.text ?? ""))
      .filter(Boolean);
  }

  const snap = await base.orderBy("createdAt", "desc").limit(80).get();
  return snap.docs
    .map((doc) => String(doc.data().text ?? ""))
    .filter(Boolean)
    .reverse();
}

export async function writeDiscussionInsight(
  spaceId: string,
  threadId: string,
  insight: SmartDiscussionInsight,
  createdBy: string
): Promise<string> {
  if (!insight.summary) {
    throw new HttpsError("failed-precondition", "No summary was generated.");
  }
  const ref = db.collection("spaces").doc(spaceId)
    .collection("smartThreads").doc(threadId)
    .collection("insights").doc();
  await ref.set({
    ...insight,
    createdBy,
    generatedBy: "smartMessageIntelligence",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return ref.id;
}
