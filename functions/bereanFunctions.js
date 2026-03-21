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

// ─── Secrets ──────────────────────────────────────────────────────────────────
// Store these in Firebase Secret Manager:
//   firebase functions:secrets:set OPENAI_API_KEY
//   firebase functions:secrets:set CLAUDE_API_KEY   (optional — only if using Claude)
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const GOOGLE_VISION_API_KEY = defineSecret("GOOGLE_VISION_API_KEY");
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

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

// ─── BIBLE Q&A ────────────────────────────────────────────────────────────────

exports.bereanBibleQA = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {prompt, maxTokens = 600} = request.data;

      const system = `You are Berean, a knowledgeable, humble biblical AI assistant for the AMEN faith community app.
Answer biblical questions with care, grace, and scriptural grounding.
Always cite specific Bible verses inline (e.g. John 3:16) when making factual or theological claims.
If uncertain, say "I'm not certain" and suggest consulting a pastor or scholar.
Do not fabricate scripture references. Tone: warm, pastoral, non-divisive across denominations.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.5);

      // Extract citations from response (verse patterns like "John 3:16")
      const citations = [];
      const versePattern = /\b([1-3]?\s?[A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s+(\d+):(\d+(?:-\d+)?)\b/g;
      let match;
      while ((match = versePattern.exec(content)) !== null) {
        citations.push(match[0]);
      }

      return makeResponse(content, "openai", "gpt-4o", [...new Set(citations)]);
    },
);

exports.bereanBibleQAFallback = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {prompt, maxTokens = 300} = request.data;

      const system = `You are Berean, a biblical AI assistant. Give a brief, scriptural answer to this question.
Cite at least one Bible verse. Be concise (under 150 words). Tone: warm, non-divisive.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.4);
      return makeResponse(content, "openai", "gpt-4o-fallback");
    },
);

// ─── MORAL COUNSEL ────────────────────────────────────────────────────────────

exports.bereanMoralCounsel = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {prompt, maxTokens = 600} = request.data;

      const system = `You are Berean, a compassionate pastoral AI for the AMEN faith community.
Offer thoughtful, biblically-grounded moral guidance with empathy and grace.
Acknowledge the complexity of real-life moral decisions. Never be harsh or judgmental.
Suggest prayer and seeking counsel from a pastor when appropriate.
Cite scripture where relevant. Avoid being preachy — be a friend and guide.`;

      const content = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, maxTokens, 0.6);
      return makeResponse(content, "openai", "gpt-4o");
    },
);

// ─── BUSINESS / TECH Q&A ──────────────────────────────────────────────────────

exports.bereanBusinessQA = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {prompt, maxTokens = 500} = request.data;

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

// ─── GENERIC PROXY ────────────────────────────────────────────────────────────
// Catch-all for routes that specify vertex/openai/claude directly
// (those providers are proxied through here rather than called on-device)

exports.bereanGenericProxy = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {taskType, prompt, maxTokens = 400} = request.data;

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

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

exports.bereanChatProxy = onCall(
    {
      region: REGION,
      secrets: [ANTHROPIC_API_KEY],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      // Rate limit: 10 Berean calls per user per hour
      const uid = request.auth.uid;
      const hourKey = new Date().toISOString().slice(0, 13); // e.g. "2026-03-21T14"
      const usageRef = admin.firestore().doc(`users/${uid}/bereanUsage/${hourKey}`);
      const usageSnap = await usageRef.get();
      const count = usageSnap.exists ? usageSnap.data().count : 0;
      if (count >= 10) {
        throw new HttpsError("resource-exhausted", "Berean usage limit reached. Try again later.");
      }
      await usageRef.set({count: count + 1}, {merge: true});

      const {systemPrompt, userMessage, maxTokens} = request.data;

      if (!userMessage || typeof userMessage !== "string") {
        throw new HttpsError("invalid-argument", "userMessage is required.");
      }

      const apiKey = ANTHROPIC_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("internal", "ANTHROPIC_API_KEY secret not configured.");
      }

      const fetch = require("node-fetch");
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-haiku-4-5-20251001",
          max_tokens: maxTokens ?? 600,
          system: systemPrompt ?? "",
          messages: [{role: "user", content: userMessage}],
        }),
      });

      const json = await response.json();
      if (!response.ok) {
        throw new HttpsError("internal", json.error?.message ?? "Anthropic API error");
      }
      return {text: json.content?.[0]?.text ?? ""};
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

      // 7. Delete Auth user (must be last)
      await admin.auth().deleteUser(uid);
      return {success: true};
    },
);
