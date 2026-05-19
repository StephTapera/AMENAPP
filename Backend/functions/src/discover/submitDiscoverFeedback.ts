import * as admin from "firebase-admin";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logDiscoverTelemetry } from "./discoverTelemetry";

const ALLOWED = new Set([
  "not_for_me", "too_intense", "repetitive", "theologically_unclear", "hide_creator", "hide_topic", "report", "reduce_local", "reduce_ai_assisted"
]);

function requireAuth(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

export const submitDiscoverFeedback = onCall({ enforceAppCheck: true, timeoutSeconds: 20 }, async (request) => {
  const uid = requireAuth(request);
  const itemId = String(request.data?.itemId ?? "").trim();
  const sessionId = String(request.data?.sessionId ?? "").trim();
  const feedbackType = String(request.data?.feedbackType ?? "").trim();

  if (!itemId || !sessionId || !ALLOWED.has(feedbackType)) {
    throw new HttpsError("invalid-argument", "itemId, sessionId, and valid feedbackType are required.");
  }

  const ref = admin.firestore().collection(`users/${uid}/discoverFeedback`).doc();
  await ref.set({
    itemId,
    sessionId,
    feedbackType,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  if (["not_for_me", "report"].includes(feedbackType)) {
    await admin.firestore().doc(`users/${uid}/hiddenDiscoverItems/${itemId}`).set({
      itemId,
      reason: feedbackType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  logDiscoverTelemetry("feedback_submitted", { uid, itemId, feedbackType });
  return { ok: true };
});
