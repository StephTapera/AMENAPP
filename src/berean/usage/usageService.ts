/**
 * usageService.ts — Berean Phase 2C
 *
 * Client-side read-only usage service.
 * The credit ledger is CF-owned (B-6). This file only reads.
 * No localStorage. No writes.
 *
 * Collection path: berean/{uid}/usage  (orderBy createdAt desc, limit 1)
 */

import {
  getFirestore,
  collection,
  query,
  orderBy,
  limit,
  getDocs,
  onSnapshot,
  Timestamp,
} from 'firebase/firestore';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface UsagePeriod {
  sessionPct: number;      // 0–100
  weeklyPct: number;       // 0–100
  creditsUsed: number;
  creditsCap: number;
  safetyExempt: true;      // always present — safety actions never counted
  resetsAt: Date;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns the next Sunday at 00:00:00 UTC following the given date.
 * Sunday is day 0 in JS. If today IS Sunday, return next Sunday (7 days out)
 * so the period is always at least 1 day away.
 */
function nextSundayMidnightUTC(from: Date): Date {
  const d = new Date(from);
  // Day 0 = Sunday
  const daysUntilSunday = (7 - d.getUTCDay()) % 7 || 7;
  d.setUTCDate(d.getUTCDate() + daysUntilSunday);
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

/**
 * Converts a raw Firestore doc data object into a typed UsagePeriod.
 * The CF always writes safetyExempt: true; we enforce it here defensively.
 */
function docToUsagePeriod(data: Record<string, unknown>): UsagePeriod {
  const sessionPct = typeof data['sessionPct'] === 'number'
    ? Math.max(0, Math.min(100, data['sessionPct']))
    : 0;

  const weeklyPct = typeof data['weeklyPct'] === 'number'
    ? Math.max(0, Math.min(100, data['weeklyPct']))
    : 0;

  const creditsUsed = typeof data['creditsUsed'] === 'number'
    ? Math.max(0, data['creditsUsed'])
    : 0;

  const creditsCap = typeof data['creditsCap'] === 'number'
    ? Math.max(1, data['creditsCap'])
    : 1;

  // resetsAt: prefer what the CF wrote; fall back to next Sunday midnight UTC
  let resetsAt: Date;
  if (data['resetsAt'] instanceof Timestamp) {
    resetsAt = data['resetsAt'].toDate();
  } else if (data['resetsAt'] instanceof Date) {
    resetsAt = data['resetsAt'];
  } else {
    resetsAt = nextSundayMidnightUTC(new Date());
  }

  return {
    sessionPct,
    weeklyPct,
    creditsUsed,
    creditsCap,
    safetyExempt: true,   // invariant — never derived from remote data
    resetsAt,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// fetchUsage — one-shot read
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetches the most recent usage period for a user.
 * Returns a default zeroed period if no document exists yet.
 */
export async function fetchUsage(userId: string): Promise<UsagePeriod> {
  const db = getFirestore();
  const usageCol = collection(db, 'berean', userId, 'usage');
  const q = query(usageCol, orderBy('createdAt', 'desc'), limit(1));
  const snap = await getDocs(q);

  if (snap.empty) {
    return {
      sessionPct: 0,
      weeklyPct: 0,
      creditsUsed: 0,
      creditsCap: 1,
      safetyExempt: true,
      resetsAt: nextSundayMidnightUTC(new Date()),
    };
  }

  return docToUsagePeriod(snap.docs[0].data() as Record<string, unknown>);
}

// ─────────────────────────────────────────────────────────────────────────────
// subscribeUsage — real-time Firestore listener
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Subscribes to the most recent usage period document in real time.
 * Returns an unsubscribe function — always call it on cleanup.
 *
 * The callback is invoked immediately with the current value (Firestore
 * onSnapshot semantics), then again on every subsequent write.
 */
export function subscribeUsage(
  userId: string,
  cb: (usage: UsagePeriod) => void,
): () => void {
  const db = getFirestore();
  const usageCol = collection(db, 'berean', userId, 'usage');
  const q = query(usageCol, orderBy('createdAt', 'desc'), limit(1));

  const unsubscribe = onSnapshot(q, (snap) => {
    if (snap.empty) {
      cb({
        sessionPct: 0,
        weeklyPct: 0,
        creditsUsed: 0,
        creditsCap: 1,
        safetyExempt: true,
        resetsAt: nextSundayMidnightUTC(new Date()),
      });
      return;
    }

    cb(docToUsagePeriod(snap.docs[0].data() as Record<string, unknown>));
  });

  return unsubscribe;
}
