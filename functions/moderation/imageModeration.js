"use strict";

/**
 * imageModeration.js
 *
 * Image safety assessment for the AMEN moderation pipeline.
 *
 * Flow per image URL:
 *   1. Download the image from Firebase Storage using the Admin SDK.
 *      The image URL must be a Firebase Storage gs:// or https://firebasestorage.googleapis.com URL.
 *   2. Convert the downloaded bytes to base64.
 *   3. Call providerRouter.callVisionModel with a faith-context safety prompt.
 *   4. Parse the JSON response.
 *   5. Return a structured result.
 *
 * FAIL CLOSED:
 *   - Any error at any step returns { safe: false, status: "pending_image_review",
 *     categories: ["image_review_required"] }.
 *   - Images are NEVER silently approved when the vision model is unavailable.
 *   - This ensures every image enters the human review queue when automation fails.
 *
 * Exports:
 *   moderateImage(imageUrl, apiKey)
 */

const { getStorage }      = require("firebase-admin/storage");
const { callVisionModel, VISION_MODEL } = require("./providerRouter");

// ─── Constants ────────────────────────────────────────────────────────────────

const FAIL_CLOSED_RESULT = Object.freeze({
  safe:       false,
  status:     "pending_image_review",
  categories: ["image_review_required"],
  provider:   "nvidia",
  model:      VISION_MODEL,
  latency:    0,
});

// Maximum image size to download (10 MB); larger images are sent to review.
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

// ─── Vision prompt ────────────────────────────────────────────────────────────

const SAFETY_PROMPT = `You are a content safety reviewer for Amen, a Christian faith-based social media platform.

Review the image and respond ONLY with valid JSON — no markdown, no prose:
{"safe": true, "categories": [], "reason": "one sentence", "confidence": "high"}

"safe" must be true or false.
"categories" must be an array of zero or more strings from this list:
  sexual_content, nudity, suggestive_content, graphic_violence, self_harm,
  hate_speech, discrimination, threat, dangerous_activity,
  cs_csam_suspected, cs_child_exploitation, other_policy_violation
"confidence" must be "high", "medium", or "low".

APPROPRIATE for Amen:
- Crosses, Scripture, churches, Christian symbols and art
- Worship services, baptisms, prayer gatherings, fellowship
- Biblical scenes (including historical depictions of suffering when clearly artistic)
- Nature, family moments, community events
- Motivational or spiritual imagery

INAPPROPRIATE for Amen:
- Sexual, nude, or suggestive content
- Gratuitous violence unrelated to spiritual context
- Hate symbols or imagery targeting any group
- Drug use or illegal activity
- Mockery of faith, believers, or Scripture
- Any content involving minors in a sexual or exploitative context`;

// ─── parseVisionResponse ──────────────────────────────────────────────────────

/**
 * parseVisionResponse(rawText)
 *
 * Parses the vision model's JSON response. Fails closed: any parse error or
 * unexpected structure returns { safe: false, categories: ["image_review_required"] }.
 *
 * @param {string} rawText
 * @returns {{ safe: boolean, categories: string[], reason: string, confidence: string }}
 */
function parseVisionResponse(rawText) {
  const stripped = rawText
    .replace(/^```json?\s*/i, "")
    .replace(/```\s*$/, "")
    .trim();

  try {
    const parsed = JSON.parse(stripped);

    const safe = parsed.safe === true;
    const categories = Array.isArray(parsed.categories)
      ? parsed.categories.map((c) => String(c).trim().toLowerCase()).filter(Boolean)
      : [];
    const reason = typeof parsed.reason === "string" ? parsed.reason.slice(0, 300) : "";
    const confidence = ["high", "medium", "low"].includes(parsed.confidence)
      ? parsed.confidence
      : "medium";

    return { safe, categories, reason, confidence };
  } catch {
    console.warn("[imageModeration] vision response parse failed — failing closed");
    return {
      safe:       false,
      categories: ["image_review_required"],
      reason:     "parse_error",
      confidence: "low",
    };
  }
}

// ─── downloadImageBytes ───────────────────────────────────────────────────────

/**
 * downloadImageBytes(imageUrl)
 *
 * Downloads image content from Firebase Storage and returns a Buffer.
 *
 * Accepts:
 *   - gs://bucket/path  (Firebase Storage URI)
 *   - https://firebasestorage.googleapis.com/...  (download URL)
 *
 * @param {string} imageUrl
 * @returns {Promise<Buffer>}
 * @throws {Error} if the URL is not a recognised Firebase Storage URL or download fails
 */
async function downloadImageBytes(imageUrl) {
  const storage = getStorage();

  let bucketName;
  let filePath;

  // Parse gs:// URI
  const gsMatch = imageUrl.match(/^gs:\/\/([^/]+)\/(.+)$/);
  if (gsMatch) {
    bucketName = gsMatch[1];
    filePath   = gsMatch[2];
  } else {
    // Parse https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>...
    const httpsMatch = imageUrl.match(
      /https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/([^/]+)\/o\/([^?]+)/
    );
    if (httpsMatch) {
      bucketName = httpsMatch[1];
      filePath   = decodeURIComponent(httpsMatch[2]);
    } else {
      throw new Error(`[imageModeration] Unrecognised Firebase Storage URL: ${imageUrl.slice(0, 100)}`);
    }
  }

  const file = storage.bucket(bucketName).file(filePath);
  const [buffer] = await file.download();

  if (buffer.length > MAX_IMAGE_BYTES) {
    throw new Error(
      `[imageModeration] Image too large (${buffer.length} bytes > ${MAX_IMAGE_BYTES}) — ` +
      "routing to human review"
    );
  }

  return buffer;
}

// ─── moderateImage ────────────────────────────────────────────────────────────

/**
 * moderateImage(imageUrl, apiKey)
 *
 * Assesses a single image URL for content safety.
 *
 * FAIL CLOSED: any error at any step returns FAIL_CLOSED_RESULT.
 * Images are NEVER silently passed when the vision model is unavailable.
 *
 * @param {string} imageUrl  Firebase Storage URL (gs:// or https://firebasestorage...)
 * @param {string} apiKey    NVIDIA_API_KEY.value() from the calling Cloud Function
 * @returns {Promise<{
 *   safe:       boolean,
 *   status:     string,           // "approved" | "blocked" | "pending_image_review"
 *   categories: string[],
 *   reason:     string,
 *   confidence: string,
 *   provider:   string,
 *   model:      string,
 *   latency:    number,
 * }>}
 */
async function moderateImage(imageUrl, apiKey) {
  const startMs = Date.now();

  try {
    // Step 1: Download image from Firebase Storage.
    let imageBuffer;
    try {
      imageBuffer = await downloadImageBytes(imageUrl);
    } catch (downloadErr) {
      console.warn(`[imageModeration] Download failed (${downloadErr.message}) — failing closed`);
      return { ...FAIL_CLOSED_RESULT };
    }

    // Step 2: Convert to base64.
    const imageBase64 = imageBuffer.toString("base64");

    // Step 3: Call vision model via providerRouter.
    let rawText;
    let latencyMs;
    try {
      const response = await callVisionModel(imageBase64, SAFETY_PROMPT, apiKey);
      rawText   = response.rawText;
      latencyMs = response.latencyMs;
    } catch (visionErr) {
      // Vision model unavailable — fail closed.
      console.warn(`[imageModeration] Vision model unavailable (${visionErr.message}) — failing closed`);
      return { ...FAIL_CLOSED_RESULT };
    }

    // Step 4: Parse response.
    const { safe, categories, reason, confidence } = parseVisionResponse(rawText);

    const totalLatency = Date.now() - startMs;

    // Determine status string.
    let status;
    if (safe && categories.length === 0) {
      status = "approved";
    } else if (
      categories.some((c) =>
        ["sexual_content", "nudity", "graphic_violence", "cs_csam_suspected",
         "cs_child_exploitation", "hate_speech", "threat"].includes(c)
      )
    ) {
      status = "blocked";
    } else {
      status = "pending_image_review";
    }

    console.log(
      `[imageModeration] safe=${safe} status=${status} ` +
      `categories=${categories.join(",") || "(none)"} ` +
      `confidence=${confidence} latency=${totalLatency}ms`
    );

    return {
      safe,
      status,
      categories,
      reason,
      confidence,
      provider: "nvidia",
      model:    VISION_MODEL,
      latency:  totalLatency,
    };

  } catch (err) {
    // Outermost catch — any unexpected error: FAIL CLOSED.
    console.error(`[imageModeration] FAIL CLOSED — unexpected error: ${err.message}`);
    return { ...FAIL_CLOSED_RESULT };
  }
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = { moderateImage };
