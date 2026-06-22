/**
 * DiscipleshipTrackerService.ts
 *
 * Records and retrieves discipleship events; generates follow-up prompts;
 * surfaces growth path suggestions. All operations are fire-and-forget from
 * the caller's perspective — failures are logged but never block a response.
 *
 * Privacy constraints:
 *  - Growth data is private to the user
 *  - Leaders can only see shared data with explicit user consent
 *  - No public spiritual scores or leaderboards
 *  - Growth paths are invitations; never auto-activated
 */

import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import {
  DiscipleshipEvent,
  DiscipleshipEventType,
  FollowUpPrompt,
} from "../models/berean";

// ---------------------------------------------------------------------------
// Event Recording
// ---------------------------------------------------------------------------

/**
 * Records a discipleship event for a user.
 * Non-blocking — callers do not await this.
 */
export async function recordDiscipleshipEvent(
  userId: string,
  eventType: DiscipleshipEventType,
  options: {
    passageId?: string;
    passageReference?: string;
    bereanSessionId?: string;
    note?: string;
  } = {}
): Promise<void> {
  const db = admin.firestore();
  const eventId = uuidv4();
  const event: DiscipleshipEvent = {
    id: eventId,
    userId,
    eventType,
    passageId: options.passageId,
    passageReference: options.passageReference,
    bereanSessionId: options.bereanSessionId,
    note: options.note,
    occurredAt: admin.firestore.Timestamp.now(),
  };

  await db
    .collection("users")
    .doc(userId)
    .collection("discipleshipEvents")
    .doc(eventId)
    .set(event);

  // Increment session counter on profile
  await db
    .collection("users")
    .doc(userId)
    .collection("discipleshipProfile")
    .doc(userId)
    .set(
      {
        totalStudySessions: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.Timestamp.now(),
        lastStudiedBook: options.passageReference
          ? extractBookFromReference(options.passageReference)
          : admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );
}

// ---------------------------------------------------------------------------
// Follow-Up Prompt Generation
// ---------------------------------------------------------------------------

/**
 * Creates a follow-up prompt after a study session.
 * Stored for later surfacing by the notification system.
 */
export async function createFollowUpPrompt(
  userId: string,
  sourceSessionId: string,
  passageReference: string,
  promptText: string,
  scheduledDelayHours = 24
): Promise<void> {
  const db = admin.firestore();
  const promptId = uuidv4();
  const scheduledFor = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + scheduledDelayHours * 60 * 60 * 1000)
  );

  const prompt: FollowUpPrompt = {
    id: promptId,
    userId,
    promptText,
    sourceSessionId,
    passageReference,
    scheduledFor,
    status: "pending",
    createdAt: admin.firestore.Timestamp.now(),
    dismissedAt: undefined,
    engagedAt: undefined,
  };

  await db
    .collection("users")
    .doc(userId)
    .collection("followUpPrompts")
    .doc(promptId)
    .set(prompt);
}

// ---------------------------------------------------------------------------
// Recent Event Fetcher (for AI context window)
// ---------------------------------------------------------------------------

/**
 * Fetches the user's most recent discipleship events for use as context
 * in the AI's generation call.
 */
export async function getRecentEvents(
  userId: string,
  limit = 10
): Promise<DiscipleshipEvent[]> {
  try {
    const db = admin.firestore();
    const snapshot = await db
      .collection("users")
      .doc(userId)
      .collection("discipleshipEvents")
      .orderBy("occurredAt", "desc")
      .limit(limit)
      .get();

    return snapshot.docs.map((d) => d.data() as DiscipleshipEvent);
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function extractBookFromReference(reference: string): string {
  // "John 3:16" → "John", "1 Corinthians 13:4" → "1 Corinthians"
  const match = reference.match(/^([1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)?)/);
  return match ? match[1].trim() : reference.split(" ")[0];
}

export const discipleshipTrackerService = {
  recordDiscipleshipEvent,
  createFollowUpPrompt,
  getRecentEvents,
  async generateNextSteps(
    userId: string,
    conversationId: string,
    sourceThemeIds: string[],
    sourcePassageIds: string[]
  ) {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const theme = sourceThemeIds[0] ?? "faithfulness";
    const passage = sourcePassageIds[0] ?? "Scripture";
    const recommendation = {
      userId,
      title: `Practice ${theme} this week`,
      description: `Choose one concrete response from ${passage} and revisit it before your next Berean study.`,
      practiceType: "scripture_application",
      status: "open" as const,
      conversationId,
      sourceThemeIds,
      sourcePassageIds,
      createdAt: now,
      updatedAt: now,
    };
    const recommendationRef = db.collection("users").doc(userId).collection("practiceRecommendations").doc();
    await recommendationRef.set(recommendation);

    const followUp = {
      id: uuidv4(),
      userId,
      promptText: `What did you notice as you practiced ${theme}?`,
      sourceSessionId: conversationId,
      passageReference: passage,
      scheduledFor: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)),
      status: "pending" as const,
      createdAt: now,
    };
    await db.collection("users").doc(userId).collection("followUpPrompts").doc(followUp.id).set(followUp);

    return {
      recommendations: [{ id: recommendationRef.id, ...recommendation }],
      followUps: [followUp],
    };
  },
};
