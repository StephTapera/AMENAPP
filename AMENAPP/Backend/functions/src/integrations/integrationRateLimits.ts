// integrations/integrationRateLimits.ts
// Per-user, per-provider rate limiting using Firestore counters

import * as admin from "firebase-admin";
import { AmenIntegrationError } from "./integrationErrors";
import type { AmenIntegrationProvider } from "./types";

const db = admin.firestore();

const RATE_LIMITS: Record<string, { maxRequests: number; windowMs: number }> = {
  oauth_start: { maxRequests: 5, windowMs: 60_000 },
  meeting_create: { maxRequests: 10, windowMs: 60_000 },
  slack_notify: { maxRequests: 20, windowMs: 60_000 },
  token_refresh: { maxRequests: 10, windowMs: 60_000 },
};

export async function checkRateLimit(
  uid: string,
  action: string,
  provider?: AmenIntegrationProvider
): Promise<void> {
  const limit = RATE_LIMITS[action];
  if (!limit) return;

  const key = provider ? `${uid}_${provider}_${action}` : `${uid}_${action}`;
  const windowStart = Date.now() - limit.windowMs;
  const ref = db.collection("integrationRateLimits").doc(key);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const count = data?.["count"] as number ?? 0;
    const windowStartStored = (data?.["windowStart"] as admin.firestore.Timestamp)?.toMillis() ?? 0;

    if (windowStartStored < windowStart) {
      // New window
      tx.set(ref, {
        count: 1,
        windowStart: admin.firestore.Timestamp.fromMillis(Date.now()),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (count >= limit.maxRequests) {
      throw new AmenIntegrationError("rate-limited");
    } else {
      tx.update(ref, {
        count: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
}
