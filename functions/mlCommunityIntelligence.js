/**
 * ML Community & Pastoral Intelligence + Safety Functions
 *
 * Congregation health reports, coordinated behavior detection,
 * linguistic fingerprinting, grief/crisis pre-incident detection,
 * harassment zero-tolerance, theological drift scoring.
 */

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const {
  hfInference, logFunction, sleep, cosineSimilarity,
} = require("./mlClients");

const db = admin.firestore();
let _rtdb = null;
const getRtdb = () => {
  if (!_rtdb) _rtdb = admin.database("https://amen-5e359-default-rtdb.firebaseio.com");
  return _rtdb;
};

// ═══════════════════════════════════════════
// generateCongregationHealthReport — Weekly Sunday 3am
// ═══════════════════════════════════════════

const generateCongregationHealthReport = onSchedule(
  { schedule: "0 3 * * 0", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    const weekAgo = new Date(Date.now() - 7 * 86400000);
    const threeWeeksAgo = new Date(Date.now() - 21 * 86400000);

    const communities = await db.collection("communities")
      .where("isActive", "==", true)
      .limit(100)
      .get();

    for (const communityDoc of communities.docs) {
      const communityId = communityDoc.id;

      try {
        // 1. Aggregate sentiment — anonymous
        const posts = await db.collection("posts")
          .where("communityId", "==", communityId)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(weekAgo))
          .limit(200)
          .get();

        let sentimentSum = 0;
        let sentimentCount = 0;
        const topicCounts = {};

        for (const p of posts.docs) {
          const ml = p.data().ml || {};
          if (ml.sentimentScore) {
            sentimentSum += ml.sentiment === "positive" ? ml.sentimentScore : -ml.sentimentScore;
            sentimentCount++;
          }
          if (ml.classification) {
            topicCounts[ml.classification] = (topicCounts[ml.classification] || 0) + 1;
          }
        }

        const avgSentiment = sentimentCount > 0 ? sentimentSum / sentimentCount : 0;

        // Compare to prior 3 weeks for trend
        const priorPosts = await db.collection("posts")
          .where("communityId", "==", communityId)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(threeWeeksAgo))
          .where("createdAt", "<", admin.firestore.Timestamp.fromDate(weekAgo))
          .limit(500)
          .get();

        let priorSentimentSum = 0;
        let priorSentimentCount = 0;
        for (const p of priorPosts.docs) {
          const ml = p.data().ml || {};
          if (ml.sentimentScore) {
            priorSentimentSum += ml.sentiment === "positive" ? ml.sentimentScore : -ml.sentimentScore;
            priorSentimentCount++;
          }
        }
        const priorAvg = priorSentimentCount > 0 ? priorSentimentSum / priorSentimentCount : 0;
        const sentimentTrend = avgSentiment > priorAvg + 0.05 ? "improving"
          : avgSentiment < priorAvg - 0.05 ? "declining" : "stable";

        // 2. Engagement health
        const totalMembers = communityDoc.data().memberCount || 1;
        const uniqueAuthors = new Set(posts.docs.map((p) => p.data().authorId)).size;
        const weeklyActiveRatio = uniqueAuthors / totalMembers;

        // 3. Prayer health
        const prayerPosts = posts.docs.filter((p) => p.data().category === "prayer");
        const prayerResponseRate = prayerPosts.length > 0
          ? prayerPosts.filter((p) => (p.data().amenCount || 0) > 0).length / prayerPosts.length
          : 0;

        // Unanswered prayers older than 7 days
        const unansweredPrayers = await db.collection("posts")
          .where("communityId", "==", communityId)
          .where("category", "==", "prayer")
          .where("amenCount", "==", 0)
          .where("createdAt", "<=", admin.firestore.Timestamp.fromDate(weekAgo))
          .limit(20)
          .get();

        // 4. Crisis signals — anonymous count only
        const crisisAlerts = await db.collection("pastoralAlerts")
          .where("communityId", "==", communityId)
          .where("detectedAt", ">=", admin.firestore.Timestamp.fromDate(weekAgo))
          .count()
          .get();

        // Top topics
        const topTopics = Object.entries(topicCounts)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 5)
          .map(([topic, count]) => ({ topic, count }));

        // 5. Write report
        const weekId = new Date().toISOString().split("T")[0];
        await db.collection("communities").doc(communityId)
          .collection("insights")
          .doc(`weekly_${weekId}`)
          .set({
            weekId,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            sentiment: {
              average: avgSentiment,
              trend: sentimentTrend,
              postCount: sentimentCount,
            },
            engagement: {
              weeklyActiveUsers: uniqueAuthors,
              totalMembers,
              activeRatio: weeklyActiveRatio,
              totalPosts: posts.docs.length,
            },
            prayer: {
              totalRequests: prayerPosts.length,
              responseRate: prayerResponseRate,
              unansweredCount: unansweredPrayers.docs.length,
            },
            crisis: {
              alertCount: crisisAlerts.data().count || 0,
            },
            topTopics,
          });
      } catch (err) {
        console.error(`[CongregationHealth] Error for ${communityId}:`, err.message);
      }
    }

    logFunction("generateCongregationHealthReport", { durationMs: Date.now() - startMs });
  }
);

// ═══════════════════════════════════════════
// detectCoordinatedBehavior — Daily 1am
// ═══════════════════════════════════════════

const detectCoordinatedBehavior = onSchedule(
  { schedule: "0 1 * * *", region: "us-central1", timeoutSeconds: 300 },
  async () => {
    const startMs = Date.now();
    const dayAgo = new Date(Date.now() - 86400000);

    // Fetch recent interactions (reactions within same minute on same post)
    const recentReactions = await db.collectionGroup("reactions")
      .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(dayAgo))
      .orderBy("createdAt", "desc")
      .limit(5000)
      .get();

    // Group by post + minute window
    const timeWindows = {};
    for (const doc of recentReactions.docs) {
      const data = doc.data();
      const postId = doc.ref.parent.parent?.id || "unknown";
      const timestamp = data.createdAt?.toDate?.();
      if (!timestamp) continue;

      // 60-second window key
      const windowKey = `${postId}_${Math.floor(timestamp.getTime() / 60000)}`;
      if (!timeWindows[windowKey]) timeWindows[windowKey] = [];
      timeWindows[windowKey].push({
        userId: data.userId,
        timestamp: timestamp.getTime(),
      });
    }

    // Detect suspicious clusters: 3+ unique accounts in same 60s window
    let flagged = 0;
    for (const [windowKey, actions] of Object.entries(timeWindows)) {
      const uniqueUsers = new Set(actions.map((a) => a.userId));
      if (uniqueUsers.size >= 3) {
        // Check timing precision (within 5 seconds of each other)
        const timestamps = actions.map((a) => a.timestamp).sort();
        const spread = timestamps[timestamps.length - 1] - timestamps[0];

        if (spread < 10000) { // All within 10 seconds
          const confidence = Math.min(1.0, uniqueUsers.size / 5);

          if (confidence > 0.6) {
            const postId = windowKey.split("_")[0];
            await db.collection("admin").doc("trustSafety")
              .collection("flaggedClusters")
              .add({
                postId,
                userIds: [...uniqueUsers],
                actionCount: actions.length,
                timeSpreadMs: spread,
                confidence,
                detectedAt: admin.firestore.FieldValue.serverTimestamp(),
                status: "pending_review",
              });
            flagged++;
          }
        }
      }
    }

    logFunction("detectCoordinatedBehavior", {
      durationMs: Date.now() - startMs,
      windowsAnalyzed: Object.keys(timeWindows).length,
      flagged,
    });
  }
);

// ═══════════════════════════════════════════
// runLinguisticFingerprint — Weekly
// ═══════════════════════════════════════════

const runLinguisticFingerprint = onSchedule(
  { schedule: "0 5 * * 1", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();
    let flagged = 0;

    const users = await db.collection("users")
      .where("lastActiveAt", ">=", admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 14 * 86400000)
      ))
      .select("lastActiveAt")
      .limit(300)
      .get();

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      try {
        const posts = await db.collection("posts")
          .where("authorId", "==", uid)
          .orderBy("createdAt", "desc")
          .limit(50)
          .get();

        if (posts.docs.length < 10) continue;

        // Build style features
        const texts = posts.docs.map((d) => d.data().content || "").filter(Boolean);

        // Feature: average sentence length
        const sentenceLengths = texts.flatMap((t) =>
          t.split(/[.!?]+/).filter((s) => s.trim().length > 0).map((s) => s.trim().split(/\s+/).length)
        );
        const avgSentenceLength = sentenceLengths.length > 0
          ? sentenceLengths.reduce((a, b) => a + b, 0) / sentenceLengths.length
          : 0;

        // Feature: vocabulary diversity
        const allWords = texts.join(" ").toLowerCase().split(/\s+/);
        const uniqueWords = new Set(allWords);
        const vocabDiversity = allWords.length > 0 ? uniqueWords.size / allWords.length : 0;

        // Feature: emoji density
        const emojiRegex = /[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]/gu;
        const emojiCount = texts.join("").match(emojiRegex)?.length || 0;
        const emojiDensity = allWords.length > 0 ? emojiCount / allWords.length : 0;

        // Build style vector
        const styleVector = [avgSentenceLength / 30, vocabDiversity, emojiDensity * 10];

        // Compare to stored historical vector
        const prevStyle = await db.collection("users").doc(uid)
          .collection("securityData")
          .doc("linguisticFingerprint")
          .get();

        if (prevStyle.exists) {
          const prevVector = prevStyle.data()?.styleVector || [];
          if (prevVector.length === styleVector.length) {
            const similarity = cosineSimilarity(styleVector, prevVector);

            if (similarity < 0.6) {
              // Dramatic shift — flag for review
              await db.collection("users").doc(uid)
                .collection("securityFlags")
                .doc("styleShift")
                .set({
                  similarity,
                  currentVector: styleVector,
                  previousVector: prevVector,
                  detectedAt: admin.firestore.FieldValue.serverTimestamp(),
                  status: "pending_review",
                });
              flagged++;
              console.log(`[LinguisticFingerprint] Style shift for user ${uid}: similarity ${similarity.toFixed(3)}`);
            }
          }
        }

        // Update stored fingerprint
        await db.collection("users").doc(uid)
          .collection("securityData")
          .doc("linguisticFingerprint")
          .set({
            styleVector,
            avgSentenceLength,
            vocabDiversity,
            emojiDensity,
            sampleSize: texts.length,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      } catch (err) {
        console.error(`[LinguisticFingerprint] Error for user ${uid}:`, err.message);
      }
    }

    logFunction("runLinguisticFingerprint", {
      durationMs: Date.now() - startMs,
      usersAnalyzed: users.docs.length,
      flagged,
    });
  }
);

// ═══════════════════════════════════════════
// detectGriefCrisisPreIncident — On any content write
// ═══════════════════════════════════════════

const detectGriefCrisisPreIncident = onDocumentWritten(
  { document: "posts/{postId}", region: "us-central1" },
  async (event) => {
    const data = event.data?.after?.data();
    if (!data) return;

    const authorId = data.authorId;
    if (!authorId) return;

    const content = (data.content || "").toLowerCase();

    // Quick keyword check — only proceed to heavier analysis if signals present
    const riskKeywords = [
      "hopeless", "give up", "no point", "alone", "empty",
      "can't go on", "dark place", "nobody cares", "end it",
      "no reason", "nothing matters", "worthless",
    ];
    const hasRiskSignal = riskKeywords.some((kw) => content.includes(kw));
    if (!hasRiskSignal) return;

    try {
      // Maintain rolling 72hr window in RTDB
      const ref = getRtdb().ref(`crisisMonitoring/${authorId}`);
      const snap = await ref.get();
      const history = snap.val() || { signals: [], lastUpdated: 0 };

      // Clean old signals (> 72hrs)
      const cutoff = Date.now() - 72 * 3600 * 1000;
      const recentSignals = (history.signals || []).filter((s) => s.timestamp > cutoff);

      // Add current signal
      recentSignals.push({
        timestamp: Date.now(),
        keywords: riskKeywords.filter((kw) => content.includes(kw)),
        postId: event.params.postId,
      });

      // Compute severity from signal density
      const signalCount = recentSignals.length;
      let severity = "low";

      if (signalCount >= 4 || content.includes("end it") || content.includes("can't go on")) {
        severity = "high";
      } else if (signalCount >= 2) {
        severity = "medium";
      }

      // Update RTDB
      await ref.set({
        signals: recentSignals.slice(-20), // Keep last 20
        lastUpdated: Date.now(),
        currentSeverity: severity,
      });

      // Actions by severity
      if (severity === "high") {
        // Surface crisis resources + notify pastoral care
        await db.collection("users").doc(authorId).update({
          "ml.showCrisisResources": true,
        }).catch(() => {});

        await db.collection("pastoralAlerts").add({
          userId: authorId,
          severity: "high",
          type: "pre_incident_pattern",
          signalCount,
          detectedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "unreviewed",
          // PRIVACY: Never include content, only severity
        });

        console.log(`[CrisisPreIncident] HIGH severity for user ${authorId} (${signalCount} signals in 72hrs)`);
      } else if (severity === "medium") {
        // Surface wellness resources silently
        await db.collection("users").doc(authorId).update({
          "ml.showWellnessResources": true,
        }).catch(() => {});
      }
    } catch (err) {
      console.error(`[CrisisPreIncident] Error:`, err.message);
    }
  }
);

// ═══════════════════════════════════════════
// runZeroHarassmentDetection — On comment/message write
// ═══════════════════════════════════════════

const runZeroHarassmentDetection = onDocumentWritten(
  { document: "posts/{postId}/comments/{commentId}", region: "us-central1" },
  async (event) => {
    const data = event.data?.after?.data();
    if (!data) return;

    const authorId = data.authorId || "";
    const targetUserId = data.postAuthorId || "";
    const content = (data.content || "").toLowerCase();

    if (!authorId || !targetUserId || authorId === targetUserId) return;

    try {
      // Track interaction frequency in RTDB
      const key = `harassmentTracking/${targetUserId}/${authorId}`;
      const ref = getRtdb().ref(key);
      const snap = await ref.get();
      const history = snap.val() || { interactions: [], sentimentSum: 0 };

      // Clean old interactions (> 24hrs)
      const cutoff = Date.now() - 24 * 3600 * 1000;
      const recent = (history.interactions || []).filter((i) => i.timestamp > cutoff);

      // Quick sentiment check
      const negativeIndicators = [
        "stupid", "idiot", "shut up", "wrong", "terrible",
        "fake", "liar", "hypocrite", "disgusting",
      ];
      const isNegative = negativeIndicators.some((w) => content.includes(w));

      recent.push({
        timestamp: Date.now(),
        isNegative,
        commentId: event.params.commentId,
      });

      const negativeCount = recent.filter((i) => i.isNegative).length;
      const totalCount = recent.length;

      // Compute confidence
      let confidence = 0;
      if (totalCount >= 5 && negativeCount >= 3) confidence = 0.9;
      else if (totalCount >= 3 && negativeCount >= 2) confidence = 0.7;
      else if (totalCount >= 3) confidence = 0.5;

      await ref.set({
        interactions: recent.slice(-50),
        lastUpdated: Date.now(),
      });

      // Actions by confidence
      if (confidence >= 0.9) {
        // Shadow restriction on sender
        await db.collection("users").doc(authorId).update({
          "ml.shadowRestricted": true,
          "ml.shadowRestrictedAt": admin.firestore.FieldValue.serverTimestamp(),
          "ml.shadowRestrictReason": "automated_harassment_detection",
        }).catch(() => {});

        await db.collection("moderationQueue").add({
          type: "harassment",
          sourceUserId: authorId,
          targetUserId,
          confidence,
          recentInteractionCount: totalCount,
          negativeCount,
          detectedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "pending",
        });

        console.log(`[Harassment] CRITICAL: ${authorId} → ${targetUserId}, confidence ${confidence}`);
      } else if (confidence >= 0.7) {
        // Notify target proactively
        await db.collection("users").doc(targetUserId).collection("notifications").add({
          type: "safety_check",
          title: "We're looking out for you",
          body: "We noticed some interactions that may be unwanted. Tap to manage.",
          sourceUserId: authorId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
        });
      }
      // 0.5-0.7: monitor only (slow-roll would need middleware integration)
    } catch (err) {
      console.error(`[Harassment] Error:`, err.message);
    }
  }
);

// ═══════════════════════════════════════════
// scoreTheologicalDrift — Weekly per community
// ═══════════════════════════════════════════

const scoreTheologicalDrift = onSchedule(
  { schedule: "0 4 * * 1", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    const startMs = Date.now();

    const communities = await db.collection("communities")
      .where("isActive", "==", true)
      .where("doctrinalBaselineEnabled", "==", true)
      .limit(50)
      .get();

    let flagged = 0;

    for (const communityDoc of communities.docs) {
      const communityId = communityDoc.id;
      const baselineVector = communityDoc.data().doctrinalBaselineVector;
      if (!baselineVector || !Array.isArray(baselineVector)) continue;

      try {
        const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);
        const posts = await db.collection("posts")
          .where("communityId", "==", communityId)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
          .limit(100)
          .get();

        // Group by author
        const authorPosts = {};
        for (const p of posts.docs) {
          const authorId = p.data().authorId;
          if (!authorPosts[authorId]) authorPosts[authorId] = [];
          authorPosts[authorId].push(p.data().content || "");
        }

        for (const [authorId, texts] of Object.entries(authorPosts)) {
          if (texts.length < 3) continue;

          // Generate embedding for author's combined recent content
          const combined = texts.join(". ").substring(0, 2000);
          const embedding = await hfInference(
            "sentence-transformers/all-MiniLM-L6-v2",
            combined
          );

          if (!embedding) continue;
          const vector = Array.isArray(embedding[0]) ? embedding[0] : embedding;

          const similarity = cosineSimilarity(vector, baselineVector);

          if (similarity < 0.4) {
            // Check if pattern persists (look for prior flag)
            const priorFlags = await db.collection("communities").doc(communityId)
              .collection("driftFlags")
              .where("authorId", "==", authorId)
              .where("detectedAt", ">=", admin.firestore.Timestamp.fromDate(
                new Date(Date.now() - 21 * 86400000) // 3 weeks
              ))
              .count()
              .get();

            const persistentWeeks = (priorFlags.data().count || 0) + 1;

            await db.collection("communities").doc(communityId)
              .collection("driftFlags")
              .add({
                authorId,
                similarity,
                persistentWeeks,
                detectedAt: admin.firestore.FieldValue.serverTimestamp(),
                status: persistentWeeks >= 3 ? "pastoral_review" : "monitoring",
              });

            if (persistentWeeks >= 3) {
              flagged++;
              console.log(`[TheologicalDrift] ${authorId} in ${communityId}: similarity ${similarity.toFixed(3)}, ${persistentWeeks} weeks`);
            }
          }
        }
      } catch (err) {
        console.error(`[TheologicalDrift] Error for ${communityId}:`, err.message);
      }

      await sleep(2000); // Throttle HF calls
    }

    logFunction("scoreTheologicalDrift", {
      durationMs: Date.now() - startMs,
      flagged,
    });
  }
);

module.exports = {
  generateCongregationHealthReport,
  detectCoordinatedBehavior,
  runLinguisticFingerprint,
  detectGriefCrisisPreIncident,
  runZeroHarassmentDetection,
  scoreTheologicalDrift,
};
