import * as admin from "firebase-admin";

const db = admin.firestore();

export function recordSmartMessageMetric(
  event: string,
  uid: string,
  data: Record<string, unknown> = {}
): void {
  const safeData = Object.fromEntries(
    Object.entries(data).filter(([key]) => !/text|body|transcript|summary|prayer/i.test(key))
  );
  db.collection("_analyticsEvents").add({
    event,
    uid,
    surface: "smart_message_intelligence",
    ...safeData,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }).catch(() => {
    // Analytics must never block a user-facing callable.
  });
}
