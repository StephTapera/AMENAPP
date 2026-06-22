"use strict";

/**
 * textModeration.js
 *
 * Text safety classification via NVIDIA NeMo Guard.
 *
 * This module is a thin, hardened wrapper around providerRouter.callSafetyModel.
 * It owns:
 *   - Calling the NeMo Guard model
 *   - Parsing the raw completion text into structured { safe, categories }
 *   - Fail-closed error handling (any error → safe: false)
 *
 * Parsing rules (hardened against prompt-injection and negation bypass):
 *   - Parse the JSON object from the model output.
 *   - Read "User Safety" field: ONLY the literal string "safe" (case-insensitive)
 *     maps to safe=true. Any other value — "unsafe", empty, missing, or unexpected —
 *     maps to safe=false.  There is NO negation logic ("not unsafe" is NOT safe).
 *   - Read "Safety Categories" field: split on comma, trim, lower-case.
 *   - If JSON parse fails: examine raw text for "safe" as a standalone word;
 *     ONLY match the exact word "safe" (not "unsafe").
 *
 * Exports:
 *   moderateText(text, apiKey)
 */

const { callSafetyModel, SAFETY_MODEL } = require("./providerRouter");

// ─── parseNemoResponse ────────────────────────────────────────────────────────

/**
 * parseNemoResponse(rawText)
 *
 * Parses the raw string returned by NeMo Guard into { safe, categories }.
 *
 * Hardened rules:
 *   1. Attempt JSON.parse on rawText (strip any accidental markdown fences first).
 *   2. On success: safe = (User Safety === "safe") — strict equality after toLower().
 *   3. On JSON failure: safe = /\bsafe\b/i.test(rawText) && !/\bunsafe\b/i.test(rawText)
 *      — the word "safe" must appear AND the word "unsafe" must NOT appear.
 *   4. categories are always an array of trimmed, lower-cased strings.
 *
 * @param {string} rawText  Raw completion text from the model
 * @returns {{ safe: boolean, categories: string[] }}
 */
function parseNemoResponse(rawText) {
  const stripped = rawText
    .replace(/^```json?\s*/i, "")
    .replace(/```\s*$/, "")
    .trim();

  // ── JSON path ────────────────────────────────────────────────────────────────
  try {
    const parsed = JSON.parse(stripped);

    // "User Safety" must be exactly the string "safe" (case-insensitive).
    // Any other value — "unsafe", missing, null, non-string — is NOT safe.
    const userSafetyField = parsed["User Safety"];
    const safe =
      typeof userSafetyField === "string" &&
      userSafetyField.trim().toLowerCase() === "safe";

    // "Safety Categories" may be a comma-separated string or an array.
    let categories = [];
    const catField = parsed["Safety Categories"] ?? parsed["safety_categories"] ?? "";
    if (Array.isArray(catField)) {
      categories = catField.map((c) => String(c).trim().toLowerCase()).filter(Boolean);
    } else if (typeof catField === "string" && catField.trim()) {
      categories = catField.split(",").map((c) => c.trim().toLowerCase()).filter(Boolean);
    }

    return { safe, categories };
  } catch {
    // JSON parse failed — fall through to text heuristic.
  }

  // ── Text heuristic (fallback) ────────────────────────────────────────────────
  // Safe ONLY when the word "safe" appears and the word "unsafe" does NOT.
  // This prevents "not unsafe" from being misread as safe.
  const hasSafe   = /\bsafe\b/i.test(stripped);
  const hasUnsafe = /\bunsafe\b/i.test(stripped);
  const safe      = hasSafe && !hasUnsafe;

  return { safe, categories: [] };
}

// ─── moderateText ─────────────────────────────────────────────────────────────

/**
 * moderateText(text, apiKey)
 *
 * Classifies `text` for safety using NVIDIA NeMo Guard.
 *
 * FAIL CLOSED: any unhandled error returns safe: false.
 * This means that if the model is unavailable, the content is treated as unsafe
 * and will enter the pending/review queue rather than being silently approved.
 *
 * @param {string} text    Pre-normalised (trimmed) text content to classify
 * @param {string} apiKey  NVIDIA_API_KEY.value() from the calling Cloud Function
 * @returns {Promise<{
 *   safe:        boolean,
 *   categories:  string[],
 *   rawResponse: string,
 *   provider:    string,
 *   model:       string,
 *   latency:     number,
 * }>}
 */
async function moderateText(text, apiKey) {
  try {
    const { rawText, latencyMs } = await callSafetyModel(text, apiKey);
    const { safe, categories }   = parseNemoResponse(rawText);

    console.log(
      `[textModeration] safe=${safe} categories=${categories.join(",") || "(none)"} ` +
      `model=${SAFETY_MODEL} latency=${latencyMs}ms`
    );

    return {
      safe,
      categories,
      rawResponse: rawText.slice(0, 500),   // truncated for audit storage, never user content
      provider:    "nvidia",
      model:       SAFETY_MODEL,
      latency:     latencyMs,
    };
  } catch (err) {
    // FAIL CLOSED: model unavailable or unexpected error → treat as unsafe.
    console.error(`[textModeration] FAIL CLOSED — model error: ${err.message}`);
    return {
      safe:        false,
      categories:  ["unknown_model_error"],
      rawResponse: "",
      provider:    "nvidia",
      model:       SAFETY_MODEL,
      latency:     0,
    };
  }
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = { moderateText };
