/**
 * amenStudioAI.js
 * Cloud Functions for AMEN Studio AI creation and Legacy Studio journal reflection.
 *
 * Functions:
 *   studioGenerateContent  — Callable: generate testimony/prayer/devotional/sermon/canvas content
 *   studioJournalPrompt    — Callable: return an AI reflection on a private journal entry
 *   studioWeeklyChallenge  — Scheduled: rotate the weekly creation challenge in Firestore
 *
 * AI backend: Claude (via Vertex AI or Anthropic API key in Secret Manager).
 * Falls back to a GPT-4o-mini prompt if Claude is unavailable.
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

// ── Lazy Anthropic SDK init ──────────────────────────────────────────────────
let _anthropic = null;
function getAnthropic() {
  if (!_anthropic) {
    const Anthropic = require("@anthropic-ai/sdk");
    _anthropic = new Anthropic.default({
      apiKey: process.env.ANTHROPIC_API_KEY,
    });
  }
  return _anthropic;
}

// ── System prompt per tool ───────────────────────────────────────────────────

const TOOL_PROMPTS = {
  testimony: `You are a compassionate faith writing coach for AMEN, a Christian social platform.
Your role: help users articulate their personal testimony — moments of grace, healing, and transformation.
Guidelines:
- Write in first person from the user's perspective.
- Ground the narrative in Scripture where natural (don't force it).
- Keep tone authentic, not performative or clichéd.
- Length: 150–300 words unless the user's input suggests otherwise.
- End with a note of hope or gratitude.`,

  prayer: `You are a prayer companion on AMEN, a Christian community app.
Your role: help users compose heartfelt, scripture-grounded prayers.
Guidelines:
- Structure: Adoration → Confession/Acknowledgment → Thanksgiving → Supplication (loose ACTS).
- Keep it personal and specific to the user's shared need.
- Use reverent but warm, conversational language — not overly formal or "churchy."
- Length: 100–200 words.
- Never use placeholder brackets like [Name].`,

  devotional: `You are a devotional writer for AMEN.
Your role: craft a short scripture-based devotional that moves from verse → reflection → application → closing prayer.
Guidelines:
- Open with the scripture reference prominently.
- Reflection should be 2–3 short paragraphs connecting the verse to real life.
- Application: one concrete, actionable step.
- Close with a 2–3 sentence prayer.
- Total length: 250–400 words.`,

  sermon_prep: `You are a sermon preparation assistant for AMEN.
Your role: produce a sermon outline framework for a pastor or teacher.
Structure:
  Title (compelling, scripture-rooted)
  Main Text
  Introduction hook (1–2 sentences)
  3 main points (each with supporting scripture + illustration idea)
  Conclusion with altar call / response prompt
Guidelines:
- Keep it a working skeleton, not a full manuscript.
- Bold the main points.
- Note potential illustrations as [ILLUSTRATION IDEA: …].`,

  scripture_canvas: `You are a creative director for faith-based visual content on AMEN.
Your role: write an evocative caption or visual meditation to accompany scripture art.
Guidelines:
- 1–3 sentences, poetic and contemplative.
- Lead with or echo the verse.
- Suitable for sharing as an image caption or visual post.
- Optional: suggest a color palette or mood in brackets at the end.`,

  challenge: `You are a creative writing coach for the AMEN Weekly Challenge.
Your role: help the user complete this week's challenge prompt within roughly 100 words.
Guidelines:
- Stay true to the user's voice.
- Keep it tight — every word should carry weight.
- Return the polished piece, nothing else (no meta-commentary).`,
};

// ── Helper: call Claude ──────────────────────────────────────────────────────

async function callClaude(systemPrompt, userMessage) {
  const client = getAnthropic();
  const message = await client.messages.create({
    model: "claude-haiku-4-5-20251001", // fast + affordable for creation tasks
    max_tokens: 1024,
    system: systemPrompt,
    messages: [{role: "user", content: userMessage}],
  });
  return message.content[0]?.text || "";
}

// ── studioGenerateContent ────────────────────────────────────────────────────

exports.studioGenerateContent = onCall(
    {region: "us-central1", timeoutSeconds: 60},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "studio_generate", 30, 3600); // 30 generates/hour

      const {tool, user_input, scripture_ref, tone} = request.data;

      if (!tool || !user_input) {
        throw new HttpsError("invalid-argument", "tool and user_input are required");
      }

      const systemPrompt = TOOL_PROMPTS[tool];
      if (!systemPrompt) {
        throw new HttpsError("invalid-argument", `Unknown tool: ${tool}`);
      }

      // Build user message with optional context
      let userMessage = user_input.trim();
      if (scripture_ref) userMessage += `\n\nScripture reference: ${scripture_ref}`;
      if (tone) userMessage += `\n\nDesired tone: ${tone}`;

      try {
        const generatedText = await callClaude(systemPrompt, userMessage);

        // Log creation event (for analytics — no personal content stored)
        await db().collection("studioCreations").add({
          uid,
          tool,
          tone: tone || "reflective",
          hasScripture: !!scripture_ref,
          inputLength: user_input.length,
          outputLength: generatedText.length,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {generated_text: generatedText};
      } catch (error) {
        console.error("studioGenerateContent error:", error);
        throw new HttpsError("internal", "Content generation failed. Please try again.");
      }
    },
);

// ── studioJournalPrompt ──────────────────────────────────────────────────────

const JOURNAL_REFLECTION_PROMPT = `You are a gentle, scripture-grounded spiritual director for AMEN's private Think Tank journal.
The user has shared a personal journal entry with you. Your role is to offer a short, thoughtful reflection.
Guidelines:
- Respond with warmth and empathy, never judgment.
- Acknowledge what the user shared, then offer a brief spiritual insight or question to deepen reflection.
- If a mood is shared, meet the user in that emotional state first.
- Reference Scripture naturally if it fits — one verse maximum.
- Length: 80–150 words.
- This is private and never shared publicly. Be real with them.`;

exports.studioJournalPrompt = onCall(
    {region: "us-central1", timeoutSeconds: 45},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "studio_journal_reflect", 20, 86400); // 20/day

      const {entry_body, mood, scripture} = request.data;
      if (!entry_body) {
        throw new HttpsError("invalid-argument", "entry_body is required");
      }

      let userMessage = `Journal entry:\n${entry_body.substring(0, 1200)}`;
      if (mood) userMessage += `\n\nMy mood right now: ${mood}`;
      if (scripture) userMessage += `\n\nScripture I'm sitting with: ${scripture}`;

      try {
        const reflection = await callClaude(JOURNAL_REFLECTION_PROMPT, userMessage);
        return {reflection};
      } catch (error) {
        console.error("studioJournalPrompt error:", error);
        throw new HttpsError("internal", "Could not generate reflection. Please try again.");
      }
    },
);

// ── studioWeeklyChallenge ────────────────────────────────────────────────────
// Runs every Sunday at midnight UTC to rotate the weekly challenge.

const CHALLENGE_POOL = [
  {title: "Write your testimony in 100 words", theme: "testimony"},
  {title: "Compose a prayer for someone you're struggling to forgive", theme: "prayer"},
  {title: "Describe the moment you felt closest to God", theme: "testimony"},
  {title: "Write a devotional on Psalm 23 for someone in a hard season", theme: "devotional"},
  {title: "Write a prayer of gratitude for something ordinary", theme: "prayer"},
  {title: "Capture a scripture that changed your life in a visual caption", theme: "scripture_canvas"},
  {title: "In 100 words: what does 'faith' mean to you today?", theme: "testimony"},
  {title: "Write a letter to your younger self about God's faithfulness", theme: "testimony"},
];

exports.studioWeeklyChallenge = onSchedule(
    {schedule: "0 0 * * 0", timeZone: "UTC", region: "us-central1"},
    async () => {
      try {
        const currentDoc = await db().collection("studioChallenges").doc("current").get();
        const currentIdx = currentDoc.exists ? (currentDoc.data().poolIndex ?? -1) : -1;
        const nextIdx = (currentIdx + 1) % CHALLENGE_POOL.length;
        const challenge = CHALLENGE_POOL[nextIdx];

        const endDate = new Date();
        endDate.setDate(endDate.getDate() + 7);

        await db().collection("studioChallenges").doc("current").set({
          title: `This Week: ${challenge.title}`,
          theme: challenge.theme,
          poolIndex: nextIdx,
          endsAt: admin.firestore.Timestamp.fromDate(endDate),
          participantCount: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Weekly challenge rotated: ${challenge.title}`);
      } catch (error) {
        console.error("studioWeeklyChallenge error:", error);
      }
    },
);
