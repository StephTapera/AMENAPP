/**
 * genkitFunctions.js
 * AMEN App — Genkit-style AI flows as Cloud Functions
 *
 * Replaces the external Genkit Cloud Run service that was never deployed.
 * DailyVerseGenkitService and NotificationGenkitService on iOS will be
 * updated to call these Cloud Functions instead of the missing HTTP endpoint.
 *
 * Exports:
 *   generateDailyVerse        — personalized scripture + reflection
 *   generateVerseReflection   — reflection prompt for a given verse
 *   generateNotificationText  — non-bait notification copy
 *   summarizeNotifications    — digest summary of multiple notifications
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const REGION = "us-central1";

// ─── Shared OpenAI helper ─────────────────────────────────────────────────────

async function callOpenAI(apiKey, system, user, maxTokens = 400, temperature = 0.6) {
  const fetch = (await import("node-fetch")).default;
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: [
        {role: "system", content: system},
        {role: "user", content: user},
      ],
      max_tokens: maxTokens,
      temperature,
    }),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.choices?.[0]?.message?.content ?? "";
}

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
}

// ─── Daily Verse ──────────────────────────────────────────────────────────────

exports.generateDailyVerse = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {goals = [], recentTopics = [], prayerThemes = []} = request.data ?? {};

      const context = [
        goals.length ? `User's faith goals: ${goals.join(", ")}.` : "",
        recentTopics.length ? `Recent topics of interest: ${recentTopics.join(", ")}.` : "",
        prayerThemes.length ? `Recent prayer themes: ${prayerThemes.join(", ")}.` : "",
      ].filter(Boolean).join(" ");

      const system = `You are Berean, a scripture curator for the AMEN faith community app.
Select one Bible verse that will be uplifting and personally meaningful for today.
${context ? `Context about this user: ${context}` : "Choose a generally uplifting verse."}
Output JSON exactly:
{
  "reference": "Book Chapter:Verse",
  "text": "Full verse text (NIV translation preferred)",
  "theme": "One-word theme (e.g. Hope, Strength, Peace)",
  "reflection": "A warm 2-sentence personal reflection prompt for journaling or prayer",
  "prayer": "A 1-sentence prayer prompt based on this verse"
}`;

      const raw = await callOpenAI(OPENAI_API_KEY.value(), system, "Generate today's verse.", 350, 0.7);

      // Parse JSON, fall back to structured response on parse error
      try {
        const parsed = JSON.parse(raw);
        return {success: true, verse: parsed};
      } catch {
        return {
          success: true,
          verse: {
            reference: "Philippians 4:13",
            text: "I can do all this through him who gives me strength.",
            theme: "Strength",
            reflection: "What challenge are you facing today that you need God's strength for? How can you lean on Him in this moment?",
            prayer: "Lord, remind me that your strength is made perfect in my weakness.",
          },
        };
      }
    },
);

// ─── Verse Reflection ─────────────────────────────────────────────────────────

exports.generateVerseReflection = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {reference, verseText} = request.data ?? {};
      if (!reference) throw new HttpsError("invalid-argument", "reference required");

      const system = `You are Berean, a thoughtful biblical reflection guide.
Generate a personal reflection for this Bible verse to help the user apply it to daily life.
Output JSON:
{
  "reflection": "2-3 sentences connecting the verse to modern daily life",
  "journalPrompt": "One open-ended journaling question",
  "prayerStarter": "One-sentence prayer opener"
}`;

      const raw = await callOpenAI(
          OPENAI_API_KEY.value(),
          system,
          `Verse: ${reference} — "${verseText ?? ""}"`,
          250,
          0.6,
      );

      try {
        return {success: true, reflection: JSON.parse(raw)};
      } catch {
        return {
          success: true,
          reflection: {
            reflection: "This verse reminds us that God's word is alive and active in our lives today.",
            journalPrompt: "How does this verse speak to what you're experiencing right now?",
            prayerStarter: "Lord, help me to hold onto this truth today...",
          },
        };
      }
    },
);

// ─── Notification Text ────────────────────────────────────────────────────────

exports.generateNotificationText = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {eventType, actorName, context: ctx} = request.data ?? {};

      const system = `Write a push notification for a faith-based social app.
Rules: No engagement bait. No urgency tricks. No "Don't miss out!" language.
Notifications should feel calm, warm, and informative.
Output JSON: { "title": "max 40 chars", "body": "max 100 chars" }`;

      const prompt = `Event: ${eventType ?? "activity"}. Actor: ${actorName ?? "Someone"}. Context: ${ctx ?? ""}`;
      const raw = await callOpenAI(OPENAI_API_KEY.value(), system, prompt, 120, 0.4);

      try {
        return {success: true, notification: JSON.parse(raw)};
      } catch {
        return {
          success: true,
          notification: {title: actorName ?? "AMEN", body: "You have a new notification."},
        };
      }
    },
);

// ─── Notification Digest ──────────────────────────────────────────────────────

exports.summarizeNotifications = onCall(
    {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {notifications = []} = request.data ?? {};
      if (!notifications.length) {
        return {success: true, summary: "You're all caught up."};
      }

      const system = `Summarize these app notifications into one brief, friendly sentence (max 15 words).
Focus on the most meaningful activity. Don't list every item.
Example: "3 people commented on your testimony and Sarah sent you a message."`;

      const list = notifications.slice(0, 10).map((n) => `- ${n}`).join("\n");
      const summary = await callOpenAI(OPENAI_API_KEY.value(), system, list, 80, 0.5);

      return {success: true, summary: summary.trim().replace(/^"|"$/g, "")};
    },
);
