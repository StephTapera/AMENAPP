/**
 * churchVisitLifecycle.ts
 * AMENAPP Cloud Functions — Church Visit Lifecycle Orchestration
 *
 * Functions:
 *   onChurchInteractionAttended    — Triggered when phase transitions to "attended".
 *                                    Schedules follow-up prompt tasks and sends FCM.
 *   onChurchInteractionReflected   — Triggered when phase transitions to "reflected".
 *                                    Schedules the Day-3 return decision prompt.
 *   scheduleChurchFollowUpPrompt   — Callable used by ChurchFollowUpEngine to queue
 *                                    server-side follow-up scheduling.
 *
 * Privacy: all writes are scoped to users/{uid}/churchInteractions/{churchId}.
 * No community-facing visibility is added.
 */

import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const db = admin.firestore();
const messaging = admin.messaging();

// ---------------------------------------------------------------------------
// MARK: - onChurchInteractionAttended
// Trigger: users/{uid}/churchInteractions/{churchId} updated with phase=attended
// ---------------------------------------------------------------------------

export const onChurchInteractionAttended = onDocumentUpdated(
  "users/{uid}/churchInteractions/{churchId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!before || !after) return;

    // Only react to phase transitions into "attended"
    if (before.phase === after.phase || after.phase !== "attended") return;

    const uid = event.params.uid;
    const churchId = event.params.churchId;
    const churchName: string = after.church_name ?? "your church";

    // Write a follow-up schedule record
    const followUpRef = db
      .collection("users")
      .doc(uid)
      .collection("churchFollowUps")
      .doc(churchId);

    await followUpRef.set(
      {
        churchId,
        churchName,
        attendedAt: after.attended_at ?? admin.firestore.Timestamp.now(),
        scheduledSteps: [0, 1, 2],          // sameDay, nextDay, dayThree
        completedSteps: [],
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Send same-day FCM nudge (3h delay simulated via scheduled function)
    await sendFollowUpNotification(uid, churchName, "sameDay", churchId);
  }
);

// ---------------------------------------------------------------------------
// MARK: - onChurchInteractionReflected
// Trigger: users/{uid}/churchInteractions/{churchId} updated with phase=reflected
// ---------------------------------------------------------------------------

export const onChurchInteractionReflected = onDocumentUpdated(
  "users/{uid}/churchInteractions/{churchId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!before || !after) return;
    if (before.phase === after.phase || after.phase !== "reflected") return;

    const uid = event.params.uid;
    const churchId = event.params.churchId;
    const churchName: string = after.church_name ?? "your church";

    // Mark sameDay and nextDay steps as triggered (reflected means user engaged)
    await db
      .collection("users")
      .doc(uid)
      .collection("churchFollowUps")
      .doc(churchId)
      .set(
        {
          completedSteps: admin.firestore.FieldValue.arrayUnion(0, 1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    // Schedule Day-3 follow-up notification (return decision prompt)
    const day3Date = new Date(Date.now() + 3 * 86_400_000);
    await scheduleFollowUpTask(uid, churchId, churchName, "dayThree", day3Date);
  }
);

// ---------------------------------------------------------------------------
// MARK: - scheduleChurchFollowUpPrompt (Callable)
// Called by ChurchFollowUpEngine when completing a step client-side.
// ---------------------------------------------------------------------------

export const scheduleChurchFollowUpPrompt = onCall(
  { enforceAppCheck: false },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

    const { churchId, churchName, step } = request.data as {
      churchId: string;
      churchName: string;
      step: "sameDay" | "nextDay" | "dayThree";
    };

    if (!churchId || !churchName || !step) {
      throw new HttpsError("invalid-argument", "churchId, churchName, and step are required.");
    }

    const offsetDays: Record<string, number> = { sameDay: 0, nextDay: 1, dayThree: 3 };
    const daysOffset = offsetDays[step] ?? 0;
    const fireDate = new Date(Date.now() + daysOffset * 86_400_000);

    await scheduleFollowUpTask(uid, churchId, churchName, step, fireDate);

    return { success: true, step, scheduledAt: fireDate.toISOString() };
  }
);

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

async function sendFollowUpNotification(
  uid: string,
  churchName: string,
  step: string,
  churchId: string
) {
  // Get user's FCM token from Firestore
  const userDoc = await db.collection("users").doc(uid).get();
  const fcmToken: string | undefined = userDoc.data()?.fcmToken;
  if (!fcmToken) return;

  const messages: Record<string, { title: string; body: string }> = {
    sameDay: {
      title: `How was ${churchName}?`,
      body: "Take a moment to capture your thoughts from today's service.",
    },
    nextDay: {
      title: `Still thinking about ${churchName}?`,
      body: "What from Sunday's service is still on your heart?",
    },
    dayThree: {
      title: `Ready to go back to ${churchName}?`,
      body: "Would you like to return, connect, or share your experience?",
    },
  };

  const msg = messages[step];
  if (!msg) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title: msg.title, body: msg.body },
      data: {
        type: "church_follow_up",
        churchId,
        step,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            category: "CHURCH_FOLLOW_UP",
          },
        },
      },
    });
  } catch (error) {
    console.error(`[churchLifecycle] FCM error for uid=${uid} step=${step}:`, error);
  }
}

async function scheduleFollowUpTask(
  uid: string,
  churchId: string,
  churchName: string,
  step: string,
  fireDate: Date
) {
  // Store the scheduled follow-up in Firestore for audit / client sync
  await db
    .collection("users")
    .doc(uid)
    .collection("churchFollowUps")
    .doc(churchId)
    .set(
      {
        [`scheduled_${step}`]: admin.firestore.Timestamp.fromDate(fireDate),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}
