// integrations/integrationIdempotency.ts
// Idempotency guard for meeting creation and other non-repeatable operations

import * as admin from "firebase-admin";

const db = admin.firestore();

export async function checkIdempotency(
  idempotencyKey: string
): Promise<{ isDuplicate: boolean; existingResult?: Record<string, unknown> }> {
  const snap = await db.collection("integrationIdempotencyKeys").doc(idempotencyKey).get();
  if (!snap.exists) return { isDuplicate: false };
  return {
    isDuplicate: true,
    existingResult: snap.data()?.["result"] as Record<string, unknown> | undefined,
  };
}

export async function recordIdempotency(
  idempotencyKey: string,
  result: Record<string, unknown>
): Promise<void> {
  await db.collection("integrationIdempotencyKeys").doc(idempotencyKey).set({
    idempotencyKey,
    result,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    // 24h TTL — cleaned up by scheduled function
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
  });
}
