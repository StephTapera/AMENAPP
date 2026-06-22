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

// ── Tier + daily quota ─────────────────────────────────────────────────────

/**
 * BereanTier represents the user's subscription level.
 * Values are the daily Berean message caps for each tier.
 * free=20, plus=200, pro/founder=Infinity (unlimited).
 */
export type BereanTier = "free" | "plus" | "pro" | "founder";

const DAILY_CAPS: Record<BereanTier, number> = {
  free: 20,
  plus: 200,
  pro: Infinity,
  founder: Infinity,
};

/**
 * Reads users/{uid}.amenTier from Firestore and returns the corresponding
 * BereanTier. Falls back to "free" if the field is missing or unrecognised.
 */
export async function getBereanUserTier(uid: string): Promise<BereanTier> {
  const snap = await db().collection("users").doc(uid).get();
  const raw = snap.data()?.amenTier as string | undefined;
  const VALID: BereanTier[] = ["free", "plus", "pro", "founder"];
  return VALID.includes(raw as BereanTier) ? (raw as BereanTier) : "free";
}

/**
 * Enforces the per-user, per-day Berean message quota.
 *
 * Returns { messagesUsed, dailyLimit } on success so the caller can surface
 * remaining credits to the client.
 *
 * Throws an Error with name "BereanDailyQuotaError" when the limit is hit
 * so the caller can map it to a 429 with quotaExceeded: true.
 */
export async function enforceBereanDailyQuota(
  uid: string,
  tier: BereanTier
): Promise<{ messagesUsed: number; dailyLimit: number }> {
  const dailyLimit = DAILY_CAPS[tier];

  // Unlimited tiers skip the Firestore round-trip entirely.
  if (!isFinite(dailyLimit)) {
    return { messagesUsed: 0, dailyLimit };
  }

  const today = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
  const docRef = db().collection("bereanDailyQuota").doc(`${uid}:${today}`);

  let messagesUsed = 0;

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const current = snap.exists ? Number(snap.data()?.count ?? 0) : 0;

    if (current >= dailyLimit) {
      const err = new Error("DAILY_QUOTA_EXCEEDED");
      err.name = "BereanDailyQuotaError";
      throw err;
    }

    messagesUsed = current + 1;

    tx.set(
      docRef,
      {
        uid,
        date: today,
        count: messagesUsed,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        // TTL: expire the doc 2 days after the quota day so Firestore TTL can clean it up.
        expiresAt: admin.firestore.Timestamp.fromDate(
          new Date(new Date(today).getTime() + 2 * 24 * 60 * 60 * 1000)
        ),
      },
      { merge: true }
    );
  });

  return { messagesUsed, dailyLimit };
}
