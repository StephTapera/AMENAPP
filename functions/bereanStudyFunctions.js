/**
 * bereanStudyFunctions.js
 * AMEN App — Berean Study Assistant Callables
 *
 * All outputs are DRAFTS returned to the iOS UI for user approval.
 * Nothing is ever written to a public feed automatically.
 *
 * Exported callables:
 *   bereanExplainVerse         — plain-language explanation + historical context
 *   bereanStudyPlan            — 7-day study plan from a topic or verse
 *   bereanCompareTranslations  — side-by-side KJV / NIV / ESV / NLT comparison
 *   bereanDiscussionQuestions  — 5 group-study discussion questions from a passage
 *   bereanPrayerFromPassage    — personalised prayer draft from a passage
 *   bereanConvertToChurchNotes — structure a passage into a Church Notes entry
 *
 * Hard rules (never violate):
 *   1. Auth required — unauthenticated calls are rejected.
 *   2. NVIDIA_API_KEY only via Secret Manager / defineSecret.
 *   3. All outputs are drafts; approved: false until user explicitly approves.
 *   4. Shared rate limit: 20 AI requests per user per hour (across all 6 callables).
 *   5. Timeout: 30 seconds per call.
 *   6. Safe fallback: if NVIDIA unavailable → { draft: null, error: "study_unavailable" }.
 *   7. Every draft logged to bereanStudySessions/{uid}/drafts/{draftId}.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// ─── Secret ───────────────────────────────────────────────────────────────────
const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────
const REGION = "us-central1";
const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const NIM_MODEL = "meta/llama-3.1-70b-instruct";

const BASE_CONFIG = {
  region: REGION,
  secrets: [NVIDIA_API_KEY],
  timeoutSeconds: 30,
  memory: "256MiB",
};

// Shared rate-limit pool across all Berean study callables: 20 / hour / user
const RL_MAX = 20;
const RL_WINDOW_S = 3600;

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return request.auth.uid;
}

/**
 * Firestore-backed rate limiter shared across all Berean study actions.
 * Uses a single bucket per user so the 20/hr limit is pooled.
 */
async function enforceStudyRateLimit(uid) {
  const db = getFirestore();
  const docRef = db.collection("rateLimits").doc(`${uid}_bereanStudy`);
  const nowMs = Date.now();
  const windowMs = RL_WINDOW_S * 1000;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) {
      tx.set(docRef, { count: 1, windowStart: nowMs, expiresAt: new Date(nowMs + windowMs) });
      return;
    }
    const data = snap.data();
    if (nowMs - data.windowStart > windowMs) {
      tx.set(docRef, { count: 1, windowStart: nowMs, expiresAt: new Date(nowMs + windowMs) });
      return;
    }
    if (data.count >= RL_MAX) {
      throw new HttpsError(
        "resource-exhausted",
        "You've reached the hourly Berean study limit. Please try again in a little while."
      );
    }
    tx.update(docRef, { count: FieldValue.increment(1) });
  });
}

/**
 * Call NVIDIA NIM (llama-3.1-70b-instruct).
 * Throws on any error — callers handle and return the safe fallback.
 */
async function callNIM(apiKey, systemPrompt, userPrompt, maxTokens = 1024) {
  const controller = new AbortController();
  const tid = setTimeout(() => controller.abort(), 25000);

  try {
    const res = await fetch(NIM_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: NIM_MODEL,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        max_tokens: maxTokens,
        temperature: 0.3,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "(no body)");
      throw new Error(`NIM ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = await res.json();
    return data.choices?.[0]?.message?.content ?? "";
  } finally {
    clearTimeout(tid);
  }
}

/**
 * Persist a draft record to bereanStudySessions/{uid}/drafts/{draftId}.
 * Returns the draftId.
 */
async function saveDraft(uid, type, input, output) {
  const db = getFirestore();
  const ref = db
    .collection("bereanStudySessions")
    .doc(uid)
    .collection("drafts")
    .doc();

  await ref.set({
    type,
    input,
    output,
    approved: false,
    timestamp: FieldValue.serverTimestamp(),
  });

  return ref.id;
}

// ─── 1. bereanExplainVerse ────────────────────────────────────────────────────

/**
 * Explain a Bible verse in plain language with historical and cultural context.
 * Input:  { verseRef: string, passageText?: string }
 * Output: { draft: { explanation, historicalContext, applicationToday }, draftId }
 */
exports.bereanExplainVerse = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  await enforceStudyRateLimit(uid);

  const { verseRef, passageText, context } = request.data || {};
  if (!verseRef || typeof verseRef !== "string" || verseRef.trim().length === 0) {
    throw new HttpsError("invalid-argument", "verseRef is required.");
  }
  if (verseRef.length > 200) {
    throw new HttpsError("invalid-argument", "verseRef is too long (max 200 chars).");
  }

  console.log(JSON.stringify({ event: "bereanExplainVerse_start", uid, verseRef }));

  const systemPrompt =
    "You are Berean, a biblical AI assistant for the AMEN faith community. " +
    "You explain Bible passages with scholarly accuracy, historical context, and pastoral warmth. " +
    "Never fabricate scripture references. Cite multiple translations when helpful. " +
    "Return ONLY a JSON object — no markdown, no explanation outside the JSON.";

  const userPrompt =
    `Explain this Bible verse/passage: ${verseRef}` +
    (passageText ? `\n\nPassage text: ${passageText.slice(0, 2000)}` : "") +
    (context ? `\n\nAdditional context from user: ${context.slice(0, 500)}` : "") +
    `\n\nReturn a JSON object with these exact keys:
{
  "explanation": "plain-language explanation (100-200 words)",
  "historicalContext": "1-3 sentences on the historical/cultural setting",
  "applicationToday": "1-2 sentences on how this applies to modern life",
  "relatedVerses": ["Book Chapter:Verse", ...]
}`;

  let draft = null;
  let draftId = null;

  try {
    const apiKey = NVIDIA_API_KEY.value();
    const raw = await callNIM(apiKey, systemPrompt, userPrompt);
    const cleaned = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    draft = JSON.parse(cleaned);

    draftId = await saveDraft(uid, "explainVerse", { verseRef, passageText, context }, draft);
    console.log(JSON.stringify({ event: "bereanExplainVerse_complete", uid, draftId }));
    return { draft, draftId, type: "explainVerse", timestamp: Date.now() };
  } catch (err) {
    console.error(JSON.stringify({ event: "bereanExplainVerse_error", uid, message: err.message }));
    return { draft: null, error: "study_unavailable", fallback: "Please try again in a few minutes." };
  }
});

// ─── 2. bereanStudyPlan ───────────────────────────────────────────────────────

/**
 * Create a 7-day study plan from a topic or verse.
 * Input:  { verseRef?: string, topic?: string, context?: string }
 * Output: { draft: { title, days: [{ day, scripture, theme, reflection, prayer }] }, draftId }
 */
exports.bereanStudyPlan = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  await enforceStudyRateLimit(uid);

  const { verseRef, topic, context } = request.data || {};
  if (!verseRef && !topic) {
    throw new HttpsError("invalid-argument", "Either verseRef or topic is required.");
  }

  const subject = verseRef
    ? `the verse/passage: ${verseRef}`
    : `the topic: ${String(topic).slice(0, 300)}`;

  console.log(JSON.stringify({ event: "bereanStudyPlan_start", uid, subject }));

  const systemPrompt =
    "You are Berean, a biblically grounded AI study guide writer for the AMEN faith community. " +
    "Create study plans that are practical, scripture-rich, and accessible to everyday Christians. " +
    "Return ONLY a JSON object — no markdown, no explanation outside the JSON.";

  const userPrompt =
    `Create a 7-day personal Bible study plan based on ${subject}` +
    (context ? `\nUser context: ${context.slice(0, 300)}` : "") +
    `\n\nReturn a JSON object with these exact keys:
{
  "title": "study plan title (max 10 words)",
  "overview": "2-3 sentence overview of what this study covers",
  "days": [
    {
      "day": 1,
      "scripture": "Book Chapter:Verse-Verse",
      "theme": "daily theme (3-5 words)",
      "reflection": "reflection prompt (1-2 sentences)",
      "prayer": "short prayer focus (1 sentence)"
    }
  ]
}`;

  try {
    const raw = await callNIM(NVIDIA_API_KEY.value(), systemPrompt, userPrompt, 1500);
    const cleaned = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    const draft = JSON.parse(cleaned);

    const draftId = await saveDraft(uid, "studyPlan", { verseRef, topic, context }, draft);
    console.log(JSON.stringify({ event: "bereanStudyPlan_complete", uid, draftId }));
    return { draft, draftId, type: "studyPlan", timestamp: Date.now() };
  } catch (err) {
    console.error(JSON.stringify({ event: "bereanStudyPlan_error", uid, message: err.message }));
    return { draft: null, error: "study_unavailable", fallback: "Please try again in a few minutes." };
  }
});

// ─── 3. bereanCompareTranslations ─────────────────────────────────────────────

/**
 * Compare KJV, NIV, ESV, NLT for a given verse reference.
 * Input:  { verseRef: string }
 * Output: { draft: { verseRef, translations: { KJV, NIV, ESV, NLT }, insight }, draftId }
 */
exports.bereanCompareTranslations = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  await enforceStudyRateLimit(uid);

  const { verseRef } = request.data || {};
  if (!verseRef || typeof verseRef !== "string" || verseRef.trim().length === 0) {
    throw new HttpsError("invalid-argument", "verseRef is required.");
  }

  console.log(JSON.stringify({ event: "bereanCompareTranslations_start", uid, verseRef }));

  const systemPrompt =
    "You are Berean, a biblical translation scholar for the AMEN faith community. " +
    "Provide accurate translation text for KJV, NIV, ESV, and NLT. " +
    "If you are not certain of the exact wording, indicate this with a note. " +
    "Return ONLY a JSON object — no markdown, no explanation outside the JSON.";

  const userPrompt =
    `Compare the following verse across four major translations: ${verseRef}

Return a JSON object with these exact keys:
{
  "verseRef": "${verseRef}",
  "translations": {
    "KJV": "King James Version text",
    "NIV": "New International Version text",
    "ESV": "English Standard Version text",
    "NLT": "New Living Translation text"
  },
  "insight": "2-3 sentences highlighting significant translation differences and what they reveal",
  "note": "optional accuracy note — use if uncertain of exact text"
}`;

  try {
    const raw = await callNIM(NVIDIA_API_KEY.value(), systemPrompt, userPrompt, 800);
    const cleaned = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    const draft = JSON.parse(cleaned);

    const draftId = await saveDraft(uid, "compareTranslations", { verseRef }, draft);
    console.log(JSON.stringify({ event: "bereanCompareTranslations_complete", uid, draftId }));
    return { draft, draftId, type: "compareTranslations", timestamp: Date.now() };
  } catch (err) {
    console.error(JSON.stringify({ event: "bereanCompareTranslations_error", uid, message: err.message }));
    return { draft: null, error: "study_unavailable", fallback: "Please try again in a few minutes." };
  }
});

// ─── 4. bereanDiscussionQuestions ─────────────────────────────────────────────

/**
 * Generate 5 group-study discussion questions from a passage.
 * Input:  { verseRef: string, passageText?: string, groupContext?: string }
 * Output: { draft: { questions: [{ question, scriptureAnchor, type }] }, draftId }
 */
exports.bereanDiscussionQuestions = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  await enforceStudyRateLimit(uid);

  const { verseRef, passageText, groupContext } = request.data || {};
  if (!verseRef || typeof verseRef !== "string" || verseRef.trim().length === 0) {
    throw new HttpsError("invalid-argument", "verseRef is required.");
  }

  console.log(JSON.stringify({ event: "bereanDiscussionQuestions_start", uid, verseRef }));

  const systemPrompt =
    "You are Berean, a small-group facilitator for the AMEN faith community. " +
    "Write open-ended discussion questions that draw people into honest, scripture-grounded conversation. " +
    "Avoid yes/no questions. Vary question types (observational, interpretive, applicational). " +
    "Return ONLY a JSON object — no markdown, no explanation outside the JSON.";

  const userPrompt =
    `Generate 5 discussion questions for a small group studying: ${verseRef}` +
    (passageText ? `\n\nPassage text: ${passageText.slice(0, 2000)}` : "") +
    (groupContext ? `\n\nGroup context: ${groupContext.slice(0, 300)}` : "") +
    `\n\nReturn a JSON object with these exact keys:
{
  "questions": [
    {
      "question": "the discussion question",
      "scriptureAnchor": "Book Chapter:Verse (optional — verse most related to this question)",
      "type": "observational" | "interpretive" | "applicational" | "personal"
    }
  ]
}`;

  try {
    const raw = await callNIM(NVIDIA_API_KEY.value(), systemPrompt, userPrompt);
    const cleaned = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    const draft = JSON.parse(cleaned);

    const draftId = await saveDraft(uid, "discussionQuestions", { verseRef, passageText, groupContext }, draft);
    console.log(JSON.stringify({ event: "bereanDiscussionQuestions_complete", uid, draftId }));
    return { draft, draftId, type: "discussionQuestions", timestamp: Date.now() };
  } catch (err) {
    console.error(JSON.stringify({ event: "bereanDiscussionQuestions_error", uid, message: err.message }));
    return { draft: null, error: "study_unavailable", fallback: "Please try again in a few minutes." };
  }
});

// ─── 5. bereanPrayerFromPassage ───────────────────────────────────────────────

/**
 * Draft a personalised prayer based on a passage.
 * Input:  { verseRef: string, passageText?: string, context?: string }
 * Output: { draft: { prayer, keyThemes, scriptureEchoes }, draftId }
 */
exports.bereanPrayerFromPassage = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  await enforceStudyRateLimit(uid);

  const { verseRef, passageText, context } = request.data || {};
  if (!verseRef || typeof verseRef !== "string" || verseRef.trim().length === 0) {
    throw new HttpsError("invalid-argument", "verseRef is required.");
  }

  console.log(JSON.stringify({ event: "bereanPrayerFromPassage_start", uid, verseRef }));

  const systemPrompt =
    "You are Berean, a pastoral AI prayer guide for the AMEN faith community. " +
    "Write sincere, scripture-grounded prayers that the user can personalise and pray as their own. " +
    "The prayer should feel authentic, not overly formal. " +
    "Return ONLY a JSON object — no markdown, no explanation outside the JSON.";

  const userPrompt =
    `Write a personal prayer draft based on: ${verseRef}` +
    (passageText ? `\n\nPassage text: ${passageText.slice(0, 2000)}` : "") +
    (context ? `\n\nPersonal context from user: ${context.slice(0, 400)}` : "") +
    `\n\nReturn a JSON object with these exact keys:
{
  "prayer": "the prayer text (150-250 words, written in first person, e.g. 'Lord, I come to you...')",
  "keyThemes": ["theme1", "theme2", "theme3"],
  "scriptureEchoes": ["Book Chapter:Verse — one or two verses woven into the prayer"]
}`;

  try {
    const raw = await callNIM(NVIDIA_API_KEY.value(), systemPrompt, userPrompt);
    const cleaned = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    const draft = JSON.parse(cleaned);

    const draftId = await saveDraft(uid, "prayerFromPassage", { verseRef, passageText, context }, draft);
    console.log(JSON.stringify({ event: "bereanPrayerFromPassage_complete", uid, draftId }));
    return { draft, draftId, type: "prayerFromPassage", timestamp: Date.now() };
  } catch (err) {
    console.error(JSON.stringify({ event: "bereanPrayerFromPassage_error", uid, message: err.message }));
    return { draft: null, error: "study_unavailable", fallback: "Please try again in a few minutes." };
  }
});

// ─── 6. bereanConvertToChurchNotes ────────────────────────────────────────────

/**
 * Structure a passage into a Church Notes entry for user approval.
 * Input:  { verseRef: string, passageText?: string, sermonTitle?: string, context?: string }
 * Output: { draft: { title, summary, keyVerses, actionItems, discussionQuestions, prayerFocus }, draftId }
 *
 * The output is a DRAFT only. The user approves it in ChurchNotesAIDraftReviewView
 * before it is saved to the churchNotes collection.
 */
exports.bereanConvertToChurchNotes = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  await enforceStudyRateLimit(uid);

  const { verseRef, passageText, sermonTitle, context } = request.data || {};
  if (!verseRef || typeof verseRef !== "string" || verseRef.trim().length === 0) {
    throw new HttpsError("invalid-argument", "verseRef is required.");
  }

  console.log(JSON.stringify({ event: "bereanConvertToChurchNotes_start", uid, verseRef }));

  const systemPrompt =
    "You are Berean, a pastoral AI assistant for the AMEN faith community. " +
    "Structure Bible passages into well-organised Church Notes entries that a believer " +
    "can keep in their personal note library. Be concise, practical, and scripturally faithful. " +
    "Return ONLY a JSON object — no markdown, no explanation outside the JSON.";

  const userPrompt =
    `Create a Church Notes entry from this passage: ${verseRef}` +
    (sermonTitle ? `\n\nSermon/study title: ${sermonTitle}` : "") +
    (passageText ? `\n\nPassage text: ${passageText.slice(0, 2000)}` : "") +
    (context ? `\n\nAdditional context: ${context.slice(0, 400)}` : "") +
    `\n\nReturn a JSON object with these exact keys:
{
  "title": "concise title for the note (max 10 words)",
  "summary": "150-200 word summary of the passage and its main message",
  "keyVerses": ["Book Chapter:Verse", ...],
  "actionItems": ["practical action a believer can take this week", ...],
  "discussionQuestions": ["open-ended question for group or personal reflection", ...],
  "prayerFocus": "1-2 sentence prayer focus based on the passage"
}`;

  try {
    const raw = await callNIM(NVIDIA_API_KEY.value(), systemPrompt, userPrompt, 1200);
    const cleaned = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    const draft = JSON.parse(cleaned);

    const draftId = await saveDraft(uid, "convertToChurchNotes", { verseRef, passageText, sermonTitle, context }, draft);
    console.log(JSON.stringify({ event: "bereanConvertToChurchNotes_complete", uid, draftId }));
    return { draft, draftId, type: "convertToChurchNotes", timestamp: Date.now() };
  } catch (err) {
    console.error(JSON.stringify({ event: "bereanConvertToChurchNotes_error", uid, message: err.message }));
    return { draft: null, error: "study_unavailable", fallback: "Please try again in a few minutes." };
  }
});
