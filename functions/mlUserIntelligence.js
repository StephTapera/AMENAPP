/**
 * ML User Intelligence Functions
 *
 * Passive interest graph, social fatigue detection,
 * creation propensity, session intent classification,
 * spiritual health scoring.
 */

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall } = require("firebase-functions/v2/https");
const {
  hfInference, pineconeUpsert, pineconeQuery,
  logFunction, checkRateLimit, sleep,
} = require("./mlClients");

const db = admin.firestore();

// ═══════════════════════════════════════════
// buildPassiveInterestGraph — Nightly 2am UTC
// ═══════════════════════════════════════════

const buildPassiveInterestGraph = onSchedule(
  { schedule: "0 2 * * *", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);

    // Fetch active users (posted or logged in within 30 days)
    const activeUsers = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .select("lastActiveAt")
      .limit(500)
      .get();

    let processed = 0;

    for (const userDoc of activeUsers.docs) {
      const uid = userDoc.id;

      try {
        // Collect ghost signals
        const signals = [];

        // 1. Drafts never posted
        const drafts = await db.collection("users").doc(uid)
          .collection("drafts")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .limit(20)
          .get();
        for (const d of drafts.docs) {
          const text = d.data().content || "";
          if (text.length > 20) signals.push({ text, weight: 0.9, type: "draft" });
        }

        // 2. Profile visits without follow
        const visits = await db.collection("users").doc(uid)
          .collection("profileVisits")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .where("didFollow", "==", false)
          .limit(30)
          .get();
        for (const v of visits.docs) {
          const bio = v.data().visitedUserBio || "";
          if (bio.length > 10) signals.push({ text: bio, weight: 0.5, type: "profileVisit" });
        }

        // 3. Searches without engagement
        const searches = await db.collection("users").doc(uid)
          .collection("searchHistory")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .where("clickedResults", "==", 0)
          .limit(20)
          .get();
        for (const s of searches.docs) {
          const query = s.data().query || "";
          if (query.length > 3) signals.push({ text: query, weight: 0.4, type: "search" });
        }

        if (signals.length === 0) continue;

        // Generate embeddings for top signals (batch to save API calls)
        const topSignals = signals.slice(0, 10);
        const texts = topSignals.map((s) => s.text);
        const embeddings = await hfInference(
          "sentence-transformers/all-MiniLM-L6-v2",
          texts
        );

        if (!embeddings || !Array.isArray(embeddings)) continue;

        // Weighted average of embeddings
        const dim = embeddings[0]?.length || 384;
        const avgVector = new Array(dim).fill(0);
        let totalWeight = 0;

        for (let i = 0; i < embeddings.length && i < topSignals.length; i++) {
          const vec = embeddings[i];
          const weight = topSignals[i].weight;
          if (!Array.isArray(vec)) continue;
          for (let j = 0; j < dim; j++) {
            avgVector[j] += (vec[j] || 0) * weight;
          }
          totalWeight += weight;
        }

        if (totalWeight > 0) {
          for (let j = 0; j < dim; j++) {
            avgVector[j] /= totalWeight;
          }
        }

        // Upsert to Pinecone user-interest-embeddings
        await pineconeUpsert("user-interest-embeddings", [{
          id: uid,
          values: avgVector,
          metadata: {
            userId: uid,
            signalCount: signals.length,
            dominantType: getMostCommon(signals.map((s) => s.type)),
            updatedAt: new Date().toISOString(),
          },
        }]);

        // Store summary (never raw content)
        await db.collection("users").doc(uid).update({
          "ml.passiveInterestUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
          "ml.passiveSignalCount": signals.length,
        }).catch(() => {});

        processed++;
      } catch (err) {
        console.error(`[PassiveInterest] Error for user ${uid}:`, err.message);
      }

      // Throttle to avoid overwhelming HF API
      if (processed % 10 === 0) await sleep(2000);
    }

    logFunction("buildPassiveInterestGraph", {
      durationMs: Date.now() - startMs,
      usersProcessed: processed,
      totalActive: activeUsers.docs.length,
    });
  }
);

// ═══════════════════════════════════════════
// detectSocialFatigue — Daily 6am UTC
// ═══════════════════════════════════════════

const detectSocialFatigue = onSchedule(
  { schedule: "0 6 * * *", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    const sevenDaysAgo = new Date(Date.now() - 7 * 86400000);
    const fourteenDaysAgo = new Date(Date.now() - 14 * 86400000);

    const activeUsers = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
      .select("lastActiveAt")
      .limit(500)
      .get();

    let processed = 0;

    for (const userDoc of activeUsers.docs) {
      const uid = userDoc.id;

      try {
        // Fetch session data (last 14 days)
        const sessions = await db.collection("users").doc(uid)
          .collection("sessions")
          .where("startedAt", ">=", admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
          .orderBy("startedAt", "desc")
          .limit(100)
          .get();

        if (sessions.empty) continue;

        const allSessions = sessions.docs.map((d) => d.data());
        const recent7 = allSessions.filter((s) =>
          s.startedAt?.toDate?.() >= sevenDaysAgo
        );
        const prior7 = allSessions.filter((s) => {
          const date = s.startedAt?.toDate?.();
          return date < sevenDaysAgo && date >= fourteenDaysAgo;
        });

        // Feature: Session length trend
        const avgLengthRecent = recent7.length > 0
          ? recent7.reduce((sum, s) => sum + (s.durationSeconds || 0), 0) / recent7.length
          : 0;
        const avgLengthPrior = prior7.length > 0
          ? prior7.reduce((sum, s) => sum + (s.durationSeconds || 0), 0) / prior7.length
          : avgLengthRecent;
        const sessionLengthTrend = avgLengthPrior > 0
          ? (avgLengthRecent - avgLengthPrior) / avgLengthPrior
          : 0;

        // Feature: Session frequency trend
        const freqRecent = recent7.length / 7;
        const freqPrior = prior7.length / 7;
        const freqTrend = freqPrior > 0 ? (freqRecent - freqPrior) / freqPrior : 0;

        // Feature: Engagement ratio (simple proxy)
        const recentActions = recent7.reduce((sum, s) => sum + (s.actionsCount || 0), 0);
        const recentViews = recent7.reduce((sum, s) => sum + (s.viewsCount || 1), 0);
        const engagementRatio = recentViews > 0 ? recentActions / recentViews : 0;

        // Compute fatigue score (logistic-like combination)
        let fatigue = 0.3; // Base

        // Declining session length → more fatigue
        if (sessionLengthTrend < -0.2) fatigue += 0.2;
        else if (sessionLengthTrend < -0.1) fatigue += 0.1;

        // Declining frequency → more fatigue
        if (freqTrend < -0.3) fatigue += 0.25;
        else if (freqTrend < -0.15) fatigue += 0.1;

        // Low engagement ratio → more fatigue
        if (engagementRatio < 0.05) fatigue += 0.15;

        // No sessions in last 3 days → high fatigue
        const threeDaysAgo = new Date(Date.now() - 3 * 86400000);
        const recentSessions = recent7.filter((s) =>
          s.startedAt?.toDate?.() >= threeDaysAgo
        );
        if (recentSessions.length === 0) fatigue += 0.2;

        fatigue = Math.max(0, Math.min(1, fatigue));

        // Store fatigue score
        await db.collection("users").doc(uid).update({
          "ml.fatigueScore": fatigue,
          "ml.fatigueUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
        });

        // Actions by threshold
        if (fatigue >= 0.8) {
          // Pause non-critical notifications
          await db.collection("users").doc(uid).update({
            "ml.notificationMode": "minimal",
            "ml.takeBreakSuggested": true,
          });
          console.log(`[Fatigue] User ${uid}: CRITICAL fatigue ${fatigue.toFixed(2)} — pausing notifications`);
        } else if (fatigue >= 0.6) {
          await db.collection("users").doc(uid).update({
            "ml.notificationMode": "digest",
          });
        } else if (fatigue >= 0.4) {
          await db.collection("users").doc(uid).update({
            "ml.notificationMode": "reduced",
          });
        }

        processed++;
      } catch (err) {
        console.error(`[Fatigue] Error for user ${uid}:`, err.message);
      }
    }

    logFunction("detectSocialFatigue", {
      durationMs: Date.now() - startMs,
      usersProcessed: processed,
    });
  }
);

// ═══════════════════════════════════════════
// predictCreationPropensity — Every 6 hours
// ═══════════════════════════════════════════

const predictCreationPropensity = onSchedule(
  { schedule: "0 */6 * * *", region: "us-central1", timeoutSeconds: 300 },
  async () => {
    const startMs = Date.now();
    const sevenDaysAgo = new Date(Date.now() - 7 * 86400000);

    // Users who haven't posted in 7+ days
    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
      .select("lastActiveAt", "lastPostAt")
      .limit(500)
      .get();

    let nudged = 0;

    for (const userDoc of users.docs) {
      const uid = userDoc.id;
      const data = userDoc.data();
      const lastPost = data.lastPostAt?.toDate?.();

      // Skip users who posted recently
      if (lastPost && lastPost > sevenDaysAgo) continue;

      try {
        // Check draft activity (strong signal)
        const recentDrafts = await db.collection("users").doc(uid)
          .collection("drafts")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - 3 * 86400000)
          ))
          .limit(5)
          .get();

        let propensity = 0.3; // Base

        // Draft saves boost propensity
        propensity += Math.min(0.3, recentDrafts.docs.length * 0.1);

        // Days since last post
        if (lastPost) {
          const daysSince = (Date.now() - lastPost.getTime()) / 86400000;
          if (daysSince > 14) propensity += 0.1; // Long absence, returning users create
          else if (daysSince > 7) propensity += 0.15;
        }

        // Active engagement with others' content (they're inspired)
        const recentReactions = await db.collectionGroup("reactions")
          .where("userId", "==", uid)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - 3 * 86400000)
          ))
          .limit(20)
          .get();
        propensity += Math.min(0.2, recentReactions.docs.length * 0.02);

        propensity = Math.max(0, Math.min(1, propensity));

        if (propensity > 0.7) {
          await db.collection("users").doc(uid).update({
            "ml.creationNudgePending": true,
            "ml.creationPropensity": propensity,
          });
          nudged++;
        }
      } catch (err) {
        // Skip user on error
      }
    }

    logFunction("predictCreationPropensity", {
      durationMs: Date.now() - startMs,
      usersChecked: users.docs.length,
      nudgesSent: nudged,
    });
  }
);

// ═══════════════════════════════════════════
// computeSessionIntent — HTTPS callable
// ═══════════════════════════════════════════

const computeSessionIntent = onCall(
  { region: "us-central1" },
  async (request) => {
    const { userId, timeOfDay, dayOfWeek, lastSessionBehavior } = request.data;

    if (!userId) throw new Error("userId required");

    const allowed = await checkRateLimit(userId, "sessionIntent", 5);
    if (!allowed) throw new Error("Rate limited");

    const startMs = Date.now();

    // Simple rule-based intent classification
    // (Vertex AI endpoint would replace this in production)
    let intentClass = "Browse"; // Default
    const hour = timeOfDay || new Date().getHours();
    const day = dayOfWeek || new Date().getDay();
    const lastBehavior = lastSessionBehavior || {};

    // Morning → devotional/catchup intent
    if (hour >= 5 && hour <= 8) {
      intentClass = "CatchUp";
    }
    // Midday → quick browse
    else if (hour >= 11 && hour <= 13) {
      intentClass = "KillTime";
    }
    // Evening → deeper engagement
    else if (hour >= 19 && hour <= 22) {
      if (lastBehavior.draftStarted) intentClass = "Create";
      else intentClass = "Connect";
    }
    // Late night → light browsing
    else if (hour >= 23 || hour <= 4) {
      intentClass = "KillTime";
    }
    // Sunday → spiritual focus
    if (day === 0) {
      intentClass = "Connect";
    }

    // Override based on recent behavior
    if (lastBehavior.compositTrend === "creating") intentClass = "Create";
    if (lastBehavior.compositTrend === "messaging") intentClass = "Connect";

    // Feed composition by intent
    const feedComposition = {
      Browse: { discovery: 0.4, following: 0.4, trending: 0.2 },
      Connect: { following: 0.5, prayers: 0.3, discovery: 0.2 },
      CatchUp: { following: 0.8, discovery: 0.1, trending: 0.1 },
      KillTime: { trending: 0.4, discovery: 0.3, following: 0.3 },
      Create: { trending: 0.3, discovery: 0.4, prompts: 0.3 },
    }[intentClass] || { following: 0.5, discovery: 0.3, trending: 0.2 };

    // Store session intent
    await db.collection("users").doc(userId).update({
      "sessionState.currentIntent": intentClass,
      "sessionState.intentUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});

    logFunction("computeSessionIntent", {
      userId,
      intentClass,
      durationMs: Date.now() - startMs,
    });

    return { intentClass, feedComposition };
  }
);

// ═══════════════════════════════════════════
// updateSpiritualHealthScore — Weekly Sunday midnight
// ═══════════════════════════════════════════

const updateSpiritualHealthScore = onSchedule(
  { schedule: "0 0 * * 0", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .select("lastActiveAt")
      .limit(500)
      .get();

    let processed = 0;

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      try {
        // Prayer activity
        const prayers = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("category", "==", "prayer")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .count()
          .get();
        const prayerCount = prayers.data().count || 0;
        const prayerActivity = Math.min(100, prayerCount * 10);

        // Testimony sharing
        const testimonies = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("category", "==", "testimonies")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .count()
          .get();
        const testimonyCount = testimonies.data().count || 0;
        const testimonySharing = Math.min(100, testimonyCount * 20);

        // Community investment (comments on others' posts)
        const comments = await db.collectionGroup("comments")
          .where("authorId", "==", uid)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .count()
          .get();
        const commentCount = comments.data().count || 0;
        const communityInvestment = Math.min(100, commentCount * 5);

        // Scripture engagement (posts with scripture tags)
        const scripturePosts = await db.collection("posts")
          .where("authorId", "==", uid)
          .where("verseReference", "!=", null)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .count()
          .get();
        const scriptureCount = scripturePosts.data().count || 0;
        const scriptureEngagement = Math.min(100, scriptureCount * 15);

        // Consistency (days active in last 30)
        const sessions = await db.collection("users").doc(uid)
          .collection("sessions")
          .where("startedAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .limit(100)
          .get();
        const uniqueDays = new Set(
          sessions.docs.map((d) => {
            const date = d.data().startedAt?.toDate?.();
            return date ? date.toISOString().split("T")[0] : null;
          }).filter(Boolean)
        );
        const consistencyScore = Math.min(100, (uniqueDays.size / 30) * 100);

        // Weighted average
        const overall = Math.round(
          prayerActivity * 0.25 +
          scriptureEngagement * 0.20 +
          communityInvestment * 0.20 +
          testimonySharing * 0.15 +
          consistencyScore * 0.20
        );

        // Determine trend (compare to last week)
        const weekId = new Date().toISOString().split("T")[0];
        let trendDirection = "stable";
        try {
          const prevWeeks = await db.collection("users").doc(uid)
            .collection("spiritualHealth")
            .orderBy("weekTimestamp", "desc")
            .limit(1)
            .get();
          if (!prevWeeks.empty) {
            const prevScore = prevWeeks.docs[0].data().overallScore || 0;
            if (overall > prevScore + 5) trendDirection = "growing";
            else if (overall < prevScore - 5) trendDirection = "declining";
          }
        } catch (e) { /* first week */ }

        // Store — PRIVATE to the user only
        await db.collection("users").doc(uid)
          .collection("spiritualHealth")
          .doc(weekId)
          .set({
            weekTimestamp: admin.firestore.FieldValue.serverTimestamp(),
            overallScore: overall,
            prayerActivity,
            scriptureEngagement,
            communityInvestment,
            testimonySharing,
            consistencyScore,
            trendDirection,
          });

        processed++;
      } catch (err) {
        console.error(`[SpiritualHealth] Error for user ${uid}:`, err.message);
      }
    }

    logFunction("updateSpiritualHealthScore", {
      durationMs: Date.now() - startMs,
      usersProcessed: processed,
    });
  }
);

// ═══════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════

function getMostCommon(arr) {
  const counts = {};
  for (const item of arr) {
    counts[item] = (counts[item] || 0) + 1;
  }
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] || "unknown";
}

module.exports = {
  buildPassiveInterestGraph,
  detectSocialFatigue,
  predictCreationPropensity,
  computeSessionIntent,
  updateSpiritualHealthScore,
};
