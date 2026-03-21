/**
 * bereanShield.js
 * AMEN App — Berean Shield & Compass Cloud Functions
 *
 * Functions exported:
 *   bereanShieldAnalyze  — analyzes a claim for truth / sourcing / consensus / distortion / motive
 *   bereanCompassAnalyze — analyzes a DM conversation for manipulation arc patterns
 *
 * Both require an authenticated Firebase user (auth context checked).
 * Uses Anthropic Claude claude-sonnet-4-6 via @anthropic-ai/sdk.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

// ─── Shared helpers ────────────────────────────────────────────────────────────

/** Lazy Anthropic client — instantiated only when the function cold-starts with a request. */
let _anthropic = null;
function getAnthropicClient(apiKey) {
  if (!_anthropic) {
    const Anthropic = require("@anthropic-ai/sdk");
    _anthropic = new Anthropic.default({ apiKey });
  }
  return _anthropic;
}

/** Ensure user is authenticated. Throws HttpsError if not. */
function requireAuth(auth) {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "You must be signed in to use this feature.");
  }
}

/** Safe JSON extraction from Claude response text. */
function extractJSON(text) {
  try {
    // Strip markdown code fences if present
    const stripped = text
      .replace(/```json\s*/gi, "")
      .replace(/```\s*/g, "")
      .trim();
    return JSON.parse(stripped);
  } catch {
    return null;
  }
}

// ─── bereanShieldAnalyze ──────────────────────────────────────────────────────

exports.bereanShieldAnalyze = onCall(
  {
    secrets: [CLAUDE_API_KEY],
    timeoutSeconds: 60,
    memory: "256MiB",
    region: "us-central1",
  },
  async (request) => {
    requireAuth(request.auth);

    const { claim } = request.data || {};
    if (!claim || typeof claim !== "string" || claim.trim().length === 0) {
      throw new HttpsError("invalid-argument", "A non-empty claim is required.");
    }

    const trimmedClaim = claim.trim().slice(0, 1000); // cap at 1000 chars

    const systemPrompt = `You are Berean Shield, a faith-rooted truth-verification layer for a Christian social app.

Your job is to analyze a claim, headline, or quote across five dimensions and return a structured JSON object.

IMPORTANT rules:
- Be conservative. When in doubt, lean toward "unverifiable" rather than "false".
- Do not fabricate sources or events. If you are unsure of sourcing, say so.
- Be concise. Each dimension answer should be 1-3 sentences maximum.
- Do not include political bias or partisan framing.
- Return ONLY a valid JSON object, no markdown, no explanation outside the JSON.

Return this exact JSON structure:
{
  "sourcing": "Where did this claim originate? Identify the original source if possible.",
  "consensus": "What do credible sources generally agree on about this claim?",
  "distortion": "How far has this claim drifted from the original source or context, if at all?",
  "motive": "Who might benefit from this claim spreading, and why might that be relevant?",
  "verdict": "verified|likely_true|misleading|likely_false|false|unverifiable",
  "verdictExplanation": "2-3 sentence summary explaining the verdict.",
  "confidence": 0.0
}

Verdict definitions:
- verified: Claim is confirmed by multiple credible primary sources.
- likely_true: Claim appears accurate but lacks complete primary source verification.
- misleading: Claim has a factual kernel but is framed in a way that distorts meaning.
- likely_false: Evidence suggests the claim is probably inaccurate.
- false: Claim is directly contradicted by verifiable primary sources.
- unverifiable: Cannot be assessed without more information or access to sources.

Confidence is a float from 0.0 to 1.0 reflecting how certain you are in your verdict.`;

    const userMessage = `Please analyze this claim:\n\n"${trimmedClaim}"`;

    try {
      const anthropic = getAnthropicClient(CLAUDE_API_KEY.value());

      const message = await anthropic.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 800,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      });

      const rawText = message.content[0]?.text || "";
      const parsed = extractJSON(rawText);

      if (!parsed || !parsed.verdict || !parsed.verdictExplanation) {
        throw new HttpsError("internal", "Failed to parse Shield analysis response.");
      }

      // Normalize and validate fields
      const validVerdicts = ["verified", "likely_true", "misleading", "likely_false", "false", "unverifiable"];
      if (!validVerdicts.includes(parsed.verdict)) {
        parsed.verdict = "unverifiable";
      }

      const confidence = typeof parsed.confidence === "number"
        ? Math.max(0, Math.min(1, parsed.confidence))
        : 0.5;

      return {
        sourcing: parsed.sourcing || "Sourcing information unavailable.",
        consensus: parsed.consensus || "Consensus data unavailable.",
        distortion: parsed.distortion || "Distortion analysis unavailable.",
        motive: parsed.motive || "Motive analysis unavailable.",
        verdict: parsed.verdict,
        verdictExplanation: parsed.verdictExplanation,
        confidence,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[bereanShieldAnalyze] Error:", err.message);
      throw new HttpsError("internal", "Shield analysis failed. Please try again.");
    }
  }
);

// ─── bereanCompassAnalyze ─────────────────────────────────────────────────────

exports.bereanCompassAnalyze = onCall(
  {
    secrets: [CLAUDE_API_KEY],
    timeoutSeconds: 45,
    memory: "256MiB",
    region: "us-central1",
  },
  async (request) => {
    requireAuth(request.auth);

    const { messages } = request.data || {};
    if (!Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "A non-empty messages array is required.");
    }

    // Validate and sanitize message payloads
    const sanitizedMessages = messages
      .filter(
        (m) =>
          m &&
          typeof m.text === "string" &&
          typeof m.isFromOther === "boolean"
      )
      .slice(0, 100) // cap at 100 messages
      .map((m) => ({
        text: m.text.trim().slice(0, 200), // already trimmed on client but enforce here
        isFromOther: m.isFromOther,
      }));

    if (sanitizedMessages.length === 0) {
      return { stage: 0, patterns: [], intervention: "", resources: [] };
    }

    const systemPrompt = `You are Berean Compass, a privacy-first safety layer embedded in a faith-based social app.

Your job is to detect early-stage manipulation patterns in a DM conversation between a user and another person.
You are analyzing messages marked "isFromOther: true" for manipulation patterns, and messages marked "isFromOther: false" to understand how the user is responding.

CRITICAL rules:
- Be VERY conservative. Many false negatives are strongly preferred over false positives.
- Only flag clear, unmistakable patterns. A single message is almost never enough.
- Stage 1 (Isolation): Look for repeated language that positions the other person as uniquely understanding, subtly discourages contact with family or other friends.
- Stage 2 (Identity Shift): Look for language that frames the user as "special", "not like others", or "chosen" in a way that builds exclusivity and flattery toward dependency.
- Stage 3+ exists but should return stage 0 — Compass only intervenes at stages 1-2.
- NEVER reference specific message content in your response. Only describe abstract patterns.
- Return ONLY valid JSON, no markdown, no explanation outside the JSON.

Return this exact JSON structure:
{
  "stage": 0,
  "patterns": [],
  "intervention": "",
  "resources": []
}

If stage 1 or 2 detected:
{
  "stage": 1,
  "patterns": ["Short, non-alarming description of an observed pattern (no quotes from messages)"],
  "intervention": "A single gentle, non-accusatory sentence to show the user. E.g. 'You've been talking with this person for a while — it's always good to check in with someone you trust.'",
  "resources": [
    { "title": "Talk to a Trusted Adult", "icon": "person.crop.circle.badge.checkmark", "deepLink": "amen://crisis-resources" }
  ]
}

Stage 0 means no manipulation pattern detected. Return stage 0 for any ambiguous situation.`;

    // Build a summarized transcript for the model (no user identifiers)
    const transcript = sanitizedMessages
      .map((m, i) => `[${m.isFromOther ? "Other" : "User"}] ${m.text}`)
      .join("\n");

    const userMessage = `Analyze this conversation transcript for manipulation patterns:\n\n${transcript}`;

    try {
      const anthropic = getAnthropicClient(CLAUDE_API_KEY.value());

      const message = await anthropic.messages.create({
        model: "claude-sonnet-4-6",
        max_tokens: 600,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      });

      const rawText = message.content[0]?.text || "";
      const parsed = extractJSON(rawText);

      if (!parsed || typeof parsed.stage !== "number") {
        // Fail-safe: return no signal on parse failure
        return { stage: 0, patterns: [], intervention: "", resources: [] };
      }

      // Only allow stages 1–2 to propagate to the client
      const stage = parsed.stage === 1 || parsed.stage === 2 ? parsed.stage : 0;

      return {
        stage,
        patterns: Array.isArray(parsed.patterns) ? parsed.patterns.slice(0, 5) : [],
        intervention: typeof parsed.intervention === "string" ? parsed.intervention : "",
        resources: Array.isArray(parsed.resources) ? parsed.resources.slice(0, 3) : [],
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[bereanCompassAnalyze] Error:", err.message);
      // Fail-safe: compass failure should never break chat
      return { stage: 0, patterns: [], intervention: "", resources: [] };
    }
  }
);
