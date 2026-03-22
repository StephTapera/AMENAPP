/**
 * bereanFeatureFunctions.js
 * AMEN App — Berean AI Feature Cloud Functions
 *
 * Functions:
 *   bereanEmbedProxy         — on-demand: OpenAI text-embedding-3-small for semantic search
 *   generateSpiritualTimeline — on-demand: Claude generates spiritual journey milestones
 *   generateStudyGuide       — on-demand: Claude generates small group study guide from note
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret}       = require("firebase-functions/params");
const admin                = require("firebase-admin");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const OPENAI_API_KEY    = defineSecret("OPENAI_API_KEY");
const REGION            = "us-central1";

// ─── Shared helpers ────────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
}

async function callClaude(apiKey, systemPrompt, userContent, maxTokens = 800, temperature = 0.4) {
  const fetch    = (await import("node-fetch")).default;
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method:  "POST",
    headers: {
      "Content-Type":      "application/json",
      "x-api-key":         apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model:      "claude-sonnet-4-6",
      max_tokens: maxTokens,
      system:     systemPrompt,
      messages:   [{role: "user", content: userContent}],
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

// ─── BEREAN EMBED PROXY ───────────────────────────────────────────────────────
// Used by BereanSemanticSearch.swift to embed church notes and queries.
// Returns: { embedding: [number] }

exports.bereanEmbedProxy = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], timeoutSeconds: 30},
    async (request) => {
      requireAuth(request);
      const {text} = request.data;
      if (!text || typeof text !== "string") {
        throw new HttpsError("invalid-argument", "text is required.");
      }

      const fetch    = (await import("node-fetch")).default;
      const response = await fetch("https://api.openai.com/v1/embeddings", {
        method:  "POST",
        headers: {
          "Content-Type":  "application/json",
          "Authorization": `Bearer ${OPENAI_API_KEY.value()}`,
        },
        body: JSON.stringify({
          model: "text-embedding-3-small",
          input: text.slice(0, 8000),  // model limit
        }),
      });

      if (!response.ok) {
        const err = await response.text();
        throw new HttpsError("internal", `OpenAI Embeddings error: ${err}`);
      }

      const json      = await response.json();
      const embedding = json.data?.[0]?.embedding;
      if (!embedding) throw new HttpsError("internal", "No embedding returned.");

      return {embedding};
    },
);

// ─── GENERATE SPIRITUAL TIMELINE ─────────────────────────────────────────────
// Input:  { uid: string, context: string }
// Output: { milestones: [{ id, date, title, description, category, sourceType }] }

exports.generateSpiritualTimeline = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 90},
    async (request) => {
      requireAuth(request);
      const {context} = request.data;

      if (!context?.trim()) {
        return {milestones: []};
      }

      const system = `You are a compassionate spiritual life coach helping a Christian reflect on their faith journey.
Analyze the provided prayer requests and sermon notes to identify meaningful spiritual milestones.
Return a JSON array of 5-8 milestones representing key moments in their spiritual journey.
Each milestone: { "id": "uuid-string", "date": "approximate period e.g. Early 2026", "title": "short title", "description": "1-2 sentences", "category": "answered_prayer|spiritual_growth|challenge|breakthrough|service|community", "sourceType": "prayer|note|testimony" }
Return ONLY valid JSON: { "milestones": [...] }`;

      const raw    = await callClaude(ANTHROPIC_API_KEY.value(), system, context.slice(0, 4000), 1000, 0.5);
      const clean  = raw.replace(/```json|```/g, "").trim();

      let result = {milestones: []};
      try {
        const parsed = JSON.parse(clean);
        result = Array.isArray(parsed) ? {milestones: parsed} : parsed;
      } catch {
        console.error("generateSpiritualTimeline parse error:", raw.slice(0, 200));
      }

      return result;
    },
);

// ─── GENERATE STUDY GUIDE ────────────────────────────────────────────────────
// Input:  { noteTitle: string, noteContent: string }
// Output: { bigIdea, context, discussionQuestions, scriptureDeep, actionSteps, closingPrayer }

exports.generateStudyGuide = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 60},
    async (request) => {
      requireAuth(request);
      const {noteTitle, noteContent} = request.data;

      if (!noteContent?.trim()) {
        throw new HttpsError("invalid-argument", "noteContent is required.");
      }

      const system = `You are a small group curriculum designer for a Christian community.
Generate a small group study guide from this sermon note.
Return JSON only:
{
  "bigIdea": "core message in one memorable sentence",
  "context": "1-2 sentences of theological/historical background",
  "discussionQuestions": [
    { "question": "...", "depth": "opening" },
    { "question": "...", "depth": "opening" },
    { "question": "...", "depth": "exploration" },
    { "question": "...", "depth": "exploration" },
    { "question": "...", "depth": "exploration" },
    { "question": "...", "depth": "application" },
    { "question": "...", "depth": "application" }
  ],
  "scriptureDeep": ["Book Ch:V", "Book Ch:V"],
  "actionSteps": ["specific step 1", "specific step 2", "specific step 3"],
  "closingPrayer": "short group prayer suggestion (2-3 sentences)"
}
Make questions genuinely thoughtful — not surface-level. JSON only, no markdown.`;

      const userContent = `Sermon title: ${noteTitle}\n\nSermon content:\n${noteContent.slice(0, 3000)}`;
      const raw         = await callClaude(ANTHROPIC_API_KEY.value(), system, userContent, 1200, 0.4);
      const clean       = raw.replace(/```json|```/g, "").trim();

      let guide = {};
      try { guide = JSON.parse(clean); } catch {
        console.error("generateStudyGuide parse error:", raw.slice(0, 200));
        throw new HttpsError("internal", "Failed to parse study guide.");
      }

      return guide;
    },
);
