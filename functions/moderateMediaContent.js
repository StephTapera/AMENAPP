/**
 * moderateMediaContent.js
 * AI-powered media moderation for AMEN posts.
 *
 * Called by MediaModerationService.swift when PostDetailView loads a post with images.
 *
 * Input (request.data):
 *   post_type          string   Post category (e.g. "testimony", "prayer")
 *   post_caption       string   The post's text content
 *   user_display_name  string
 *   account_age_days   number
 *   prior_reports      number
 *   media_type         string   "image" | "video"
 *   media_url          string   Primary media URL
 *   media_urls         string[] All media URLs
 *   video_duration_seconds number
 *   has_audio          bool
 *   user_report_count  number   How many times users have reported this post
 *   post_author_id     string
 *   requesting_uid     string
 *
 * Output (JSON):
 *   approved           bool
 *   confidence         number  0.0–1.0
 *   media_type         string
 *   flags              string[]
 *   flag_categories    string[]
 *   severity           "none"|"low"|"medium"|"high"|"critical"
 *   action             "approve"|"flag_for_review"|"blur_pending_review"|"auto_reject"
 *   auto_reject_reason string|null
 *   reviewer_notes     string
 *   safe_to_display    bool
 *   display_with_warning bool
 *   warning_message    string|null
 *   post_context_match bool
 *   post_context_notes string
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

// ── Lazy Vision client ───────────────────────────────────────────────────────
let _vision = null;
function getVision() {
  if (!_vision) {
    const vision = require("@google-cloud/vision");
    _vision = new vision.ImageAnnotatorClient();
  }
  return _vision;
}

// ── Lazy Anthropic ───────────────────────────────────────────────────────────
let _anthropic = null;
function getAnthropic() {
  if (!_anthropic) {
    const Anthropic = require("@anthropic-ai/sdk");
    _anthropic = new Anthropic.default({apiKey: process.env.ANTHROPIC_API_KEY});
  }
  return _anthropic;
}

// ── Severity thresholds ──────────────────────────────────────────────────────
// Vision SafeSearch likelihoods: UNKNOWN(0) VERY_UNLIKELY(1) UNLIKELY(2)
//   POSSIBLE(3) LIKELY(4) VERY_LIKELY(5)
const LIKELIHOOD_SCORE = {
  UNKNOWN: 0, VERY_UNLIKELY: 1, UNLIKELY: 2,
  POSSIBLE: 3, LIKELY: 4, VERY_LIKELY: 5,
};

function likelihoodScore(label) {
  return LIKELIHOOD_SCORE[label] ?? 0;
}

// ── Run Cloud Vision SafeSearch ───────────────────────────────────────────────
async function runVisionSafeSearch(imageUrl) {
  try {
    const [result] = await getVision().safeSearchDetection(imageUrl);
    const safe = result.safeSearchAnnotation || {};
    return {
      adult: likelihoodScore(safe.adult),
      violence: likelihoodScore(safe.violence),
      racy: likelihoodScore(safe.racy),
      medical: likelihoodScore(safe.medical),
      spoof: likelihoodScore(safe.spoof),
      raw: safe,
    };
  } catch (err) {
    console.warn("Vision SafeSearch failed:", err.message);
    return null; // fail open
  }
}

// ── AI context analysis (Claude) ─────────────────────────────────────────────
const MODERATION_SYSTEM_PROMPT = `You are a content moderation AI for AMEN, a faith-based Christian community app.
Your role is to analyze media (images and videos) posted by users and determine
whether they are safe, appropriate, and aligned with community standards before
they are displayed in the app's post detail view.

AMEN is a Spirit-filled Christian social platform where users share testimonies,
prayer requests, worship content, scripture, and community life. The platform
upholds biblical values, mutual edification, and a holy standard of content.

---

### YOUR RESPONSIBILITIES:

1. **SAFETY CHECK** — Flag any content that violates legal or ethical boundaries:
   - CSAM or any exploitation of minors (auto-reject, escalate immediately)
   - Graphic violence, gore, or self-harm imagery
   - Nudity or sexually explicit content
   - Hate speech, racist symbols, or extremist imagery
   - Drug paraphernalia or illegal activity

2. **COMMUNITY STANDARDS CHECK** — Flag content misaligned with a Christian community:
   - Occult symbols, imagery, or messaging
   - Blasphemous or anti-Christian content
   - Content that mocks faith, prayer, or Scripture
   - Alcohol, tobacco, or gambling glorification
   - Content that is divisive, demeaning, or spiritually harmful

3. **CONTEXTUAL ALIGNMENT** — Evaluate whether the content fits the post type:
   - Testimony post: Does the media align with a personal story of God's faithfulness?
   - Prayer request: Is the media appropriate for a vulnerable, prayerful context?
   - Worship/Scripture: Does the media honor the intent of worship or devotion?
   - Community post: Is it wholesome, uplifting, and family-appropriate?

4. **VIDEO-SPECIFIC CHECKS** (stricter pipeline):
   - Evaluate thumbnail/keyframes for visual safety
   - Flag audio descriptions that may reference harmful content
   - Check for embedded text overlays that may violate standards
   - Assess whether the video's pace/editing style is appropriate (no seizure-inducing flashing)
   - Confirm the video has no watermarks from platforms banned in AMEN (adult sites, etc.)

---

### RESPONSE FORMAT:

Always return a JSON object with the following structure:

{
  "approved": true,
  "confidence": 0.95,
  "media_type": "image",
  "flags": [],
  "flag_categories": [],
  "severity": "none",
  "action": "approve",
  "auto_reject_reason": null,
  "reviewer_notes": "",
  "safe_to_display": true,
  "display_with_warning": false,
  "warning_message": null,
  "post_context_match": true,
  "post_context_notes": ""
}

Return ONLY the JSON object. No markdown fences. No explanation outside the JSON.

---

### SEVERITY THRESHOLDS & ACTIONS:

| Severity | Action               | Visibility                |
|----------|----------------------|---------------------------|
| none     | approve              | Display immediately       |
| low      | flag_for_review      | Display immediately       |
| medium   | blur_pending_review  | Blurred until reviewed    |
| high     | flag_for_review      | Hidden until reviewed     |
| critical | auto_reject          | Never displayed, escalate |

---

### CRITICAL RULES:
- Never approve CSAM under any circumstance. Severity is always "critical".
- You are not the final authority. Humans review "high" severity flags.
- When in doubt, flag for review — do not auto-approve ambiguous content.
- Extend grace for cultural expressions of worship (shouting, dancing, tears) —
  these are biblically valid and must never be flagged as concerning.
- Sermons, scripture readings, and prophetic content should be approved unless
  they contain heresy that could harm the community (e.g., prosperity gospel extremism,
  cult-adjacent teaching).
- Political content should be flagged as "low" severity for human review regardless
  of alignment — AMEN is not a political platform.`;

async function runAIContextCheck(data) {
  try {
    const client = getAnthropic();
    const videoLines = data.media_type === "video" ? `
- Video Duration: ${data.video_duration_seconds ?? "unknown"}s
- Video Has Audio: ${data.has_audio ?? "unknown"}` : "";

    const userContent = [
      {
        type: "text",
        text: `Analyze the following media submitted to the AMEN app for post detail display.

POST CONTEXT:
- Post Type: ${data.post_type || "community"}
- Caption: "${data.post_caption || "(none)"}"
- Posted By: ${data.user_display_name || "Unknown"} (Account age: ${data.account_age_days ?? "unknown"} days, Reports: ${data.prior_reports ?? 0})
- Media Type: ${data.media_type}
- Media URL: ${data.media_url}${videoLines}
- Flagged by users: ${data.user_report_count ?? 0} user(s) have reported this post

INSTRUCTIONS:
Evaluate this media against AMEN's safety and community standards.
Return only a valid JSON object matching the required response format.
Do not include any explanation outside the JSON.`,
      },
      {
        type: "image",
        source: {
          type: "url",
          url: data.media_url,
        },
      },
    ];

    const response = await client.messages.create({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 512,
      system: MODERATION_SYSTEM_PROMPT,
      messages: [{role: "user", content: userContent}],
    });

    const rawText = response.content[0]?.text || "{}";
    // Strip any accidental markdown fences
    const jsonText = rawText.replace(/```json?\n?/g, "").replace(/```/g, "").trim();
    return JSON.parse(jsonText);
  } catch (err) {
    console.warn("AI context check failed:", err.message);
    return null; // fail open
  }
}

// ── Merge Vision + AI results ────────────────────────────────────────────────
function synthesizeDecision(visionResult, aiResult, inputData) {
  const flags = [];
  const flagCategories = [];
  let severity = "none";
  let action = "approve";
  let autoRejectReason = null;
  let reviewerNotes = "";
  let displayWithWarning = false;
  let warningMessage = null;

  // === Step 1: Vision SafeSearch hard blocks ===
  if (visionResult) {
    if (visionResult.adult >= 4) {
      flags.push("explicit adult content detected");
      flagCategories.push("nudity");
      severity = "critical";
      action = "auto_reject";
      autoRejectReason = "Explicit adult content";
    } else if (visionResult.adult >= 3) {
      flags.push("possible adult content");
      flagCategories.push("nudity");
      severity = "high";
      action = "blur_pending_review";
      displayWithWarning = true;
      warningMessage = "This image may contain sensitive content.";
    }

    if (visionResult.violence >= 4) {
      flags.push("graphic violence detected");
      flagCategories.push("violence");
      severity = "critical";
      action = "auto_reject";
      autoRejectReason = "Graphic violence";
    } else if (visionResult.violence >= 3 && severity !== "critical") {
      flags.push("possible violence");
      flagCategories.push("violence");
      severity = severity === "none" ? "medium" : severity;
      if (action === "approve") action = "flag_for_review";
    }

    if (visionResult.racy >= 4 && action === "approve") {
      flags.push("racy content");
      flagCategories.push("nudity");
      severity = "medium";
      action = "flag_for_review";
      displayWithWarning = true;
      warningMessage = "This image may be sensitive.";
    }
  }

  // === Step 2: Merge AI analysis ===
  if (aiResult && action !== "auto_reject") {
    const aiSeverityOrder = ["none", "low", "medium", "high", "critical"];
    const aiSevIdx = aiSeverityOrder.indexOf(aiResult.severity || "none");
    const curSevIdx = aiSeverityOrder.indexOf(severity);

    if (aiSevIdx > curSevIdx) severity = aiResult.severity;

    if (aiResult.flags) flags.push(...aiResult.flags.filter((f) => !flags.includes(f)));
    if (aiResult.flag_categories) {
      flagCategories.push(...aiResult.flag_categories.filter((c) => !flagCategories.includes(c)));
    }

    // AI can only escalate action, not downgrade Vision's decision
    const actionOrder = ["approve", "flag_for_review", "blur_pending_review", "auto_reject"];
    const aiActionIdx = actionOrder.indexOf(aiResult.action || "approve");
    const curActionIdx = actionOrder.indexOf(action);
    if (aiActionIdx > curActionIdx) {
      action = aiResult.action;
      autoRejectReason = aiResult.auto_reject_reason || autoRejectReason;
    }

    if (aiResult.display_with_warning) {
      displayWithWarning = true;
      warningMessage = aiResult.warning_message || warningMessage;
    }

    reviewerNotes = aiResult.reviewer_notes || "";
  }

  // === Step 3: Trust signals — boost trust for new accounts with reports ===
  if (inputData.user_report_count >= 3 && action === "approve") {
    action = "flag_for_review";
    reviewerNotes = `${reviewerNotes} [Flagged by ${inputData.user_report_count} users]`.trim();
  }

  const approved = action === "approve";
  const safeToDisplay = action === "approve" || action === "flag_for_review";

  const postContextMatch = aiResult?.post_context_match !== false;
  const postContextNotes = aiResult?.post_context_notes || "";

  // Compute confidence
  let confidence = 0.9;
  if (!visionResult && !aiResult) confidence = 0.3;
  else if (!visionResult || !aiResult) confidence = 0.65;

  return {
    approved,
    confidence,
    media_type: inputData.media_type,
    flags,
    flag_categories: flagCategories,
    severity,
    action,
    auto_reject_reason: autoRejectReason,
    reviewer_notes: reviewerNotes,
    safe_to_display: safeToDisplay,
    display_with_warning: displayWithWarning,
    warning_message: warningMessage,
    post_context_match: postContextMatch,
    post_context_notes: postContextNotes,
  };
}

// ── Main callable ────────────────────────────────────────────────────────────

exports.moderateMediaContent = onCall(
    {region: "us-central1", timeoutSeconds: 60},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "moderate_media", 60, 3600);

      const data = request.data;
      if (!data.media_url) {
        throw new HttpsError("invalid-argument", "media_url is required");
      }

      // Check result cache in Firestore (keyed by post author + URL hash for privacy)
      const cacheKey = `${data.post_author_id}_${Buffer.from(data.media_url).toString("base64").substring(0, 40)}`;
      const cacheRef = db().collection("mediaModerationCache").doc(cacheKey);
      const cached = await cacheRef.get();
      if (cached.exists) {
        const cachedData = cached.data();
        const age = Date.now() - cachedData.cachedAt?.toMillis();
        if (age < 30 * 60 * 1000) { // 30-minute TTL
          console.log(`Cache hit for ${cacheKey}`);
          return cachedData.result;
        }
      }

      // Run Vision SafeSearch and AI context check in parallel
      const [visionResult, aiResult] = await Promise.allSettled([
        runVisionSafeSearch(data.media_url),
        runAIContextCheck(data),
      ]);

      const vision = visionResult.status === "fulfilled" ? visionResult.value : null;
      const ai = aiResult.status === "fulfilled" ? aiResult.value : null;

      const decision = synthesizeDecision(vision, ai, data);

      // Cache the result
      await cacheRef.set({
        result: decision,
        cachedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Write to moderation log if flagged
      if (decision.action !== "approve") {
        await db().collection("mediaModerationLog").add({
          postAuthorId: data.post_author_id,
          requestingUid: uid,
          mediaUrl: data.media_url,
          decision,
          reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return decision;
    },
);

// ── escalateModerationAlert ──────────────────────────────────────────────────

exports.escalateModerationAlert = onCall(
    {region: "us-central1"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {postId, reason, severity} = request.data;
      if (!postId) throw new HttpsError("invalid-argument", "postId required");

      await db().collection("moderationEscalations").add({
        postId,
        reason: reason || "critical_severity",
        severity: severity || "critical",
        reportedBy: uid,
        status: "pending_review",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Flag the post itself
      await db().collection("posts").doc(postId).update({
        flaggedForReview: true,
        moderationEscalated: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => {}); // post may not exist — ignore

      console.log(`Moderation escalation created for post ${postId} (${reason})`);
      return {success: true};
    },
);
