import * as admin from "firebase-admin";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logDiscoverTelemetry } from "./discoverTelemetry";

const ALLOWED = new Set([
  "impression", "visible_ms", "tap", "detail_open", "dwell", "watch_start", "watch_complete", "save", "share", "pray", "follow", "visit_church", "open_notes", "continue_selah"
]);

function requireAuth(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return uid;
}

export const logDiscoverEvent = onCall({ enforceAppCheck: true, timeoutSeconds: 20 }, async (request) => {
  const uid = requireAuth(request);
  const event = String(request.data?.event ?? "").trim();
  const itemId = String(request.data?.itemId ?? "").trim();
  const sessionId = String(request.data?.sessionId ?? "").trim();
  if (!ALLOWED.has(event) || !itemId || !sessionId) {
    throw new HttpsError("invalid-argument", "event, itemId, and sessionId are required.");
  }

  const ref = admin.firestore().collection(`users/${uid}/discoverEvents`).doc();
  await ref.set({
    event,
    itemId,
    sessionId,
    visible_ms: Number(request.data?.visible_ms ?? 0),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logDiscoverTelemetry("event_logged", { uid, event, itemId });
  return { ok: true };
});
