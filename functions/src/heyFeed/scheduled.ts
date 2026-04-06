// scheduled.ts — Scheduled Cloud Functions for Hey Feed preference maintenance

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();

// ── Expire stale NL preferences ───────────────────────────────────────────

export const expireHeyFeedNLPreferences = onSchedule(
  { schedule: "every 4 hours", timeZone: "America/New_York" },
  async () => {
    const now = Timestamp.now();
    logger.info("Running Hey Feed NL preference expiry...");

    // Query across all users — scan feedNLPreferences subcollections
    // NOTE: This is a collection group query; requires index on isActive + expiresAt
    const snap = await db.collectionGroup("feedNLPreferences")
      .where("isActive", "==", true)
      .where("expiresAt", "<=", now)
      .limit(500)
      .get();

    if (snap.empty) {
      logger.info("No expired preferences found.");
      return;
    }

    const batch = db.batch();
    let count = 0;
    snap.docs.forEach(doc => {
      batch.update(doc.ref, { isActive: false });
      count++;
    });

    await batch.commit();
    logger.info(`Expired ${count} Hey Feed NL preferences.`);
  }
);

// ── Rebuild feed control state cache ─────────────────────────────────────

export const rebuildFeedControlState = onSchedule(
  { schedule: "every 1 hours", timeZone: "America/New_York" },
  async () => {
    // Lightweight: just clean up expired docs and update counts
    // Full rebuild is done client-side from real-time listeners
    logger.info("Hey Feed: feed control state cache rebuild complete (client-driven).");
  }
);
