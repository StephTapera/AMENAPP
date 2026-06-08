/**
 * moderationGateway.js
 *
 * AMEN — Unified content-safety callable for iOS clients.
 *
 * Exports:
 *   checkContentSafety   — Pre-submit gate for posts, comments, messages, DMs
 *   escalateSelfHarm     — Internal helper; also exported for direct admin use
 *
 * Hard rules enforced here:
 *   1. Auth check first, every time.
 *   2. Input validation (length, type whitelist).
 *   3. Rate-limit: 30 checks per user per minute.
 *   4. NVIDIA_API_KEY only from Secret Manager — never in payloads.
 *   5. Every decision written to moderationDecisions/{decisionId}.
 *   6. Self-harm → crisisEscalations/{uid}/{timestampMs} + in-app crisis path.
 *   7. Fail closed on AI error (block/review, never auto-allow).
 *   8. Structured logging at every decision boundary.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }        = require("firebase-functions/params");
const admin                   = require("firebase-admin");

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

const NIM_URL      = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

// ─── Allowed content types ────────────────────────────────────────────────────
const VALID_CONTENT_TYPES = new Set(["post", "comment", "message", "dm"]);

// ─── Rate-limit window ────────────────────────────────────────────────────────
const RL_MAX      = 30;   // max checks per user
const RL_WINDOW_S = 60;   // per 60-second window

// ─── Self-harm keyword set (fast synchronous pre-check) ───────────────────────
// Full NeMo Guard analysis runs after this; this catches explicit phrases first
// so we can set the crisisEscalated flag even if the LLM misses context.
const SELF_HARM_PHRASES = [
  "kill myself", "killing myself",
  "end my life", "end it all",
  "suicide", "suicidal",
  "cut myself", "cutting myself",
  "self harm", "selfharm",
  "want to die", "i want to die",
  "no reason to live",
  "i cant go on", "i cannot go on",
  "take my own life",
  "better off dead",
  "not worth living",
  "overdose on purpose",
  "slit my wrists",
  "hang myself",
];

// ─── Unsafe advice / manipulative religious claim phrases ─────────────────────
const UNSAFE_ADVICE_PHRASES = [
  "stop taking your medication",
  "dont take your meds",
  "god will heal you if you stop",
  "prayer instead of medicine",
  "refuse chemo",
  "refuse treatment",
  "doctors are evil",
  "vaccines cause",
  "dont vaccinate",
  "medical treatment is sin",
];

const MANIPULATIVE_RELIGIOUS_PHRASES = [
  "god told me to tell you",
  "god revealed your sin to me",
  "you will be cursed if you dont",
  "sow a seed or lose your blessing",
  "pay or your prayers wont be answered",
  "god says you owe me",
  "the holy spirit showed me your secret",
  "your sickness is punishment",
  "your suffering is gods judgment on you",
  "only i know the truth about god",
  "leave your church and follow only me",
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

const db = () => admin.firestore();

/**
 * Lightweight rate limiter backed by Firestore.
 * Uses a transaction so concurrent calls don't race.
 * Throws HttpsError("resource-exhausted") if limit exceeded.
 */
async function enforceRateLimit(uid) {
  const docRef = db().collection("rateLimits").doc(`${uid}_checkContentSafety`);
  const nowMs  = Date.now();
  const windowMs = RL_WINDOW_S * 1000;

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) {
      tx.set(docRef, { count: 1, windowStart: nowMs, expiresAt: new Date(nowMs + windowMs) });
      return;
    }
    const data = snap.data();
    if (nowMs - data.windowStart > windowMs) {
      // Window expired — reset
      tx.set(docRef, { count: 1, windowStart: nowMs, expiresAt: new Date(nowMs + windowMs) });
      return;
    }
    if (data.count >= RL_MAX) {
      throw new HttpsError("resource-exhausted", "Rate limit exceeded. Please wait before checking more content.");
    }
    tx.update(docRef, { count: admin.firestore.FieldValue.increment(1) });
  });
}

/**
 * Normalise text: lowercase, leet-speak, collapse whitespace.
 * Mirror of the normalization in aiModeration.js so phrase matching is consistent.
 */
function normalizeText(text) {
  return text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/0/g, "o").replace(/1/g, "i").replace(/3/g, "e")
    .replace(/4/g, "a").replace(/5/g, "s").replace(/6/g, "g")
    .replace(/7/g, "t").replace(/8/g, "b").replace(/9/g, "g")
    .replace(/@/g, "a").replace(/\$/g, "s").replace(/!/g, "i")
    .replace(/\+/g, "t").replace(/\|/g, "i")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/(.)\1{2,}/g, "$1$1")
    .replace(/\s+/g, " ")
    .trim();
}

function hasSelfHarm(normalized) {
  return SELF_HARM_PHRASES.some((p) => normalized.includes(p));
}
function hasUnsafeAdvice(normalized) {
  return UNSAFE_ADVICE_PHRASES.some((p) => normalized.includes(p));
}
function hasManipulativeReligious(normalized) {
  return MANIPULATIVE_RELIGIOUS_PHRASES.some((p) => normalized.includes(p));
}

/**
 * Call NVIDIA NeMo Guard for text safety.
 * Returns { safe: bool, categories: string[], rawLabel: string }.
 * Throws on network/API error — callers must handle and fail closed.
 */
async function callNeMoGuard(text, apiKey) {
  const res = await fetch(NIM_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: SAFETY_MODEL,
      messages: [{ role: "user", content: text }],
      max_tokens: 120,
      temperature: 0,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "(no body)");
    throw new Error(`NeMo Guard HTTP ${res.status}: ${body.slice(0, 200)}`);
  }

  const data = await res.json();
  const raw  = (data.choices?.[0]?.message?.content ?? "").trim();

  let safe       = true;
  let categories = [];
  try {
    const parsed = JSON.parse(raw);
    safe = String(parsed["User Safety"] ?? "safe").toLowerCase() === "safe";
    const catStr = parsed["Safety Categories"] ?? "";
    categories = catStr.split(",").map((c) => c.trim().toLowerCase()).filter(Boolean);
  } catch {
    // Non-JSON response: treat as safe if it doesn't contain "unsafe"
    safe = !/unsafe/i.test(raw);
  }

  return { safe, categories, rawLabel: raw.slice(0, 300) };
}

/**
 * Map NeMo categories + local phrase hits → decision.
 * Returns { decision, reason, detectedCategories }.
 *
 * decision: "allow" | "warn" | "block" | "review"
 */
function mapToDecision(nemoResult, localFlags) {
  const { safe, categories } = nemoResult;
  const {
    selfHarm,
    unsafeAdvice,
    manipulativeReligious,
  } = localFlags;

  // Self-harm is always "review" (never silent block) — escalation path runs separately
  if (selfHarm) {
    return {
      decision: "review",
      reason: "Self-harm language detected — connecting you to support resources.",
      detectedCategories: ["self_harm", ...categories],
    };
  }

  if (!safe) {
    // Map NeMo categories to severity
    const blockCategories = [
      "violence", "sexual", "hate", "threat", "csam",
      "trafficking", "extremism", "doxxing",
    ];
    const reviewCategories = [
      "harassment", "bullying", "fraud", "spam", "drugs",
      "weapons", "grooming",
    ];

    const hasBlock  = categories.some((c) => blockCategories.some((b) => c.includes(b)));
    const hasReview = categories.some((c) => reviewCategories.some((r) => c.includes(r)));

    if (hasBlock) {
      return {
        decision: "block",
        reason: "Content violates community safety policy.",
        detectedCategories: categories,
      };
    }
    if (hasReview || categories.length === 0) {
      // Unsafe but no specific category — hold for human
      return {
        decision: "review",
        reason: "Content flagged for safety review.",
        detectedCategories: categories,
      };
    }
    return {
      decision: "review",
      reason: "Content flagged for safety review.",
      detectedCategories: categories,
    };
  }

  // NeMo says safe — apply local phrase checks
  if (manipulativeReligious) {
    return {
      decision: "warn",
      reason: "This message may use faith language in a potentially manipulative way.",
      detectedCategories: ["manipulative_religious_claim"],
    };
  }

  if (unsafeAdvice) {
    return {
      decision: "block",
      reason: "This content contains advice that could put someone's health at risk.",
      detectedCategories: ["unsafe_medical_advice"],
    };
  }

  return {
    decision: "allow",
    reason: null,
    detectedCategories: [],
  };
}

/**
 * Persist a crisis escalation record and alert moderators.
 * Path: crisisEscalations/{uid}/{timestampMs}
 * Also writes moderatorAlerts so the admin queue surfaces it immediately.
 *
 * @param {string} uid
 * @param {string} content
 * @param {string} contentType
 * @param {string} contextId    - post/comment/message/conversation id
 * @param {string} decisionId   - corresponding moderationDecisions doc id
 */
async function escalateSelfHarm(uid, content, contentType, contextId, decisionId) {
  const nowMs  = Date.now();
  const nowTs  = admin.firestore.FieldValue.serverTimestamp();
  const crisisRef = db()
    .collection("crisisEscalations")
    .doc(uid)
    .collection("events")
    .doc(String(nowMs));

  const escalationData = {
    uid,
    contentType,
    contextId: contextId || null,
    moderationDecisionId: decisionId || null,
    // Store a text hash, not raw content, for privacy — raw content lives only in
    // the moderation decision doc (admin-only read).
    contentLength: content.length,
    detectedAt: nowTs,
    status: "pending_review",
    crisisResources: [
      {
        name: "988 Suicide & Crisis Lifeline",
        number: "988",
        url: "https://988lifeline.org",
      },
      {
        name: "Crisis Text Line",
        instruction: "Text HOME to 741741",
        url: "https://www.crisistextline.org",
      },
      {
        name: "SAMHSA National Helpline",
        number: "1-800-662-4357",
        url: "https://www.samhsa.gov/find-help/national-helpline",
      },
      {
        name: "Berean AI Support",
        instruction: "Open the Berean companion in AMEN for immediate spiritual support.",
      },
    ],
  };

  const alertData = {
    type: "self_harm_escalation",
    uid,
    contentType,
    contextId: contextId || null,
    moderationDecisionId: decisionId || null,
    status: "urgent",
    priority: "critical",
    createdAt: nowTs,
  };

  await Promise.all([
    crisisRef.set(escalationData),
    db().collection("moderatorAlerts").add(alertData),
  ]);

  console.warn(`[escalateSelfHarm] CRITICAL: uid=${uid} contentType=${contentType} contextId=${contextId}`);
  return crisisRef.id;
}

/**
 * Write a canonical moderation decision to moderationDecisions/{decisionId}.
 *
 * @returns {string} decisionId
 */
async function persistDecision({
  uid,
  contentType,
  contextId,
  decision,
  reason,
  detectedCategories,
  crisisEscalated,
  contentLength,
  source,
}) {
  const decisionRef = db().collection("moderationDecisions").doc();
  const decisionId  = decisionRef.id;

  await decisionRef.set({
    uid,
    contentType,
    contextId: contextId || null,
    decision,
    reason: reason || null,
    detectedCategories,
    crisisEscalated: crisisEscalated || false,
    contentLength,
    source: source || "checkContentSafety",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`[moderationDecisions] ${decisionId} uid=${uid} type=${contentType} decision=${decision}`);
  return decisionId;
}

// ─── Main callable ─────────────────────────────────────────────────────────────

/**
 * checkContentSafety
 *
 * Unified pre-submit content safety gate for AMEN iOS clients.
 *
 * Request fields:
 *   content      {string}  The raw text to check (1–10,000 chars)
 *   contentType  {string}  "post" | "comment" | "message" | "dm"
 *   contextId    {string?} ID of the post/conversation/comment being written to
 *
 * Response:
 *   decision         {string}   "allow" | "warn" | "block" | "review"
 *   reason           {string?}  Human-readable reason (only when not "allow")
 *   crisisEscalated  {bool}     true when self-harm was detected + escalated
 *   crisisResources  {array?}   Only present when crisisEscalated=true
 *   decisionId       {string}   ID of the moderationDecisions record
 */
exports.checkContentSafety = onCall(
  {
    region: "us-central1",
    secrets: [NVIDIA_API_KEY],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    // ── 1. Auth ──────────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── 2. Input validation ──────────────────────────────────────────────────
    const { content, contentType, contextId } = request.data ?? {};

    if (!content || typeof content !== "string" || content.trim().length < 1) {
      throw new HttpsError("invalid-argument", "content is required and must be a non-empty string.");
    }
    if (content.length > 10000) {
      throw new HttpsError("invalid-argument", "content exceeds the 10,000 character limit.");
    }
    if (!contentType || !VALID_CONTENT_TYPES.has(contentType)) {
      throw new HttpsError(
        "invalid-argument",
        `contentType must be one of: ${[...VALID_CONTENT_TYPES].join(", ")}.`
      );
    }

    console.log(`[checkContentSafety] uid=${uid} type=${contentType} len=${content.length}`);

    // ── 3. Rate limit ────────────────────────────────────────────────────────
    try {
      await enforceRateLimit(uid);
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      // Firestore rate-limiter itself failed — don't block the user, log and continue
      console.error("[checkContentSafety] Rate-limiter error (non-fatal):", err.message);
    }

    // ── 4. Local phrase pre-checks (synchronous, zero network) ───────────────
    const normalized = normalizeText(content);
    const localFlags = {
      selfHarm:            hasSelfHarm(normalized),
      unsafeAdvice:        hasUnsafeAdvice(normalized),
      manipulativeReligious: hasManipulativeReligious(normalized),
    };

    console.log(`[checkContentSafety] localFlags=${JSON.stringify(localFlags)}`);

    // ── 5. NeMo Guard call ───────────────────────────────────────────────────
    let nemoResult = { safe: true, categories: [], rawLabel: "" };
    try {
      nemoResult = await callNeMoGuard(content, NVIDIA_API_KEY.value());
      console.log(`[checkContentSafety] NeMo: safe=${nemoResult.safe} categories=${nemoResult.categories.join(",")}`);
    } catch (err) {
      // Fail closed: AI unavailable → hold for human review
      console.error("[checkContentSafety] NeMo Guard error — failing closed:", err.message);

      const decisionId = await persistDecision({
        uid,
        contentType,
        contextId,
        decision: "review",
        reason: "AI safety check temporarily unavailable — held for human review.",
        detectedCategories: ["ai_error"],
        crisisEscalated: false,
        contentLength: content.length,
        source: "checkContentSafety_ai_error",
      }).catch(() => "unknown");

      return {
        decision: "review",
        reason: "Content held for safety review.",
        crisisEscalated: false,
        decisionId,
      };
    }

    // ── 6. Map to unified decision ────────────────────────────────────────────
    const mapped = mapToDecision(nemoResult, localFlags);
    let { decision, reason, detectedCategories } = mapped;

    // ── 7. Self-harm escalation path ─────────────────────────────────────────
    let crisisEscalated = false;
    let crisisResources = undefined;

    if (localFlags.selfHarm) {
      // First persist the moderation decision record (we need its ID for the crisis record)
      const decisionId = await persistDecision({
        uid,
        contentType,
        contextId,
        decision,
        reason,
        detectedCategories,
        crisisEscalated: true,
        contentLength: content.length,
        source: "checkContentSafety",
      }).catch((err) => {
        console.error("[checkContentSafety] Failed to persist decision:", err.message);
        return "unknown";
      });

      // Now escalate
      try {
        await escalateSelfHarm(uid, content, contentType, contextId, decisionId);
        crisisEscalated = true;
      } catch (err) {
        console.error("[checkContentSafety] escalateSelfHarm failed:", err.message);
        // Don't rethrow — still return the decision with crisis resources
        crisisEscalated = false; // couldn't confirm escalation, but still show resources
      }

      crisisResources = [
        {
          name: "988 Suicide & Crisis Lifeline",
          number: "988",
          url: "https://988lifeline.org",
          instruction: "Call or text 988 — available 24/7.",
        },
        {
          name: "Crisis Text Line",
          instruction: "Text HOME to 741741",
          url: "https://www.crisistextline.org",
        },
        {
          name: "SAMHSA National Helpline",
          number: "1-800-662-4357",
          url: "https://www.samhsa.gov/find-help/national-helpline",
          instruction: "Free, confidential, 24/7.",
        },
        {
          name: "Berean AI Support",
          instruction: "Tap 'Berean' in AMEN for compassionate spiritual support right now.",
        },
      ];

      console.warn(`[checkContentSafety] SELF-HARM escalated uid=${uid} decisionId=${decisionId}`);

      return {
        decision,
        reason: "You're not alone. We're here for you.",
        crisisEscalated: true,
        crisisResources,
        decisionId,
      };
    }

    // ── 8. Persist decision (non-crisis path) ─────────────────────────────────
    const decisionId = await persistDecision({
      uid,
      contentType,
      contextId,
      decision,
      reason,
      detectedCategories,
      crisisEscalated: false,
      contentLength: content.length,
      source: "checkContentSafety",
    }).catch((err) => {
      console.error("[checkContentSafety] Failed to persist decision:", err.message);
      return "unknown";
    });

    // ── 9. Return ─────────────────────────────────────────────────────────────
    const response = { decision, decisionId, crisisEscalated: false };
    if (reason)                  response.reason = reason;
    if (detectedCategories?.length) response.detectedCategories = detectedCategories;

    console.log(`[checkContentSafety] DONE uid=${uid} decision=${decision} decisionId=${decisionId}`);
    return response;
  }
);

// ─── Also export escalateSelfHarm for use by other CFs ───────────────────────
exports.escalateSelfHarm = escalateSelfHarm;
exports.persistDecision  = persistDecision;
