/**
 * bereanFunctions.js
 * AMEN App — Berean AI Cloud Functions
 *
 * All LLM credentials live here server-side. The iOS client calls these
 * via Firebase Functions SDK (BereanOrchestrator.swift → callCloudFunction).
 *
 * Functions exported:
 *   bereanBibleQA            — Biblical Q&A with citations
 *   bereanBibleQAFallback    — Lighter fallback Q&A
 *   bereanMoralCounsel       — Pastoral / moral guidance
 *   bereanBusinessQA         — Faith + business/tech integration
 *   bereanNoteSummary        — Church note structured summarization
 *   bereanScriptureExtract   — Extract scripture references from text
 *   bereanPostAssist         — Post tone rewrite suggestions
 *   bereanCommentAssist      — Comment rewrite / anti-harassment
 *   bereanDMSafety           — DM safety scan (safety-critical, never fail-open)
 *   bereanMediaSafety        — Image/media safety via Cloud Vision
 *   bereanFeedExplainer      — One-sentence feed post explanation
 *   bereanNotificationText   — Non-bait notification copy generation
 *   bereanReportTriage       — Content report harm assessment
 *   bereanRankingLabels      — Addiction-risk / diversity feed labels
 *   bereanGenericProxy       — Generic proxy for vertex/openai/claude routes
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const { callModel } = require("./router/callModel");

// ─── Secrets ──────────────────────────────────────────────────────────────────
// bereanBibleQA + bereanMoralCounsel now route through callModel (Claude via the
// router); they declare ANTHROPIC_API_KEY + NVIDIA_API_KEY + PINECONE secrets.
// Remaining functions that still call OpenAI directly keep OPENAI_API_KEY.
const OPENAI_API_KEY        = defineSecret("OPENAI_API_KEY");
const ANTHROPIC_API_KEY     = defineSecret("ANTHROPIC_API_KEY");
const CLAUDE_API_KEY        = defineSecret("CLAUDE_API_KEY");
const NVIDIA_API_KEY        = defineSecret("NVIDIA_API_KEY");
const PINECONE_API_KEY      = defineSecret("PINECONE_API_KEY");
const PINECONE_HOST         = defineSecret("PINECONE_HOST");
const GOOGLE_VISION_API_KEY = defineSecret("GOOGLE_VISION_API_KEY");

// ─── Shared helpers ───────────────────────────────────────────────────────────

const REGION = "us-central1";

/**
 * Call OpenAI chat completions.
 * @param {string} apiKey
 * @param {string} systemPrompt
 * @param {string} userPrompt
 * @param {number} maxTokens
 * @param {number} temperature
 * @returns {Promise<string>} assistant message content
 */
async function callOpenAI(apiKey, systemPrompt, userPrompt, maxTokens = 512, temperature = 0.4) {
  const fetch = (await import("node-fetch")).default;
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: [
        {role: "system", content: systemPrompt},
        {role: "user", content: userPrompt},
      ],
      max_tokens: maxTokens,
      temperature,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`OpenAI error ${response.status}: ${err}`);
  }

  const json = await response.json();
  return json.choices?.[0]?.message?.content ?? "";
}

/**
 * Call Anthropic Claude Messages API.
 * @param {string} apiKey
 * @param {string} systemPrompt
 * @param {string} userPrompt
 * @param {number} maxTokens
 * @param {number} temperature
 * @returns {Promise<string>} assistant message text
 */
async function callClaude(apiKey, systemPrompt, userPrompt, maxTokens = 512, temperature = 0.5) {
  const fetch = (await import("node-fetch")).default;
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-opus-4-5-20251101",
      system: systemPrompt,
      messages: [{role: "user", content: userPrompt}],
      max_tokens: maxTokens,
      temperature,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude error ${response.status}: ${err}`);
  }

  const json = await response.json();
  return json.content?.[0]?.text ?? "";
}

/**
 * Standard response envelope expected by BereanOrchestrator.swift
 */
function makeResponse(content, provider = "openai", modelVersion = "gpt-4o", citations = []) {
  return {content, provider, modelVersion, citations};
}

/**
 * Validate that the caller is authenticated.
 */
function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in to use Berean AI.");
  }
}

/**
 * Reject callers whose Firestore profile has isMinor === true (COPPA guard).
 * @param {string} uid
 */
async function requireNotMinor(uid) {
  const profile = await admin.firestore().collection('users').doc(uid).get();
  if (profile.data()?.isMinor === true) {
    throw new HttpsError('permission-denied', 'AI features unavailable for users under 13.');
  }
}

/**
 * Per-user hourly rate limiter backed by Firestore atomic transactions.
 * @param {string} uid
 * @param {string} feature
 * @param {number} limitPerHour
 */
async function checkBereanRateLimit(uid, feature, limitPerHour) {
  const hourKey = new Date().toISOString().slice(0, 13); // YYYY-MM-DDTHH
  const ref = admin.firestore()
      .collection('users').doc(uid)
      .collection('bereanUsage').doc(`${feature}_${hourKey}`);
  await admin.firestore().runTransaction(async (t) => {
    const snap = await t.get(ref);
    const count = snap.exists ? (snap.data().count || 0) : 0;
    if (count >= limitPerHour) {
      throw new HttpsError('resource-exhausted', `Hourly limit reached for ${feature}. Try again later.`);
    }
    t.set(ref, { count: count + 1, windowStart: hourKey }, { merge: true });
  });
}

// ─── BIBLE Q&A ────────────────────────────────────────────────────────────────

// ── Migrated to callModel router (Claude, fail_closed, NVIDIA guards, Pinecone retrieval).
// Response format unchanged so BereanOrchestrator.swift requires no iOS update.
exports.bereanBibleQA = onCall(
    {
      region: REGION,
      enforceAppCheck: true,
      secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
    },
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await requireNotMinor(uid);
      await checkBereanRateLimit(uid, 'bible_qa', 20);

      const rawPrompt = request.data?.prompt;
      if (!rawPrompt || typeof rawPrompt !== 'string' || rawPrompt.length > 4000) {
        throw new HttpsError('invalid-argument', 'prompt must be a non-empty string under 4000 characters.');
      }

      const systemPrompt = [
        "You are Berean, a knowledgeable, humble biblical AI assistant for the AMEN faith community app.",
        "Answer biblical questions with care, grace, and scriptural grounding.",
        "Always cite specific Bible verses inline (e.g. John 3:16) when making factual or theological claims.",
        "If uncertain, say \"I'm not certain\" and suggest consulting a pastor or scholar.",
        "Do not fabricate scripture references. Tone: warm, pastoral, non-divisive across denominations.",
        "Clearly separate Scripture from interpretation. Flag uncertain answers.",
      ].join("\n");

      const result = await callModel({
        task: "berean_answer",
        input: rawPrompt,
        systemPrompt,
        userId: uid,
      });

      if (result.blocked) {
        const reason = result.reason === "input_guard_failed"
          ? "Your question could not be processed. Please rephrase and try again."
          : "Berean is unable to answer right now. Please try again shortly.";
        throw new HttpsError("failed-precondition", reason);
      }

      // Extract citations for the response envelope (router already validated they exist).
      const content = result.output ?? "";
      const citations = [];
      const versePattern = /\b([1-3]?\s?[A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s+(\d+):(\d+(?:-\d+)?)\b/g;
      let match;
      while ((match = versePattern.exec(content)) !== null) {
        citations.push(match[0]);
      }

      return makeResponse(content, result.provider ?? "anthropic", "claude-opus-4-7", [...new Set(citations)]);
    },
);

// ── Migrated: uses berean_explain task (Claude, fail_closed, NVIDIA guards, Pinecone retrieval).
exports.bereanBibleQAFallback = onCall(
    {
      region: REGION,
      enforceAppCheck: true,
      secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
    },
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await requireNotMinor(uid);
      await checkBereanRateLimit(uid, 'bible_qa_fallback', 20);

      const rawPrompt = request.data?.prompt;
      if (!rawPrompt || typeof rawPrompt !== 'string' || rawPrompt.length > 4000) {
        throw new HttpsError('invalid-argument', 'prompt must be a non-empty string under 4000 characters.');
      }

      const systemPrompt = [
        "You are Berean, a biblical AI assistant. Give a brief, scriptural answer.",
        "Cite at least one Bible verse (e.g. John 3:16). Be concise (under 150 words). Tone: warm, non-divisive.",
      ].join("\n");

      const result = await callModel({
        task: "berean_explain",
        input: rawPrompt,
        systemPrompt,
        userId: uid,
      });

      if (result.blocked) {
        throw new HttpsError("failed-precondition", "Berean is unable to answer right now. Please try again.");
      }

      return makeResponse(result.output ?? "", result.provider ?? "anthropic", "claude-sonnet-4-6");
    },
);

// ─── MORAL COUNSEL ────────────────────────────────────────────────────────────

// ── Migrated to callModel router (Claude pastoral_reply, fail_closed, NVIDIA output guard).
exports.bereanMoralCounsel = onCall(
    {
      region: REGION,
      enforceAppCheck: true,
      secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY],
    },
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await requireNotMinor(uid);
      await checkBereanRateLimit(uid, 'moral_counsel', 10);

      const rawPrompt = request.data?.prompt;
      if (!rawPrompt || typeof rawPrompt !== 'string' || rawPrompt.length > 4000) {
        throw new HttpsError('invalid-argument', 'prompt must be a non-empty string under 4000 characters.');
      }

      const systemPrompt = [
        "You are Berean, a compassionate pastoral AI for the AMEN faith community.",
        "Offer thoughtful, biblically-grounded moral guidance with empathy and grace.",
        "Acknowledge the complexity of real-life moral decisions. Never be harsh or judgmental.",
        "Suggest prayer and seeking counsel from a pastor when appropriate.",
        "Cite scripture where relevant (e.g. Proverbs 3:5-6). Avoid being preachy — be a friend and guide.",
        "If the person expresses thoughts of self-harm, respond with care and direct them to appropriate support.",
      ].join("\n");

      const result = await callModel({
        task: "pastoral_reply",
        input: rawPrompt,
        systemPrompt,
        userId: uid,
      });

      if (result.blocked) {
        throw new HttpsError("failed-precondition", "Unable to process this request. Please try again.");
      }

      return makeResponse(result.output ?? "", result.provider ?? "anthropic", "claude-opus-4-7");
    },
);

// ─── BUSINESS / TECH Q&A ──────────────────────────────────────────────────────

exports.bereanBusinessQA = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'business_qa', 15);
      const rawPrompt = request.data?.prompt;
      const maxTokens = Math.min(Number(request.data?.maxTokens) || 500, 2000);
      if (!rawPrompt || typeof rawPrompt !== 'string' || rawPrompt.length > 4000) {
        throw new HttpsError('invalid-argument', 'prompt must be a non-empty string under 4000 characters.');
      }
      const prompt = rawPrompt;

      const system = `You are Berean, a faith-integrated business and technology advisor.
Help believers integrate their faith into professional and entrepreneurial decisions.
Provide practical, biblically-informed advice. Cite relevant scripture and principles.
Output as JSON: { faithPrinciple: string, practicalSteps: [string], scripture: string }`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.4);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── NOTE SUMMARY ─────────────────────────────────────────────────────────────

exports.bereanNoteSummary = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'note_summary', 30);
      const {prompt, maxTokens = 400} = request.data;

      const system = `You are Berean, a church note summarization assistant.
Summarize this sermon/church note into structured JSON with these exact keys:
{
  "mainTheme": "string — the central message in one sentence",
  "scripture": ["array of scripture references mentioned"],
  "keyPoints": ["array of 2-4 key takeaways"],
  "actionSteps": ["array of 1-3 personal application steps"]
}
Be concise and faithful to the content. Do not add content not in the notes.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.3);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── SCRIPTURE EXTRACTION ─────────────────────────────────────────────────────

exports.bereanScriptureExtract = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'scripture_extract', 30);
      const {prompt, maxTokens = 300} = request.data;

      const system = `Extract all Bible verse references from the following text.
Output JSON: { "references": ["array of verse references like John 3:16, Romans 8:28"] }
Only include explicit references (book + chapter:verse). Do not infer or guess.
If none are found, return { "references": [] }.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.1);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── POST ASSIST ──────────────────────────────────────────────────────────────

exports.bereanPostAssist = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'post_assist', 20);
      const {prompt, maxTokens = 300} = request.data;

      const system = `You are Berean, a faith community writing assistant.
Review this post draft for tone. The AMEN app is a faith-centered community — posts should be
uplifting, thoughtful, and non-divisive.
Output JSON:
{
  "toneScore": 0.0-1.0,
  "issues": ["array of tone issues found, or empty"],
  "suggestedRewrite": "improved version of the post, or null if tone is already good"
}
Be encouraging, not harsh. Suggestions should feel like a friend's advice, not a correction.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.4);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── COMMENT ASSIST ───────────────────────────────────────────────────────────

exports.bereanCommentAssist = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'comment_assist', 20);
      const {prompt, maxTokens = 200} = request.data;

      const system = `You are Berean, a faith community comment advisor.
Review this comment draft for harassment, rudeness, or divisiveness.
Output JSON:
{
  "isHarassing": true/false,
  "suggestedRewrite": "kinder rewrite, or null if comment is fine",
  "reason": "brief explanation"
}
Be constructive and kind. Most comments are fine — only flag genuine issues.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.3);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── DM SAFETY (SAFETY-CRITICAL) ──────────────────────────────────────────────

exports.bereanDMSafety = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {prompt, maxTokens = 200} = request.data;

      const system = `You are a content safety classifier for a faith-based messaging app.
Analyze this message for: harassment, grooming, trafficking, sexual content, hate speech,
explicit threats, or self-harm encouragement.
This is SAFETY-CRITICAL. When in doubt, flag as unsafe.
Output JSON ONLY:
{
  "isSafe": true/false,
  "riskLevel": "none" | "low" | "medium" | "high" | "critical",
  "categories": ["array of detected risk categories"],
  "reason": "brief explanation"
}`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.1);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── MEDIA SAFETY ─────────────────────────────────────────────────────────────

exports.bereanMediaSafety = onCall(
    {region: REGION, secrets: [GOOGLE_VISION_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {imageUrl} = request.data;

      if (!imageUrl) {
        throw new HttpsError("invalid-argument", "imageUrl is required");
      }

      try {
        const fetch = (await import("node-fetch")).default;
        const response = await fetch(
            `https://vision.googleapis.com/v1/images:annotate?key=${GOOGLE_VISION_API_KEY.value()}`,
            {
              method: "POST",
              headers: {"Content-Type": "application/json"},
              body: JSON.stringify({
                requests: [{
                  image: {source: {imageUri: imageUrl}},
                  features: [{type: "SAFE_SEARCH_DETECTION"}],
                }],
              }),
            },
        );

        if (!response.ok) {
          throw new Error(`Vision API error: ${response.status}`);
        }

        const json = await response.json();
        const safeSearch = json.responses?.[0]?.safeSearchAnnotation ?? {};

        // VERY_LIKELY or LIKELY = unsafe
        const unsafeValues = ["VERY_LIKELY", "LIKELY"];
        const isUnsafe = unsafeValues.includes(safeSearch.adult) ||
                         unsafeValues.includes(safeSearch.violence) ||
                         unsafeValues.includes(safeSearch.racy);

        const result = {
          isSafe: !isUnsafe,
          adult: safeSearch.adult ?? "UNKNOWN",
          violence: safeSearch.violence ?? "UNKNOWN",
          racy: safeSearch.racy ?? "UNKNOWN",
          medical: safeSearch.medical ?? "UNKNOWN",
        };

        return makeResponse(JSON.stringify(result), "google_vision", "cloud-vision-v1");
      } catch (err) {
        // Fail-safe: flag as unsafe on error (never fail-open for media safety)
        console.error("❌ bereanMediaSafety error:", err);
        return makeResponse(
            JSON.stringify({isSafe: false, error: err.message}),
            "google_vision",
            "cloud-vision-v1",
        );
      }
    },
);

// ─── FEED EXPLAINER ───────────────────────────────────────────────────────────

exports.bereanFeedExplainer = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'feed_explainer', 40);
      const {prompt, maxTokens = 100} = request.data;

      const system = `You are Berean, an assistant that explains why content was shown in a faith app feed.
Write ONE short sentence (max 12 words) explaining why this post matches the user's goals.
Be friendly and specific. Example: "Shown because you follow prayer topics."
Do not include quotation marks in your response.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.5);
      return makeResponse(content.trim(), "openai", "gpt-4o");
    },
);

// ─── NOTIFICATION TEXT ────────────────────────────────────────────────────────

exports.bereanNotificationText = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'notification_text', 20);
      const {prompt, maxTokens = 150} = request.data;

      const system = `You write push notification copy for a faith-based social app (AMEN).
Rules: NO engagement bait. NO scarcity hooks ("Don't miss out!"). NO trending pulls.
Notifications must be calm, informative, and faith-appropriate.
Output JSON: { "title": "max 40 chars", "body": "max 100 chars" }`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.4);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── REPORT TRIAGE ────────────────────────────────────────────────────────────

exports.bereanReportTriage = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'report_triage', 20);
      const {prompt, maxTokens = 300} = request.data;

      const system = `You are a content moderation classifier for a faith-based community app.
Assess this user report and classify the severity.
Output JSON:
{
  "severity": "none" | "low" | "medium" | "high" | "critical",
  "categories": ["harassment", "hate_speech", "spam", "misinformation", "explicit", "other"],
  "recommendedAction": "dismiss" | "warn" | "remove" | "suspend" | "escalate",
  "reason": "brief explanation (max 50 words)"
}
Be thorough. This is safety-critical — err on the side of caution.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.2);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── RANKING LABELS ───────────────────────────────────────────────────────────

exports.bereanRankingLabels = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'ranking_labels', 30);
      const {prompt, maxTokens = 200} = request.data;

      const system = `You are a feed ranking classifier for a faith-based social app.
Classify this post for responsible ranking. Do NOT optimize for engagement or session length.
Output JSON:
{
  "addictionRisk": 0.0-1.0,
  "diversityScore": 0.0-1.0,
  "goalRelevance": 0.0-1.0,
  "isRagebait": true/false,
  "hasMisinformation": true/false
}
addictionRisk > 0.7 should be downranked. isRagebait = true should be heavily downranked.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.2);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── SERMON SNAP PROXY ────────────────────────────────────────────────────────
// Accepts: { base64Image: string, prompt: string }
// Returns: { text: string }   (raw JSON text — parsed on device by BereanSnapService)
//
// Setup: firebase functions:secrets:set ANTHROPIC_API_KEY
// Claude claude-sonnet-4-6 is used for multimodal vision (claude-haiku-4-5 does not support images).

exports.sermonSnapProxy = onCall(
    {
      region: REGION,
      secrets: [ANTHROPIC_API_KEY],
      // Allow larger payloads for base64 images (~1MB compressed JPEG → ~1.3MB base64)
      memory: "512MiB",
      timeoutSeconds: 60,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'sermon_snap', 10);

      const {base64Image, prompt} = request.data;

      if (!base64Image || typeof base64Image !== 'string') {
        throw new HttpsError('invalid-argument', 'base64Image is required.');
      }
      if (base64Image.length > 1_400_000) {
        throw new HttpsError('invalid-argument', 'Image too large. Maximum size is approximately 1 MB.');
      }

      const apiKey = ANTHROPIC_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("internal", "ANTHROPIC_API_KEY secret not configured.");
      }

      const fetch = (await import("node-fetch")).default;
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-sonnet-4-6",
          max_tokens: 1024,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: {
                    type: "base64",
                    media_type: "image/jpeg",
                    data: base64Image,
                  },
                },
                {
                  type: "text",
                  text: prompt ?? "Extract sermon notes from this image. Return JSON only.",
                },
              ],
            },
          ],
        }),
      });

      const json = await response.json();
      if (!response.ok) {
        throw new HttpsError("internal", json.error?.message ?? "Anthropic API error");
      }

      return {text: json.content?.[0]?.text ?? ""};
    },
);

// ─── GENERIC PROXY ────────────────────────────────────────────────────────────
// Catch-all for routes that specify vertex/openai/claude directly
// (those providers are proxied through here rather than called on-device)

exports.bereanGenericProxy = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'generic_proxy', 15);
      const taskType = request.data?.taskType;
      const rawPrompt = request.data?.prompt;
      const maxTokens = Math.min(Number(request.data?.maxTokens) || 400, 2000);
      if (!rawPrompt || typeof rawPrompt !== 'string' || rawPrompt.length > 4000) {
        throw new HttpsError('invalid-argument', 'prompt must be a non-empty string under 4000 characters.');
      }
      const prompt = rawPrompt;

      const system = `You are Berean, a faith-community AI assistant for the AMEN app.
Task type: ${taskType ?? "general"}.
Respond helpfully, biblically-grounded, and with pastoral warmth.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.5);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── SMART REPLY ──────────────────────────────────────────────────────────────
// Called by SmartReplySuggestionService.swift via LiveActivity / Reply Assist.
//
//  mode = "smart_reply"   → 3 short, contextual faith-community reply suggestions
//  mode = "tone_rewrite"  → rewrite user's draft with a gentler, more gracious tone
//
// Body: { mode: string, context?: string, draft?: string }
// Returns: { suggestions: [string, string, string] }

exports.bereanSmartReply = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY, CLAUDE_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {mode, context = "", draft = ""} = request.data;

      if (!mode) {
        throw new HttpsError("invalid-argument", "mode is required (smart_reply | tone_rewrite)");
      }

      // ── smart_reply: 3 contextual suggestions via OpenAI structured JSON ──────
      if (mode === "smart_reply") {
        const systemPrompt = `You are a kind, biblically-grounded reply assistant for the AMEN faith community app.
Generate exactly 3 short, warm reply suggestions for the given post or comment context.
Rules:
- Each suggestion must be ≤ 60 characters
- Responses should reflect Christian values: love, encouragement, empathy, truth
- No hashtags, no emoji, no filler phrases ("Of course!", "Sure!")
- Do NOT suggest anything that could be hurtful, divisive, or clickbait
- Return ONLY valid JSON: { "suggestions": ["...", "...", "..."] }`;

        const userPrompt = context
          ? `Reply to this post/comment:\n"${context.slice(0, 300)}"`
          : "Generate 3 warm, general faith-community reply suggestions.";

        let rawContent = "";
        try {
          rawContent = await callOpenAI(OPENAI_API_KEY.value(), systemPrompt, userPrompt, 150, 0.7);
          const parsed = JSON.parse(rawContent);
          const suggestions = (parsed.suggestions ?? [])
            .slice(0, 3)
            .map((s) => String(s).slice(0, 60));

          // Pad to exactly 3 with fallbacks if OpenAI returned fewer
          const fallbacks = ["I hear you.", "Praying for you.", "Thanks for sharing."];
          while (suggestions.length < 3) {
            suggestions.push(fallbacks[suggestions.length]);
          }

          return {suggestions};
        } catch (err) {
          // JSON parse error or OpenAI failure → return safe fallbacks
          console.error("bereanSmartReply smart_reply error:", err, "raw:", rawContent);
          return {suggestions: ["I hear you.", "Praying for you.", "Thanks for sharing."]};
        }
      }

      // ── tone_rewrite: rewrite draft with gentler tone via Claude ─────────────
      if (mode === "tone_rewrite") {
        if (!draft?.trim()) {
          throw new HttpsError("invalid-argument", "draft is required for tone_rewrite mode");
        }

        const systemPrompt = `You are a compassionate writing coach for a Christian social community.
Rewrite the user's draft message with a gentler, more gracious tone while preserving their intent.
Rules:
- Keep the same meaning and length (± 20 words)
- Remove anything harsh, accusatory, or divisive
- Add warmth and empathy without being preachy
- Do NOT add scriptural quotes unless the user included them
- Return ONLY the rewritten text — no explanation, no prefix, no quotes`;

        const userPrompt = `Original draft:\n"${draft.slice(0, 500)}"${context ? `\n\nConversation context:\n"${context.slice(0, 200)}"` : ""}`;

        try {
          const apiKey = CLAUDE_API_KEY.value();
          if (!apiKey) {
            throw new Error("CLAUDE_API_KEY secret not configured");
          }

          const rewritten = await callClaude(apiKey, systemPrompt, userPrompt, 300, 0.5);
          const trimmed = rewritten.trim().slice(0, 500);

          // Return as 3 slots: slot 1 = rewritten, slots 2-3 = shorter fallback variants
          // This matches the { suggestions: [...] } contract on the iOS side
          const shortened = trimmed.split(". ").slice(0, 2).join(". ").trim();
          const concise = trimmed.split(" ").slice(0, 10).join(" ").trim() + "…";

          return {suggestions: [trimmed, shortened || trimmed, concise || trimmed]};
        } catch (err) {
          console.error("bereanSmartReply tone_rewrite error:", err);
          // Graceful degradation: return the original draft as-is
          const fallback = draft.trim().slice(0, 60);
          return {suggestions: [fallback, fallback, fallback]};
        }
      }

      throw new HttpsError("invalid-argument", `Unknown mode: ${mode}. Use smart_reply or tone_rewrite.`);
    },
);

// ============================================================================
// BEREAN CHAT PROXY — routes Berean AI chat through Cloud Functions.
// SETUP: firebase functions:secrets:set ANTHROPIC_API_KEY
// The iOS client (ClaudeService) calls this instead of api.anthropic.com directly.
// ============================================================================

exports.bereanChatProxy = onCall(
    {
      region: REGION,
      secrets: [ANTHROPIC_API_KEY],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      // COPPA guard — reject if caller is flagged as minor
      const callerUid = request.auth?.uid;
      if (!callerUid) throw new HttpsError('unauthenticated', 'Auth required');
      const profile = await admin.firestore().collection('users').doc(callerUid).get();
      if (profile.data()?.isMinor === true) {
        throw new HttpsError('permission-denied', 'AI features unavailable for users under 13');
      }

      // Rate limit: 10 Berean calls per user per hour (atomic transaction — prevents TOCTOU)
      const uid = request.auth.uid;
      const hourKey = new Date().toISOString().slice(0, 13); // e.g. "2026-03-21T14"
      const usageRef = admin.firestore().doc(`users/${uid}/bereanUsage/${hourKey}`);
      await admin.firestore().runTransaction(async (t) => {
        const snap = await t.get(usageRef);
        const count = snap.exists ? (snap.data().count || 0) : 0;
        if (count >= 10) {
          throw new HttpsError('resource-exhausted', 'Hourly limit reached. Try again later.');
        }
        t.set(usageRef, { count: count + 1, windowStart: hourKey }, { merge: true });
      });

      // C-01 SECURITY FIX: System prompt is constructed server-side.
      // The iOS client sends bereanMode (e.g. "shepherd", "scholar", "default")
      // instead of a raw systemPrompt string. This prevents authenticated users
      // from overriding safety guardrails by supplying arbitrary system prompts.
      const BEREAN_SYSTEM_PROMPTS = {
        shepherd: `You are Berean, a wise, compassionate AI companion deeply rooted in Scripture. You offer pastoral guidance grounded in biblical truth. You maintain theological humility on contested doctrinal matters, presenting multiple orthodox perspectives rather than adjudicating. You detect distress signals and gently surface appropriate resources. You never produce content that is sexual, violent, or harmful. You always point to professional help for medical, legal, or psychological crises.`,
        scholar: `You are Berean in Scholar Mode, a rigorous biblical study companion. You provide in-depth exegetical analysis, historical context, and cross-reference insights. You cite sources carefully and acknowledge when a reference is uncertain. You maintain theological humility on contested matters.`,
        default: `You are Berean, a wise and compassionate AI companion grounded in Scripture. You offer thoughtful, biblically-informed responses with pastoral care. You acknowledge the limits of your knowledge and encourage users to consult their pastor or counselor for serious matters.`,
      };

      const {bereanMode, userMessage, maxTokens} = request.data;
      // Build system prompt server-side; ignore any client-supplied systemPrompt.
      const systemPrompt = BEREAN_SYSTEM_PROMPTS[bereanMode] ?? BEREAN_SYSTEM_PROMPTS.default;
      const safeUserMessage = (userMessage ?? '').slice(0, 4000);

      // H-08: Server-side input validation — mirrors iOS PromptPolicyEngine.
      // Cannot be bypassed by modified or non-iOS clients.
      const INJECTION_PATTERNS = [
        /ignore\s+(all\s+)?(previous|prior|above)\s+instructions/i,
        /you\s+are\s+now\s+(?!berean)/i,
        /system:\s*\[/i,
        /new\s+instructions:/i,
        /forget\s+(everything|all)\s+(you|i)/i,
        /<\s*system\s*>/i,
        /\[INST\]/i,
        /###\s*(system|instruction)/i,
      ];
      const inputViolation = INJECTION_PATTERNS.find(p => p.test(safeUserMessage));
      if (inputViolation) {
        console.warn(`[bereanChatProxy] injection attempt blocked for uid=${uid}`);
        throw new HttpsError('invalid-argument', 'Message contains disallowed content.');
      }

      if (!userMessage || typeof userMessage !== "string") {
        throw new HttpsError("invalid-argument", "userMessage is required.");
      }

      const apiKey = ANTHROPIC_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("internal", "ANTHROPIC_API_KEY secret not configured.");
      }

      const fetch = (await import("node-fetch")).default;
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-haiku-4-5-20251001",
          max_tokens: Math.min(Number(maxTokens) || 600, 1500),
          system: systemPrompt,
          messages: [{role: "user", content: safeUserMessage}],
        }),
      });

      const json = await response.json();
      if (!response.ok) {
        throw new HttpsError("internal", json.error?.message ?? "Anthropic API error");
      }

      const text = json.content?.[0]?.text ?? "";

      // ── Scripture reference validation ────────────────────────────────────
      // Extract all verse-pattern references (e.g. "John 3:16", "Ps. 23:1-6")
      // and check them against the recognized canon. The iOS client shows a
      // "verify references in your Bible app" footer when hasUnverifiedReferences=true.
      const versePattern = /\b([1-3]\s)?([A-Za-z]+\.?)\s+(\d{1,3}):(\d{1,3})(?:-(\d{1,3}))?\b/g;
      const canonicalBooks = new Set([
        "genesis", "exodus", "leviticus", "numbers", "deuteronomy",
        "joshua", "judges", "ruth", "samuel", "kings", "chronicles",
        "ezra", "nehemiah", "esther", "job", "psalms", "psalm", "ps",
        "proverbs", "ecclesiastes", "song", "isaiah", "jeremiah",
        "lamentations", "ezekiel", "daniel", "hosea", "joel", "amos",
        "obadiah", "jonah", "micah", "nahum", "habakkuk", "zephaniah",
        "haggai", "zechariah", "malachi",
        "matthew", "mark", "luke", "john", "acts", "romans",
        "corinthians", "galatians", "ephesians", "philippians",
        "colossians", "thessalonians", "timothy", "titus", "philemon",
        "hebrews", "james", "peter", "jude", "revelation",
        // Common abbreviations
        "gen", "exo", "exod", "lev", "num", "deut", "deut",
        "josh", "judg", "sam", "kgs", "chr", "neh", "est",
        "prov", "ecc", "eccl", "eccles", "isa", "jer", "lam",
        "ezek", "dan", "hos", "zech", "mal",
        "matt", "mk", "lk", "jn", "rev", "rom", "gal", "eph",
        "phil", "col", "thess", "tim", "tit", "phlm", "heb", "jas",
        "pet", "jude",
      ]);

      const scriptureReferences = [];
      let hasUnrecognizedBook = false;
      let match;
      while ((match = versePattern.exec(text)) !== null) {
        const bookRaw = match[2].replace(/\.$/, "").toLowerCase();
        const isRecognized = canonicalBooks.has(bookRaw);
        scriptureReferences.push({
          reference: match[0].trim(),
          recognized: isRecognized,
        });
        if (!isRecognized) hasUnrecognizedBook = true;
      }

      // If the AI cited any scripture references, flag them for client-side display
      const hasUnverifiedReferences = scriptureReferences.length > 0;

      return {
        text,
        scriptureReferences,
        hasUnverifiedReferences,
        hasUnrecognizedBook,
      };
    },
);

// ============================================================================
// DELETE ACCOUNT — server-side cascade deletion callable.
// Called by AccountDeletionService when the user confirms account deletion.
// Covers: Auth + Firestore + RTDB + Storage.
// ============================================================================

exports.deleteAccount = onCall(
    {
      region: REGION,
      secrets: [PINECONE_API_KEY, PINECONE_HOST],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const uid = request.auth.uid;
      const db = admin.firestore();
      const rtdb = admin.database();
      const storage = admin.storage();
      const bucket = storage.bucket();

      // 1. Delete Firestore user document
      await db.doc(`users/${uid}`).delete();

      // 2. Delete subcollections
      const subcollections = [
        "followers", "following", "notifications", "prayerRequests",
        "berean_feedback", "compose_suggestion_feedback", "bereanUsage",
        "bookmarkedMedia", "mediaHistory", "readingProgress",
        "completedReflections", "fcmTokens", "blockedUsers",
      ];
      for (const sub of subcollections) {
        const snap = await db.collection(`users/${uid}/${sub}`).get();
        if (snap.docs.length > 0) {
          const batch = db.batch();
          snap.docs.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();
        }
      }


      // 2b. Delete additional subcollections missed in original implementation (H-18)
      // bereanConversations
      const bereanConvsSnap = await db.collection(`users/${uid}/bereanConversations`).get();
      await Promise.all(bereanConvsSnap.docs.map((d) => d.ref.delete()));

      // weeklyRecaps
      const recapsSnap = await db.collection(`users/${uid}/weeklyRecaps`).get();
      await Promise.all(recapsSnap.docs.map((d) => d.ref.delete()));

      // spiritualGraph
      const graphSnap = await db.collection(`users/${uid}/spiritualGraph`).get();
      await Promise.all(graphSnap.docs.map((d) => d.ref.delete()));

      // spiritualHealth
      const healthSnap = await db.collection(`users/${uid}/spiritualHealth`).get();
      await Promise.all(healthSnap.docs.map((d) => d.ref.delete()));

      // wellness (prayerSentiment etc.)
      const wellnessSnap = await db.collection(`users/${uid}/wellness`).get();
      await Promise.all(wellnessSnap.docs.map((d) => d.ref.delete()));

      // H-18 FIX: Delete all Pinecone vectors belonging to this user.
      // Covers: user-interest-embeddings, prayer-partner-pool, testimony-embeddings.
      try {
        const { deleteUserPineconeVectors } = require('./pineconeCleanupFunctions');
        const pcApiKey = PINECONE_API_KEY.value();
        const pcHost   = PINECONE_HOST.value();
        if (pcApiKey && pcHost) {
          const pineconeResults = await deleteUserPineconeVectors(uid, pcApiKey, pcHost);
          console.log(`[deleteAccount] Pinecone vectors deleted for uid=${uid}:`, JSON.stringify(pineconeResults));
        } else {
          console.warn(`[deleteAccount] Pinecone secrets not configured — skipping vector deletion for uid=${uid}`);
        }
      } catch (pcErr) {
        // Log but do not abort account deletion — Pinecone cleanup is best-effort.
        console.error(`[deleteAccount] Pinecone cleanup error for uid=${uid}:`, pcErr.message);
      }

      // 3. Delete user's posts
      const postsSnap = await db.collection("posts").where("authorId", "==", uid).get();
      if (postsSnap.docs.length > 0) {
        const postBatch = db.batch();
        postsSnap.docs.forEach((doc) => postBatch.delete(doc.ref));
        await postBatch.commit();
      }

      // 4. Delete keyBundle
      await db.doc(`keyBundles/${uid}`).delete().catch(() => {});

      // 5. Delete RTDB presence
      await rtdb.ref(`users/${uid}`).remove();

      // 6. Delete Storage files
      try {
        await bucket.deleteFiles({prefix: `users/${uid}/`});
        await bucket.deleteFiles({prefix: `posts/${uid}/`});
      } catch (e) {
        console.warn("Storage cleanup partial:", e);
      }

      // C-13 FIX: Cancel future events owned by this user and notify attendees.
      try {
        const now = admin.firestore.Timestamp.now();
        const ownedEventsSnap = await db
            .collection("faithEvents")
            .where("organizerId", "==", uid)
            .where("startDate", ">", now)
            .get();

        await Promise.all(
            ownedEventsSnap.docs.map(async (eventDoc) => {
              const eventId = eventDoc.id;
              const eventData = eventDoc.data();

              // Soft-delete the event
              await eventDoc.ref.update({
                isDeleted: true,
                cancellationReason: "Organizer account deleted",
                cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
              });

              // Notify all RSVPs for this event
              const rsvpsSnap = await db
                  .collection("eventRSVPs")
                  .where("eventId", "==", eventId)
                  .get();

              await Promise.all(
                  rsvpsSnap.docs.map(async (rsvpDoc) => {
                    const attendeeUid = rsvpDoc.data().userId;
                    if (!attendeeUid || attendeeUid === uid) return;
                    await db
                        .collection("users")
                        .doc(attendeeUid)
                        .collection("notifications")
                        .add({
                          type: "event_cancelled",
                          eventId,
                          eventTitle: eventData.title || "",
                          reason: "Organizer account deleted",
                          read: false,
                          createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                  }),
              );
            }),
        );
      } catch (evtErr) {
        // Log but do not abort account deletion — event cancellation is best-effort.
        console.error(`[deleteAccount] Event cancellation error for uid=${uid}:`, evtErr.message);
      }

      // C-14 FIX: Handle church ownership when the pastor/owner deletes their account.
      try {
        const ownedChurchesSnap = await db
            .collection("churches")
            .where("ownerUid", "==", uid)
            .get();

        await Promise.all(
            ownedChurchesSnap.docs.map(async (churchDoc) => {
              const churchId = churchDoc.id;

              // Look for other admins or pastors in the church_admins collection
              const adminsSnap = await db
                  .collection("church_admins")
                  .where("churchId", "==", churchId)
                  .where("role", "in", ["admin", "pastor"])
                  .get();

              // Filter out the departing owner
              const otherAdmins = adminsSnap.docs.filter(
                  (d) => d.data().uid !== uid,
              );

              if (otherAdmins.length > 0) {
                // Promote the first available admin to owner
                const newOwnerUid = otherAdmins[0].data().uid;
                await churchDoc.ref.update({ownerUid: newOwnerUid});
                console.log(
                    `[deleteAccount] Church ${churchId} ownership transferred to ${newOwnerUid}`,
                );
              } else {
                // No successor — flag for admin review queue
                await churchDoc.ref.update({
                  requiresSuccessor: true,
                  ownerDeleted: true,
                  ownerDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.warn(
                    `[deleteAccount] Church ${churchId} has no successor — flagged for review`,
                );
              }
            }),
        );
      } catch (churchErr) {
        // Log but do not abort account deletion — church cleanup is best-effort.
        console.error(`[deleteAccount] Church ownership cleanup error for uid=${uid}:`, churchErr.message);
      }

      // 7. Delete Auth user (must be last)
      await admin.auth().deleteUser(uid);
      return {success: true};
    },
);

// ─── Sermon Week Plan Generator ───────────────────────────────────────────────
// Called by SermonWeekTransformationService.swift
// Input:  { title, topic, keyVerses, keyPoints, pastorName, date }
// Output: { days: [{ title, prompt, scriptureReference, actionStep, reflectionQuestion }] }
// APP CHECK: Flip to enforceAppCheck: true requires iOS App Check to be initialized first.
// See: https://firebase.google.com/docs/app-check/ios/default-providers
// iOS setup steps: 1) Add AppCheckProviderFactory in AppDelegate, 2) Configure DeviceCheck/AppAttest provider.
exports.bereanSermonWeekPlan = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'sermon_plan', 5);

      const {title, topic, keyVerses, keyPoints, pastorName} = request.data;
      if (!topic || !keyVerses || !keyPoints) {
        throw new HttpsError("invalid-argument", "topic, keyVerses, and keyPoints are required.");
      }

      const dayFocuses = [
        {name: "Identify", desc: "Recognize how this truth applies to your life"},
        {name: "Meditate", desc: "Go deeper into the scripture"},
        {name: "Pray", desc: "Bring this area to God specifically"},
        {name: "Act", desc: "Take a concrete step of obedience"},
        {name: "Share", desc: "Encourage someone with what you've learned"},
        {name: "Reflect", desc: "Evaluate the week's impact on your life"},
      ];

      const systemPrompt = `You are a discipleship content generator for the AMEN app.
Given a Sunday sermon's topic, key verses, and key points, generate a 6-day growth plan (Monday through Saturday).
Each day has a specific focus: ${dayFocuses.map((d) => d.name).join(", ")}.

Return ONLY valid JSON with this structure:
{
  "days": [
    {
      "title": "Day title (focus: topic)",
      "prompt": "The main reflection prompt for the day",
      "scriptureReference": "A relevant verse reference",
      "actionStep": "A concrete action to take",
      "reflectionQuestion": "A journaling question"
    }
  ]
}

Guidelines:
- Each day should build on the previous
- Use actual scripture references (Book Chapter:Verse)
- Action steps should be specific and doable
- Questions should be personal and introspective
- Tone: warm, challenging, pastoral
- Day 1 (Identify): help them see the truth in their life
- Day 2 (Meditate): go deeper into a specific verse
- Day 3 (Pray): guide focused prayer
- Day 4 (Act): give a concrete obedience step
- Day 5 (Share): encourage sharing with others
- Day 6 (Reflect): evaluate the week's growth`;

      const userPrompt = `Sermon: "${title || topic}"
Topic: ${topic}
Key Verses: ${keyVerses.join(", ")}
Key Points: ${keyPoints.join("; ")}
${pastorName ? `Pastor: ${pastorName}` : ""}

Generate the 6-day plan as JSON.`;

      try {
        const content = await callOpenAI(OPENAI_API_KEY.value(), systemPrompt, userPrompt, 1500, 0.6);
        const parsed = JSON.parse(content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim());
        return parsed;
      } catch (e) {
        console.error("bereanSermonWeekPlan error:", e);
        throw new HttpsError("internal", "Failed to generate sermon week plan.");
      }
    },
);

// ─── Spiritual Graph Analysis ─────────────────────────────────────────────────
// Called by PersonalSpiritualGraphService for deeper pattern analysis.
// Input:  { patterns: [{ category, count, avgIntensity, isRecurring }], rhythms: [{ rhythm, engagements, isConsistent }] }
// Output: { insight, suggestedFocus, suggestedVerse, encouragement }
// APP CHECK: Flip to enforceAppCheck: true requires iOS App Check to be initialized first.
// See: https://firebase.google.com/docs/app-check/ios/default-providers
// iOS setup steps: 1) Add AppCheckProviderFactory in AppDelegate, 2) Configure DeviceCheck/AppAttest provider.
exports.bereanSpiritualGraphAnalysis = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');

      // Check consent — user must explicitly opt in before struggle data is sent to OpenAI.
      const db = admin.firestore();
      const consentDoc = await db.doc(`users/${uid}/consents/spiritualAnalysisAI`).get();
      if (!consentDoc.exists || consentDoc.data().granted !== true) {
        throw new HttpsError('failed-precondition',
          'Explicit consent required. Berean will analyze your spiritual growth patterns using AI processed by OpenAI. Enable this in Berean Settings > Privacy.');
      }

      await checkBereanRateLimit(uid, 'spiritual_graph', 5);

      const {patterns, rhythms} = request.data;
      if (!patterns) {
        throw new HttpsError("invalid-argument", "patterns array is required.");
      }

      const safePatterns = (Array.isArray(patterns) ? patterns : [])
          .slice(0, 20)
          .map(p => ({ ...p, category: String(p.category ?? '').slice(0, 100) }));
      const safeRhythms = (Array.isArray(rhythms) ? rhythms : [])
          .slice(0, 20)
          .map(r => ({ ...r, rhythm: String(r.rhythm ?? '').slice(0, 100) }));

      const systemPrompt = `You are a pastoral AI assistant analyzing a user's spiritual growth patterns.
Given a user's struggle patterns and spiritual rhythm data, provide a brief, personalized insight.

Return ONLY valid JSON:
{
  "insight": "A 1-2 sentence personalized observation about their spiritual state",
  "suggestedFocus": "The one area they should focus on this week",
  "suggestedVerse": "One scripture reference that speaks to their situation (Book Chapter:Verse)",
  "encouragement": "A brief word of encouragement grounded in Scripture"
}

Guidelines:
- Be pastoral and warm, never clinical
- Focus on growth, not shame
- If recurring struggles are present, acknowledge them with hope
- If rhythms are consistent, celebrate them
- Always ground suggestions in Scripture
- Never diagnose or label the person`;

      const userPrompt = `Patterns (struggles):
${safePatterns.map((p) => `- ${p.category}: ${p.count} times, intensity ${p.avgIntensity}, recurring: ${p.isRecurring}`).join("\n")}

Rhythms (positive disciplines):
${safeRhythms.map((r) => `- ${r.rhythm}: ${r.engagements} engagements, consistent: ${r.isConsistent}`).join("\n")}

Provide pastoral insight as JSON.`;

      try {
        const content = await callOpenAI(OPENAI_API_KEY.value(), systemPrompt, userPrompt, 500, 0.5);
        const parsed = JSON.parse(content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim());
        return parsed;
      } catch (e) {
        console.error("bereanSpiritualGraphAnalysis error:", e);
        throw new HttpsError("internal", "Failed to analyze spiritual graph.");
      }
    },
);

// ─── Seasonal Prompt Generator ────────────────────────────────────────────────
// Called by SeasonalPromptService / HolidayReflectionJourneyService
// for AI-generated seasonal reflection content.
// Input:  { season, holiday, userContext, promptType }
// Output: { reflection, scripture, actionStep, prayer, followUpQuestion }
// APP CHECK: Flip to enforceAppCheck: true requires iOS App Check to be initialized first.
// See: https://firebase.google.com/docs/app-check/ios/default-providers
// iOS setup steps: 1) Add AppCheckProviderFactory in AppDelegate, 2) Configure DeviceCheck/AppAttest provider.
exports.bereanSeasonalPrompt = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
      await checkBereanRateLimit(uid, 'seasonal_prompt', 10);

      const {season, holiday, userContext, promptType} = request.data;
      if (!season) {
        throw new HttpsError("invalid-argument", "season is required.");
      }

      const systemPrompt = `You are a pastoral AI assistant generating seasonal spiritual content for the AMEN app.
The current Christian season is: ${season}${holiday ? ` (specifically: ${holiday})` : ""}.

Generate a personalized seasonal reflection appropriate for this time in the Christian calendar.

Return ONLY valid JSON:
{
  "reflection": "A 2-3 sentence seasonal reflection connecting the user's situation to the current season",
  "scripture": "A relevant scripture reference (Book Chapter:Verse)",
  "actionStep": "A concrete action the user can take today that connects to the season",
  "prayer": "A short prayer (2-3 sentences) appropriate for the season",
  "followUpQuestion": "A thought-provoking question for further reflection"
}

Guidelines:
- Be warm, pastoral, and seasonally appropriate
- Match the tone to the season (contemplative for Advent, reflective for Lent, joyful for Easter, bold for Pentecost)
- Ground everything in Scripture
- Never be manipulative, guilt-driven, or performance-focused
- Always preserve dignity and grace
- If the user seems isolated, gently encourage real community
- Never replace church or pastoral care with app content
- Keep it reverent, not commercial or gimmicky`;

      const userPrompt = `Season: ${season}
${holiday ? `Holiday: ${holiday}` : ""}
${userContext ? `User context: ${userContext}` : ""}
Prompt type: ${promptType || "reflection"}

Generate a seasonal reflection as JSON.`;

      try {
        const content = await callOpenAI(OPENAI_API_KEY.value(), systemPrompt, userPrompt, 600, 0.6);
        const parsed = JSON.parse(content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim());
        return parsed;
      } catch (e) {
        console.error("bereanSeasonalPrompt error:", e);
        throw new HttpsError("internal", "Failed to generate seasonal prompt.");
      }
    },
);

// ============================================================================
// ROUTE BEREAN CONTEXTUAL ACTION
// Called by BereanContextActionEngine.swift for all in-context study actions.
//
// Implements 7 required actions (all DRAFT-ONLY — never writes to public feeds):
//   explainVerse            — plain-language explanation + historical context
//   scriptureContext        — historical/cultural/author background
//   createStudyPlan         — multi-week study plan draft
//   compareTranslations     — KJV / NIV / ESV / NLT side-by-side
//   convertToChurchNote     — formatted Church Note draft
//   createDiscussionQuestions — 5 discussion questions
//   createPrayer            — prayer draft based on a passage
//
// Also handles legacy BereanContextAction rawValues surfaced by the iOS tray:
//   explain, historicalContext, createStudy, compareScripture,
//   saveToChurchNotes, discussWithGroup, turnIntoPrayer, prayAboutThis
//
// Input:  { action: string, payload: { selectedText, scriptureReference, ... } }
// Output: { draft: string, type: string, scriptureReferences: [string],
//           suggestedActions: [string], answer: string, title: string }
//
// Hard rules:
//   - Returns draft in response. NEVER writes to posts / feeds / public collections.
//   - Auth required. Rate limit: 20 calls/user/hour.
//   - Input validation: scriptureReference ≤ 100 chars, text content ≤ 5000 chars.
// ============================================================================

const CONTEXTUAL_ACTION_RATE_LIMIT = 20;

// Validate & sanitise the incoming payload
function validateContextualPayload(payload) {
  if (!payload || typeof payload !== "object") {
    throw new HttpsError("invalid-argument", "payload is required.");
  }

  const ref    = String(payload.scriptureReference ?? "").trim();
  const text   = String(payload.selectedText ?? "").trim();
  const surr   = String(payload.surroundingText ?? "").trim();
  const notes  = String(payload.notes ?? "").trim();

  if (ref.length > 100) {
    throw new HttpsError("invalid-argument", "scriptureReference must be ≤ 100 characters.");
  }
  const combinedText = [text, surr, notes].join(" ");
  if (combinedText.length > 5000) {
    throw new HttpsError("invalid-argument", "Text content must be ≤ 5000 characters total.");
  }

  return {
    ref,
    text: text.slice(0, 5000),
    surr: surr.slice(0, 1000),
    notes: notes.slice(0, 2000),
  };
}

// Structured log helper
function logContextAction(uid, action, durationMs, success) {
  console.log(JSON.stringify({
    event:      "berean_contextual_action",
    uid,
    action,
    durationMs,
    success,
    ts:         new Date().toISOString(),
  }));
}

// Normalise iOS rawValues to canonical action keys
function normaliseAction(raw) {
  const map = {
    // Direct mappings for required 7 actions
    "explainVerse":             "explainVerse",
    "scriptureContext":         "scriptureContext",
    "createStudyPlan":          "createStudyPlan",
    "compareTranslations":      "compareTranslations",
    "convertToChurchNote":      "convertToChurchNote",
    "createDiscussionQuestions":"createDiscussionQuestions",
    "createPrayer":             "createPrayer",
    // iOS BereanContextAction rawValues → canonical
    "explain":            "explainVerse",
    "historicalContext":  "scriptureContext",
    "createStudy":        "createStudyPlan",
    "compareScripture":   "compareTranslations",
    "saveToChurchNotes":  "convertToChurchNote",
    "discussWithGroup":   "createDiscussionQuestions",
    "turnIntoPrayer":     "createPrayer",
    "prayAboutThis":      "createPrayer",
    // Passthrough for generic ask
    "askBerean":          "askBerean",
    "reflect":            "askBerean",
    "summarize":          "askBerean",
    "simplify":           "askBerean",
  };
  return map[raw] ?? "askBerean";
}

// ── Action handlers ────────────────────────────────────────────────────────────

async function handleExplainVerse(apiKey, ref, text) {
  const subject = ref || text.slice(0, 200);
  const system  = `You are Berean, a knowledgeable biblical study assistant for the AMEN faith community.
Provide a clear, warm, plain-language explanation of the scripture passage requested.
Include:
1. What the verse means in plain language (2-3 sentences)
2. The historical and cultural context when it was written (2-3 sentences)
3. The theological significance and how it applies today (1-2 sentences)
Tone: pastoral, accessible to all backgrounds, non-denominational.
Do NOT fabricate scripture. Cite real supporting verses where helpful.`;

  const user = ref
    ? `Explain this Bible passage in plain language with historical context:\n"${ref}"${text ? `\n\nPassage text:\n"${text}"` : ""}`
    : `Explain this scripture in plain language with historical context:\n"${text}"`;

  const draft = await callOpenAI(apiKey, system, user, 700, 0.5);
  return { draft, type: "explainVerse", title: `Explanation: ${subject.slice(0, 60)}` };
}

async function handleScriptureContext(apiKey, ref, text) {
  const subject = ref || text.slice(0, 200);
  const system  = `You are Berean, a biblical scholar assistant for the AMEN faith community.
Provide detailed historical, cultural, and author context for the requested passage.
Include:
1. Who wrote it, when, and to whom (author context)
2. The historical and cultural setting (2-3 sentences)
3. Where this passage fits in the surrounding narrative (1-2 sentences)
4. How this context shapes our understanding of the text (1-2 sentences)
Tone: scholarly but accessible. Do not fabricate historical claims.`;

  const user = ref
    ? `Provide the historical/cultural background and author context for:\n"${ref}"${text ? `\n\nPassage text:\n"${text}"` : ""}`
    : `Provide the historical/cultural background and author context for this scripture:\n"${text}"`;

  const draft = await callOpenAI(apiKey, system, user, 800, 0.4);
  return { draft, type: "scriptureContext", title: `Context: ${subject.slice(0, 60)}` };
}

async function handleCreateStudyPlan(apiKey, ref, text) {
  const subject = ref || text.slice(0, 100);
  const system  = `You are Berean, a discipleship study plan creator for the AMEN faith community.
Create a structured multi-week personal Bible study plan for the requested topic or book.
Format as a clear, actionable plan with:
- Overview (1-2 sentences about the study goal)
- Week-by-week breakdown (3–4 weeks minimum):
  • Week title
  • Key passages to read
  • Focus question for the week
  • One practical application step
Tone: encouraging, growth-oriented, pastoral. This is a DRAFT for the user to review and personalize.`;

  const user = `Create a multi-week Bible study plan for: "${subject}"${text && text !== subject ? `\n\nAdditional context:\n"${text}"` : ""}`;

  const draft = await callOpenAI(apiKey, system, user, 900, 0.5);
  return { draft, type: "createStudyPlan", title: `Study Plan: ${subject.slice(0, 60)}` };
}

async function handleCompareTranslations(apiKey, ref, text) {
  if (!ref && !text) {
    throw new HttpsError("invalid-argument", "A scripture reference or text is required for compareTranslations.");
  }
  const subject = ref || text.slice(0, 100);
  const system  = `You are Berean, a Bible translation comparison assistant.
Provide a side-by-side comparison of the requested verse in four major English translations:
KJV (King James Version), NIV (New International Version), ESV (English Standard Version), NLT (New Living Translation).

Format your response as:
**KJV:** [text]
**NIV:** [text]
**ESV:** [text]
**NLT:** [text]

**Key Translation Differences:**
[2-3 sentences noting any meaningful differences in word choice or emphasis]

Only provide text for verses you are confident about. If uncertain, note that the user should verify in their Bible app.`;

  const user = `Show the KJV, NIV, ESV, and NLT translations for: "${subject}"`;

  const draft = await callOpenAI(apiKey, system, user, 600, 0.2);
  return { draft, type: "compareTranslations", title: `Translations: ${subject.slice(0, 60)}` };
}

async function handleConvertToChurchNote(apiKey, ref, text, notes) {
  const system  = `You are Berean, a Church Note formatting assistant for the AMEN app.
Convert the provided scripture and user notes into a well-formatted Church Note draft.
Structure:
- **Scripture Reference:** [reference]
- **Main Theme:** [one sentence]
- **Key Insights:** [2–4 bullet points from the notes]
- **Personal Application:** [1–2 sentences]
- **Prayer Point:** [one sentence prayer prompt]

This is a DRAFT for the user to review and personalize before saving. Do not add content not present in the input.`;

  const user = `Create a Church Note draft from:
Scripture: "${ref || "Not specified"}"
Passage text: "${text}"
${notes ? `User notes:\n"${notes}"` : ""}`;

  const draft = await callOpenAI(apiKey, system, user, 600, 0.3);
  return { draft, type: "convertToChurchNote", title: "Church Note Draft" };
}

async function handleCreateDiscussionQuestions(apiKey, ref, text) {
  const subject = ref || text.slice(0, 100);
  const system  = `You are Berean, a small group discussion facilitator for the AMEN faith community.
Generate exactly 5 thoughtful discussion questions for the provided scripture passage.
Questions should:
1. Open with an observation question (what does the text say?)
2. Include an interpretation question (what does it mean?)
3. Include a context question (why did the author write this?)
4. Include an application question (how does this apply to life?)
5. Close with a personal reflection question (what does this mean for you personally?)
Tone: warm, inclusive, non-divisive. These are DRAFT questions for a group leader to adapt.`;

  const user = ref
    ? `Generate 5 discussion questions for: "${ref}"${text ? `\n\nPassage text:\n"${text}"` : ""}`
    : `Generate 5 discussion questions for this scripture:\n"${text}"`;

  const draft = await callOpenAI(apiKey, system, user, 500, 0.5);
  return { draft, type: "createDiscussionQuestions", title: `Discussion Questions: ${subject.slice(0, 60)}` };
}

async function handleCreatePrayer(apiKey, ref, text) {
  const subject = ref || text.slice(0, 100);
  const system  = `You are Berean, a prayer writing companion for the AMEN faith community.
Write a personal, heartfelt prayer inspired by the provided scripture passage.
The prayer should:
- Open with adoration/acknowledgment of God (1-2 sentences)
- Include confession or thanksgiving rooted in the passage (1-2 sentences)
- Offer specific intercession or petition tied to the scripture (2-3 sentences)
- Close with a commitment or surrender statement (1-2 sentences)
Tone: warm, personal, non-denominational, conversational with God.
This is a DRAFT prayer for the user to personalize before using.`;

  const user = ref
    ? `Write a prayer based on: "${ref}"${text ? `\n\nPassage text:\n"${text}"` : ""}`
    : `Write a prayer based on this scripture:\n"${text}"`;

  const draft = await callOpenAI(apiKey, system, user, 400, 0.6);
  return { draft, type: "createPrayer", title: `Prayer: ${subject.slice(0, 60)}` };
}

async function handleAskBerean(apiKey, action, ref, text) {
  const system = `You are Berean, a wise and compassionate biblical AI assistant for the AMEN faith community.
Action requested: ${action}.
Respond helpfully and biblically, with pastoral warmth. Cite scripture where relevant.`;
  const user   = [ref ? `Scripture: "${ref}"` : "", text ? `Text: "${text}"` : ""].filter(Boolean).join("\n\n") ||
                 "Please offer a biblical reflection.";
  const draft  = await callOpenAI(apiKey, system, user, 600, 0.5);
  return { draft, type: action, title: "Berean Study" };
}

// ── Main callable ─────────────────────────────────────────────────────────────

exports.routeBereanContextualAction = onCall(
    {
      region:          REGION,
      secrets:         [OPENAI_API_KEY],
      enforceAppCheck: true,
      timeoutSeconds:  60,
    },
    async (request) => {
      // 1. Auth check
      requireAuth(request);
      const uid = request.auth.uid;

      // 2. Rate limit: 20 calls/user/hour
      await checkBereanRateLimit(uid, "contextual_action", CONTEXTUAL_ACTION_RATE_LIMIT);

      // 3. Input validation
      const { action: rawAction, payload: rawPayload } = request.data;

      if (!rawAction || typeof rawAction !== "string") {
        throw new HttpsError("invalid-argument", "action is required.");
      }
      if (rawAction.length > 100) {
        throw new HttpsError("invalid-argument", "action must be ≤ 100 characters.");
      }

      const { ref, text, surr, notes } = validateContextualPayload(rawPayload);
      const action = normaliseAction(rawAction);

      const t0     = Date.now();
      const apiKey = OPENAI_API_KEY.value();

      let result;
      try {
        switch (action) {
          case "explainVerse":
            result = await handleExplainVerse(apiKey, ref, text || surr);
            break;
          case "scriptureContext":
            result = await handleScriptureContext(apiKey, ref, text || surr);
            break;
          case "createStudyPlan":
            result = await handleCreateStudyPlan(apiKey, ref, text || surr);
            break;
          case "compareTranslations":
            result = await handleCompareTranslations(apiKey, ref, text || surr);
            break;
          case "convertToChurchNote":
            result = await handleConvertToChurchNote(apiKey, ref, text || surr, notes);
            break;
          case "createDiscussionQuestions":
            result = await handleCreateDiscussionQuestions(apiKey, ref, text || surr);
            break;
          case "createPrayer":
            result = await handleCreatePrayer(apiKey, ref, text || surr);
            break;
          default:
            result = await handleAskBerean(apiKey, rawAction, ref, text || surr);
        }
      } catch (err) {
        logContextAction(uid, action, Date.now() - t0, false);
        // Re-throw HttpsErrors as-is; wrap everything else
        if (err instanceof HttpsError) throw err;
        console.error("[routeBereanContextualAction] LLM error:", err.message);
        throw new HttpsError("internal", "Berean could not complete this action. Please try again.");
      }

      logContextAction(uid, action, Date.now() - t0, true);

      // 4. Return draft envelope — NEVER writes to public Firestore collections.
      //    The iOS client stores this locally until the user explicitly saves/posts it.
      return {
        id:                  `berean_${uid}_${Date.now()}`,
        draft:               result.draft,
        type:                result.type,
        title:               result.title,
        answer:              result.draft,        // alias for BereanContextActionResult.answer
        scriptureReferences: [],                  // client-side verse extraction handles this
        suggestedActions:    [],
        safetyNotice:        null,
        threadId:            null,
      };
    },
);
