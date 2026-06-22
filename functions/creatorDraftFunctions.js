/**
 * creatorDraftFunctions.js
 * AMEN App — Creator Draft AI (generateCreatorDraft callable)
 *
 * Accepts: { contentType, topic, tone, targetAudience, scriptureBase, length }
 * Returns: { draftId, contentType, title, body, suggestedHashtags, scriptures,
 *             callToAction, approved: false }
 *
 * Hard rules (never violate):
 *   1. Auth required — unauthenticated calls are rejected.
 *   2. Role check — only users with role "creator" | "mentor" | "church" may call.
 *   3. NVIDIA_API_KEY only via Secret Manager / defineSecret.
 *   4. Draft saved to creatorDrafts/{uid}/{draftId} with approved:false, publishedAt:null.
 *   5. Draft runs through moderation gate before being returned to the UI.
 *   6. NEVER auto-publishes — approved is always false at write time.
 *   7. Fallback: if NVIDIA unavailable, return { draft: null, error: "draft_unavailable" }.
 *   8. Rate limit: 20 drafts per user per hour.
 *   9. Timeout: 60 seconds.
 *   10. AI model: nvidia/meta/llama-3.1-70b-instruct via integrate.api.nvidia.com.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// ─── Secret ───────────────────────────────────────────────────────────────────
// Set once: firebase functions:secrets:set NVIDIA_API_KEY --project amen-5e359
const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";
const NIM_CHAT_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const CREATOR_MODEL = "meta/llama-3.1-70b-instruct";

// Roles authorised to generate creator drafts
const ALLOWED_ROLES = ["creator", "mentor", "church"];

// Valid input enumerations
const VALID_CONTENT_TYPES = ["post", "devotional", "studyGuide", "sermon"];
const VALID_TONES = ["encouraging", "teaching", "prophetic", "pastoral"];
const VALID_LENGTHS = ["short", "medium", "long"];

// Approximate token budgets per length × content-type combination
const TOKEN_BUDGET = {
  short:  { post: 200, devotional: 400, studyGuide: 500, sermon: 600 },
  medium: { post: 400, devotional: 700, studyGuide: 900, sermon: 1100 },
  long:   { post: 600, devotional: 1000, studyGuide: 1400, sermon: 1600 },
};

// ─── System prompt (spec-mandated, must not be altered) ──────────────────────

const CREATOR_SYSTEM_PROMPT = `You are a helpful assistant for Christian content creators. You help write posts, devotionals, and study guides that are:
- Biblically grounded and theologically sound
- Encouraging and pastoral in tone
- Free of prosperity gospel, manipulation, or harmful theology
- Appropriate for a diverse Christian community
Always cite specific scripture references. Never make claims about guaranteed health, wealth, or outcomes.

You MUST respond with a single valid JSON object (no markdown, no explanation, no extra text) with this exact shape:
{
  "title": "string (concise title, max 10 words)",
  "body": "string (the main draft content)",
  "suggestedHashtags": ["string", ...],
  "scriptures": ["reference string", ...],
  "callToAction": "string (one sentence)"
}`;

// ─── Helper: call NVIDIA NIM ──────────────────────────────────────────────────

async function callNIM(apiKey, userPrompt, maxTokens) {
  const controller = new AbortController();
  // Inner timeout guard — function-level timeout is 60 s; NIM call budget is 50 s.
  const tid = setTimeout(() => controller.abort(), 50000);

  let res;
  try {
    res = await fetch(NIM_CHAT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: CREATOR_MODEL,
        messages: [
          { role: "system", content: CREATOR_SYSTEM_PROMPT },
          { role: "user",   content: userPrompt },
        ],
        max_tokens: maxTokens,
        temperature: 0.7,
        top_p: 0.9,
        stream: false,
      }),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(tid);
  }

  if (!res.ok) {
    const body = await res.text().catch(() => "(no body)");
    throw new Error(`NIM ${res.status}: ${body}`);
  }

  const data = await res.json();
  const raw = data.choices?.[0]?.message?.content ?? "";
  // Strip any accidental markdown fences the model may add
  const cleaned = raw
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();

  return JSON.parse(cleaned); // Throws if model returns invalid JSON
}

// ─── Helper: moderate draft body via NeMo Guard ───────────────────────────────

const NIM_SAFETY_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL   = "nvidia/llama-3.1-nemoguard-8b-content-safety";

async function moderateDraft(text, apiKey) {
  try {
    const res = await fetch(NIM_SAFETY_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: SAFETY_MODEL,
        messages: [{ role: "user", content: text }],
        max_tokens: 100,
        temperature: 0,
        stream: false,
      }),
      signal: AbortSignal.timeout(15000),
    });

    // SECURITY FIX (HIGH 2026-06-11): Fail closed on HTTP error.
    // The previous return { safe: true } allowed unsafe draft content to reach the
    // onCreate trigger with no client-side warning, weakening defense-in-depth.
    if (!res.ok) return { safe: false, categories: ["http_error"] };

    const data = await res.json();
    const raw  = data.choices?.[0]?.message?.content ?? "";

    let safe       = false; // fail closed by default
    let categories = [];
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && "User Safety" in parsed) {
        // EXACT match only — never use negation-based substring checks.
        // !/unsafe/i.test(raw) is bypassable via "this is not unsafe content".
        safe = String(parsed["User Safety"]).trim().toLowerCase() === "safe";
        if (parsed["Safety Categories"]) {
          categories = String(parsed["Safety Categories"])
            .split(",")
            .map((c) => c.trim().toLowerCase())
            .filter(Boolean);
        }
      }
      // else: JSON parsed but "User Safety" key absent — fail closed (safe stays false).
    } catch {
      // Non-JSON response — treat as UNSAFE (fail closed).
      // SECURITY: Do NOT use !/unsafe/i.test(raw) here — that pattern can be defeated
      // by responses like "this is not unsafe content" and classifies harm as safe.
      safe = false;
      categories = ["parse_error"];
    }

    return { safe, categories };
  } catch {
    // SECURITY FIX (HIGH 2026-06-11): Fail closed on outer catch.
    // The previous return { safe: true } allowed unsafe draft content through when the
    // moderation fetch itself failed. Defense-in-depth requires failing closed here.
    return { safe: false, categories: ["moderation_fetch_failed"] };
  }
}

// ─── Helper: enforce hourly rate limit ───────────────────────────────────────

async function enforceCreatorDraftRateLimit(uid) {
  const db = getFirestore();
  const limiterRef = db
    .collection("users")
    .doc(uid)
    .collection("creatorDraftUsage")
    .doc("hourly");

  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(limiterRef);
    const d    = snap.exists ? snap.data() : { count: 0, windowStart: now };
    const inWindow = now - d.windowStart < 3_600_000;

    if (inWindow && d.count >= 20) {
      throw new HttpsError(
        "resource-exhausted",
        "Draft generation limit reached (20/hour). Please try again later."
      );
    }

    tx.set(
      limiterRef,
      inWindow
        ? { count: d.count + 1, windowStart: d.windowStart }
        : { count: 1, windowStart: now }
    );
  });
}

// ─── Main callable ────────────────────────────────────────────────────────────

exports.generateCreatorDraft = onCall(
  {
    region: REGION,
    secrets: [NVIDIA_API_KEY],
    enforceAppCheck: true,
    timeoutSeconds: 60,
  },
  async (request) => {
    // ── 1. Auth check ─────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── 2. Role check: creator / mentor / church only ─────────────────────────
    const db = getFirestore();
    const userSnap = await db.collection("users").doc(uid).get();
    const userRole = userSnap.exists ? (userSnap.data().role || "") : "";

    if (!ALLOWED_ROLES.includes(userRole)) {
      throw new HttpsError(
        "permission-denied",
        "Creator draft generation requires a creator, mentor, or church account."
      );
    }

    // ── 3. Input validation ───────────────────────────────────────────────────
    const {
      contentType,
      topic,
      tone          = "pastoral",
      targetAudience = "faith community",
      scriptureBase  = "",
      length         = "medium",
    } = request.data || {};

    if (!contentType || !VALID_CONTENT_TYPES.includes(contentType)) {
      throw new HttpsError(
        "invalid-argument",
        `contentType must be one of: ${VALID_CONTENT_TYPES.join(", ")}.`
      );
    }
    if (!topic || typeof topic !== "string" || topic.trim().length < 5) {
      throw new HttpsError("invalid-argument", "topic is required (min 5 characters).");
    }
    if (topic.length > 500) {
      throw new HttpsError("invalid-argument", "topic must be 500 characters or fewer.");
    }
    const safeTone     = VALID_TONES.includes(tone)     ? tone     : "pastoral";
    const safeLength   = VALID_LENGTHS.includes(length) ? length   : "medium";
    const safeAudience = typeof targetAudience === "string"
      ? targetAudience.trim().slice(0, 150)
      : "faith community";
    const safeScripture = typeof scriptureBase === "string"
      ? scriptureBase.trim().slice(0, 200)
      : "";

    // ── 4. Rate limit: 20 / hour ──────────────────────────────────────────────
    await enforceCreatorDraftRateLimit(uid);

    // ── 5. Build NIM user prompt ──────────────────────────────────────────────
    const contentTypeLabels = {
      post:       "social media post (Christian community)",
      devotional: "daily devotional",
      studyGuide: "Bible study guide",
      sermon:     "sermon draft / outline",
    };

    const lengthGuidance = {
      short:  "Keep content concise — roughly 100-200 words for the body.",
      medium: "Use moderate length — roughly 300-500 words for the body.",
      long:   "Write a fuller piece — roughly 600-900 words for the body.",
    };

    const userPrompt = [
      `Create a ${safeTone}-toned ${contentTypeLabels[contentType]}.`,
      `Topic: ${topic.trim()}`,
      safeAudience ? `Target audience: ${safeAudience}` : null,
      safeScripture ? `Scripture base / passage: ${safeScripture}` : null,
      lengthGuidance[safeLength],
      "Remember to cite specific scripture references and never claim guaranteed health, wealth, or outcomes.",
    ]
      .filter(Boolean)
      .join("\n");

    const maxTokens = TOKEN_BUDGET[safeLength][contentType] ?? 700;

    // ── 6. Call NVIDIA NIM ────────────────────────────────────────────────────
    const apiKey = NVIDIA_API_KEY.value();
    if (!apiKey) {
      return { draft: null, error: "draft_unavailable" };
    }

    let parsed;
    try {
      parsed = await callNIM(apiKey, userPrompt, maxTokens);
    } catch (err) {
      console.error("[generateCreatorDraft] NIM error:", err.message);
      return { draft: null, error: "draft_unavailable" };
    }

    // Validate parsed shape — NIM may occasionally return well-formed JSON but
    // missing required keys.
    if (!parsed || typeof parsed.body !== "string") {
      console.error("[generateCreatorDraft] Unexpected NIM response shape:", parsed);
      return { draft: null, error: "draft_unavailable" };
    }

    // ── 7. Moderation gate before returning to UI ─────────────────────────────
    const draftTextForModeration = [
      parsed.title || "",
      parsed.body  || "",
      parsed.callToAction || "",
    ]
      .join(" ")
      .trim();

    const modResult = await moderateDraft(draftTextForModeration, apiKey);
    const isSafe    = modResult.safe;
    const moderationCategories = modResult.categories;

    // ── 8. Persist to Firestore: creatorDrafts/{uid}/{draftId} ───────────────
    const draftRef = db
      .collection("creatorDrafts")
      .doc(uid)
      .collection("drafts")
      .doc(); // auto-id

    const draftId = draftRef.id;

    const draftDoc = {
      draftId,
      uid,
      contentType,
      title:             (parsed.title            || "").trim().slice(0, 200),
      body:              (parsed.body             || "").trim(),
      suggestedHashtags: Array.isArray(parsed.suggestedHashtags)
        ? parsed.suggestedHashtags.map((h) => String(h)).slice(0, 10)
        : [],
      scriptures:        Array.isArray(parsed.scriptures)
        ? parsed.scriptures.map((s) => String(s)).slice(0, 20)
        : [],
      callToAction:      (parsed.callToAction     || "").trim().slice(0, 300),
      // Draft contract — approved must remain false at write time
      approved:          false,
      publishedAt:       null,
      // Metadata
      tone:              safeTone,
      length:            safeLength,
      targetAudience:    safeAudience,
      scriptureBase:     safeScripture,
      topic:             topic.trim(),
      moderation: {
        safe:        isSafe,
        categories:  moderationCategories,
        checkedAt:   FieldValue.serverTimestamp(),
        provider:    "nvidia-nemoguard",
      },
      createdAt: FieldValue.serverTimestamp(),
    };

    try {
      await draftRef.set(draftDoc);
    } catch (writeErr) {
      console.error("[generateCreatorDraft] Firestore write failed:", writeErr.message);
      // Return the draft anyway — the save failure is logged but shouldn't
      // block the creator's workflow. A retry mechanism can be added later.
    }

    // ── 9. If moderation flagged the draft, still return it but mark as flagged ─
    //    The UI should inform the creator that the draft needs review before sharing.

    console.info("[generateCreatorDraft] Draft generated:", {
      uid, draftId, contentType, isSafe, moderationCategories,
    });

    return {
      draftId,
      contentType,
      title:             draftDoc.title,
      body:              draftDoc.body,
      suggestedHashtags: draftDoc.suggestedHashtags,
      scriptures:        draftDoc.scriptures,
      callToAction:      draftDoc.callToAction,
      approved:          false,
      moderationFlagged: !isSafe,
    };
  }
);
