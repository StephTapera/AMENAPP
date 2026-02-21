/**
 * AI-Powered Feed Personalization Cloud Functions
 * Integrates with Vertex AI for ML-powered recommendations
 */

const admin = require("firebase-admin");
const {onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {VertexAI} = require("@google-cloud/vertexai");

// Initialize Vertex AI
const vertexAI = new VertexAI({
  project: process.env.GOOGLE_CLOUD_PROJECT,
  location: "us-central1",
});

// ============================================================================
// PERSONALIZED FEED GENERATION
// ============================================================================

/**
 * Generate personalized feed using Vertex AI predictions
 * Called by: Swift app when user opens home feed
 */
exports.generatePersonalizedFeed = onCall(
    {
      region: "us-central1",
      memory: "512MB",
      timeoutSeconds: 60,
    },
    async (request) => {
      const userId = request.auth?.uid;
      if (!userId) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be authenticated"
        );
      }

      console.log(`🎯 [PERSONALIZE] Generating feed for user ${userId}`);

      try {
        // Step 1: Fetch candidate posts (recent posts from following + trending)
        const candidatePosts = await getCandidatePosts(userId);
        console.log(`📋 [CANDIDATES] Found ${candidatePosts.length} posts`);

        // Step 2: Get user's engagement history for context
        const userHistory = await getUserEngagementHistory(userId);
        console.log(`📊 [HISTORY] User has ${userHistory.length} interactions`);

        // Step 3: Call Vertex AI for predictions
        const predictions = await getPredictionsFromVertexAI(
            userId,
            candidatePosts,
            userHistory
        );

        // Step 4: Rank posts by prediction score
        const rankedPosts = candidatePosts
            .map((post, index) => ({
              postId: post.id,
              score: predictions[index]?.score || 0.5,
              features: predictions[index]?.features || {},
            }))
            .sort((a, b) => b.score - a.score);

        console.log(`✅ [PERSONALIZE] Ranked ${rankedPosts.length} posts`);

        return {
          success: true,
          rankedPostIds: rankedPosts.map((p) => p.postId),
          scores: rankedPosts.map((p) => p.score),
          timestamp: Date.now(),
        };
      } catch (error) {
        console.error("❌ [PERSONALIZE] Error:", error);
        throw new functions.https.HttpsError(
            "internal",
            "Failed to generate personalized feed",
            error.message
        );
      }
    }
);

/**
 * Get candidate posts for personalization
 */
async function getCandidatePosts(userId) {
  const db = admin.firestore();

  // Get user's following list
  const followingSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("following")
      .limit(100)
      .get();

  const followingIds = followingSnapshot.docs.map((doc) => doc.id);

  // Fetch recent posts from following
  const postsSnapshot = await db
      .collection("posts")
      .where("userId", "in", followingIds.slice(0, 10)) // Firestore 'in' limit
      .where("createdAt", ">", new Date(Date.now() - 7 * 24 * 60 * 60 * 1000))
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();

  return postsSnapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
}

/**
 * Get user's engagement history
 */
async function getUserEngagementHistory(userId) {
  const db = admin.firestore();

  const snapshot = await db
      .collection("engagementEvents")
      .where("userId", "==", userId)
      .orderBy("timestamp", "desc")
      .limit(100)
      .get();

  return snapshot.docs.map((doc) => doc.data());
}

/**
 * Get predictions from Vertex AI model
 */
async function getPredictionsFromVertexAI(
    userId,
    candidatePosts,
    userHistory
) {
  // Extract user features
  const userFeatures = extractUserFeatures(userHistory);

  // Build prediction instances
  const instances = candidatePosts.map((post) => ({
    user_id: userId,
    post_id: post.id,
    user_features: userFeatures,
    post_features: extractPostFeatures(post),
  }));

  try {
    // Call Vertex AI Prediction endpoint
    // TODO: Replace with your deployed model endpoint
    const model = vertexAI.preview.getGenerativeModel({
      model: "gemini-1.5-flash",
    });

    // For now, return mock predictions (replace with actual model call)
    return instances.map(() => ({
      score: Math.random(),
      features: {
        topicMatch: Math.random(),
        authorAffinity: Math.random(),
        engagementQuality: Math.random(),
      },
    }));
  } catch (error) {
    console.error("⚠️ [VERTEX AI] Prediction error:", error);
    // Fallback to random scores
    return instances.map(() => ({score: 0.5, features: {}}));
  }
}

/**
 * Extract user features from engagement history
 */
function extractUserFeatures(history) {
  const features = {
    totalInteractions: history.length,
    reactionCount: 0,
    commentCount: 0,
    shareCount: 0,
    avgSessionLength: 0,
    topTopics: [],
    topAuthors: [],
  };

  const topicCounts = {};
  const authorCounts = {};

  for (const event of history) {
    if (event.eventType === "reaction") features.reactionCount++;
    if (event.eventType === "comment") features.commentCount++;
    if (event.eventType === "share") features.shareCount++;

    if (event.metadata?.topic) {
      topicCounts[event.metadata.topic] =
        (topicCounts[event.metadata.topic] || 0) + 1;
    }
    if (event.metadata?.author) {
      authorCounts[event.metadata.author] =
        (authorCounts[event.metadata.author] || 0) + 1;
    }
  }

  // Top 5 topics and authors
  features.topTopics = Object.entries(topicCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map((entry) => entry[0]);

  features.topAuthors = Object.entries(authorCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map((entry) => entry[0]);

  return features;
}

/**
 * Extract post features
 */
function extractPostFeatures(post) {
  return {
    category: post.category || "general",
    authorId: post.userId,
    amenCount: post.amenCount || 0,
    commentCount: post.commentCount || 0,
    ageHours: (Date.now() - post.createdAt?.toMillis()) / (1000 * 60 * 60),
    contentLength: post.content?.length || 0,
    hasImage: !!post.imageURLs && post.imageURLs.length > 0,
  };
}

// ============================================================================
// SMART NOTIFICATION FILTERING
// ============================================================================

/**
 * Filter notifications by predicted relevance
 * Scheduled: Runs every 5 minutes
 */
exports.filterSmartNotifications = onSchedule(
    {
      schedule: "every 5 minutes",
      region: "us-central1",
      memory: "512MB",
    },
    async (event) => {
      console.log("🔔 [FILTER] Starting smart notification filter...");

      const db = admin.firestore();

      // Get pending notifications
      const pendingSnapshot = await db
          .collection("pendingNotifications")
          .where("processed", "==", false)
          .limit(100)
          .get();

      if (pendingSnapshot.empty) {
        console.log("ℹ️ [FILTER] No pending notifications");
        return null;
      }

      console.log(
          `📋 [FILTER] Processing ${pendingSnapshot.docs.length} notifications`
      );

      let sentCount = 0;
      let suppressedCount = 0;

      for (const doc of pendingSnapshot.docs) {
        const notification = doc.data();

        // Predict relevance
        const relevanceScore = await predictNotificationRelevance(
            notification.userId,
            notification.type,
            notification.metadata
        );

        console.log(
            `🔔 [SCORE] User ${notification.userId}: ${relevanceScore.toFixed(
                2
            )}`
        );

        // Decision threshold: 0.6
        if (relevanceScore >= 0.6) {
          // Send notification
          await sendNotification(notification);
          sentCount++;
        } else {
          suppressedCount++;
          console.log(
              `🔕 [SUPPRESSED] ${notification.type} (score: ${relevanceScore.toFixed(
                  2
              )})`
          );
        }

        // Mark as processed
        await doc.ref.update({processed: true, relevanceScore});
      }

      console.log(
          `✅ [FILTER] Sent ${sentCount}, Suppressed ${suppressedCount}`
      );
      return null;
    }
);

/**
 * Predict notification relevance score
 */
async function predictNotificationRelevance(userId, type, metadata) {
  const db = admin.firestore();

  // Get user's notification engagement history
  const historySnapshot = await db
      .collection("notificationEngagement")
      .where("userId", "==", userId)
      .orderBy("timestamp", "desc")
      .limit(50)
      .get();

  const totalNotifications = historySnapshot.docs.length;
  const openedNotifications = historySnapshot.docs.filter(
      (doc) => doc.data().opened
  ).length;

  const baseEngagementRate =
    totalNotifications > 0 ? openedNotifications / totalNotifications : 0.5;

  // Type-specific multipliers
  const typeMultipliers = {
    comment: 1.2,
    reaction: 0.9,
    follow: 1.1,
    message: 1.3,
    mention: 1.4,
  };
  const typeMultiplier = typeMultipliers[type] || 1.0;

  // Time-based adjustment
  const hour = new Date().getHours();
  let timeMultiplier = 1.0;
  if (hour >= 22 || hour < 8) {
    timeMultiplier = 0.3; // Nighttime
  } else if (hour >= 9 && hour <= 20) {
    timeMultiplier = 1.0; // Daytime
  } else {
    timeMultiplier = 0.7; // Early/late
  }

  return Math.min(1.0, baseEngagementRate * typeMultiplier * timeMultiplier);
}

/**
 * Send notification via FCM
 */
async function sendNotification(notification) {
  const db = admin.firestore();

  // Get user's FCM token
  const userDoc = await db.collection("users").doc(notification.userId).get();
  const fcmToken = userDoc.data()?.fcmToken;

  if (!fcmToken) {
    console.log(`⚠️ [FCM] No token for user ${notification.userId}`);
    return;
  }

  // Send via FCM
  await admin.messaging().send({
    token: fcmToken,
    notification: {
      title: notification.title,
      body: notification.body,
    },
    data: notification.metadata,
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  });

  console.log(`✅ [SENT] Notification to user ${notification.userId}`);
}

// ============================================================================
// MODEL TRAINING DATA EXPORT
// ============================================================================

/**
 * Export engagement data for Vertex AI training
 * Triggered: Manual call or scheduled weekly
 */
exports.exportEngagementData = onCall(
    {
      region: "us-central1",
      memory: "1GB",
      timeoutSeconds: 300,
    },
    async (request) => {
      console.log("📤 [EXPORT] Starting engagement data export...");

      const db = admin.firestore();

      // Get last 30 days of engagement events
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - 30);

      const snapshot = await db
          .collection("engagementEvents")
          .where("timestamp", ">=", startDate)
          .get();

      console.log(`📊 [EXPORT] Found ${snapshot.docs.length} events`);

      // Convert to training format
      const trainingData = snapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          user_id: data.userId,
          post_id: data.postId,
          event_type: data.eventType,
          timestamp: data.timestamp?.toMillis(),
          duration: data.duration || 0,
          features: data.metadata || {},
        };
      });

      // Upload to Cloud Storage (for Vertex AI)
      const {Storage} = require("@google-cloud/storage");
      const storage = new Storage();
      const bucket = storage.bucket(`${process.env.GOOGLE_CLOUD_PROJECT}.appspot.com`);
      const fileName = `training-data/engagement_${Date.now()}.jsonl`;
      const file = bucket.file(fileName);

      // Write as JSONL
      const jsonlContent = trainingData
          .map((item) => JSON.stringify(item))
          .join("\n");

      await file.save(jsonlContent, {
        contentType: "application/jsonl",
      });

      console.log(
          `✅ [EXPORT] Uploaded ${trainingData.length} records to gs://${bucket.name}/${fileName}`
      );

      return {
        success: true,
        recordCount: trainingData.length,
        gcsPath: `gs://${bucket.name}/${fileName}`,
      };
    }
);
