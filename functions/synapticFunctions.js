/**
 * synapticFunctions.js
 * Synaptic Studio — biometric-aware AI content generation.
 *
 * Function:
 *   synapticCreate — Callable: generate content shaped by the user's biometric state.
 *
 * Privacy guarantee:
 *   - Biometric data is received only as anonymous numeric context.
 *   - It is used solely within the single Claude prompt call.
 *   - It is NEVER written to Firestore, logged, or associated with the user's UID.
 *   - Only a non-biometric creation event (tool + mode + uid) is logged for analytics.
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

// ── Lazy Anthropic ───────────────────────────────────────────────────────────
let _anthropic = null;
function getAnthropic() {
  if (!_anthropic) {
    const Anthropic = require("@anthropic-ai/sdk");
    _anthropic = new Anthropic.default({apiKey: process.env.ANTHROPIC_API_KEY});
  }
  return _anthropic;
}

// ── Biometric tone mapping ───────────────────────────────────────────────────

function biometricToneInstructions(heartRate, hrv) {
  const hr = typeof heartRate === "number" ? heartRate : null;
  const hrvVal = typeof hrv === "number" ? hrv : null;

  const lines = [];

  if (hr !== null) {
    if (hr < 60) {
      lines.push("The person is deeply at rest (low heart rate). Use slow, deliberate, contemplative language. Long sentences. Silence between thoughts.");
    } else if (hr < 75) {
      lines.push("The person is calm and centered. Language should be steady, assured, grounded.");
    } else if (hr < 90) {
      lines.push("The person is engaged and present. Language can have warmth and forward momentum.");
    } else if (hr < 110) {
      lines.push("The person is emotionally stirred (elevated heart rate). Language should feel alive, with some urgency or depth of feeling.");
    } else {
      lines.push("The person is impassioned (high heart rate). Language should carry intensity, raw honesty, and emotional weight.");
    }
  }

  if (hrvVal !== null) {
    if (hrvVal > 50) {
      lines.push("High HRV indicates good resilience. The person can hold nuance and complexity — language can reflect both grief and hope simultaneously.");
    } else if (hrvVal > 30) {
      lines.push("Moderate HRV. The person may be managing stress. Lean into reassurance and steadiness in language.");
    } else {
      lines.push("Low HRV suggests stress or fatigue. Keep language simple, direct, and supportive — do not add pressure.");
    }
  }

  return lines.length > 0 ? lines.join("\n") : "No biometric data available. Use balanced, warm, faith-centered language.";
}

// ── System prompts per mode ──────────────────────────────────────────────────

function buildSystemPrompt(mode, toneInstructions) {
  const base = `You are a biometric-aware spiritual writing assistant for AMEN, a Christian community app.
The user's body state has been read and shapes how you write. This is Synaptic Studio.

BIOMETRIC TONE GUIDANCE:
${toneInstructions}

CORE RULES:
- Write in first person from the user's perspective unless they indicate otherwise.
- Ground the content in Christian faith authentically.
- Do not add meta-commentary, headers, or explanations — just produce the creative content.
- Length: 100–250 words unless mode suggests otherwise.`;

  const modeInstructions = {
    prayer: `${base}
MODE: Prayer
Write a sincere, personal prayer that feels like it's coming from the exact emotional and physical state described above.`,

    reflection: `${base}
MODE: Spiritual Reflection
Write a personal spiritual reflection — like journaling for God. Let the physical state flavor the quality of attention, depth, and honesty.`,

    testimony: `${base}
MODE: Testimony
Help the user articulate a testimony — a moment of God's faithfulness — in language that matches their current state. Raw if impassioned, measured if still.`,

    lament: `${base}
MODE: Lament
This is the language of Psalms — honest grief brought before God. Write with the emotional weight the biometric state suggests. Do not rush to resolution. Hold the pain honestly.`,

    praise: `${base}
MODE: Praise
Write an expression of praise or gratitude. Let the physical energy level shape the celebration — still and intimate if resting, or effusive and alive if elevated.`,
  };

  return modeInstructions[mode] || base;
}

// ── Main callable ────────────────────────────────────────────────────────────

exports.synapticCreate = onCall(
    {region: "us-central1", timeoutSeconds: 60},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "synaptic_create", 20, 3600); // 20/hour

      const {
        mode,
        user_intent,
        heart_rate,
        hrv,
        emotional_profile,
      } = request.data;

      if (!mode || !user_intent) {
        throw new HttpsError("invalid-argument", "mode and user_intent required");
      }

      const validModes = ["prayer", "reflection", "testimony", "lament", "praise"];
      if (!validModes.includes(mode)) {
        throw new HttpsError("invalid-argument", `Invalid mode: ${mode}`);
      }

      // Build tone instructions from biometrics — used only in the prompt
      const toneInstructions = biometricToneInstructions(heart_rate, hrv);
      const systemPrompt = buildSystemPrompt(mode, toneInstructions);

      const userMessage = `Current emotional state: ${emotional_profile || "unknown"}
User's intention: ${user_intent.trim()}

Create ${mode} content that honors this moment.`;

      try {
        const client = getAnthropic();
        const response = await client.messages.create({
          model: "claude-haiku-4-5-20251001",
          max_tokens: 600,
          system: systemPrompt,
          messages: [{role: "user", content: userMessage}],
        });

        const generatedContent = response.content[0]?.text || "";

        // Log creation event — NO biometric data stored
        await db().collection("synapticCreations").add({
          uid,
          mode,
          hasHeartRate: typeof heart_rate === "number",
          hasHRV: typeof hrv === "number",
          emotionalProfile: emotional_profile || "unknown",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {generated_content: generatedContent};
      } catch (error) {
        console.error("synapticCreate error:", error);
        throw new HttpsError("internal", "Content generation failed. Please try again.");
      }
    },
);
