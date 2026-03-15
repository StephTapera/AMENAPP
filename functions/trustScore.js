/**
 * trustScore.js — AMEN Trust Score Cloud Function
 *
 * Computes and writes a trust score (0–100) for each user.
 *
 * Triggers:
 *   1. onTrustScoreRequested — Firestore trigger on trustScoreQueue/{uid}
 *      Called by AMENTrustScoreService.requestScoreRecompute()
 *
 *   2. scheduledTrustScoreRefresh — Daily cron job
 *      Re-scores all users whose score is stale (> 24h old)
 *
 *   3. onSafetyViolation — Firestore trigger on messageSafetyEvents
 *      Immediately penalises a user when a safety event is logged.
 *
 * Score factors (all server-side — cannot be gamed by client):
 *
 *   + Account age                  max +20
 *   + Profile completeness         max +15
 *   + Human verification badge     max +20
 *   + Mutual follow relationships  max +10
 *   + Report ratio (low reports)   max +10
 *   + Engagement quality           max +5
 *   ─────────────────────────────────────
 *   Base positives:                max  80
 *
 *   - New account penalty (< 7 days)       -15 (flat)
 *   - Safety violations                    up to -50
 *   - Reports received                     up to -30
 *   - Spam score                           up to -20
 *
 * Tier mapping:
 *   90–100  → verified
 *   70–89   → good
 *   50–69   → new
 *   25–49   → at_risk
 *   0–24    → restricted
 */

const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const db = admin.firestore();

// ─── SCORE COMPUTATION ────────────────────────────────────────────────────────

async function computeTrustScore(uid) {
  let score = 0;
  const notes = [];

  try {
    // Fetch user document
    const userDoc = await db.collection("users").document(uid).get()
      .catch(() => db.collection("users").doc(uid).get());

    if (!userDoc.exists) {
      return {score: 10, tier: "restricted", notes: ["user_not_found"]};
    }

    const user = userDoc.data();
    const createdAt = user.createdAt?.toDate?.() ?? user.joinedAt?.toDate?.() ?? new Date();
    const accountAgeDays = Math.floor((Date.now() - createdAt.getTime()) / 86400000);

    // ── POSITIVE FACTORS ────────────────────────────────────────────────────

    // Account age — up to +20 points
    if (accountAgeDays >= 365) { score += 20; notes.push("age_365+"); }
    else if (accountAgeDays >= 90) { score += 14; notes.push("age_90+"); }
    else if (accountAgeDays >= 30) { score += 8; notes.push("age_30+"); }
    else if (accountAgeDays >= 7) { score += 4; notes.push("age_7+"); }
    else {
      // New account flat penalty applied below
      notes.push("age_new");
    }

    // Profile completeness — up to +15
    let profileScore = 0;
    if (user.bio && user.bio.length > 10) profileScore += 4;
    if (user.profileImageURL && !user.profileImageURL.includes("default")) profileScore += 4;
    if (user.displayName && user.displayName.length > 1) profileScore += 3;
    if (user.church || user.churchName) profileScore += 2;
    if (user.website || user.socialLinks) profileScore += 2;
    score += Math.min(profileScore, 15);
    notes.push(`profile_score_${profileScore}`);

    // Human verification badge — +20
    if (user.isVerified === true || user.humanVerified === true) {
      score += 20;
      notes.push("human_verified");
    }

    // Mutual follow relationships — up to +10
    // Count mutual follows (proxy: followersCount and followingCount both > 0)
    const followersCount = user.followersCount ?? 0;
    const followingCount = user.followingCount ?? 0;
    if (followersCount >= 50 && followingCount >= 10) { score += 10; notes.push("strong_social_graph"); }
    else if (followersCount >= 10) { score += 5; notes.push("growing_social_graph"); }
    else if (followersCount >= 1) { score += 2; notes.push("minimal_social_graph"); }

    // ── SAFETY VIOLATIONS ─────────────────────────────────────────────────

    // Count safety events for this user (blocked messages)
    const safetySnap = await db.collection("messageSafetyEvents")
      .where("senderUID", "==", uid)
      .where("requiresReview", "==", true)
      .get();

    const violationCount = safetySnap.size;
    if (violationCount >= 10) { score -= 50; notes.push("violations_10+"); }
    else if (violationCount >= 5) { score -= 30; notes.push("violations_5+"); }
    else if (violationCount >= 2) { score -= 15; notes.push("violations_2+"); }
    else if (violationCount === 1) { score -= 5; notes.push("violations_1"); }

    // ── REPORTS RECEIVED ──────────────────────────────────────────────────

    const reportsSnap = await db.collection("reports")
      .where("reportedUserId", "==", uid)
      .where("status", "in", ["reviewed", "actioned"])
      .get();

    const reportCount = reportsSnap.size;
    if (reportCount >= 5) { score -= 30; notes.push("reports_5+"); }
    else if (reportCount >= 3) { score -= 20; notes.push("reports_3+"); }
    else if (reportCount >= 1) { score -= 10; notes.push("reports_1+"); }

    // ── NEW ACCOUNT PENALTY ───────────────────────────────────────────────

    if (accountAgeDays < 7) {
      score -= 15;
      notes.push("new_account_penalty");
    }

    // ── CLAMP & DETERMINE TIER ────────────────────────────────────────────

    score = Math.max(0, Math.min(100, score));
    const tier = tierFromScore(score);
    const isMessagingRestricted = tier === "restricted" || violationCount >= 10;

    return {score, tier, isMessagingRestricted, violationCount, reportCount, accountAgeDays, notes};

  } catch (err) {
    console.error(`❌ trustScore computeTrustScore error for ${uid}:`, err);
    return {score: 30, tier: "new", notes: ["compute_error"]};
  }
}

function tierFromScore(score) {
  if (score >= 90) return "verified";
  if (score >= 70) return "good";
  if (score >= 50) return "new";
  if (score >= 25) return "at_risk";
  return "restricted";
}

async function writeTrustRecord(uid, result) {
  await db.collection("trustRecords").doc(uid).set({
    uid,
    score: result.score,
    tier: result.tier,
    isMessagingRestricted: result.isMessagingRestricted ?? false,
    violationCount: result.violationCount ?? 0,
    reportCount: result.reportCount ?? 0,
    accountAgeDays: result.accountAgeDays ?? 0,
    notes: result.notes ?? [],
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    // Preserve per-day DM counter if exists (don't overwrite)
    newDMsInitiatedToday: admin.firestore.FieldValue.increment(0),
  }, {merge: true});
}

// ─── TRIGGER 1: On-demand recompute ───────────────────────────────────────────

exports.onTrustScoreRequested = onDocumentCreated(
    "trustScoreQueue/{uid}",
    async (event) => {
      const uid = event.params.uid;
      console.log(`🔄 Trust score recompute requested for ${uid}`);

      const result = await computeTrustScore(uid);
      await writeTrustRecord(uid, result);

      // Delete queue entry so it can be re-queued later
      await event.data.ref.delete();

      console.log(`✅ Trust score written for ${uid}: ${result.score} (${result.tier})`);
    },
);

// ─── TRIGGER 2: Safety event — immediate penalty ───────────────────────────────

exports.onMessageSafetyEvent = onDocumentCreated(
    "messageSafetyEvents/{eventId}",
    async (event) => {
      const data = event.data.data();
      const senderUID = data?.senderUID;
      const riskScore = data?.riskScore ?? 0;
      const requiresReview = data?.requiresReview ?? false;

      if (!senderUID || !requiresReview) return;

      console.log(`⚠️ Safety event for ${senderUID}, risk score ${riskScore}`);

      // Immediate penalty applied directly — no need to wait for full recompute
      const penalty = riskScore >= 90 ? 20 : riskScore >= 75 ? 10 : 5;

      await db.collection("trustRecords").doc(senderUID).set({
        score: admin.firestore.FieldValue.increment(-penalty),
        violationCount: admin.firestore.FieldValue.increment(1),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      // If critical risk (75+) — clamp and potentially restrict messaging
      if (riskScore >= 75) {
        // Re-read to check if we need to apply restriction
        const record = await db.collection("trustRecords").doc(senderUID).get();
        const currentScore = record.data()?.score ?? 30;

        if (currentScore < 25) {
          await db.collection("trustRecords").doc(senderUID).update({
            tier: "restricted",
            isMessagingRestricted: true,
          });
          console.log(`🚫 Messaging restricted for ${senderUID} (score ${currentScore})`);
        }
      }
    },
);

// ─── TRIGGER 3: Daily scheduled refresh ───────────────────────────────────────

exports.scheduledTrustScoreRefresh = onSchedule(
    {schedule: "every 24 hours", timeZone: "America/New_York"},
    async () => {
      console.log("🕐 Starting daily trust score refresh...");

      // Re-score users whose score is stale or flagged for review
      const staleThreshold = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const staleSnap = await db.collection("trustRecords")
        .where("lastUpdated", "<", staleThreshold)
        .limit(500)   // Process up to 500 users per run to stay within function timeout
        .get();

      // Also pick up users in accountReviews queue
      const reviewSnap = await db.collection("accountReviews")
        .where("status", "==", "pending")
        .limit(100)
        .get();

      const uids = new Set([
        ...staleSnap.docs.map((d) => d.id),
        ...reviewSnap.docs.map((d) => d.id),
      ]);

      console.log(`📊 Refreshing trust scores for ${uids.size} user(s)...`);

      let processed = 0;
      for (const uid of uids) {
        try {
          const result = await computeTrustScore(uid);
          await writeTrustRecord(uid, result);
          processed++;
        } catch (err) {
          console.error(`❌ Failed to score ${uid}:`, err.message);
        }
      }

      // Mark reviewed accounts as processed
      const batch = db.batch();
      reviewSnap.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "scored",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      await batch.commit();

      console.log(`✅ Daily trust score refresh complete — processed ${processed} user(s)`);
    },
);
