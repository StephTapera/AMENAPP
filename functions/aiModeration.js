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

            // Store error result — hold for human review; never auto-approve on failure
            await db.collection("moderationResults").doc(requestId).set({
                isApproved: false,
                flaggedReasons: ["AI processing error — held for human review"],
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

When in doubt about borderline content, use severity "review" and set isApproved to false so a human moderator can decide. Do NOT approve ambiguous content involving sexual themes, minors, or solicitation.`;

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

// ============================================================================
// MODERATION LEXICON
// ============================================================================
//
// ARCHITECTURE NOTES:
//   - These lists are a first-pass signal gate, NOT a final verdict.
//   - A keyword hit sets a category + confidence score (0.7–0.8).
//   - The AI classifier (analyzeContentWithAI) then resolves context:
//       reclaimed language, theological use, quoted/academic text, etc.
//   - Severity tiers map directly to enforcement actions:
//       severe   → block immediately + human review (isApproved: false, "blocked")
//       high     → hold for human review            (isApproved: false, "review")
//       medium   → nudge to rewrite, allow          (isApproved: true,  "warning")
//
// INPUT NORMALISATION is applied before every match to defeat:
//   - leet-speak: f*ck, sh1t, n1gg3r, b!tch
//   - repeated chars: fuuuck, shiiiit
//   - punctuation splitting: f.u.c.k, k-y-s, f*ck
//   - spacing tricks: k y s, f u c k
//   - symbol swaps: @ss, $hit, a$$hole
// ============================================================================

/**
 * Normalise input text before keyword matching.
 * Order of operations matters — leet substitutions run before punctuation strip.
 */
function normalizeText(text) {
    return text
        .toLowerCase()
        .normalize("NFKD")                        // decompose accented chars
        .replace(/0/g, "o")                        // leet: 0 → o
        .replace(/1/g, "i")                        // leet: 1 → i
        .replace(/3/g, "e")                        // leet: 3 → e
        .replace(/4/g, "a")                        // leet: 4 → a
        .replace(/5/g, "s")                        // leet: 5 → s
        .replace(/6/g, "g")                        // leet: 6 → g
        .replace(/7/g, "t")                        // leet: 7 → t
        .replace(/8/g, "b")                        // leet: 8 → b
        .replace(/9/g, "g")                        // leet: 9 → g
        .replace(/@/g, "a")                        // @ → a
        .replace(/\$/g, "s")                       // $ → s
        .replace(/!/g, "i")                        // ! → i
        .replace(/\+/g, "t")                       // + → t
        .replace(/\|/g, "i")                       // | → i
        .replace(/[^a-z0-9\s]/g, " ")             // strip remaining punctuation
        .replace(/(.)\1{2,}/g, "$1$1")            // collapse repeated chars: fuuuck → fuck
        .replace(/\s+/g, " ")                      // collapse whitespace
        .trim();
}

/**
 * Full moderation lexicon organised by category.
 * Each entry is matched against the normalised input.
 * Phrase-level entries (multi-word) take priority over single words.
 */
const moderationLexicon = {

    // ── PROFANITY ─────────────────────────────────────────────────────────────
    // High severity: hold for review. Context can legitimise some (e.g. quoting).
    profanity: [
        "fuck", "fucc", "fuk", "frick",
        "shit", "shat",
        "cunt",
        "bitch",
        "motherfucker", "mofo",
        "bullshit",
        "asshole", "ashole",
        "bastard",
        "dick",
        "pussy",
        "whore",
        "slut",
        "damn", "dammit",
        "piss",
        "cock",
        "ass",
    ],

    // ── HARASSMENT / TARGETED ABUSE ───────────────────────────────────────────
    // Medium severity: nudge to rewrite. Targeted abuse escalates to high.
    harassment: [
        "kill yourself", "kys",
        "drop dead",
        "you should die", "i hope you die",
        "nobody wants you",
        "you are worthless", "youre worthless",
        "go hang yourself",
        "no one likes you",
        "you are pathetic", "youre pathetic",
        "stupid", "idiot", "dumbass", "moron",
        "loser", "trash", "ugly", "worthless",
        "freak", "weirdo",
        "get out of here",
        "you belong in hell",
    ],

    // ── THREATS / VIOLENCE ────────────────────────────────────────────────────
    // Severe: block immediately + human review.
    threats: [
        "i will kill you", "i will kill",
        "im going to kill",
        "i will hurt you", "going to hurt you",
        "ill find you", "i will find you",
        "watch your back",
        "ill shoot you", "i will shoot you", "shoot you",
        "ill stab you", "i will stab you", "stab you",
        "ill beat you", "beat your ass", "beat you up",
        "rape you", "ill rape you",
        "put a bullet", "put hands on you",
        "you will pay for this",
        "i know where you live",
        "pull up on you",
    ],

    // ── HATE SPEECH / SLURS ───────────────────────────────────────────────────
    // Severe: block immediately + human review. Context still evaluated by AI.
    hate: [
        // Racial slurs
        "nigger", "nigga",
        "wetback", "spic", "beaner",
        "chink", "gook", "zipperhead",
        "kike", "hymie",
        "raghead", "towelhead", "sandnigger",
        "cracker", "honky",
        // Anti-LGBTQ slurs
        "faggot", "fag", "dyke", "tranny", "trannies",
        "queer" ,  // context-dependent — AI handles
        // Ableist slurs
        "retard", "retarded",
        // Dehumanising phrases
        "go back to your country",
        "go back where you came from",
        "they should all die",
        "those people dont belong",
        "subhuman",
        "vermin",
        "white supremacy", "heil", "kkk", "nazi",
    ],

    // ── SEXUAL / EXPLICIT CONTENT ─────────────────────────────────────────────
    // High severity: hold for review.
    sexual: [
        "porn", "porno", "pornography",
        "xxx", "nsfw",
        "blowjob", "handjob", "rimjob", "footjob",
        "cum", "cumshot", "creampie",
        "dildo", "vibrator",
        "anal", "anal sex",
        "gangbang", "orgy",
        "nude", "nudes", "naked pics",
        "sex tape",
        "onlyfans", "only fans",
        "fap", "masturbate", "masturbation",
        "erection", "boner",
        "wet pussy", "big cock",
        "strip for me",
        "show me your body",
        "take your clothes off",
        "send me something sexy",
    ],

    // ── MINOR SAFETY / GROOMING ───────────────────────────────────────────────
    // Severe: block immediately + escalate to human review.
    minorSafety: [
        "send nudes", "send pics", "send me pics",
        "show me your body", "take your clothes off",
        "sext", "sexting",
        "meet alone", "meet me alone",
        "dont tell your parents", "don't tell your parents",
        "keep this between us", "keep this secret",
        "dont tell anyone", "don't tell anyone",
        "our little secret",
        "you look mature for your age",
        "you seem mature",
        "age is just a number",
        "prove you are mature",
        "are your parents home",
        "are you home alone",
        "how old are you", "what is your age",
        "you look young",
        "jailbait",
        "underage",
        "minor",
    ],

    // ── SELF-HARM / SUICIDE ───────────────────────────────────────────────────
    // High severity: hold for crisis review + surface crisis resources.
    selfHarm: [
        "kill myself", "killing myself",
        "end my life", "end it all",
        "suicide", "suicidal",
        "cut myself", "cutting myself",
        "self harm", "selfharm",
        "want to die", "i want to die",
        "no reason to live",
        "i cant go on", "i can not go on",
        "take my own life",
        "better off dead",
        "not worth living",
        "overdose on purpose",
    ],

    // ── TRAFFICKING / SEXUAL EXPLOITATION ────────────────────────────────────
    // Severe: block immediately + human review.
    trafficking: [
        "cash app me for pics",
        "venmo for pics", "pay for pics",
        "private meetup", "discreet meetup",
        "pay for play",
        "selling content", "selling pics", "selling videos",
        "incall", "outcall",
        "full service",
        "booking now", "dm for booking",
        "rose for rose",
        "sugar daddy", "sugar baby", "seeking arrangement",
        "fresh girl", "new girl",
        "escort",
        "dm for rates", "rates available",
        "hosting available",
    ],

    // ── DOXXING / PRIVACY VIOLATIONS ──────────────────────────────────────────
    // Severe: block immediately.
    doxxing: [
        "here is their address", "heres their address",
        "leak their number", "post their number",
        "post their info", "posting their info",
        "where do they live",
        "what school do they go to",
        "send me their location",
        "find their address",
        "their home address",
        "expose them",
        "dox", "doxx",
    ],

    // ── FRAUD / SCAMS / IMPERSONATION ─────────────────────────────────────────
    // High severity: hold for review.
    fraud: [
        "verify your account here",
        "send otp", "send the code", "send me your code",
        "investment guaranteed", "guaranteed returns",
        "flip your money", "double your money",
        "claim your prize", "you have won",
        "wire me", "wire transfer",
        "cash app only", "zelle only",
        "i am from support", "official support team",
        "your account will be suspended",
        "click here to verify",
        "dm me to earn",
        "work from home guaranteed",
        "send first",
    ],

    // ── EXTREMISM / ORGANISED VIOLENCE ────────────────────────────────────────
    // Severe: block immediately + human review.
    extremism: [
        "white power", "white pride",
        "racial holy war",
        "great replacement",
        "final solution",
        "death to all",
        "jihad against",
        "infidels must die",
        "race war now",
        "join the movement",          // context-dependent — AI handles
        "manifesto",                  // context-dependent — AI handles
        "lone wolf attack",
        "mass shooting",
        "blow up the",
        "bomb the",
    ],

    // ── DRUGS / ILLEGAL SALES ─────────────────────────────────────────────────
    // High severity: hold for review.
    drugs: [
        "plug", "my plug",
        "ship discreet", "discreet delivery",
        "no prescription needed",
        "meth", "heroin", "fentanyl",
        "crack cocaine", "crack rock",
        "pills for sale", "xans for sale", "percs for sale",
        "lean for sale",
        "weed delivery", "cart delivery",
        "dm to buy",
    ],

    // ── WEAPONS ───────────────────────────────────────────────────────────────
    // Severe when combined with threat language; high on own.
    weapons: [
        "bring the gun",
        "got a strap", "got straps",
        "ghost gun",
        "switch on the", "drum on the",        // gun mod slang
        "put a bullet in",
        "hollow tips",
        "i am armed",
        "pull up strapped",
        "extended clip",
    ],

    // ── SPAM / BOT LANGUAGE ───────────────────────────────────────────────────
    // Medium severity: nudge.
    spam: [
        "dm me to earn",
        "link in bio",
        "follow for follow",
        "f4f", "l4l",
        "comment amen to receive",
        "type amen if you believe",
        "share this to 10 people",
        "guaranteed investment",
        "make money fast",
        "earn from home",
        "click the link below",
    ],
};

// ── SEVERITY ROUTING ──────────────────────────────────────────────────────────
// Maps lexicon category → enforcement tier.
// Categories not listed here default to "high".
const categoryToSeverity = {
    profanity:   "high",
    harassment:  "medium",
    threats:     "severe",
    hate:        "severe",
    sexual:      "high",
    minorSafety: "severe",
    selfHarm:    "high",
    trafficking: "severe",
    doxxing:     "severe",
    fraud:       "high",
    extremism:   "severe",
    drugs:       "high",
    weapons:     "severe",
    spam:        "medium",
};

// Human-readable category labels used in flaggedReasons
const categoryLabels = {
    profanity:   "Inappropriate language",
    harassment:  "Harassment or targeted abuse",
    threats:     "Threat of violence",
    hate:        "Hate speech or slur",
    sexual:      "Explicit sexual content",
    minorSafety: "Minor safety concern",
    selfHarm:    "Self-harm or suicide language",
    trafficking: "Sexual exploitation or trafficking",
    doxxing:     "Privacy violation or doxxing",
    fraud:       "Fraud or scam language",
    extremism:   "Extremist or violent ideology",
    drugs:       "Drug solicitation",
    weapons:     "Weapon reference",
    spam:        "Spam or promotional content",
};

/**
 * Keyword-based moderation with full lexicon, normalisation, and severity routing.
 *
 * Flow:
 *   1. Normalise input (leet-speak, punctuation, repeated chars).
 *   2. Scan all lexicon categories in severity order (severe → high → medium).
 *   3. Return the highest-severity hit found, with category label.
 *   4. If no hit, pass through to AI classifier.
 *
 * Confidence is intentionally ≤0.85 because keyword hits alone are not
 * conclusive — the AI classifier handles reclaimed language, theological
 * context, quotes, and other nuanced cases.
 */
function performBasicModeration(content) {
    const normalized = normalizeText(content);

    // Process in severity order so the worst category always wins
    const severityOrder = ["severe", "high", "medium"];

    // Build reverse map: severity → [{category, term}]
    const hitsBySeverity = {severe: null, high: null, medium: null};

    for (const [category, terms] of Object.entries(moderationLexicon)) {
        const severity = categoryToSeverity[category] || "high";
        if (hitsBySeverity[severity]) continue; // already found a hit at this tier

        for (const term of terms) {
            if (normalized.includes(term)) {
                hitsBySeverity[severity] = {category, term};
                break;
            }
        }
    }

    // Return result for the highest severity hit found
    for (const severity of severityOrder) {
        const hit = hitsBySeverity[severity];
        if (!hit) continue;

        const label = categoryLabels[hit.category] || "Policy violation";
        console.log(`⚡ [MODERATION] ${severity.toUpperCase()} hit [${hit.category}]: "${hit.term}"`);

        if (severity === "severe") {
            return {
                isApproved: false,
                flaggedReasons: [label],
                flaggedCategory: hit.category,
                severityLevel: "blocked",
                suggestedAction: "block",
                confidence: 0.85,
            };
        }

        if (severity === "high") {
            return {
                isApproved: false,
                flaggedReasons: [label],
                flaggedCategory: hit.category,
                severityLevel: "review",
                suggestedAction: "human_review",
                confidence: 0.75,
            };
        }

        if (severity === "medium") {
            return {
                isApproved: true,
                flaggedReasons: [label],
                flaggedCategory: hit.category,
                severityLevel: "warning",
                suggestedAction: "nudge_rewrite",
                confidence: 0.7,
            };
        }
    }

    // No keyword hit — pass through to AI classifier
    return {
        isApproved: true,
        flaggedReasons: [],
        flaggedCategory: null,
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
        const userId = data.userId || null;

        console.log(`📖 [SCRIPTURE REF] Finding related verses for: ${data.verse}`);

        try {
            const references = await findRelatedVerses(data.verse);

            // Store result — include userId so Firestore rules allow the client to poll
            await db.collection("scriptureReferenceResults").doc(requestId).set({
                references: references,
                userId: userId,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ [SCRIPTURE REF] Found ${references.length} related verses`);
        } catch (error) {
            console.error(`❌ [SCRIPTURE REF] Error:`, error);

            // Store error fallback — include userId so client can read the error doc
            await db.collection("scriptureReferenceResults").doc(requestId).set({
                references: [],
                userId: userId,
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
        const userId = data.userId || null;

        console.log(`⛪ [CHURCH RECS] Analyzing ${data.churches.length} churches for user`);

        try {
            const recommendations = await generateChurchRecommendations(
                data.userProfile,
                data.churches,
                data.userLocation,
            );

            // Store result — include userId so Firestore rules allow the client to poll
            await db.collection("churchRecommendationResults").doc(requestId).set({
                recommendations: recommendations,
                userId: userId,
                processedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ [CHURCH RECS] Generated ${recommendations.length} recommendations`);
        } catch (error) {
            console.error(`❌ [CHURCH RECS] Error:`, error);

            // Store error fallback — include userId so client can read the error doc
            await db.collection("churchRecommendationResults").doc(requestId).set({
                recommendations: [],
                userId: userId,
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
