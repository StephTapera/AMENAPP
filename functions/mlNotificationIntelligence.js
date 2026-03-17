/**
 * ML Notification Intelligence + Infrastructure Functions
 *
 * Optimal send time, storm suppression, churn prediction,
 * feed re-ranking, predictive cache warming, SLO monitoring,
 * cost optimization audit.
 */

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall } = require("firebase-functions/v2/https");
const { onValueWritten } = require("firebase-functions/v2/database");
const {
  hfInference, pineconeQuery, logFunction,
  checkRateLimit, sleep,
} = require("./mlClients");

const db = admin.firestore();
let _rtdb = null;
const getRtdb = () => {
  if (!_rtdb) _rtdb = admin.database("https://amen-5e359-default-rtdb.firebaseio.com");
  return _rtdb;
};

// ═══════════════════════════════════════════
// optimizeNotificationSendTime — Called before any send
// ═══════════════════════════════════════════

async function optimizeNotificationSendTime(userId, notificationType, urgencyLevel) {
  // Critical = send immediately
  if (urgencyLevel === "critical") return { sendNow: true };

  try {
    // Fetch user's optimal windows
    const windowDoc = await db.collection("users").doc(userId)
      .collection("ml")
      .doc("notificationOptimalWindows")
      .get();

    const now = new Date();
    const currentHour = now.getUTCHours();
    const currentDay = now.getUTCDay();

    // Check unread count
    const unreadSnap = await db.collection("users").doc(userId)
      .collection("notifications")
      .where("read", "==", false)
      .count()
      .get();
    const unreadCount = unreadSnap.data().count || 0;
    if (unreadCount >= 3) {
      return { sendNow: false, reason: "too_many_unread", delayMinutes: 60 };
    }

    if (windowDoc.exists) {
      const windows = windowDoc.data()?.hourDayMatrix || {};
      const key = `${currentDay}_${currentHour}`;
      const openRate = windows[key] || 0.5;

      // Find next optimal window within 4 hours
      if (openRate < 0.3) {
        for (let offset = 1; offset <= 4; offset++) {
          const futureHour = (currentHour + offset) % 24;
          const futureKey = `${currentDay}_${futureHour}`;
          const futureRate = windows[futureKey] || 0.5;
          if (futureRate >= 0.4) {
            return { sendNow: false, delayMinutes: offset * 60, optimalHour: futureHour };
          }
        }
      }
    }

    // Check predicted sleep window (11pm - 6am user local)
    if (currentHour >= 23 || currentHour < 6) {
      return { sendNow: false, reason: "predicted_sleep", delayMinutes: Math.max(1, (6 - currentHour + 24) % 24 * 60) };
    }

    return { sendNow: true };
  } catch (err) {
    console.error(`[NotifOptimize] Error:`, err.message);
    return { sendNow: true }; // Fail open
  }
}

// ═══════════════════════════════════════════
// suppressNotificationStorm — Called before every FCM send
// ═══════════════════════════════════════════

async function suppressNotificationStorm(userId, notificationType) {
  // Always exempt critical types
  const exemptTypes = ["crisis_alert", "direct_message", "prayer_response"];
  if (exemptTypes.includes(notificationType)) return { suppress: false };

  try {
    const key = `notifThrottle/${userId}`;
    const ref = getRtdb().ref(key);
    const snap = await ref.get();
    const data = snap.val() || { count: 0, windowStart: 0 };

    const now = Date.now();
    const oneHourMs = 3600000;

    if (now - data.windowStart > oneHourMs) {
      // Reset window
      await ref.set({ count: 1, windowStart: now });
      return { suppress: false };
    }

    if (data.count >= 4) {
      // Suppress — batch into digest
      await ref.update({ count: data.count + 1 });
      return {
        suppress: true,
        reason: "storm_suppression",
        pendingCount: data.count + 1,
      };
    }

    await ref.update({ count: data.count + 1 });
    return { suppress: false };
  } catch (err) {
    return { suppress: false }; // Fail open
  }
}

// ═══════════════════════════════════════════
// predictNotificationChurn — Weekly
// ═══════════════════════════════════════════

const predictNotificationChurn = onSchedule(
  { schedule: "0 7 * * 1", region: "us-central1", timeoutSeconds: 300 },
  async () => {
    const startMs = Date.now();
    const fourteenDaysAgo = new Date(Date.now() - 14 * 86400000);

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
      .select("lastActiveAt")
      .limit(500)
      .get();

    let reduced = 0;
    let restored = 0;

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      try {
        // Calculate notification open rate
        const notifications = await db.collection("users").doc(uid)
          .collection("notifications")
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
          .limit(100)
          .get();

        if (notifications.docs.length < 5) continue;

        const readCount = notifications.docs.filter((d) => d.data().read === true).length;
        const openRate = readCount / notifications.docs.length;

        // Fetch prior state
        const currentMode = (await db.collection("users").doc(uid).get())
          .data()?.ml?.notificationMode || "normal";

        if (openRate < 0.15) {
          // Reduce to max 2/day
          if (currentMode !== "minimal") {
            await db.collection("users").doc(uid).update({
              "ml.notificationMode": "digest_only",
              "ml.notificationChurnRisk": true,
              "ml.notificationOpenRate": openRate,
            });
            reduced++;
          }
        } else if (openRate > 0.30 && currentMode !== "normal") {
          // Restore normal
          await db.collection("users").doc(uid).update({
            "ml.notificationMode": "normal",
            "ml.notificationChurnRisk": false,
            "ml.notificationOpenRate": openRate,
          });
          restored++;
        }
      } catch (err) {
        // Skip
      }
    }

    logFunction("predictNotificationChurn", {
      durationMs: Date.now() - startMs,
      reduced,
      restored,
    });
  }
);

// ═══════════════════════════════════════════
// reRankFeedRealTime — HTTPS callable
// ═══════════════════════════════════════════

const reRankFeedRealTime = onCall(
  { region: "us-central1" },
  async (request) => {
    const { userId, currentFeedPostIds, sessionSignals } = request.data;
    if (!userId) throw new Error("userId required");

    const allowed = await checkRateLimit(userId, "reRankFeed", 5);
    if (!allowed) throw new Error("Rate limited");

    const startMs = Date.now();

    try {
      // Fetch user ML profile
      const userDoc = await db.collection("users").doc(userId).get();
      const ml = userDoc.data()?.ml || {};
      const fatigueScore = ml.fatigueScore || 0;

      // Fetch saturation topics
      const saturationRef = getRtdb().ref(`contentSaturation/${userId}`);
      const satSnap = await saturationRef.get();
      const saturationData = satSnap.val() || {};
      const now = Date.now();
      const saturatedTopics = Object.entries(saturationData)
        .filter(([_, data]) => data.count >= 5 && (now - data.lastSeen) < 3 * 3600000)
        .map(([topic]) => topic);

      // Fetch posts data
      const postIds = (currentFeedPostIds || []).slice(0, 50);
      if (postIds.length === 0) return { rankedPostIds: [] };

      // Score each post
      const scored = [];
      for (const postId of postIds) {
        try {
          const postDoc = await db.collection("posts").doc(postId).get();
          if (!postDoc.exists) continue;

          const post = postDoc.data();
          const postMl = post.ml || {};

          // Recency score (0-1)
          const ageHours = (Date.now() - (post.createdAt?.toDate?.()?.getTime() || Date.now())) / 3600000;
          const recencyScore = Math.max(0, 1 - ageHours / 168); // 1 week decay

          // Sentiment match (higher if matches user's usual engagement)
          const sentimentMatchScore = postMl.sentiment === "positive" ? 0.7 : 0.5;

          // Engagement strength
          const engagement = (post.amenCount || 0) + (post.commentCount || 0);
          const engagementScore = Math.min(1, engagement / 20);

          let compositeScore = (
            recencyScore * 0.20 +
            sentimentMatchScore * 0.15 +
            engagementScore * 0.25 +
            (postMl.authenticityScore || 0.5) * 0.20 +
            (postMl.viralityScore || 0) * 0.20
          );

          // Saturation penalty
          const postTopic = postMl.classification || "";
          if (saturatedTopics.includes(postTopic)) {
            compositeScore *= 0.3;
          }

          // Fatigue adjustment
          if (fatigueScore > 0.7) {
            // Only keep high sentiment match posts
            if (sentimentMatchScore < 0.6) compositeScore *= 0.5;
          }

          scored.push({ postId, score: compositeScore });
        } catch (e) {
          scored.push({ postId, score: 0.5 }); // Default score
        }
      }

      // Sort by score descending
      scored.sort((a, b) => b.score - a.score);

      // Fatigue: limit to top 10
      const finalPosts = fatigueScore > 0.7
        ? scored.slice(0, 10)
        : scored;

      logFunction("reRankFeedRealTime", {
        userId,
        durationMs: Date.now() - startMs,
        inputCount: postIds.length,
        outputCount: finalPosts.length,
        fatigueScore,
      });

      return { rankedPostIds: finalPosts.map((p) => p.postId) };
    } catch (err) {
      logFunction("reRankFeedRealTime", { userId, error: err.message, durationMs: Date.now() - startMs });
      return { rankedPostIds: currentFeedPostIds || [] };
    }
  }
);

// ═══════════════════════════════════════════
// runSLOAnomalyDetection — Every 5 minutes
// ═══════════════════════════════════════════

const runSLOAnomalyDetection = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1" },
  async () => {
    const startMs = Date.now();
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60000);

    try {
      // Check auth success rate
      const authAttempts = await db.collection("authLogs")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(fiveMinutesAgo))
        .count()
        .get();
      const authFailures = await db.collection("authLogs")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(fiveMinutesAgo))
        .where("success", "==", false)
        .count()
        .get();

      const totalAuth = authAttempts.data().count || 0;
      const failedAuth = authFailures.data().count || 0;
      const authSuccessRate = totalAuth > 0 ? (totalAuth - failedAuth) / totalAuth : 1;

      // Check Firestore errors
      const firestoreErrors = await db.collection("errorLogs")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(fiveMinutesAgo))
        .where("service", "==", "firestore")
        .count()
        .get();

      const metrics = {
        authSuccessRate,
        firestoreErrorCount: firestoreErrors.data().count || 0,
        checkedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Store metrics
      await db.collection("admin").doc("sloMetrics").set(metrics, { merge: true });

      // Check thresholds
      const breaches = [];
      if (authSuccessRate < 0.999 && totalAuth > 10) {
        breaches.push({ metric: "authSuccessRate", value: authSuccessRate, threshold: 0.999 });
      }

      if (breaches.length > 0) {
        // Check if consecutive breach (2 checks in a row)
        const lastCheck = await db.collection("admin").doc("sloLastBreach").get();
        const lastBreachTime = lastCheck.data()?.timestamp?.toDate?.()?.getTime() || 0;
        const isConsecutive = (Date.now() - lastBreachTime) < 10 * 60000;

        await db.collection("admin").doc("sloLastBreach").set({
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          breaches,
        });

        if (isConsecutive) {
          // Create incident
          await db.collection("admin").doc("incidents").collection("active").add({
            breaches,
            severity: "warning",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            status: "open",
          });
          console.error(`[SLO] Consecutive breach detected:`, JSON.stringify(breaches));
        }
      }
    } catch (err) {
      console.error(`[SLO] Monitoring error:`, err.message);
    }

    logFunction("runSLOAnomalyDetection", { durationMs: Date.now() - startMs });
  }
);

// ═══════════════════════════════════════════
// costOptimizationAudit — Weekly Monday 4am
// ═══════════════════════════════════════════

const costOptimizationAudit = onSchedule(
  { schedule: "0 4 * * 1", region: "us-central1" },
  async () => {
    const startMs = Date.now();
    const weekAgo = new Date(Date.now() - 7 * 86400000);

    try {
      // Count function invocations from logs
      const functionLogs = await db.collection("functionLogs")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(weekAgo))
        .limit(10000)
        .get();

      const functionCounts = {};
      const functionDurations = {};

      for (const doc of functionLogs.docs) {
        const data = doc.data();
        const fn = data.function || "unknown";
        functionCounts[fn] = (functionCounts[fn] || 0) + 1;
        if (!functionDurations[fn]) functionDurations[fn] = [];
        if (data.durationMs) functionDurations[fn].push(data.durationMs);
      }

      // Estimate costs
      const hfCallCount = (functionCounts["onPostCreatedML"] || 0) * 5; // 5 HF calls per post
      const pineconeOps = (functionCounts["onPostCreatedML"] || 0) * 2 + // upsert + query
        (functionCounts["matchIntercessors"] || 0) +
        (functionCounts["reRankFeedRealTime"] || 0);

      const estimatedCosts = {
        huggingFace: hfCallCount * 0.001, // ~$0.001 per inference
        pinecone: pineconeOps * 0.00008,  // ~$0.00008 per operation
        firestore: functionLogs.docs.length * 0.00006, // ~$0.06 per 1K reads
        functions: Object.values(functionCounts).reduce((a, b) => a + b, 0) * 0.0000004, // per invocation
      };

      const totalEstimated = Object.values(estimatedCosts).reduce((a, b) => a + b, 0);

      // Find optimization opportunities
      const topOptimizations = [];

      // Check for duplicate calls
      if (hfCallCount > 1000) {
        topOptimizations.push({
          area: "Hugging Face",
          suggestion: "Consider batching embeddings for bulk operations",
          projectedSavings: hfCallCount * 0.0003,
        });
      }

      // Check for expensive long-running functions
      for (const [fn, durations] of Object.entries(functionDurations)) {
        const avg = durations.reduce((a, b) => a + b, 0) / durations.length;
        if (avg > 5000 && durations.length > 100) {
          topOptimizations.push({
            area: fn,
            suggestion: `Average ${Math.round(avg)}ms — consider caching or optimization`,
            projectedSavings: durations.length * 0.0001,
          });
        }
      }

      const weekId = new Date().toISOString().split("T")[0];
      await db.collection("admin").doc("costReports").collection("weekly").doc(weekId).set({
        weekId,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        totalEstimatedCost: totalEstimated,
        breakdown: estimatedCosts,
        functionInvocations: functionCounts,
        topOptimizations,
        projectedMonthlyCost: totalEstimated * 4.3,
      });

      logFunction("costOptimizationAudit", {
        durationMs: Date.now() - startMs,
        totalEstimated,
      });
    } catch (err) {
      logFunction("costOptimizationAudit", { error: err.message, durationMs: Date.now() - startMs });
    }
  }
);

// ═══════════════════════════════════════════
// runAgeSignalDetection — Weekly
// ═══════════════════════════════════════════

const runAgeSignalDetection = onSchedule(
  { schedule: "0 6 * * 3", region: "us-central1", timeoutSeconds: 300 },
  async () => {
    const startMs = Date.now();
    let flagged = 0;

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 14 * 86400000)
      ))
      .select("lastActiveAt", "dateOfBirth")
      .limit(500)
      .get();

    for (const userDoc of users.docs) {
      const uid = userDoc.id;
      const userData = userDoc.data();

      // Skip if age is already verified
      if (userData.ageVerified) continue;

      try {
        const posts = await db.collection("posts")
          .where("authorId", "==", uid)
          .orderBy("createdAt", "desc")
          .limit(30)
          .get();

        if (posts.docs.length < 5) continue;

        // Analyze posting times
        const hours = posts.docs.map((d) => {
          const date = d.data().createdAt?.toDate?.();
          return date ? date.getUTCHours() : 12;
        });

        // School hours activity (8am-3pm weekdays)
        const schoolHourPosts = posts.docs.filter((d) => {
          const date = d.data().createdAt?.toDate?.();
          if (!date) return false;
          const hour = date.getHours();
          const day = date.getDay();
          return day >= 1 && day <= 5 && hour >= 8 && hour <= 15;
        });
        const schoolHourRatio = schoolHourPosts.length / posts.docs.length;

        // Early bedtime signal (no posts after 10pm)
        const lateNightPosts = hours.filter((h) => h >= 22 || h <= 5).length;
        const earlyBedtime = lateNightPosts === 0 && posts.docs.length >= 10;

        // Language complexity (simple vocabulary)
        const allContent = posts.docs.map((d) => d.data().content || "").join(" ");
        const words = allContent.split(/\s+/);
        const avgWordLength = words.length > 0
          ? words.reduce((sum, w) => sum + w.length, 0) / words.length
          : 5;
        const simpleVocab = avgWordLength < 4;

        // Score
        let confidence = 0;
        if (schoolHourRatio > 0.5) confidence += 0.3;
        if (earlyBedtime) confidence += 0.2;
        if (simpleVocab) confidence += 0.3;

        if (confidence >= 0.6) {
          await db.collection("users").doc(uid).update({
            "securityFlags.possibleMinor": true,
            "securityFlags.minorConfidence": confidence,
            "securityFlags.flaggedAt": admin.firestore.FieldValue.serverTimestamp(),
          });

          await db.collection("admin").doc("trustSafety")
            .collection("minorFlags")
            .add({
              userId: uid,
              confidence,
              signals: {
                schoolHourRatio,
                earlyBedtime,
                avgWordLength,
              },
              detectedAt: admin.firestore.FieldValue.serverTimestamp(),
              status: "pending_review",
            });

          flagged++;
        }
      } catch (err) {
        // Skip user
      }
    }

    logFunction("runAgeSignalDetection", {
      durationMs: Date.now() - startMs,
      flagged,
    });
  }
);

module.exports = {
  optimizeNotificationSendTime,
  suppressNotificationStorm,
  predictNotificationChurn,
  reRankFeedRealTime,
  runSLOAnomalyDetection,
  costOptimizationAudit,
  runAgeSignalDetection,
};
