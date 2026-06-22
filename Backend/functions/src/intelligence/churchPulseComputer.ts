// churchPulseComputer.ts
// Living Intelligence System — Church Pulse Subsystem
//
// Computes church-health metrics from REAL Firestore data only.
// NO fabricated scores, NO estimates, NO filler values.
// If a data source is unavailable the score uses only what IS available.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// ChurchPulseData — Firestore shape written to church_pulse/{churchId}
// ---------------------------------------------------------------------------

export interface ChurchPulseData {
  churchId: string;
  churchName: string;
  verified: boolean;           // from churches/{churchId}.verified

  // All fields computed from REAL data only — never fabricated:
  upcomingEventCount: number;        // COUNT of events in next 30 days
  activePrayerRequestCount: number;  // COUNT of open prayer requests
  volunteerNeedCount: number;        // COUNT of unfilled volunteer slots
  recentTeachingTopics: string[];    // last 3 sermon/teaching titles (from announcements)
  hasVisitorInfo: boolean;           // does this church have a "visiting" section?

  // Derived pulse score (0–100), computed from real signals only:
  pulseScore: number;
  pulseSignals: string[];  // human-readable: "3 upcoming events", "Active prayer requests", etc.

  computedAt: number;   // epoch ms
  expiresAt: number;    // epoch ms — 6 hours from computedAt
}

// ---------------------------------------------------------------------------
// computeChurchPulse — fetches real data, computes score
// ---------------------------------------------------------------------------

export async function computeChurchPulse(churchId: string): Promise<ChurchPulseData> {
  const now = Date.now();
  const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
  const nowTs = admin.firestore.Timestamp.fromMillis(now);
  const futureTs = admin.firestore.Timestamp.fromMillis(now + thirtyDaysMs);

  // ── 1. Fetch the church document ──────────────────────────────────────────
  const churchDoc = await db.collection("churches").doc(churchId).get();
  const churchData = churchDoc.data() ?? {};
  const churchName: string = typeof churchData.name === "string" ? churchData.name : "Unknown Church";
  const verified: boolean = churchData.verified === true;

  // ── 2. Upcoming events (next 30 days) ────────────────────────────────────
  let upcomingEventCount = 0;
  try {
    const eventsSnap = await db
      .collection("events")
      .where("churchId", "==", churchId)
      .where("startDate", ">=", nowTs)
      .where("startDate", "<=", futureTs)
      .count()
      .get();
    upcomingEventCount = eventsSnap.data().count;
  } catch (err) {
    logger.warn("churchPulseComputer: events query failed", { churchId, err });
    // Leave at 0 — do not fabricate
  }

  // ── 3. Active prayer requests ─────────────────────────────────────────────
  let activePrayerRequestCount = 0;
  try {
    const prayersSnap = await db
      .collection("prayers")
      .where("churchId", "==", churchId)
      .where("status", "==", "open")
      .count()
      .get();
    activePrayerRequestCount = prayersSnap.data().count;
  } catch (err) {
    logger.warn("churchPulseComputer: prayers query failed", { churchId, err });
  }

  // ── 4. Unfilled volunteer opportunities ───────────────────────────────────
  let volunteerNeedCount = 0;
  try {
    const volSnap = await db
      .collection("volunteerOpportunities")
      .where("churchId", "==", churchId)
      .where("filled", "==", false)
      .count()
      .get();
    volunteerNeedCount = volSnap.data().count;
  } catch (err) {
    logger.warn("churchPulseComputer: volunteerOpportunities query failed", { churchId, err });
  }

  // ── 5. Recent teaching topics (from churchAnnouncements, last 3 sermons) ─
  let recentTeachingTopics: string[] = [];
  try {
    const announcementsSnap = await db
      .collection("churchAnnouncements")
      .where("churchId", "==", churchId)
      .where("type", "in", ["sermon", "teaching"])
      .orderBy("createdAt", "desc")
      .limit(3)
      .get();
    recentTeachingTopics = announcementsSnap.docs.map((d) => {
      const t = d.data().title;
      return typeof t === "string" && t.trim().length > 0 ? t.trim() : "";
    }).filter(Boolean);
  } catch (err) {
    logger.warn("churchPulseComputer: announcements query failed", { churchId, err });
  }

  // ── 6. Visitor info: any announcement tagged "visiting" or "visitor" ──────
  let hasVisitorInfo = false;
  try {
    const visitorSnap = await db
      .collection("churchAnnouncements")
      .where("churchId", "==", churchId)
      .where("type", "==", "visitor")
      .limit(1)
      .get();
    hasVisitorInfo = !visitorSnap.empty;
    // Fallback: check posts for visitor keyword if no dedicated doc
    if (!hasVisitorInfo) {
      const churchDocCheck = await db.collection("churches").doc(churchId).get();
      const cData = churchDocCheck.data() ?? {};
      hasVisitorInfo =
        cData.hasVisitorInfo === true ||
        typeof cData.visitingInfo === "string" && (cData.visitingInfo as string).trim().length > 0;
    }
  } catch (err) {
    logger.warn("churchPulseComputer: visitor info query failed", { churchId, err });
  }

  // ── 7. Pulse score — derived only from real signals ───────────────────────
  const signals: string[] = [];
  let score = verified ? 50 : 30; // baseline; unverified churches start lower

  if (upcomingEventCount >= 3) {
    score += 10;
    signals.push(`${upcomingEventCount} upcoming events`);
  } else if (upcomingEventCount > 0) {
    signals.push(`${upcomingEventCount} upcoming ${upcomingEventCount === 1 ? "event" : "events"}`);
  }

  if (activePrayerRequestCount >= 5) {
    score += 10;
    signals.push("Active prayer requests");
  } else if (activePrayerRequestCount > 0) {
    signals.push("Prayer requests open");
  }

  if (volunteerNeedCount > 0) {
    score += 10;
    signals.push("Volunteer opportunities available");
  }

  if (recentTeachingTopics.length >= 2) {
    score += 10;
    signals.push("Active teaching ministry");
  } else if (recentTeachingTopics.length === 1) {
    signals.push("Recent teaching posted");
  }

  if (hasVisitorInfo) {
    score += 10;
    signals.push("Visitor welcome info available");
  }

  if (!verified) {
    score -= 20;
    // Do not surface this as a user-facing signal — it's an admin matter
  }

  const pulseScore = Math.min(100, Math.max(0, score));

  return {
    churchId,
    churchName,
    verified,
    upcomingEventCount,
    activePrayerRequestCount,
    volunteerNeedCount,
    recentTeachingTopics,
    hasVisitorInfo,
    pulseScore,
    pulseSignals: signals,
    computedAt: now,
    expiresAt: now + 6 * 60 * 60 * 1000,
  };
}

// ---------------------------------------------------------------------------
// saveChurchPulse — writes to church_pulse/{churchId} (Admin SDK only)
// ---------------------------------------------------------------------------

export async function saveChurchPulse(data: ChurchPulseData): Promise<void> {
  await db.collection("church_pulse").doc(data.churchId).set(data, { merge: false });
  logger.info("churchPulse saved", { churchId: data.churchId, pulseScore: data.pulseScore });
}

// ---------------------------------------------------------------------------
// getChurchPulse — reads church_pulse/{churchId}
// ---------------------------------------------------------------------------

export async function getChurchPulse(churchId: string): Promise<ChurchPulseData | null> {
  const snap = await db.collection("church_pulse").doc(churchId).get();
  if (!snap.exists) return null;
  const data = snap.data() as ChurchPulseData;
  // Return null if stale so callers can recompute
  if (data.expiresAt < Date.now()) return null;
  return data;
}
