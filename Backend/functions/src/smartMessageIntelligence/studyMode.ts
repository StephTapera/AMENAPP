import * as admin from "firebase-admin";
import { SmartStudySession } from "./types";

const db = admin.firestore();

export async function createSmartStudySession(input: {
  uid: string;
  spaceId: string;
  threadId: string;
  title?: string;
  scriptures: string[];
  topics: string[];
  seedMessageIds: string[];
}): Promise<SmartStudySession> {
  const now = Date.now();
  const ref = db.collection("spaces").doc(input.spaceId)
    .collection("smartThreads").doc(input.threadId)
    .collection("studySessions").doc();
  const session: SmartStudySession = {
    id: ref.id,
    spaceId: input.spaceId,
    threadId: input.threadId,
    title: input.title?.trim() || input.scriptures[0] || input.topics[0] || "Smart Study",
    scriptures: input.scriptures,
    topics: input.topics,
    notes: [],
    participants: [input.uid],
    createdBy: input.uid,
    createdAt: now,
    updatedAt: now,
  };
  await ref.set({
    ...session,
    seedMessageIds: input.seedMessageIds,
    discussionQuestions: buildQuestions(input.scriptures, input.topics),
    suggestedFlow: ["Read", "Observe", "Discuss", "Pray", "Apply"],
    createdAtServer: admin.firestore.FieldValue.serverTimestamp(),
    updatedAtServer: admin.firestore.FieldValue.serverTimestamp(),
  });
  return session;
}

function buildQuestions(scriptures: string[], topics: string[]): string[] {
  const subject = scriptures[0] ?? topics[0] ?? "this discussion";
  return [
    `What stands out most in ${subject}?`,
    "What question should the group answer before moving on?",
    "What would faithful application look like this week?",
  ];
}
