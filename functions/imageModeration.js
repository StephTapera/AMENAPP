/**
 * Cloud Function for Image Moderation using Cloud Vision SafeSearch
 *
 * Automatically triggered when images are uploaded to Firebase Storage
 * Moderates images and deletes inappropriate content
 */

const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const vision = require("@google-cloud/vision");

// Note: admin.initializeApp() is called once in index.js — no re-init here.
const admin = require("firebase-admin");

const db = getFirestore();
const storage = getStorage();

// Lazy-initialize Vision client to avoid blocking module load (causes deploy timeout)
let _visionClient = null;
function getVisionClient() {
    if (!_visionClient) {
        _visionClient = new vision.ImageAnnotatorClient();
    }
    return _visionClient;
}

/**
 * Triggered when an image is uploaded to Storage
 * Performs SafeSearch detection and removes inappropriate images
 */
exports.moderateUploadedImage = onObjectFinalized({
    region: "us-west1",  // Match Storage bucket region
    bucket: "amen-5e359.firebasestorage.app"
}, async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;

    console.log(`🛡️ [IMAGE MOD] Processing file: ${filePath}`);

    // Only process images
    if (!contentType || !contentType.startsWith("image/")) {
        console.log(`⏭️  Skipping non-image file: ${contentType}`);
        return null;
    }

    // Skip if already processed or in moderation folder
    if (filePath.includes("/moderated/") || filePath.includes("/deleted/")) {
        console.log(`⏭️  Skipping already processed image`);
        return null;
    }

    try {
        // Extract context from path (posts/userId/*, profile_pictures/userId/*, etc.)
        const pathParts = filePath.split("/");
        const context = pathParts[0]; // "posts", "profile_pictures", "messages", "church_notes"
        const userId = pathParts.length > 1 ? pathParts[1] : "unknown";

        console.log(`📋 Context: ${context}, User: ${userId}`);

        // Perform SafeSearch detection
        const imageUri = `gs://${event.data.bucket}/${filePath}`;
        const [result] = await getVisionClient().safeSearchDetection(imageUri);
        const safeSearch = result.safeSearchAnnotation;

        console.log(`🔍 SafeSearch results:`, {
            adult: safeSearch.adult,
            racy: safeSearch.racy,
            violence: safeSearch.violence,
            medical: safeSearch.medical,
            spoof: safeSearch.spoof,
        });

        // Determine moderation action
        const decision = evaluateSafeSearch(safeSearch);

        // Log to Firestore
        await db.collection("imageModerationLogs").add({
            filePath: filePath,
            userId: userId,
            context: context,
            action: decision.action,
            adult: safeSearch.adult,
            racy: safeSearch.racy,
            violence: safeSearch.violence,
            medical: safeSearch.medical,
            spoof: safeSearch.spoof,
            flaggedReasons: decision.reasons,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Take action based on decision
        if (decision.action === "blocked") {
            console.log(`❌ BLOCKING image: ${decision.reasons.join(", ")}`);

            // Delete the file
            await storage.bucket(event.data.bucket).file(filePath).delete();
            console.log(`🗑️  Deleted inappropriate image: ${filePath}`);

            // Alert moderators
            await db.collection("moderatorAlerts").add({
                type: "image_blocked_auto",
                userId: userId,
                context: context,
                filePath: filePath,
                reasons: decision.reasons,
                safeSearchScores: {
                    adult: safeSearch.adult,
                    racy: safeSearch.racy,
                    violence: safeSearch.violence,
                },
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                status: "resolved_auto",
            });

            // Notify user (optional - can be handled client-side)
            // await notifyUserOfRejection(userId, context, decision.reasons);

            return {action: "blocked", filePath};
        } else if (decision.action === "review") {
            console.log(`⚠️  Flagging for review: ${decision.reasons.join(", ")}`);

            // Add to review queue
            await db.collection("moderatorAlerts").add({
                type: "image_review_needed",
                userId: userId,
                context: context,
                filePath: filePath,
                imageUrl: `https://storage.googleapis.com/${event.data.bucket}/${filePath}`,
                reasons: decision.reasons,
                safeSearchScores: {
                    adult: safeSearch.adult,
                    racy: safeSearch.racy,
                    violence: safeSearch.violence,
                    medical: safeSearch.medical,
                    spoof: safeSearch.spoof,
                },
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                status: "pending_review",
            });

            return {action: "review", filePath};
        }

        console.log(`✅ Image approved: ${filePath}`);
        return {action: "approved", filePath};

    } catch (error) {
        console.error(`❌ Error moderating image ${filePath}:`, error);

        // Log error but don't delete image (fail safe)
        await db.collection("imageModerationErrors").add({
            filePath: filePath,
            error: error.message,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {action: "error", error: error.message};
    }
});

/**
 * Evaluate SafeSearch results and determine action
 * @param {Object} safeSearch - SafeSearch annotation from Vision API
 * @returns {Object} - {action: 'approved'|'blocked'|'review', reasons: []}
 */
function evaluateSafeSearch(safeSearch) {
    const reasons = [];
    const scores = {
        UNKNOWN: 0,
        VERY_UNLIKELY: 1,
        UNLIKELY: 2,
        POSSIBLE: 3,
        LIKELY: 4,
        VERY_LIKELY: 5,
    };

    const adultScore = scores[safeSearch.adult] || 0;
    const racyScore = scores[safeSearch.racy] || 0;
    const violenceScore = scores[safeSearch.violence] || 0;
    const medicalScore = scores[safeSearch.medical] || 0;
    const spoofScore = scores[safeSearch.spoof] || 0;

    // BLOCK: Strict thresholds for faith platform
    if (adultScore >= 3) { // POSSIBLE or higher
        reasons.push("Inappropriate content detected");
    }
    if (racyScore >= 3) { // POSSIBLE or higher
        reasons.push("Suggestive content detected");
    }
    if (violenceScore >= 4) { // LIKELY or higher
        reasons.push("Violent imagery detected");
    }

    if (reasons.length > 0) {
        return {action: "blocked", reasons};
    }

    // REVIEW: Borderline content
    const reviewReasons = [];
    if (medicalScore >= 4) {
        reviewReasons.push("Medical/graphic content");
    }
    if (spoofScore >= 4) {
        reviewReasons.push("Potentially fake/edited content");
    }
    if (adultScore === 2 || racyScore === 2) { // UNLIKELY but worth checking
        reviewReasons.push("Borderline content");
    }

    if (reviewReasons.length > 0) {
        return {action: "review", reasons: reviewReasons};
    }

    // APPROVE: Safe content
    return {action: "approved", reasons: []};
}

/**
 * Notify user that their image was rejected (optional)
 */
async function notifyUserOfRejection(userId, context, reasons) {
    try {
        // Get user's FCM token
        const userDoc = await db.collection("users").doc(userId).get();
        const fcmToken = userDoc.data()?.fcmToken;

        if (!fcmToken) {
            console.log(`⚠️  No FCM token for user ${userId}, skipping notification`);
            return;
        }

        // Send push notification
        const message = {
            token: fcmToken,
            notification: {
                title: "Image Upload Failed",
                body: `Your ${context} image could not be uploaded. Please choose an image that aligns with our community guidelines.`,
            },
            data: {
                type: "image_rejected",
                context: context,
                reasons: reasons.join(", "),
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                    },
                },
            },
        };

        await admin.messaging().send(message);
        console.log(`📬 Sent rejection notification to user ${userId}`);
    } catch (error) {
        console.error(`❌ Failed to send notification to user ${userId}:`, error);
    }
}
