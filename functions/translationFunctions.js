/**
 * translationFunctions.js
 * Cloud Function for AMEN Translation Service.
 *
 * Provides the POST /v1/translate endpoint that TranslationService.swift calls.
 * Uses Google Cloud Translation API v3 (Advanced) via the project's default
 * service account credentials (no separate API key needed in Cloud Functions).
 *
 * Firestore collections written:
 *   translations/{cacheKey}  — global translation cache (public content only)
 *   translationAnalytics/{date}/events/{eventId} — usage analytics
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

// Lazy-init GCP Translation client (avoid cold-start penalty if unused)
let translationClient = null;
function getTranslationClient() {
  if (!translationClient) {
    const {TranslationServiceClient} = require("@google-cloud/translate").v3;
    translationClient = new TranslationServiceClient();
  }
  return translationClient;
}

// GCP project ID (auto-detected from environment)
const projectId = () => process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT ||
    admin.instanceId().app.options.projectId || "amen-app";

// Supported language codes (ISO 639-1)
const SUPPORTED_LANGUAGES = new Set([
  "en", "es", "fr", "pt", "de", "it", "zh", "ja", "ko", "ar",
  "hi", "sw", "yo", "ig", "ha", "nl", "ru", "pl", "tl", "id",
]);

// ─── Main Translation Callable ───────────────────────────────────────────────

/**
 * Translates text using Google Cloud Translation API v3.
 *
 * Expected request.data:
 *   requestId: string (client-generated UUID for idempotency)
 *   text: string (source text, max 5000 chars)
 *   sourceLanguage: string | null (ISO 639-1, null for auto-detect)
 *   targetLanguage: string (ISO 639-1)
 *   contentType: string (post, comment, testimony, etc.)
 *   contentId: string (Firestore doc ID)
 *   isPublicContent: boolean (controls Firestore cache write)
 *   surface: string (feed, postDetail, commentSheet, etc.)
 *   engineHint: string | null (optional preference)
 *
 * Returns TranslationResponse:
 *   requestId, translatedText, sourceLanguage, targetLanguage,
 *   engineVersion, cacheHit, charactersBilled, latencyMs
 */
const translateText = onCall(
    {
      region: "us-central1",
      memory: "256MiB",
      timeoutSeconds: 30,
    },
    async (request) => {
      const startMs = Date.now();
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {
        requestId,
        text,
        sourceLanguage,
        targetLanguage,
        contentType,
        contentId,
        isPublicContent,
        surface,
      } = request.data;

      // ── Validation ──────────────────────────────────────────────────────

      if (!text || typeof text !== "string") {
        throw new HttpsError("invalid-argument", "text is required");
      }
      if (!targetLanguage || !SUPPORTED_LANGUAGES.has(targetLanguage)) {
        throw new HttpsError("invalid-argument", `Unsupported target language: ${targetLanguage}`);
      }
      if (text.length > 5000) {
        throw new HttpsError("invalid-argument", "Text exceeds 5000 character limit");
      }

      // ── Rate Limit (100 requests/day per user) ─────────────────────────

      try {
        await checkRateLimit(uid, "translate", 100, 86400); // 100 per 24h
      } catch (err) {
        if (err.message?.includes("rate_limit")) {
          throw new HttpsError("resource-exhausted", "Daily translation limit reached");
        }
        // Non-fatal rate limit error — allow the request
      }

      // ── Cache Check (Firestore L3) ─────────────────────────────────────

      const srcLang = sourceLanguage || "auto";
      const cacheKey = generateCacheKey(text, srcLang, targetLanguage);

      try {
        const cached = await db().collection("translations").doc(cacheKey).get();
        if (cached.exists) {
          const data = cached.data();
          // Update access metadata
          await cached.ref.update({
            lastAccessedAt: admin.firestore.FieldValue.serverTimestamp(),
            accessCount: admin.firestore.FieldValue.increment(1),
          });

          const latencyMs = Date.now() - startMs;
          await logAnalytics(uid, {requestId, contentType, surface, srcLang, targetLanguage,
            engine: "cache", cacheHit: true, charactersBilled: 0, latencyMs});

          return {
            requestId: requestId || "",
            translatedText: data.translatedText,
            sourceLanguage: data.sourceLanguage,
            targetLanguage: data.targetLanguage,
            engineVersion: data.engineVersion || "gcp-v3",
            cacheHit: true,
            charactersBilled: 0,
            latencyMs,
          };
        }
      } catch (cacheErr) {
        console.log("Cache lookup failed (non-fatal):", cacheErr.message);
      }

      // ── Google Cloud Translation API v3 ────────────────────────────────

      try {
        const client = getTranslationClient();
        const parent = `projects/${projectId()}/locations/global`;

        const apiRequest = {
          parent,
          contents: [text],
          mimeType: "text/plain",
          targetLanguageCode: targetLanguage,
        };

        // Only set source language if provided (otherwise auto-detect)
        if (sourceLanguage && sourceLanguage !== "auto") {
          apiRequest.sourceLanguageCode = sourceLanguage;
        }

        const [response] = await client.translateText(apiRequest);

        if (!response.translations || response.translations.length === 0) {
          throw new HttpsError("internal", "Translation API returned empty result");
        }

        const translation = response.translations[0];
        const translatedText = translation.translatedText;
        const detectedSourceLang = translation.detectedLanguageCode || sourceLanguage || "unknown";
        const charactersBilled = text.length;
        const latencyMs = Date.now() - startMs;

        // ── Cache Write (public content only) ────────────────────────────

        if (isPublicContent !== false) {
          try {
            await db().collection("translations").doc(cacheKey).set({
              originalText: text,
              translatedText,
              sourceLanguage: detectedSourceLang,
              targetLanguage,
              engineVersion: "gcp-v3",
              characterCount: text.length,
              isPublicContent: true,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              lastAccessedAt: admin.firestore.FieldValue.serverTimestamp(),
              accessCount: 1,
            });
          } catch (cacheWriteErr) {
            console.log("Cache write failed (non-fatal):", cacheWriteErr.message);
          }
        }

        // ── Analytics ────────────────────────────────────────────────────

        await logAnalytics(uid, {requestId, contentType, surface,
          srcLang: detectedSourceLang, targetLanguage,
          engine: "gcp-v3", cacheHit: false, charactersBilled, latencyMs});

        return {
          requestId: requestId || "",
          translatedText,
          sourceLanguage: detectedSourceLang,
          targetLanguage,
          engineVersion: "gcp-v3",
          cacheHit: false,
          charactersBilled,
          latencyMs,
        };
      } catch (error) {
        console.error("Translation API error:", error.message);

        if (error instanceof HttpsError) throw error;

        // Map GCP errors to user-friendly messages
        if (error.code === 3 || error.message?.includes("INVALID_ARGUMENT")) {
          throw new HttpsError("invalid-argument", "Unsupported language pair");
        }
        if (error.code === 8 || error.message?.includes("RESOURCE_EXHAUSTED")) {
          throw new HttpsError("resource-exhausted", "Translation quota exceeded");
        }

        throw new HttpsError("internal", "Translation service temporarily unavailable");
      }
    },
);

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Generate a deterministic cache key (same algorithm as iOS client).
 * SHA-256 of normalized text + language pair + engine version.
 */
function generateCacheKey(text, sourceLang, targetLang) {
  const crypto = require("crypto");
  const normalized = text.trim().toLowerCase().replace(/\s+/g, " ");
  const input = `${normalized}|${sourceLang}|${targetLang}|gcp-v3`;
  return crypto.createHash("sha256").update(input, "utf8").digest("hex");
}

/**
 * Fire-and-forget analytics logging.
 */
async function logAnalytics(uid, data) {
  try {
    const crypto = require("crypto");
    const userHash = crypto.createHash("sha256").update(uid).digest("hex").substring(0, 12);
    const dateStr = new Date().toISOString().split("T")[0];

    await db()
        .collection("translationAnalytics")
        .doc(dateStr)
        .collection("events")
        .add({
          userHash,
          requestId: data.requestId || "",
          contentType: data.contentType || "unknown",
          surface: data.surface || "unknown",
          sourceLanguage: data.srcLang,
          targetLanguage: data.targetLanguage,
          engine: data.engine,
          cacheHit: data.cacheHit || false,
          charactersBilled: data.charactersBilled || 0,
          latencyMs: data.latencyMs || 0,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
  } catch (err) {
    // Non-fatal — analytics should never block translation
    console.log("Analytics log failed:", err.message);
  }
}

module.exports = {
  translateText,
};
