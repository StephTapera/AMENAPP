/**
 * bereanRealtimeFunctions.js
 * AMEN App — Berean AI Realtime Cloud Functions
 *
 * H-22: createRealtimeSession — brokers ephemeral OpenAI Realtime API tokens.
 *   The iOS client (BereanRealtimeSessionManager.swift) calls this callable to
 *   obtain a short-lived client_secret without ever holding the OpenAI API key
 *   directly on-device.
 *
 * H-33: bereanSLOCheck — scheduled every 5 minutes, reads Firestore metric
 *   counters and writes systemStatus/berean when an SLO breach is detected.
 *   Pairs with the Firestore listener in RemoteKillSwitch.swift to disable
 *   Berean automatically without a code deploy.
 *
 * Secrets required (already defined in bereanFunctions.js):
 *   OPENAI_API_KEY  — firebase functions:secrets:set OPENAI_API_KEY
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

// ─── Secrets ──────────────────────────────────────────────────────────────────
// Re-declare here so this module can be required independently of bereanFunctions.js.
// Firebase Secret Manager deduplicates the actual secret references at deploy time.
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

const REGION = "us-central1";

// ─── Shared rate-limit helper (mirrors bereanFunctions.js) ────────────────────
/**
 * Per-user hourly rate limiter backed by Firestore atomic transactions.
 * @param {string} uid
 * @param {string} feature
 * @param {number} limitPerHour
 */
async function checkBereanRateLimit(uid, feature, limitPerHour) {
  const hourKey = new Date().toISOString().slice(0, 13); // YYYY-MM-DDTHH
  const ref = admin.firestore()
      .collection("users").doc(uid)
      .collection("bereanUsage").doc(`${feature}_${hourKey}`);
  await admin.firestore().runTransaction(async (t) => {
    const snap = await t.get(ref);
    const count = snap.exists ? (snap.data().count || 0) : 0;
    if (count >= limitPerHour) {
      throw new HttpsError(
          "resource-exhausted",
          `Hourly limit reached for ${feature}. Try again later.`,
      );
    }
    t.set(ref, {count: count + 1, windowStart: hourKey}, {merge: true});
  });
}

// ─── H-22: createRealtimeSession ─────────────────────────────────────────────
//
// iOS call site: BereanRealtimeSessionManager.swift › createSession(...)
//
// Payload received from iOS:
//   sessionType     — BereanRealtimeSessionType.rawValue (e.g. "voice_assistant")
//   sourceLanguage  — BCP-47 code (e.g. "en")
//   targetLanguages — [String]  BCP-47 codes
//   selectedLanguage — String   BCP-47 code
//   churchId        — String (may be "")
//   sermonId        — String (may be "")
//   prayerRoomId    — String (may be "")
//   conversationId  — String (may be "")
//
// Response expected by iOS (see BereanRealtimeSessionManager.swift lines 45-58):
//   sessionId        — String   (AMEN-generated, stored in Firestore realtimeSessions/)
//   clientSecret     — String   (OpenAI ephemeral token value)
//   expiresAtMs      — Double   (milliseconds since Unix epoch)
//   providerSessionId— String?  (OpenAI session.id)
//   model            — String?  (model used)
//
exports.createRealtimeSession = onCall(
    {
      enforceAppCheck: true,
      region: REGION,
      secrets: [OPENAI_API_KEY],
      timeoutSeconds: 30,
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Sign in required.");
      }

      const uid = request.auth.uid;

      // Rate limit: 10 realtime sessions per user per hour
      await checkBereanRateLimit(uid, "realtimeSession", 10);

      const {
        sessionType = "voice_assistant",
        sourceLanguage = "en",
        targetLanguages = ["en"],
        selectedLanguage = "en",
        churchId = "",
        sermonId = "",
        prayerRoomId = "",
        conversationId = "",
      } = request.data;

      const apiKey = OPENAI_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("internal", "OPENAI_API_KEY secret not configured.");
      }

      // ── Map AMEN session type to OpenAI instructions ──────────────────────
      const SESSION_INSTRUCTIONS = {
        voice_assistant: "You are Berean, a wise and compassionate biblical AI companion for the AMEN faith community. Answer with scriptural grounding, pastoral warmth, and theological humility. Never produce harmful, sexual, or violent content.",
        sermon_translation: "You are Berean in Sermon Translation mode. Provide accurate, faithful transcription and translation of sermon content. Preserve theological terms carefully.",
        live_prayer_room: "You are Berean in Prayer Room mode. Offer gentle, prayerful support. Detect and respond sensitively to distress signals. Always encourage real pastoral care for serious needs.",
        smart_notes: "You are Berean in Smart Notes mode. Help the user capture structured sermon notes, extract key points, and identify scripture references accurately.",
        multilingual_conversation: "You are Berean in Multilingual mode. Facilitate clear, faithful communication across languages in a faith community setting.",
      };

      const instructions = SESSION_INSTRUCTIONS[sessionType] ?? SESSION_INSTRUCTIONS["voice_assistant"];

      // ── Select voice appropriate to session type ──────────────────────────
      // alloy: neutral/informational  shimmer: warm/pastoral  echo: calm/contemplative
      const SESSION_VOICES = {
        voice_assistant: "shimmer",
        sermon_translation: "alloy",
        live_prayer_room: "shimmer",
        smart_notes: "echo",
        multilingual_conversation: "alloy",
      };
      const voice = SESSION_VOICES[sessionType] ?? "shimmer";

      // ── Call OpenAI Realtime Sessions API ─────────────────────────────────
      const fetch = (await import("node-fetch")).default;
      const openAIResponse = await fetch("https://api.openai.com/v1/realtime/sessions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-realtime-preview-2024-10-01",
          voice,
          instructions,
          modalities: ["audio", "text"],
          input_audio_format: "pcm16",
          output_audio_format: "pcm16",
          input_audio_transcription: {model: "whisper-1"},
          turn_detection: {type: "server_vad", silence_duration_ms: 500},
        }),
      });

      if (!openAIResponse.ok) {
        const errText = await openAIResponse.text();
        console.error("[createRealtimeSession] OpenAI error:", errText);
        throw new HttpsError("internal", "Failed to create realtime session.");
      }

      const providerSession = await openAIResponse.json();

      // ephemeral key lives in client_secret.value, expires at client_secret.expires_at (Unix seconds)
      const ephemeralValue = providerSession.client_secret?.value ?? "";
      const expiresAtSeconds = providerSession.client_secret?.expires_at ?? 0;
      const expiresAtMs = expiresAtSeconds * 1000;
      const providerSessionId = providerSession.id ?? "";
      const model = providerSession.model ?? "gpt-4o-realtime-preview-2024-10-01";

      // ── Persist session metadata to Firestore ─────────────────────────────
      // iOS listener (BereanRealtimeSessionManager.listen) subscribes to this doc.
      const sessionRef = admin.firestore().collection("realtimeSessions").doc();
      const sessionId = sessionRef.id;

      await sessionRef.set({
        ownerId: uid,
        sessionType,
        status: "initializing",
        sourceLanguage,
        targetLanguages: Array.isArray(targetLanguages) ? targetLanguages : [targetLanguages],
        selectedLanguage,
        churchId: churchId || null,
        sermonId: sermonId || null,
        prayerRoomId: prayerRoomId || null,
        conversationId: conversationId || null,
        provider: {
          sessionId: providerSessionId,
          model,
        },
        expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // ── Record a metric event for SLO tracking ────────────────────────────
      await _recordBereanMetric("sessionCreated", true);

      // ── Return only what iOS needs (never return the full API key) ─────────
      // Field names match exactly what BereanRealtimeSessionManager.swift parses:
      //   data["sessionId"]        → String
      //   data["clientSecret"]     → String
      //   data["expiresAtMs"]      → Double
      //   data["providerSessionId"]→ String?
      //   data["model"]            → String?
      return {
        sessionId,
        clientSecret: ephemeralValue,
        expiresAtMs,
        providerSessionId,
        model,
      };
    },
);

// ─── Internal metric recorder ─────────────────────────────────────────────────
/**
 * Increments an hourly counter in bereanMetrics/hourly for SLO tracking.
 * @param {string} event  — e.g. "sessionCreated", "sessionError", "chatError"
 * @param {boolean} success
 */
async function _recordBereanMetric(event, success) {
  try {
    const hourKey = new Date().toISOString().slice(0, 13); // YYYY-MM-DDTHH
    const ref = admin.firestore().doc("bereanMetrics/hourly");
    const successKey = `${event}_${hourKey}_success`;
    const errorKey = `${event}_${hourKey}_error`;
    const latencyKey = `latencySum_${hourKey}`;
    const callKey = `calls_${hourKey}`;

    await ref.set({
      [success ? successKey : errorKey]: admin.firestore.FieldValue.increment(1),
      [callKey]: admin.firestore.FieldValue.increment(1),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } catch (err) {
    // Non-fatal — never block the main request path on metric writes
    console.warn("[_recordBereanMetric] failed:", err.message);
  }
}

// Expose metric recorder so bereanFunctions.js can import and call it
exports._recordBereanMetric = _recordBereanMetric;

// ─── H-33: bereanSLOCheck — scheduled every 5 minutes ────────────────────────
//
// Reads bereanMetrics/hourly, computes error rate for the current hour.
// If error rate > 20% across at least 10 calls, OR average latency > 15 000 ms,
// writes systemStatus/berean { status: "degraded" } so RemoteKillSwitch.swift
// can disable Berean without a code deploy.
//
// The iOS Firestore listener (added in RemoteKillSwitch.swift) reads this doc
// and sets bereanEnabled = false when status == "degraded".
//
exports.bereanSLOCheck = onSchedule(
    {
      schedule: "every 5 minutes",
      timeZone: "UTC",
      region: REGION,
    },
    async () => {
      const db = admin.firestore();
      const hourKey = new Date().toISOString().slice(0, 13);

      try {
        const snap = await db.doc("bereanMetrics/hourly").get();
        if (!snap.exists) {
          console.log("[bereanSLOCheck] No metrics doc yet — skipping.");
          return;
        }

        const data = snap.data();

        // Tally calls and errors for the current hour window across all event types
        const eventPrefixes = ["sessionCreated", "chatProxy", "bibleQA", "moralCounsel"];
        let totalCalls = 0;
        let totalErrors = 0;

        for (const prefix of eventPrefixes) {
          const calls = data[`${prefix}_${hourKey}_success`] ?? 0;
          const errors = data[`${prefix}_${hourKey}_error`] ?? 0;
          totalCalls += calls + errors;
          totalErrors += errors;
        }

        // Also read the generic call / error counters if written directly
        const genericCalls = data[`calls_${hourKey}`] ?? 0;
        if (genericCalls > totalCalls) totalCalls = genericCalls;

        const latencySum = data[`latencySum_${hourKey}`] ?? 0;
        const latencyCalls = data[`latencyCalls_${hourKey}`] ?? 0;
        const avgLatencyMs = latencyCalls > 0 ? latencySum / latencyCalls : 0;

        const statusRef = db.doc("systemStatus/berean");

        // ── Check: error rate SLO ─────────────────────────────────────────
        if (totalCalls >= 10) {
          const errorRate = totalErrors / totalCalls;
          if (errorRate > 0.20) {
            const reason = `error rate ${(errorRate * 100).toFixed(1)}% > 20% threshold (${totalErrors}/${totalCalls} calls in hour ${hourKey})`;
            console.warn(`[bereanSLOCheck] SLO BREACH — ${reason}`);
            await statusRef.set({
              status: "degraded",
              reason: `SLO breach: ${reason}`,
              triggeredAt: admin.firestore.Timestamp.now(),
              autoTriggered: true,
              hourKey,
              errorRate,
              totalCalls,
              totalErrors,
            }, {merge: true});
            return;
          }
        }

        // ── Check: latency SLO ────────────────────────────────────────────
        if (latencyCalls >= 10 && avgLatencyMs > 15000) {
          const reason = `average latency ${(avgLatencyMs / 1000).toFixed(1)}s > 15s threshold (${latencyCalls} samples in hour ${hourKey})`;
          console.warn(`[bereanSLOCheck] SLO BREACH — ${reason}`);
          await statusRef.set({
            status: "degraded",
            reason: `SLO breach: ${reason}`,
            triggeredAt: admin.firestore.Timestamp.now(),
            autoTriggered: true,
            hourKey,
            avgLatencyMs,
            latencyCalls,
          }, {merge: true});
          return;
        }

        // ── All clear — restore status if it was previously degraded ──────
        const currentStatusSnap = await statusRef.get();
        if (currentStatusSnap.exists && currentStatusSnap.data()?.autoTriggered === true) {
          const prevStatus = currentStatusSnap.data()?.status;
          if (prevStatus === "degraded") {
            await statusRef.set({
              status: "healthy",
              reason: `Auto-recovered: error rate ${totalCalls > 0 ? ((totalErrors / totalCalls) * 100).toFixed(1) : 0}%, latency ${(avgLatencyMs / 1000).toFixed(1)}s`,
              recoveredAt: admin.firestore.Timestamp.now(),
              autoTriggered: true,
              hourKey,
            }, {merge: true});
            console.log("[bereanSLOCheck] SLO recovered — status restored to healthy.");
          }
        }

        console.log(`[bereanSLOCheck] OK — calls: ${totalCalls}, errors: ${totalErrors}, avgLatency: ${(avgLatencyMs / 1000).toFixed(1)}s`);
      } catch (err) {
        console.error("[bereanSLOCheck] check failed:", err);
      }
    },
);
