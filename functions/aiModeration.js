/**
 * Firebase Cloud Functions for AI-Powered Moderation, Crisis Detection, and Smart Notifications
 *
 * These functions work with Firebase AI Logic extension for:
 * 1. Content moderation (profanity, hate speech, spam)
 * 2. Crisis detection in prayer requests (suicide, abuse, etc.)
 * 3. Smart notification batching and delivery
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {VertexAI} = require("@google-cloud/vertexai");

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

// Initialize Vertex AI
const vertexAI = new VertexAI({
    project: "amen-5e359",
    location: "us-central1",
});

// ============================================================================
// CONTENT MODERATION
// ============================================================================

/**
 * Triggered when new moderation request is created
 * Uses Firebase AI Logic to analyze content for harmful material
 */
exports.moderateContent = onDocumentCreated("moderationRequests/{requestId}", async (event) => {
        const requestId = event.params.requestId;
        const snap = event.data;
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
 * Analyze content using Vertex AI (Gemini 1.5 Flash)
 */
async function analyzeContentWithAI(content, contentType, userId) {
    try {
        // First do quick keyword check for obvious violations
        const quickCheck = performBasicModeration(content);
        if (!quickCheck.isApproved && quickCheck.severityLevel === "blocked") {
            console.log(`⚡ [MODERATION] Quick-blocked by keyword filter`);
            return quickCheck;
        }

        // Use Vertex AI for deeper analysis
        const model = vertexAI.preview.getGenerativeModel({
            model: "gemini-1.5-flash",
            generationConfig: {
                temperature: 0.1, // Low temperature for consistent moderation
                maxOutputTokens: 256,
            },
        });

        const prompt = `You are a content moderator for AMEN, a Christian social media app.

Analyze this ${contentType}: "${content}"

IMPORTANT: Be lenient and understanding. Christian content often includes words like "hell", "hate", "die", "kill" in appropriate context (e.g., "hate sin", "hell is real", "die to self", "kill your pride"). ONLY block if CLEARLY inappropriate.

Check for SEVERE violations only:
1. Extreme profanity (not mild Christian expressions)
2. Clear hate speech targeting people (not theological discussions)
3. Explicit sexual content (not marriage discussions)
4. Obvious spam or scams (not legitimate sharing)
5. Direct threats of violence (not spiritual warfare language)
6. Mockery of God or faith (not honest questions)

Respond ONLY with valid JSON (no markdown, no code blocks):
{
  "isApproved": true,
  "flaggedReasons": [],
  "severityLevel": "safe",
  "suggestedAction": "approve",
  "confidence": 0.95
}

If content is CLEARLY harmful, set isApproved to false with brief, friendly reasons.
Severity levels: safe, warning, blocked, review

DEFAULT TO APPROVAL when in doubt. Better to approve borderline content than block legitimate Christian discussion.`;

        const result = await model.generateContent(prompt);
        const response = result.response.text();

        // Parse JSON response
        const cleanedResponse = response.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
        const aiResult = JSON.parse(cleanedResponse);

        console.log(`🤖 [MODERATION] AI result: ${aiResult.severityLevel} (confidence: ${aiResult.confidence})`);
        return aiResult;

    } catch (error) {
        console.error(`❌ [MODERATION] AI error:`, error.message);

        // Fallback to basic moderation on error
        const fallback = performBasicModeration(content);
        console.log(`⚠️ [MODERATION] Using keyword fallback: ${fallback.severityLevel}`);
        return fallback;
    }
}

/**
 * Basic keyword-based moderation
 * OPTIMIZED: Less strict, only blocks extreme cases
 */
function performBasicModeration(content) {
    const lowercased = content.toLowerCase();

    // Only check for EXTREME profanity (reduced list)
    const extremeProfanity = ["f***", "s***"];

    for (const pattern of extremeProfanity) {
        if (lowercased.includes(pattern)) {
            return {
                isApproved: false,
                flaggedReasons: ["Inappropriate language"],
                severityLevel: "blocked",
                suggestedAction: "block",
                confidence: 0.8,
            };
        }
    }

    // Pass - let AI handle nuanced cases
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
exports.detectCrisis = onDocumentCreated("crisisDetectionRequests/{requestId}", async (event) => {
        const requestId = event.params.requestId;
        const snap = event.data;
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
exports.deliverBatchedNotifications = onSchedule("every 5 minutes", async (event) => {
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

// ============================================================================
// AI RESOURCE SEARCH
// ============================================================================

/**
 * Triggered when new AI search request is created
 * Analyzes natural language query and returns structured search intent
 */
exports.analyzeSearchIntent = onDocumentCreated("aiSearchRequests/{requestId}", async (event) => {
        const requestId = event.params.requestId;
        const snap = event.data;
        const data = snap.data();

        console.log(`🔍 [AI SEARCH] Processing query: "${data.query}"`);

        try {
            const searchIntent = await analyzeQueryWithAI(data.query);

            // Store result for Swift service to retrieve
            await db.collection("aiSearchResults").doc(requestId).set({
                intent: searchIntent.intent,
                keywords: searchIntent.keywords,
                categories: searchIntent.categories,
                sentiment: searchIntent.sentiment,
                urgency: searchIntent.urgency,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ [AI SEARCH] Query analyzed: ${searchIntent.keywords.join(", ")}`);
        } catch (error) {
            console.error(`❌ [AI SEARCH] Error:`, error);

            // Store fallback result
            await db.collection("aiSearchResults").doc(requestId).set({
                intent: "general",
                keywords: extractBasicKeywords(data.query),
                categories: [],
                sentiment: "neutral",
                urgency: "normal",
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

/**
 * Analyze search query using Vertex AI
 */
async function analyzeQueryWithAI(query) {
    const model = vertexAI.preview.getGenerativeModel({
        model: "gemini-1.5-flash",
        generationConfig: {
            temperature: 0.3,
            maxOutputTokens: 256,
        },
    });

    const prompt = `You are a search assistant for AMEN, a Christian social media app with these resource categories:
- Mental Health (anxiety, depression, counseling)
- Crisis (suicide prevention, crisis lines, emergency help)
- Giving (nonprofits, missions, charitable giving)
- Reading (Bible studies, Christian books)
- Listening (podcasts, sermons, worship)
- Community (church finder, groups, dating)
- Tools (Bible apps, prayer apps, utilities)

Analyze this search query: "${query}"

Extract:
1. User intent (help_seeking, learning, exploring, crisis)
2. Key search terms (words that matter)
3. Relevant categories
4. Sentiment (positive, neutral, distressed)
5. Urgency (low, normal, high)

Respond ONLY with valid JSON (no markdown):
{
  "intent": "help_seeking",
  "keywords": ["anxiety", "help"],
  "categories": ["Mental Health", "Crisis"],
  "sentiment": "distressed",
  "urgency": "high"
}`;

    const result = await model.generateContent(prompt);
    const response = result.response.text();

    // Parse JSON response
    const cleanedResponse = response.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const aiResult = JSON.parse(cleanedResponse);

    console.log(`🤖 [AI SEARCH] Intent: ${aiResult.intent}, Keywords: ${aiResult.keywords.join(", ")}`);

    return aiResult;
}

/**
 * Extract basic keywords from query (fallback)
 */
function extractBasicKeywords(query) {
    const lowercased = query.toLowerCase();
    const keywords = [];

    const terms = [
        "anxiety", "depression", "mental health", "crisis", "suicide",
        "prayer", "bible", "church", "counseling", "therapy",
        "help", "support", "community", "giving", "donate",
        "podcast", "sermon", "book", "study", "worship",
    ];

    for (const term of terms) {
        if (lowercased.includes(term)) {
            keywords.push(term);
        }
    }

    return keywords.length > 0 ? keywords : ["general"];
}

// ============================================================================
// AI NOTE SUMMARIZATION
// ============================================================================

/**
 * Triggered when new note summary request is created
 * Generates structured summary of sermon notes
 */
exports.summarizeChurchNote = onDocumentCreated("noteSummaryRequests/{requestId}", async (event) => {
        const requestId = event.params.requestId;
        const snap = event.data;
        const data = snap.data();

        console.log(`📝 [NOTE SUMMARY] Processing note (\${data.content.length} chars)`);

        try {
            const summary = await generateNoteSummary(data.content);

            // Store result
            await db.collection("noteSummaryResults").doc(requestId).set({
                mainTheme: summary.mainTheme,
                scripture: summary.scripture,
                keyPoints: summary.keyPoints,
                actionSteps: summary.actionSteps,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ [NOTE SUMMARY] Summary generated: ${summary.mainTheme}`);
        } catch (error) {
            console.error(`❌ [NOTE SUMMARY] Error:`, error);

            // Store error fallback
            await db.collection("noteSummaryResults").doc(requestId).set({
                mainTheme: "Unable to generate summary",
                scripture: [],
                keyPoints: ["Please try again or edit your notes"],
                actionSteps: [],
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

/**
 * Generate note summary using Vertex AI
 */
async function generateNoteSummary(content) {
    const model = vertexAI.preview.getGenerativeModel({
        model: "gemini-1.5-flash",
        generationConfig: {
            temperature: 0.4,
            maxOutputTokens: 512,
        },
    });

    const prompt = `You are summarizing sermon notes for a Christian app.

Sermon notes:
"""
${content}
"""

Extract and organize:
1. Main Theme (1 short sentence)
2. Scripture References (list of verses mentioned)
3. Key Points (3-5 main takeaways)
4. Action Steps (practical next steps to apply the teaching)

Respond ONLY with valid JSON (no markdown):
{
  "mainTheme": "Being the light of the world",
  "scripture": ["Matthew 5:14-16", "John 8:12"],
  "keyPoints": [
    "Christians are called to be light in darkness",
    "Our light shines through our actions, not just words",
    "Light exposes truth and guides others to Christ"
  ],
  "actionSteps": [
    "Start a prayer journal this week",
    "Find one way to serve someone in need",
    "Share your testimony with a friend"
  ]
}`;

    const result = await model.generateContent(prompt);
    const response = result.response.text();

    const cleanedResponse = response.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const summary = JSON.parse(cleanedResponse);

    console.log(`🤖 [NOTE SUMMARY] Theme: ${summary.mainTheme}`);

    return summary;
}

// ============================================================================
// AI SCRIPTURE CROSS-REFERENCES
// ============================================================================

/**
 * Triggered when new scripture reference request is created
 * Finds related Bible verses with context
 */
exports.findRelatedScripture = onDocumentCreated("scriptureReferenceRequests/{requestId}", async (event) => {
        const requestId = event.params.requestId;
        const snap = event.data;
        const data = snap.data();

        console.log(`📖 [SCRIPTURE REF] Finding related verses for: ${data.verse}`);

        try {
            const references = await findRelatedVerses(data.verse);

            // Store result
            await db.collection("scriptureReferenceResults").doc(requestId).set({
                references: references,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ [SCRIPTURE REF] Found ${references.length} related verses`);
        } catch (error) {
            console.error(`❌ [SCRIPTURE REF] Error:`, error);

            // Store error fallback
            await db.collection("scriptureReferenceResults").doc(requestId).set({
                references: [],
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

/**
 * Find related scripture verses using Vertex AI
 */
async function findRelatedVerses(verse) {
    const model = vertexAI.preview.getGenerativeModel({
        model: "gemini-1.5-flash",
        generationConfig: {
            temperature: 0.3,
            maxOutputTokens: 384,
        },
    });

    const prompt = `For the Bible verse "${verse}", suggest 4-5 related verses that:
1. Have similar themes or teachings
2. Provide additional context or depth
3. Are commonly studied together
4. Strengthen understanding of the original verse

Return ONLY valid JSON (no markdown) with verse reference, brief description, and relevance score (0-1):
{
  "references": [
    {
      "verse": "Romans 5:8",
      "description": "God's love demonstrated through Christ",
      "relevanceScore": 0.95
    },
    {
      "verse": "1 John 4:9-10",
      "description": "God's love shown by sending His Son",
      "relevanceScore": 0.90
    }
  ]
}`;

    const result = await model.generateContent(prompt);
    const response = result.response.text();

    const cleanedResponse = response.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const data = JSON.parse(cleanedResponse);

    console.log(`🤖 [SCRIPTURE REF] ${verse} → ${data.references.length} related verses`);

    return data.references;
}

// ============================================================================
// AI CHURCH RECOMMENDATIONS
// ============================================================================

/**
 * Triggered when new church recommendation request is created
 * Analyzes user profile and ranks churches by fit
 */
exports.recommendChurches = onDocumentCreated("churchRecommendationRequests/{requestId}", async (event) => {
        const requestId = event.params.requestId;
        const snap = event.data;
        const data = snap.data();

        console.log(`⛪ [CHURCH RECS] Analyzing ${data.churches.length} churches for user`);

        try {
            const recommendations = await generateChurchRecommendations(
                data.userProfile,
                data.churches,
                data.userLocation,
            );

            // Store result
            await db.collection("churchRecommendationResults").doc(requestId).set({
                recommendations: recommendations,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ [CHURCH RECS] Generated ${recommendations.length} recommendations`);
        } catch (error) {
            console.error(`❌ [CHURCH RECS] Error:`, error);

            // Store error fallback
            await db.collection("churchRecommendationResults").doc(requestId).set({
                recommendations: [],
                error: error.message,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });

/**
 * Generate church recommendations using Vertex AI
 */
async function generateChurchRecommendations(userProfile, churches, userLocation) {
    const model = vertexAI.preview.getGenerativeModel({
        model: "gemini-1.5-flash",
        generationConfig: {
            temperature: 0.4,
            maxOutputTokens: 1024,
        },
    });

    const prompt = `You are helping a Christian find the right church.

User Profile:
- Interests: ${userProfile.interests.join(", ")}
- Recent prayer topics: ${userProfile.recentPrayerTopics.join(", ")}
- Recent post topics: ${userProfile.recentPostTopics.join(", ")}
- Family status: ${userProfile.familyStatus || "Not specified"}
- Preferred worship: ${userProfile.preferredWorshipStyle || "Not specified"}

Available churches (within 10 miles):
${JSON.stringify(churches, null, 2)}

Rank the top 5 churches by match score (0-100). For each church:
1. Calculate match score based on alignment with user's interests, needs, and preferences
2. Explain WHY it's a good fit (2-4 specific reasons)
3. Highlight key features (worship style, ministries, community vibe)

Consider:
- Doctrinal alignment
- Ministry offerings (youth, family, singles, recovery, etc.)
- Worship style match
- Community size and vibe
- Proximity (closer is slightly better)

Return ONLY valid JSON (no markdown):
{
  "recommendations": [
    {
      "id": "church_id_123",
      "churchName": "Grace Community Church",
      "address": "123 Main St",
      "distance": 2.1,
      "matchScore": 92,
      "reasons": [
        "Strong youth ministry matches your interest in family programs",
        "Contemporary worship aligns with your preferences",
        "Active community service opportunities",
        "Similar-sized community based on your engagement patterns"
      ],
      "highlights": [
        "Youth group meets Wed 7pm",
        "Contemporary worship with live band",
        "800+ member community",
        "Multiple small group options"
      ],
      "worshipStyle": "Contemporary",
      "size": "Large (800+)"
    }
  ]
}`;

    const result = await model.generateContent(prompt);
    const response = result.response.text();

    const cleanedResponse = response.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const data = JSON.parse(cleanedResponse);

    console.log(`🤖 [CHURCH RECS] Top match: ${data.recommendations[0]?.churchName} (${data.recommendations[0]?.matchScore}%)`);

    return data.recommendations;
}
