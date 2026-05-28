// unresolvedDiscussionEngine.ts
// AMEN Conversation OS — Unresolved Discussion Tracker
//
// Answers: "What remains unanswered?", "What needs follow-up?"
// Tracks questions, decisions, blockers, and commitments that didn't resolve.

import * as admin from "firebase-admin";
import { UnresolvedQuestion, Blocker, ConversationOSSurface } from "./types";
import { v4 as uuidv4 } from "uuid";

const db = admin.firestore();

// MARK: - Thread-Level Unresolved Tracker

export async function saveUnresolvedItems(
  threadId: string,
  spaceId: string,
  questions: UnresolvedQuestion[],
  blockers: Blocker[],
  surface: ConversationOSSurface
): Promise<void> {
  if (questions.length === 0 && blockers.length === 0) return;

  const insightId = uuidv4();
  const payload = {
    id: insightId,
    threadId,
    spaceId,
    surface,
    unresolvedQuestions: questions,
    blockers,
    savedAt: admin.firestore.FieldValue.serverTimestamp(),
    resolvedAt: null,
    dismissed: false,
  };

  await db
    .collection("threads").doc(threadId)
    .collection("insights").doc(insightId)
    .set(payload);
}

// MARK: - Resolve a Question

export async function markQuestionResolved(
  threadId: string,
  questionId: string
): Promise<void> {
  const snapshot = await db
    .collection("threads").doc(threadId)
    .collection("insights")
    .where("dismissed", "==", false)
    .limit(5)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const questions: UnresolvedQuestion[] = data.unresolvedQuestions ?? [];
    const updated = questions.filter((q) => q.id !== questionId);
    if (updated.length !== questions.length) {
      await doc.ref.update({ unresolvedQuestions: updated });
    }
  }
}

// MARK: - Resolve a Blocker

export async function markBlockerResolved(
  threadId: string,
  blockerId: string
): Promise<void> {
  const snapshot = await db
    .collection("threads").doc(threadId)
    .collection("insights")
    .where("dismissed", "==", false)
    .limit(5)
    .get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const blockers: Blocker[] = data.blockers ?? [];
    const updated = blockers.map((b) =>
      b.id === blockerId ? { ...b, resolved: true } : b
    );
    await doc.ref.update({ blockers: updated });
  }
}

// MARK: - Get Open Items for a Thread

export async function getOpenItems(threadId: string): Promise<{
  questions: UnresolvedQuestion[];
  blockers: Blocker[];
}> {
  try {
    const snapshot = await db
      .collection("threads").doc(threadId)
      .collection("insights")
      .where("dismissed", "==", false)
      .orderBy("savedAt", "desc")
      .limit(3)
      .get();

    const questions: UnresolvedQuestion[] = [];
    const blockers: Blocker[] = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      questions.push(...(data.unresolvedQuestions ?? []));
      blockers.push(...(data.blockers?.filter((b: Blocker) => !b.resolved) ?? []));
    }

    return {
      questions: deduplicateQuestions(questions).slice(0, 8),
      blockers: blockers.slice(0, 5),
    };
  } catch {
    return { questions: [], blockers: [] };
  }
}

// MARK: - Get Cross-Space Unresolved Items for Org

export async function getOrgUnresolvedItems(
  orgId: string,
  limit = 15
): Promise<UnresolvedQuestion[]> {
  try {
    // Get spaces belonging to this org
    const spacesSnapshot = await db
      .collection("spaces")
      .where("orgId", "==", orgId)
      .limit(20)
      .get();

    const spaceIds = spacesSnapshot.docs.map((d) => d.id);
    if (spaceIds.length === 0) return [];

    // Get recent summaries with unresolved questions
    const allQuestions: UnresolvedQuestion[] = [];
    for (const spaceId of spaceIds.slice(0, 5)) {
      const summarySnapshot = await db
        .collection("spaces").doc(spaceId)
        .collection("summaries")
        .orderBy("generatedAt", "desc")
        .limit(2)
        .get();

      for (const doc of summarySnapshot.docs) {
        const unresolvedQuestions = doc.data().unresolvedQuestions ?? [];
        allQuestions.push(...unresolvedQuestions);
      }
    }

    return deduplicateQuestions(allQuestions).slice(0, limit);
  } catch {
    return [];
  }
}

// MARK: - Detect Follow-Up Needs

export function detectFollowUpNeeds(
  questions: UnresolvedQuestion[],
  ageThresholdHours = 24
): UnresolvedQuestion[] {
  const cutoff = new Date(Date.now() - ageThresholdHours * 60 * 60 * 1000);
  return questions.filter((q) => {
    const askedAt = q.askedAt instanceof Date ? q.askedAt : new Date((q.askedAt as any)?.seconds * 1000 ?? 0);
    return askedAt < cutoff;
  });
}

// MARK: - Deduplication

function deduplicateQuestions(questions: UnresolvedQuestion[]): UnresolvedQuestion[] {
  const seen = new Set<string>();
  return questions.filter((q) => {
    const key = q.question.slice(0, 50).toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
