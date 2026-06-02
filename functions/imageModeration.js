/**
 * Cloud Function for Image Moderation using Cloud Vision SafeSearch
 *
 * Automatically triggered when images are uploaded to Firebase Storage
 * Moderates images and deletes inappropriate content
 */

const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const vision = require("@google-cloud/vision");

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");
// Vision model — same NVIDIA NIM endpoint, same key as NeMo Guard text checks.
const VISION_MODEL = "meta/llama-3.2-11b-vision-instruct";
const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";

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
    region: "us-west1",
    bucket: "amen-5e359.firebasestorage.app",
    secrets: [NVIDIA_API_KEY],
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

        // Generate a short-lived signed URL so the vision LLM can fetch the image.
        const [signedUrl] = await storage.bucket(event.data.bucket).file(filePath).getSignedUrl({
            action: "read",
            expires: Date.now() + 3 * 60 * 1000, // 3 minutes — enough for both checks
        });

        // For post_media, fetch the post's caption to give the vision LLM full context.
        const postId = context === "post_media" && pathParts.length >= 3 ? pathParts[2] : null;
        let postCaption = "";
        if (postId) {
            const postSnap = await db.collection("posts").doc(postId).get().catch(() => null);
            if (postSnap?.exists) {
                const pd = postSnap.data();
                postCaption = (pd.text || pd.body || "").trim().slice(0, 500);
            }
        }

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

        // Determine moderation action — let so the LLM second pass can override it.
        let decision = evaluateSafeSearch(safeSearch);
        const safeSearchAction = decision.action; // preserve original for the log

        // Vision LLM second pass — runs unless SafeSearch already hard-blocked.
        // Understands faith context; can approve images SafeSearch over-flagged
        // (e.g. biblical art) or block contextually inappropriate content SafeSearch missed.
        let llmVerdict = null;
        if (decision.action !== "blocked") {
            try {
                llmVerdict = await checkFaithContext(signedUrl, postCaption, NVIDIA_API_KEY.value());
                console.log(`🧠 Vision LLM verdict: appropriate=${llmVerdict.appropriate}, confidence=${llmVerdict.confidence}, reason="${llmVerdict.reason}"`);

                if (decision.action === "review" && llmVerdict.appropriate && llmVerdict.confidence !== "low") {
                    decision = { action: "approved", reasons: [] };
                    console.log("✅ LLM overrode SafeSearch review → approved");
                } else if (decision.action === "review" && !llmVerdict.appropriate) {
                    decision = { action: "blocked", reasons: [llmVerdict.reason] };
                    console.log("❌ LLM confirmed SafeSearch review → blocked");
                } else if (decision.action === "approved" && !llmVerdict.appropriate && llmVerdict.confidence === "high") {
                    decision = { action: "blocked", reasons: [llmVerdict.reason] };
                    console.log("❌ LLM overrode SafeSearch approved → blocked");
                }
            } catch (llmErr) {
                console.warn("⚠️ Vision LLM check failed, using SafeSearch verdict only:", llmErr.message);
            }
        }

        // Log final decision (after LLM override) with both SafeSearch and LLM data.
        await db.collection("imageModerationLogs").add({
            filePath: filePath,
            userId: userId,
            context: context,
            safeSearchAction,          // what SafeSearch decided before LLM
            finalAction: decision.action, // what we actually enforced
            adult: safeSearch.adult,
            racy: safeSearch.racy,
            violence: safeSearch.violence,
            medical: safeSearch.medical,
            spoof: safeSearch.spoof,
            flaggedReasons: decision.reasons,
            llm: llmVerdict ? {
                appropriate: llmVerdict.appropriate,
                reason: llmVerdict.reason,
                confidence: llmVerdict.confidence,
            } : null,
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
                blockedBy: safeSearchAction === "blocked" ? "safesearch" : "vision-llm",
                safeSearchScores: {
                    adult: safeSearch.adult,
                    racy: safeSearch.racy,
                    violence: safeSearch.violence,
                },
                llm: llmVerdict,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                status: "resolved_auto",
            });

            // For post media: hide the post and queue it for admin review.
            if (postId) {
                const provider = safeSearchAction === "blocked" ? "cloud-vision-safesearch"
                    : "nvidia-vision-llm";
                await db.collection("posts").doc(postId).update({
                    visible: false,
                    removed: true,
                    flaggedForReview: false,
                    "moderation.status": "blocked",
                    "moderation.categories": ["image_safety"],
                    "moderation.provider": provider,
                    "moderation.checkedAt": admin.firestore.FieldValue.serverTimestamp(),
                }).catch((e) => console.warn(`Could not update post ${postId}:`, e.message));

                await db.collection("moderationQueue").add({
                    postRef: `posts/${postId}`,
                    authorId: userId,
                    preview: `[image blocked: ${decision.reasons.join(", ")}]`,
                    status: "blocked",
                    categories: ["image_safety"],
                    reason: "image_blocked_safesearch",
                    // Stored so adminReviewPost can strip this dead URL from post.media.
                    blockedMediaUrl: `https://firebasestorage.googleapis.com/v0/b/${event.data.bucket}/o/${encodeURIComponent(filePath)}`,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            return {action: "blocked", filePath};
        } else if (decision.action === "review") {
            console.log(`⚠️  Flagging for review: ${decision.reasons.join(", ")}`);

            // Add to review queue
            await db.collection("moderatorAlerts").add({
                type: "image_review_needed",
                userId: userId,
                context: context,
                filePath: filePath,
                postCaption: postCaption || null,
                imageUrl: `https://storage.googleapis.com/${event.data.bucket}/${filePath}`,
                reasons: decision.reasons,
                safeSearchScores: {
                    adult: safeSearch.adult,
                    racy: safeSearch.racy,
                    violence: safeSearch.violence,
                    medical: safeSearch.medical,
                    spoof: safeSearch.spoof,
                },
                llm: llmVerdict,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                status: "pending_review",
            });

            // For post media that needs review: hold it invisible until a moderator clears it.
            if (postId) {
                await db.collection("posts").doc(postId).update({
                    visible: false,
                    flaggedForReview: true,
                    removed: false,
                    "moderation.status": "pending",
                    "moderation.provider": "cloud-vision-safesearch",
                    "moderation.checkedAt": admin.firestore.FieldValue.serverTimestamp(),
                }).catch((e) => console.warn(`Could not update post ${postId}:`, e.message));
            }

            return {action: "review", filePath};
        }

        // Image approved — if the post was held for image review, flip it visible now.
        if (postId) {
            const postSnap = await db.collection("posts").doc(postId).get().catch(() => null);
            if (postSnap && postSnap.exists) {
                const postData = postSnap.data();
                if (postData.moderation?.status === "pending_image_review") {
                    await db.collection("posts").doc(postId).update({
                        visible: true,
                        flaggedForReview: false,
                        removed: false,
                        "moderation.status": "approved",
                        "moderation.provider": "cloud-vision-safesearch",
                        "moderation.checkedAt": admin.firestore.FieldValue.serverTimestamp(),
                    });
                    console.log(`✅ Post ${postId} approved after image review`);
                }
            }
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
 * Faith-aware vision LLM check via NVIDIA NIM.
 * Runs after SafeSearch to catch context-specific issues and prevent false positives
 * on biblical/spiritual imagery that generic SafeSearch may misclassify.
 *
 * @param {string} imageUrl   - Signed Storage URL (accessible by NVIDIA servers)
 * @param {string} postCaption - Post text / caption for context (may be empty)
 * @param {string} apiKey      - NVIDIA NIM API key
 * @returns {{ appropriate: boolean, reason: string, confidence: "high"|"medium"|"low" }}
 */
async function checkFaithContext(imageUrl, postCaption, apiKey) {
    const captionClause = postCaption
        ? `\n\nThe post caption accompanying this image is: "${postCaption}"`
        : "";

    const prompt = `You are a content moderator for Amen, a Christian faith-based social media app.${captionClause}

APPROPRIATE for this platform:
- Crosses, Scripture, churches, Christian symbols and art
- Worship services, baptisms, prayer gatherings, fellowship
- Biblical scenes (including historical depictions of violence when clearly artistic)
- Nature, family moments, community events
- Motivational or spiritual imagery

INAPPROPRIATE for this platform:
- Sexual or suggestive content
- Gratuitous violence unrelated to spiritual context
- Hate symbols or imagery targeting any group
- Drug use or illegal activity
- Mockery of faith, believers, or the Bible

Respond ONLY with valid JSON, no markdown:
{"appropriate": true, "reason": "one sentence", "confidence": "high"}`;

    const res = await fetch(NIM_URL, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            model: VISION_MODEL,
            messages: [{
                role: "user",
                content: [
                    { type: "image_url", image_url: { url: imageUrl } },
                    { type: "text", text: prompt },
                ],
            }],
            max_tokens: 80,
            temperature: 0,
        }),
    });

    if (!res.ok) {
        throw new Error(`Vision LLM ${res.status}: ${await res.text()}`);
    }

    const data = await res.json();
    const raw = (data.choices?.[0]?.message?.content ?? "").trim();

    try {
        // Strip any accidental markdown fences before parsing
        const jsonStr = raw.replace(/^```json?\s*/i, "").replace(/```\s*$/, "");
        const parsed = JSON.parse(jsonStr);
        return {
            appropriate: Boolean(parsed.appropriate),
            reason: String(parsed.reason || ""),
            confidence: ["high", "medium", "low"].includes(parsed.confidence)
                ? parsed.confidence
                : "medium",
        };
    } catch {
        // If JSON parse fails, fail open (trust SafeSearch as primary layer).
        console.warn("Vision LLM returned non-JSON:", raw.slice(0, 200));
        return { appropriate: true, reason: "parse-error — defaulting to SafeSearch verdict", confidence: "low" };
    }
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
