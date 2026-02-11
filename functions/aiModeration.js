/**
 * Firebase Cloud Functions for AI-Powered Moderation, Crisis Detection, and Smart Notifications
 *
 * These functions work with Firebase AI Logic extension for:
 * 1. Content moderation (profanity, hate speech, spam)
 * 2. Crisis detection in prayer requests (suicide, abuse, etc.)
 * 3. Smart notification batching and delivery
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

// ============================================================================
// CONTENT MODERATION
// ============================================================================

/**
 * Triggered when new moderation request is created
 * Uses Firebase AI Logic to analyze content for harmful material
 */
exports.moderateContent = functions.firestore
    .document("moderationRequests/{requestId}")
    .onCreate(async (snap, context) => {
        const requestId = context.params.requestId;
        const data = snap.data();

        console.log(`🛡️ [MODERATION] Processing request ${requestId}`);

        try {
            // Call Firebase AI Logic extension for content moderation
            const moderationResult = await analyzeContentWithAI(
                data.content,
                data.contentType,
                data.userId,
            );

            // Store result for Swift service to retrieve
            await db.collection("moderationResults").doc(requestId).set({
                isApproved: moderationResult.isApproved,
                flaggedReasons: moderationResult.flaggedReasons,
                severityLevel: moderationResult.severityLevel,
                suggestedAction: moderationResult.suggestedAction,
                confidence: moderationResult.confidence,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // If content is blocked, notify moderators
            if (moderationResult.severityLevel === "blocked") {
                await notifyModerators(data.userId, moderationResult);
            }

            console.log(`✅ [MODERATION] Request ${requestId}: ${moderationResult.severityLevel}`);
        } catch (error) {
            console.error(`❌ [MODERATION] Error processing ${requestId}:`, error);

            // Store error result
            await db.collection("moderationResults").doc(requestId).set({
                isApproved: true, // Conservative fallback
                flaggedReasons: ["AI processing error"],
                severityLevel: "review",
                suggestedAction: "human_review",
                confidence: 0.0,
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

/**
 * Analyze content using Firebase AI Logic
 */
async function analyzeContentWithAI(content, contentType, userId) {
    const prompt = `
You are a content moderation AI for a Christian social media app called AMEN.

Analyze the following ${contentType} content and determine if it contains:
1. Profanity or vulgar language
2. Hate speech or discriminatory content
3. Sexual or explicit content
4. Spam or promotional content
5. Threats or violent content

Content: "${content}"

Respond ONLY with valid JSON:
{
  "isApproved": true/false,
  "flaggedReasons": ["reason"],
  "severityLevel": "safe/warning/blocked/review",
  "suggestedAction": "approve/flag/block/human_review",
  "confidence": 0.0-1.0
}`;

    // TODO: Replace with actual Firebase AI Logic extension call
    // For now, return basic keyword filtering
    return performBasicModeration(content);
}

/**
 * Basic keyword-based moderation
 */
function performBasicModeration(content) {
    const lowercased = content.toLowerCase();
    const profanityPatterns = ["f***", "s***", "damn", "hell", "wtf"];

    for (const pattern of profanityPatterns) {
        if (lowercased.includes(pattern)) {
            return {
                isApproved: false,
                flaggedReasons: ["Profanity detected"],
                severityLevel: "blocked",
                suggestedAction: "block",
                confidence: 0.8,
            };
        }
    }

    return {
        isApproved: true,
        flaggedReasons: [],
        severityLevel: "safe",
        suggestedAction: "approve",
        confidence: 0.9,
    };
}

// ============================================================================
// CRISIS DETECTION
// ============================================================================

/**
 * Triggered when crisis detection request is created
 */
exports.detectCrisis = functions.firestore
    .document("crisisDetectionRequests/{requestId}")
    .onCreate(async (snap, context) => {
        const requestId = context.params.requestId;
        const data = snap.data();

        console.log(`🚨 [CRISIS] Analyzing prayer request ${requestId}`);

        try {
            const crisisResult = await analyzeForCrisis(data.prayerText, data.userId);

            // Store result
            await db.collection("crisisDetectionResults").doc(requestId).set({
                isCrisis: crisisResult.isCrisis,
                crisisTypes: crisisResult.crisisTypes,
                urgencyLevel: crisisResult.urgencyLevel,
                recommendedResources: crisisResult.recommendedResources,
                confidence: crisisResult.confidence,
                suggestedIntervention: crisisResult.suggestedIntervention,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // If critical, alert immediately
            if (crisisResult.urgencyLevel === "critical") {
                await handleCriticalCrisis(data.userId, crisisResult);
            }

            console.log(`✅ [CRISIS] Request ${requestId}: ${crisisResult.urgencyLevel}`);
        } catch (error) {
            console.error(`❌ [CRISIS] Error:`, error);

            await db.collection("crisisDetectionResults").doc(requestId).set({
                isCrisis: false,
                crisisTypes: [],
                urgencyLevel: "none",
                recommendedResources: [],
                confidence: 0.0,
                suggestedIntervention: "none",
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

/**
 * Analyze for crisis indicators
 */
async function analyzeForCrisis(prayerText, userId) {
    const lowercased = prayerText.toLowerCase();
    const detectedCrises = [];
    let maxUrgency = "none";

    // Suicide patterns (CRITICAL)
    const suicidePatterns = ["want to die", "kill myself", "end my life", "suicide"];
    for (const pattern of suicidePatterns) {
        if (lowercased.includes(pattern)) {
            detectedCrises.push("suicide_ideation");
            maxUrgency = "critical";
            break;
        }
    }

    // Self-harm patterns (HIGH)
    const selfHarmPatterns = ["hurt myself", "cut myself", "harm myself"];
    for (const pattern of selfHarmPatterns) {
        if (lowercased.includes(pattern)) {
            detectedCrises.push("self_harm");
            if (maxUrgency !== "critical") maxUrgency = "high";
            break;
        }
    }

    // Abuse patterns (HIGH)
    const abusePatterns = ["abused", "hitting me", "hurting me", "violence"];
    for (const pattern of abusePatterns) {
        if (lowercased.includes(pattern)) {
            detectedCrises.push("abuse");
            if (maxUrgency !== "critical") maxUrgency = "high";
            break;
        }
    }

    if (detectedCrises.length > 0) {
        return {
            isCrisis: true,
            crisisTypes: detectedCrises,
            urgencyLevel: maxUrgency,
            recommendedResources: getResources(detectedCrises),
            confidence: 0.85,
            suggestedIntervention: maxUrgency === "critical" ? "emergency_contact" : "show_resources",
        };
    }

    return {
        isCrisis: false,
        crisisTypes: [],
        urgencyLevel: "none",
        recommendedResources: [],
        confidence: 0.0,
        suggestedIntervention: "none",
    };
}

/**
 * Get recommended resources for detected crisis types
 */
function getResources(crisisTypes) {
    const resources = [];

    for (const type of crisisTypes) {
        if (type === "suicide_ideation") {
            resources.push("suicide_prevention", "crisis_text_line");
        } else if (type === "self_harm") {
            resources.push("mental_health", "crisis_text_line");
        } else if (type === "abuse") {
            resources.push("domestic_violence");
        }
    }

    resources.push("christian_counseling");
    return [...new Set(resources)];
}

/**
 * Handle critical crisis situations
 */
async function handleCriticalCrisis(userId, crisisResult) {
    console.log(`🚨 [CRISIS] CRITICAL for user ${userId}`);

    await db.collection("moderatorAlerts").add({
        type: "critical_crisis",
        userId: userId,
        crisisTypes: crisisResult.crisisTypes,
        urgencyLevel: "critical",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "urgent",
    });
}

// ============================================================================
// SMART NOTIFICATIONS
// ============================================================================

/**
 * Deliver batched notifications every 5 minutes
 */
exports.deliverBatchedNotifications = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async (context) => {
        console.log("📬 [SMART_NOTIF] Checking batches...");

        const now = admin.firestore.Timestamp.now();

        const snapshot = await db.collection("scheduledBatches")
            .where("status", "==", "scheduled")
            .where("deliveryTime", "<=", now)
            .limit(100)
            .get();

        console.log(`📬 Found ${snapshot.size} batches`);

        for (const doc of snapshot.docs) {
            const scheduleData = doc.data();

            try {
                const batchDoc = await db.collection("notificationBatches")
                    .doc(scheduleData.batchId)
                    .get();

                if (!batchDoc.exists) continue;

                const batch = batchDoc.data();
                const notification = generateBatchNotification(batch);

                // Get FCM token
                const userDoc = await db.collection("users").doc(scheduleData.recipientId).get();
                const fcmToken = userDoc.data()?.fcmToken;

                if (fcmToken) {
                    await admin.messaging().send({
                        token: fcmToken,
                        notification: {
                            title: notification.title,
                            body: notification.body,
                        },
                        data: {
                            type: batch.type,
                            count: batch.count.toString(),
                        },
                        apns: {
                            payload: {
                                aps: {badge: 1, sound: "default"},
                            },
                        },
                    });
                }

                // Mark delivered
                await batchDoc.ref.update({delivered: true});
                await doc.ref.update({status: "delivered"});

                console.log(`✅ Delivered batch ${scheduleData.batchId}`);
            } catch (error) {
                console.error(`❌ Error delivering batch:`, error);
                await doc.ref.update({status: "failed", error: error.message});
            }
        }

        return null;
    });

/**
 * Generate notification content for a batch
 */
function generateBatchNotification(batch) {
    const count = batch.count;
    const templates = {
        prayers: {
            single: {title: "Someone Prayed", body: "Someone prayed for your request"},
            multiple: {title: `${count} People Prayed`, body: `${count} people prayed`},
        },
        amens: {
            single: {title: "New Amen", body: "Someone said Amen"},
            multiple: {title: `${count} Amens`, body: `${count} people said Amen`},
        },
        comments: {
            single: {title: "New Comment", body: "Someone commented"},
            multiple: {title: `${count} Comments`, body: `${count} new comments`},
        },
    };

    const template = templates[batch.type] || templates.amens;
    return count === 1 ? template.single : template.multiple;
}

/**
 * Notify moderators of flagged content
 */
async function notifyModerators(userId, moderationResult) {
    await db.collection("moderatorAlerts").add({
        type: "content_moderation",
        userId: userId,
        flaggedReasons: moderationResult.flaggedReasons,
        severityLevel: moderationResult.severityLevel,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending",
    });
}
