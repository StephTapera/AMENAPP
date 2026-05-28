// accessPassRateLimit.ts — Rate limiting for Access Pass operations
//
// Stored in Firestore rateLimits collection.
// Short windows protect against scan abuse and brute force.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const db = admin.firestore();

const WINDOWS = {
  resolve: { maxRequests: 10, windowMs: 60_000 },     // 10 resolves/min per identity
  accept: { maxRequests: 5, windowMs: 60_000 },        // 5 accepts/min per identity
  invalidToken: { maxRequests: 5, windowMs: 300_000 }, // 5 invalid attempts/5min per identity
};

/**
 * Check and increment the rate limit counter for an operation.
 * Identity is uid if authenticated, else anonymousSessionId.
 * Throws HttpsError("resource-exhausted") if limit exceeded.
 */
export async function enforceRateLimit(
  operation: keyof typeof WINDOWS,
  identity: string
): Promise<void> {
  const { maxRequests, windowMs } = WINDOWS[operation];
  const now = Date.now();
  const windowStart = now - windowMs;
  const docId = `${operation}:${identity}`;
  const ref = db.collection("rateLimits").doc(docId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? { timestamps: [] as number[] };

    // Prune old timestamps outside window
    const recent: number[] = (data.timestamps as number[]).filter(
      (ts) => ts > windowStart
    );

    if (recent.length >= maxRequests) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "rate-limited"
      );
    }

    recent.push(now);
    tx.set(ref, { timestamps: recent, updatedAt: admin.firestore.Timestamp.now() });
  });
}

/** Increment invalid token counter and check abuse threshold. */
export async function recordInvalidTokenAttempt(
  identity: string
): Promise<void> {
  await enforceRateLimit("invalidToken", identity);
}
