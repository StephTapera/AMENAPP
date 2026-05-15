import * as admin from "firebase-admin";

const db = () => admin.firestore();

type LimitKey = "berean_chat_proxy" | "berean_structured" | "berean_analyze";

const LIMITS: Record<LimitKey, { windowMs: number; maxRequests: number }> = {
  berean_chat_proxy: { windowMs: 60_000, maxRequests: 60 },
  berean_structured: { windowMs: 60_000, maxRequests: 40 },
  berean_analyze: { windowMs: 60_000, maxRequests: 90 },
};

export async function enforceBereanRateLimit(userId: string, key: LimitKey): Promise<void> {
  const config = LIMITS[key];
  const bucket = Math.floor(Date.now() / config.windowMs);
  const docRef = db().collection("rateLimits").doc(`${key}:${userId}:${bucket}`);

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const currentCount = snap.exists ? Number(snap.data()?.count ?? 0) : 0;
    if (currentCount >= config.maxRequests) {
      const err = new Error("RATE_LIMIT_EXCEEDED");
      err.name = "BereanRateLimitError";
      throw err;
    }

    tx.set(
      docRef,
      {
        userId,
        key,
        bucket,
        count: currentCount + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis((bucket + 2) * config.windowMs),
      },
      { merge: true }
    );
  });
}
