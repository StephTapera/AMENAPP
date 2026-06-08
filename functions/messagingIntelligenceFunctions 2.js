/**
 * messagingIntelligenceFunctions.js
 * AMEN App — Messaging Intelligence Cloud Functions
 *
 * Provides AI-powered capabilities for the Messaging layer:
 *   generateMessageCatchUp          — Summarise recent messages in a conversation
 *   generateThreadSummary           — Summarise a thread or full conversation
 *   detectMessagingSmartPills       — Detect contextual action pills from message text
 *   translateMessage                — Translate message preserving theological nuance
 *   detectMessageSafetyNudge        — NeMo Guard safety check on message text
 *   generateVoiceMessageSummary     — Summarise a voice-message transcript
 *   detectMessageCrossSurfaceActions — Detect cross-surface actions from message text
 *
 * Setup (one-time per environment):
 *   firebase functions:secrets:set NVIDIA_API_KEY --project amen-5e359
 *   firebase deploy --only functions:generateMessageCatchUp,... --project amen-5e359
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {getFirestore} = require("firebase-admin/firestore");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";
const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const NIM_MODEL = "meta/llama-3.1-70b-instruct";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

// ─── Shared helpers ───────────────────────────────────────────────────────────

/**
 * Call NVIDIA NIM chat completions.
 * @param {string} prompt       User-turn message
 * @param {string} systemMsg    System prompt
 * @param {string} apiKey       NVIDIA_API_KEY value
 * @param {string} [model]      NIM model ID (defaults to NIM_MODEL)
 * @returns {Promise<string>}   Raw assistant content string
 */
async function callNIM(prompt, systemMsg, apiKey, model = NIM_MODEL) {
  let res;
  try {
    res = await fetch(NIM_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          {role: "system", content: systemMsg},
          {role: "user", content: prompt},
        ],
        max_tokens: 512,
        temperature: 0.3,
      }),
    });
  } catch (err) {
    console.error("NIM fetch error:", err.message);
    throw new HttpsError("internal", "AI service unavailable");
  }

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    console.error(`NIM ${res.status}:`, body);
    throw new HttpsError("internal", "AI service unavailable");
  }

  const data = await res.json();
  return data.choices?.[0]?.message?.content ?? "";
}

/**
 * Strip markdown fences then parse JSON. Returns null on failure.
 * @param {string} raw
 * @returns {any|null}
 */
function parseJSONSafe(raw) {
  try {
    const stripped = raw.replace(/```(?:json)?/gi, "").replace(/```/g, "").trim();
    return JSON.parse(stripped);
  } catch {
    return null;
  }
}

// ─── 1. generateMessageCatchUp ────────────────────────────────────────────────

exports.generateMessageCatchUp = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {conversationId, maxMessages} = request.data ?? {};

      if (!conversationId || typeof conversationId !== "string") {
        throw new HttpsError("invalid-argument", "conversationId is required.");
      }

      const limit = Math.min(
          typeof maxMessages === "number" && maxMessages > 0 ? maxMessages : 50,
          100,
      );

      const db = getFirestore();
      const snapshot = await db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .orderBy("sentAt", "desc")
          .limit(limit)
          .get();

      const messages = snapshot.docs
          .map((d) => d.data())
          .reverse(); // chronological order

      if (messages.length === 0) {
        return {
          summary: "No messages found in this conversation.",
          messageCount: 0,
          generatedAt: new Date().toISOString(),
        };
      }

      const transcript = messages
          .map((m) => `${m.senderName || m.senderId || "Unknown"}: ${m.text || ""}`)
          .join("\n");

      const systemMsg =
        "You are a helpful assistant for Amen, a Christian community app. " +
        "Be concise, warm, and faith-sensitive.";

      const prompt =
        "Summarize these messages from a Christian community app in 2-3 sentences. " +
        "Focus on prayer requests, decisions, and action items.\n\n" +
        `Messages:\n${transcript}`;

      const summary = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());

      return {
        summary: summary.trim(),
        messageCount: messages.length,
        generatedAt: new Date().toISOString(),
      };
    },
);

// ─── 2. generateThreadSummary ─────────────────────────────────────────────────

exports.generateThreadSummary = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {conversationId, threadId} = request.data ?? {};

      if (!conversationId || typeof conversationId !== "string") {
        throw new HttpsError("invalid-argument", "conversationId is required.");
      }

      const db = getFirestore();
      let query = db
          .collection("conversations")
          .doc(conversationId)
          .collection("messages")
          .limit(100);

      if (threadId && typeof threadId === "string") {
        query = query.where("threadId", "==", threadId);
      }

      const snapshot = await query.get();
      const messages = snapshot.docs.map((d) => d.data());

      if (messages.length === 0) {
        return {
          summary: "No messages found.",
          topics: [],
          prayerRequests: [],
          openQuestions: [],
        };
      }

      const transcript = messages
          .map((m) => `${m.senderName || m.senderId || "Unknown"}: ${m.text || ""}`)
          .join("\n");

      const systemMsg =
        "You are a helpful assistant for Amen, a Christian community app. " +
        "Respond ONLY with valid JSON — no markdown fences, no extra text.";

      const prompt =
        "Summarize this conversation thread from a Christian faith app. " +
        'Return a JSON object with keys: "summary" (string), "topics" (string[]), ' +
        '"prayerRequests" (string[]), "openQuestions" (string[]). ' +
        "Extract: main topic, key decisions, open questions, prayer requests.\n\n" +
        `Thread:\n${transcript}`;

      const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
      const parsed = parseJSONSafe(raw);

      if (parsed && typeof parsed === "object") {
        return {
          summary: String(parsed.summary || ""),
          topics: Array.isArray(parsed.topics) ? parsed.topics.map(String) : [],
          prayerRequests: Array.isArray(parsed.prayerRequests)
            ? parsed.prayerRequests.map(String)
            : [],
          openQuestions: Array.isArray(parsed.openQuestions)
            ? parsed.openQuestions.map(String)
            : [],
        };
      }

      // Fallback: put full text in summary
      return {
        summary: raw.trim(),
        topics: [],
        prayerRequests: [],
        openQuestions: [],
      };
    },
);

// ─── 3. detectMessagingSmartPills ─────────────────────────────────────────────

const VALID_PILL_TYPES = new Set([
  "pray_together",
  "share_to_post",
  "save_to_church_notes",
  "schedule_reminder",
  "send_scripture",
  "berean_followup",
]);

const VALID_CONFIDENCES = new Set(["high", "medium", "low"]);

exports.detectMessagingSmartPills = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {text} = request.data ?? {};

      if (!text || typeof text !== "string") {
        throw new HttpsError("invalid-argument", "text is required.");
      }

      const trimmedText = text.slice(0, 1000);

      const systemMsg =
        "You are a smart-action detector for Amen, a Christian community app. " +
        "Respond ONLY with valid JSON — no markdown fences, no extra text.";

      const prompt =
        "Detect up to 3 smart actions a user might want to take based on this message. " +
        "Return a JSON array of objects. Each object must have:\n" +
        '  "type": one of "pray_together"|"share_to_post"|"save_to_church_notes"|' +
        '"schedule_reminder"|"send_scripture"|"berean_followup"\n' +
        '  "label": short human-readable label (≤40 chars)\n' +
        '  "confidence": "high"|"medium"|"low"\n\n' +
        `Message: "${trimmedText}"`;

      const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
      const parsed = parseJSONSafe(raw);

      const rawPills = Array.isArray(parsed) ? parsed : [];

      const pills = rawPills
          .filter((p) =>
            p &&
            VALID_PILL_TYPES.has(p.type) &&
            VALID_CONFIDENCES.has(p.confidence) &&
            p.confidence !== "low",
          )
          .slice(0, 3)
          .map((p) => ({
            type: p.type,
            label: String(p.label || "").slice(0, 40),
            confidence: p.confidence,
          }));

      return {pills};
    },
);

// ─── 4. translateMessage ──────────────────────────────────────────────────────

exports.translateMessage = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {text, targetLanguage, sourceLanguage} = request.data ?? {};

      if (!text || typeof text !== "string") {
        throw new HttpsError("invalid-argument", "text is required.");
      }
      if (!targetLanguage || typeof targetLanguage !== "string") {
        throw new HttpsError("invalid-argument", "targetLanguage is required.");
      }

      const sourcePart = sourceLanguage
        ? `from ${sourceLanguage} `
        : "";

      const systemMsg =
        "You are a professional translator working for a Christian community app. " +
        "Preserve meaning, scripture references, and theological nuance exactly. " +
        "Return ONLY the translated text — no explanations, no quotes.";

      const prompt =
        `Translate the following message ${sourcePart}into ${targetLanguage}. ` +
        "Preserve all scripture references, proper nouns, and theological terms.\n\n" +
        `Message: ${text}`;

      const translatedText = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());

      return {
        translatedText: translatedText.trim(),
        targetLanguage,
      };
    },
);

// ─── 5. detectMessageSafetyNudge ─────────────────────────────────────────────

exports.detectMessageSafetyNudge = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {text} = request.data ?? {};

      if (!text || typeof text !== "string") {
        throw new HttpsError("invalid-argument", "text is required.");
      }

      let res;
      try {
        res = await fetch(NIM_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${NVIDIA_API_KEY.value()}`,
          },
          body: JSON.stringify({
            model: SAFETY_MODEL,
            messages: [{role: "user", content: text}],
            max_tokens: 100,
            temperature: 0,
          }),
        });
      } catch (err) {
        console.error("NIM safety fetch error:", err.message);
        throw new HttpsError("internal", "AI service unavailable");
      }

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        console.error(`NIM safety ${res.status}:`, body);
        throw new HttpsError("internal", "AI service unavailable");
      }

      const data = await res.json();
      const raw = data.choices?.[0]?.message?.content ?? "";

      // NeMo Guard returns JSON like:
      //   {"User Safety": "unsafe", "Safety Categories": "Hate, Harassment"}
      let needsNudge = false;
      let reason;

      const parsed = parseJSONSafe(raw);
      if (parsed && typeof parsed === "object") {
        needsNudge =
          String(parsed["User Safety"] ?? "safe").toLowerCase() === "unsafe";
        if (needsNudge && parsed["Safety Categories"]) {
          reason = String(parsed["Safety Categories"]);
        }
      } else {
        // Fallback: plain-text contains "unsafe"
        needsNudge = /unsafe/i.test(raw);
        if (needsNudge) reason = "Content flagged by safety model.";
      }

      return needsNudge ? {needsNudge: true, reason} : {needsNudge: false};
    },
);

// ─── 6. generateVoiceMessageSummary ──────────────────────────────────────────

exports.generateVoiceMessageSummary = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {transcript, durationSeconds} = request.data ?? {};

      if (!transcript || typeof transcript !== "string") {
        throw new HttpsError("invalid-argument", "transcript is required.");
      }

      const trimmedTranscript = transcript.slice(0, 4000);

      const durationNote =
        typeof durationSeconds === "number"
          ? ` (duration: ${Math.round(durationSeconds)}s)`
          : "";

      const systemMsg =
        "You are a helpful assistant for Amen, a Christian community app. " +
        "Respond ONLY with valid JSON — no markdown fences, no extra text.";

      const prompt =
        `Summarize this voice message transcript${durationNote} from a Christian community app ` +
        "in 1-2 sentences. Also extract up to 3 key points.\n" +
        'Return a JSON object with keys: "summary" (string), "keyPoints" (string[]).\n\n' +
        `Transcript:\n${trimmedTranscript}`;

      const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
      const parsed = parseJSONSafe(raw);

      if (parsed && typeof parsed === "object") {
        return {
          summary: String(parsed.summary || "").trim(),
          keyPoints: Array.isArray(parsed.keyPoints)
            ? parsed.keyPoints.map(String).slice(0, 3)
            : [],
        };
      }

      // Fallback
      return {
        summary: raw.trim(),
        keyPoints: [],
      };
    },
);

// ─── 7. detectMessageCrossSurfaceActions ─────────────────────────────────────

const VALID_SURFACES = new Set([
  "berean",
  "church_notes",
  "selah",
  "prayer_feed",
  "discover",
]);

exports.detectMessageCrossSurfaceActions = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const {text} = request.data ?? {};

      if (!text || typeof text !== "string") {
        throw new HttpsError("invalid-argument", "text is required.");
      }

      const systemMsg =
        "You are a cross-surface action detector for Amen, a Christian social app. " +
        "Respond ONLY with valid JSON — no markdown fences, no extra text.";

      const prompt =
        "Given this message text, detect up to 3 cross-surface actions relevant to a " +
        "Christian social app. Return a JSON array of objects. Each object must have:\n" +
        '  "surface": one of "berean"|"church_notes"|"selah"|"prayer_feed"|"discover"\n' +
        '  "action": short description of the action (≤60 chars)\n' +
        '  "reason": one sentence explaining why this action is relevant (≤120 chars)\n\n' +
        `Message: "${text}"`;

      const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
      const parsed = parseJSONSafe(raw);

      const rawActions = Array.isArray(parsed) ? parsed : [];

      const actions = rawActions
          .filter((a) => a && VALID_SURFACES.has(a.surface))
          .slice(0, 3)
          .map((a) => ({
            surface: a.surface,
            action: String(a.action || "").slice(0, 60),
            reason: String(a.reason || "").slice(0, 120),
          }));

      return {actions};
    },
);
