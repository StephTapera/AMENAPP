// signalCascade.ts — Berean Island context-cache revocation cascade + 30-day TTL (Wave 0)
//
// Two responsibilities:
//   1. TTL sweep: delete bereanContextCache docs where expiresAt < now (30-day TTL).
//   2. Revocation cascade: when a signal is revoked (granted=false), delete every
//      bereanContextCache doc whose derivedFrom[] includes that signal within 24h.
//
// Mirrors the account-deletion cascade architecture pattern.

import * as functions from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp, FieldPath } from "firebase-admin/firestore";

const db = getFirestore();

// ── TTL sweep: runs daily at 03:00 UTC ────────────────────────────────────────

export const bereanContextCacheTTLSweep = functions.onSchedule(
  { schedule: "0 3 * * *", timeZone: "UTC" },
  async () => {
    logger.info("[BI-W0] bereanContextCacheTTLSweep starting");

    const now = Timestamp.now();
    let totalDeleted = 0;
    let errorCount = 0;

    // Firestore collection-group query across all users' bereanContextCache
    const expiredQuery = db
      .collectionGroup("bereanContextCache")
      .where("expiresAt", "<=", now)
      .limit(400);  // batch cap to stay under write limit

    const snapshot = await expiredQuery.get();

    if (snapshot.empty) {
      logger.info("[BI-W0] TTL sweep: no expired docs");
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
      totalDeleted++;
    }

    try {
      await batch.commit();
      logger.info("[BI-W0] TTL sweep: deleted expired docs", { totalDeleted });
    } catch (err) {
      errorCount++;
      logger.error("[BI-W0] TTL sweep batch commit failed", { error: err });
    }

    logger.info("[BI-W0] bereanContextCacheTTLSweep done", { totalDeleted, errorCount });
  }
);

// ── Revocation cascade: Firestore trigger on bereanSignals write ───────────────
// When a signal is set to granted=false, delete every cache doc derivedFrom it.

import * as firestoreTriggers from "firebase-functions/v2/firestore";

export const bereanSignalRevocationCascade = firestoreTriggers.onDocumentWritten(
  "users/{uid}/bereanSignals/{signal}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    // Only act on explicit revocations: granted changed to false
    if (!before || before.granted === false) return;
    if (!after || after.granted !== false) return;

    const uid = event.params.uid;
    const revokedSignal = event.params.signal;

    logger.info("[BI-W0] signal revoked — cascading cache delete", { uid, revokedSignal });

    // Find all cache docs that were derived from the revoked signal
    const cacheRef = db.collection(`users/${uid}/bereanContextCache`);
    const derivedQuery = cacheRef.where(
      new FieldPath("derivedFrom"),
      "array-contains",
      revokedSignal
    );

    const snapshot = await derivedQuery.get();
    if (snapshot.empty) {
      logger.info("[BI-W0] revocation cascade: no cache docs to delete", { uid, revokedSignal });
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    logger.info("[BI-W0] revocation cascade complete", {
      uid,
      revokedSignal,
      deletedCount: snapshot.size,
    });
  }
);
