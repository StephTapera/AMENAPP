/**
 * ttsService.js
 * AMEN — Text-to-Speech callable backed by Google Cloud TTS.
 *
 * Exports:
 *   generateSpeech   — convert text to an MP3 audio data URL, returned to client
 *   generatePrayerAudio — convenience wrapper for prayer/devotional audio
 *
 * HARD RULES:
 *   - Auth required on every callable.
 *   - Rate limit: 20 TTS requests per user per hour.
 *   - Max input: 5 000 characters.
 *   - Audio returned as base64 data URL — never stored without user intent.
 *   - No NVIDIA key needed; uses Google Cloud TTS via service account credentials.
 *
 * Use cases:
 *   - Daily Digest read-aloud
 *   - Devotional / prayer playback
 *   - Accessibility: read sermon notes aloud
 *   - Voice replies draft preview
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REGION = "us-central1";

// ─── Rate limit helper ────────────────────────────────────────────────────────

const TTS_LIMIT   = 20;
const TTS_WINDOW  = 60 * 60 * 1000; // 1 hour

async function isTTSRateLimited(uid) {
  const now = Date.now();
  const ref  = admin.firestore().collection("rateLimitCounters").doc(`${uid}_tts`);
  return admin.firestore().runTransaction(async (tx) => {
    const doc     = await tx.get(ref);
    const data    = doc.exists ? doc.data() : { timestamps: [] };
    const recent  = (data.timestamps || []).filter((ts) => ts > now - TTS_WINDOW);
    if (recent.length >= TTS_LIMIT) return true;
    recent.push(now);
    tx.set(ref, { timestamps: recent }, { merge: true });
    return false;
  });
}

// ─── Google Cloud TTS call ─────────────────────────────────────────────────────

const GOOGLE_TTS_URL = "https://texttospeech.googleapis.com/v1/text:synthesize";

// Voice options per content type
const VOICE_PROFILES = {
  prayer:     { languageCode: "en-US", name: "en-US-Neural2-J", ssmlGender: "MALE" },
  devotional: { languageCode: "en-US", name: "en-US-Neural2-F", ssmlGender: "FEMALE" },
  digest:     { languageCode: "en-US", name: "en-US-Neural2-C", ssmlGender: "FEMALE" },
  default:    { languageCode: "en-US", name: "en-US-Neural2-D", ssmlGender: "MALE" },
};

/**
 * Call Google Cloud TTS REST API using the Functions service account credentials.
 * Returns base64-encoded MP3 audio.
 */
async function callGoogleTTS(text, contentType) {
  // Obtain a short-lived access token from the metadata server
  const tokenRes = await fetch(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { headers: { "Metadata-Flavor": "Google" }, signal: AbortSignal.timeout(5000) }
  );
  if (!tokenRes.ok) throw new Error(`Metadata token fetch failed: ${tokenRes.status}`);
  const tokenData = await tokenRes.json();
  const accessToken = tokenData.access_token;

  const voice = VOICE_PROFILES[contentType] || VOICE_PROFILES.default;

  const res = await fetch(GOOGLE_TTS_URL, {
    method:  "POST",
    headers: {
      "Content-Type":  "application/json",
      Authorization:   `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      input:       { text: text.slice(0, 5000) },
      voice,
      audioConfig: { audioEncoding: "MP3", speakingRate: 0.95, pitch: 0 },
    }),
    signal: AbortSignal.timeout(30_000),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "(no body)");
    throw new Error(`Google TTS HTTP ${res.status}: ${body.slice(0, 200)}`);
  }

  const data = await res.json();
  if (!data.audioContent) throw new Error("Google TTS returned no audioContent");
  return data.audioContent; // base64-encoded MP3
}

// ─── generateSpeech ────────────────────────────────────────────────────────────

/**
 * generateSpeech — callable
 *
 * Request:  { text: string, contentType?: "prayer"|"devotional"|"digest"|"default" }
 * Response: { audioBase64: string, contentType: string, charCount: number }
 *
 * The client can play the MP3 via:
 *   let audio = new Audio(`data:audio/mp3;base64,${audioBase64}`);
 *   audio.play();
 */
exports.generateSpeech = onCall(
  { region: REGION, timeoutSeconds: 45, memory: "256MiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    const { text, contentType = "default" } = request.data ?? {};

    if (!text || typeof text !== "string" || text.trim().length === 0) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > 5000) {
      throw new HttpsError("invalid-argument", "text exceeds the 5 000-character limit.");
    }

    const limited = await isTTSRateLimited(uid);
    if (limited) {
      throw new HttpsError("resource-exhausted", "TTS rate limit reached. Try again in an hour.");
    }

    const validTypes = new Set(["prayer", "devotional", "digest", "default"]);
    const safeType   = validTypes.has(contentType) ? contentType : "default";

    let audioBase64 = "";
    try {
      audioBase64 = await callGoogleTTS(text.trim(), safeType);
    } catch (err) {
      console.error(`[ttsService:generateSpeech] TTS error uid=${uid}:`, err.message);
      throw new HttpsError("internal", "Audio generation failed. Please try again.");
    }

    console.log(`[ttsService:generateSpeech] uid=${uid} type=${safeType} chars=${text.length}`);
    return { audioBase64, contentType: safeType, charCount: text.length };
  }
);

// ─── generatePrayerAudio ───────────────────────────────────────────────────────

/**
 * generatePrayerAudio — callable
 *
 * Convenience wrapper: synthesises a prayer text using the "prayer" voice profile.
 *
 * Request:  { prayerText: string }
 * Response: { audioBase64: string }
 */
exports.generatePrayerAudio = onCall(
  { region: REGION, timeoutSeconds: 45, memory: "256MiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    const prayerText = request.data?.prayerText;
    if (!prayerText || typeof prayerText !== "string" || prayerText.trim().length === 0) {
      throw new HttpsError("invalid-argument", "prayerText is required.");
    }

    const limited = await isTTSRateLimited(uid);
    if (limited) {
      throw new HttpsError("resource-exhausted", "TTS rate limit reached.");
    }

    let audioBase64 = "";
    try {
      audioBase64 = await callGoogleTTS(prayerText.trim().slice(0, 5000), "prayer");
    } catch (err) {
      console.error(`[ttsService:generatePrayerAudio] uid=${uid}:`, err.message);
      throw new HttpsError("internal", "Prayer audio generation failed.");
    }

    return { audioBase64 };
  }
);
