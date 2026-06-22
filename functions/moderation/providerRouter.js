"use strict";

/**
 * providerRouter.js
 *
 * Centralised NVIDIA NIM API call layer for the AMEN moderation pipeline.
 *
 * Rules enforced here:
 *   - NVIDIA_API_KEY is obtained via defineSecret; never hardcoded or logged.
 *   - All calls are wrapped in a 10-second AbortSignal timeout.
 *   - Exponential backoff: delays of 500ms → 1000ms → 2000ms (max 3 attempts).
 *   - Structured metadata logs only — NO user content ever appears in logs.
 *   - All functions throw on final failure so that callers can implement
 *     fail-closed behaviour.
 *
 * Exports:
 *   NVIDIA_API_KEY   — defineSecret reference (declare once here; pass .value() to callers)
 *   callSafetyModel  — NeMo Guard text safety classification
 *   callVisionModel  — Llama vision instruct for image safety assessment
 */

const { defineSecret } = require("firebase-functions/params");

// ─── Secret declaration ───────────────────────────────────────────────────────
// Any Cloud Function that imports providerRouter must include NVIDIA_API_KEY in
// its secrets array: onCall({ secrets: [NVIDIA_API_KEY] }, handler)

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

// ─── NVIDIA NIM constants ─────────────────────────────────────────────────────

const NIM_URL      = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";
const VISION_MODEL = "meta/llama-3.2-11b-vision-instruct";

const CALL_TIMEOUT_MS   = 10_000;                   // 10 s per attempt
const RETRY_DELAYS_MS   = [500, 1_000, 2_000];      // exponential: 0.5s, 1s, 2s
const MAX_ATTEMPTS      = RETRY_DELAYS_MS.length + 1; // 3 retries = 4 total attempts... capped at 3

// ─── Internal retry helper ────────────────────────────────────────────────────

/**
 * withRetry(fn, label)
 *
 * Retries `fn` up to MAX_ATTEMPTS times with exponential back-off.
 * Logs attempt metadata only — no content.
 * Throws the last error when all attempts are exhausted.
 *
 * @param {() => Promise<*>} fn    Async function to retry
 * @param {string}           label Short label for log messages
 * @returns {Promise<*>}
 */
async function withRetry(fn, label) {
  let lastErr;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const isLast = attempt === MAX_ATTEMPTS - 1;
      if (isLast) break;

      const delay = RETRY_DELAYS_MS[attempt] ?? 2_000;
      console.warn(
        `[providerRouter] ${label} attempt ${attempt + 1}/${MAX_ATTEMPTS} failed ` +
        `(${err.message}) — retrying in ${delay}ms`
      );
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  console.error(
    `[providerRouter] ${label} exhausted all ${MAX_ATTEMPTS} attempts — ` +
    `final error: ${lastErr?.message}`
  );
  throw lastErr;
}

// ─── callSafetyModel ──────────────────────────────────────────────────────────

/**
 * callSafetyModel(text, apiKey)
 *
 * Calls NVIDIA NeMo Guard (llama-3.1-nemoguard-8b-content-safety) for text
 * content safety classification.
 *
 * Returns raw parsed data; higher-level parsing is done in textModeration.js.
 *
 * @param {string} text    Text to classify (should be normalised/trimmed by caller)
 * @param {string} apiKey  NVIDIA_API_KEY.value() from the calling Cloud Function
 * @returns {Promise<{ rawText: string, statusCode: number, latencyMs: number }>}
 * @throws {Error} on HTTP error or all retries exhausted
 */
async function callSafetyModel(text, apiKey) {
  const label = "callSafetyModel";
  const startMs = Date.now();

  const result = await withRetry(async () => {
    const controller = new AbortController();
    const timeoutId  = setTimeout(() => controller.abort(), CALL_TIMEOUT_MS);

    let res;
    try {
      res = await fetch(NIM_URL, {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization:  `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model:       SAFETY_MODEL,
          messages:    [{ role: "user", content: text }],
          max_tokens:  150,
          temperature: 0,
        }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }

    if (!res.ok) {
      const errBody = await res.text().catch(() => "(no body)");
      throw new Error(`NeMo Guard HTTP ${res.status}: ${errBody.slice(0, 200)}`);
    }

    const data    = await res.json();
    const rawText = String(data.choices?.[0]?.message?.content ?? "").trim();

    return { rawText, statusCode: res.status };
  }, label);

  const latencyMs = Date.now() - startMs;

  // Metadata-only log — no content
  console.log(
    `[providerRouter] ${label} provider=nvidia model=${SAFETY_MODEL} ` +
    `status=${result.statusCode} latencyMs=${latencyMs}`
  );

  return { ...result, latencyMs };
}

// ─── callVisionModel ──────────────────────────────────────────────────────────

/**
 * callVisionModel(imageBase64, prompt, apiKey)
 *
 * Calls the NVIDIA NIM Llama vision-instruct model for image safety assessment.
 *
 * The image is passed as a base64 data URI so it never requires a publicly
 * accessible URL.  The prompt must be fully constructed by the caller.
 *
 * @param {string} imageBase64  Base64-encoded image bytes (no data-URI prefix needed;
 *                              this function adds the data:image/jpeg;base64, prefix)
 * @param {string} prompt       Full text prompt for the vision model
 * @param {string} apiKey       NVIDIA_API_KEY.value()
 * @returns {Promise<{ rawText: string, statusCode: number, latencyMs: number }>}
 * @throws {Error} on HTTP error or all retries exhausted
 */
async function callVisionModel(imageBase64, prompt, apiKey) {
  const label  = "callVisionModel";
  const startMs = Date.now();

  // Build a data-URI from the raw base64 string.
  const imageDataUri = imageBase64.startsWith("data:")
    ? imageBase64
    : `data:image/jpeg;base64,${imageBase64}`;

  const result = await withRetry(async () => {
    const controller = new AbortController();
    const timeoutId  = setTimeout(() => controller.abort(), CALL_TIMEOUT_MS);

    let res;
    try {
      res = await fetch(NIM_URL, {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization:  `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model:    VISION_MODEL,
          messages: [{
            role:    "user",
            content: [
              { type: "image_url", image_url: { url: imageDataUri } },
              { type: "text",      text: prompt },
            ],
          }],
          max_tokens:  120,
          temperature: 0,
        }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }

    if (!res.ok) {
      const errBody = await res.text().catch(() => "(no body)");
      throw new Error(`Vision model HTTP ${res.status}: ${errBody.slice(0, 200)}`);
    }

    const data    = await res.json();
    const rawText = String(data.choices?.[0]?.message?.content ?? "").trim();

    return { rawText, statusCode: res.status };
  }, label);

  const latencyMs = Date.now() - startMs;

  // Metadata-only log — no content or image data
  console.log(
    `[providerRouter] ${label} provider=nvidia model=${VISION_MODEL} ` +
    `status=${result.statusCode} latencyMs=${latencyMs}`
  );

  return { ...result, latencyMs };
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  NVIDIA_API_KEY,
  callSafetyModel,
  callVisionModel,
  // Expose model names so callers can stamp them in audit records
  SAFETY_MODEL,
  VISION_MODEL,
};
