// TODO(gate: HUMAN-MACHINE) — MIGRATE_TO_V2: still using Gen1 runWith() pattern; migration requires re-deploy + smoke-test
// moderationSweep.js — v1 Cloud Function (avoids Cloud Run quota)
// Scheduled every 4h: finds aged moderation queue items and alerts admins.
// Items pending >24h for normal content, or >2h for critical categories
// (csam, grooming, trafficking) are escalated to criticalReviewQueue.

const functions = require("firebase-functions/v1");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const CRITICAL_CATEGORIES = ["csam", "grooming", "trafficking", "child_safety", "minor_safety"];
const NORMAL_SLA_HOURS = 24;
const CRITICAL_SLA_HOURS = 2;

exports.moderationSweep = functions.region("us-central1").pubsub
  .schedule("every 4 hours")
  .onRun(async (_context) => {
    const db = getFirestore();

    try {
      const now = Date.now();
      const normalThreshold = new Date(now - NORMAL_SLA_HOURS * 3600 * 1000);

      const agedSnap = await db.collection("moderationQueue")
        .where("status", "==", "pending")
        .where("createdAt", "<", normalThreshold)
        .limit(100)
        .get();

      let count = 0;
      let criticalCount = 0;

      for (const doc of agedSnap.docs) {
        count++;
        const data = doc.data();
        const contentRef = data.contentRef || data.postRef || null;
        const categories = Array.isArray(data.categories) ? data.categories : [];
        const createdAt = data.createdAt?.toMillis ? data.createdAt.toMillis() : now;
        const ageMs = now - createdAt;

        const isCritical = categories.some((cat) =>
          CRITICAL_CATEGORIES.includes(String(cat).toLowerCase())
        );

        if (isCritical && ageMs > CRITICAL_SLA_HOURS * 3600 * 1000) {
          await db.collection("criticalReviewQueue").doc(doc.id).set({
            ...data,
            escalatedAt: FieldValue.serverTimestamp(),
            escalationReason: "sla_breach_critical",
          });

          await db.collection("moderatorAlerts").add({
            type: "critical_review_needed",
            contentRef,
            urgency: "critical",
            createdAt: FieldValue.serverTimestamp(),
            read: false,
          });

          criticalCount++;
        } else if (!isCritical) {
          await db.collection("moderatorAlerts").add({
            type: "pending_review_aged",
            contentRef,
            createdAt: FieldValue.serverTimestamp(),
            ageHours: Math.floor(ageMs / 3600000),
            read: false,
          });
        }
      }

      console.log(`[moderationSweep] Checked ${count} aged items, escalated ${criticalCount} critical`);
    } catch (err) {
      console.error("[moderationSweep] Error during sweep:", err);
    }
  });
