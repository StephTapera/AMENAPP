// TODO: USE_DEFINE_SECRET — migrate this secret to defineSecret() for Functions v2
// TODO: MIGRATE_TO_V2 — still using Gen1 runWith() pattern
// moderateUGC.js — v1 Cloud Functions (avoids Cloud Run quota)
// Server-side onCreate moderation triggers for Sanctuary messages, prayer requests,
// and DM messages. Reuses the same NVIDIA NeMo Guard pipeline as moderatePost.js.
// All three triggers fail closed: if the NIM call errors, the document is hidden
// and queued for admin review.

const functions = require("firebase-functions/v1");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { withRetry } = require("./retryHelper");

// Shared moderation decision persistence + self-harm escalation.
// Lazy-require to avoid circular dependency issues at module load time.
function getGateway() {
    return require("./moderationGateway");
}

const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";
const TTL_PENDING_MS = 90 * 24 * 60 * 60 * 1000;

const ugcFunctions = functions.region("us-central1").runWith({ secrets: ["NVIDIA_API_KEY"] });

async function checkSafety(text) {
  const apiKey = process.env.NVIDIA_API_KEY;
  // FIX: withRetry only catches thrown exceptions — it does NOT retry on HTTP error
  // status codes (429/5xx) because fetch() resolves (not throws) on those. Use an
  // inline retry loop that inspects res.status before resolving, mirroring
  // moderatePost.js fetchWithRetry. This ensures rate-limit and server errors
  // are retried rather than silently skipped.
  const delays = [500, 1000, 2000];
  let res = null;
  let lastErr = null;
  for (let attempt = 0; attempt <= 3; attempt++) {
    try {
      res = await fetch(NIM_URL, {
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
        }),
      });
    } catch (err) {
      lastErr = err;
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, delays[Math.min(attempt, delays.length - 1)]));
        continue;
      }
      throw new Error(`NIM fetch failed after 3 retries: ${err.message}`);
    }
    // Retry on 429 or 5xx.
    if (res.status === 429 || res.status >= 500) {
      lastErr = new Error(`NIM ${res.status}`);
      if (attempt < 3) {
        await new Promise((r) => setTimeout(r, delays[Math.min(attempt, delays.length - 1)]));
        continue;
      }
      throw new Error(`NIM ${res.status} after 3 retries`);
    }
    break; // success or non-retryable error
  }

  if (!res || !res.ok) {
    const body = res ? await res.text().catch(() => "(no body)") : "(no response)";
    throw new Error(`NIM ${res ? res.status : "unknown"}: ${body}`);
  }

  const data = await res.json();
  const raw = data.choices?.[0]?.message?.content ?? "";

  // Jailbreak-resistant parsing — mirrors moderatePost.js parseSafetyResponse.
  // Fail closed: any non-JSON or ambiguous response → safe = false.
  let safe = false;
  let categories = [];
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && "User Safety" in parsed) {
      // EXACT match only — never use negation-based substring checks.
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Self-harm phrases for fast synchronous pre-check (mirrors moderationGateway.js)
// ─────────────────────────────────────────────────────────────────────────────
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
];

function detectSelfHarm(text) {
  const lower = text.toLowerCase();
  return SELF_HARM_PHRASES.some((p) => lower.includes(p));
}

/**
 * After determining the moderation outcome, write to moderationDecisions/
 * and (if self-harm detected) trigger the escalation path.
 *
 * @param {string} uid
 * @param {string} contentType   "sanctuary_message"|"prayer_request"|"dm_message"
 * @param {string} contextId     Firestore path of the content document
 * @param {string} status        "approved"|"blocked"|"pending"
 * @param {string[]} categories  NeMo categories
 * @param {boolean} selfHarm     Whether self-harm was locally detected
 * @param {string} rawText       Original text (for escalation)
 */
async function persistUGCDecision(uid, contentType, contextId, status, categories, selfHarm, rawText) {
  const decision = status === "approved" ? "allow"
                 : status === "blocked"  ? "block"
                 : "review";

  const { persistDecision, escalateSelfHarm } = getGateway();

  const decisionId = await persistDecision({
    uid,
    contentType,
    contextId,
    decision: selfHarm ? "review" : decision,
    reason: selfHarm ? "Self-harm language detected" : (categories.length ? categories.join(", ") : null),
    detectedCategories: selfHarm ? ["self_harm", ...categories] : categories,
    crisisEscalated: selfHarm,
    contentLength: rawText.length,
    source: "moderateUGC_trigger",
  }).catch((err) => {
    console.error("[moderateUGC] persistDecision error:", err.message);
    return "unknown";
  });

  if (selfHarm) {
    await escalateSelfHarm(uid, rawText, contentType, contextId, decisionId).catch((err) => {
      console.error("[moderateUGC] escalateSelfHarm error:", err.message);
    });
  }

  return decisionId;
}

// ─────────────────────────────────────────────────────────────────────────────
// moderateSanctuaryMessage
// Path: sanctuaries/{sanctuaryId}/messages/{messageId}
// ─────────────────────────────────────────────────────────────────────────────
exports.moderateSanctuaryMessage = ugcFunctions.firestore
  .document("sanctuaries/{sanctuaryId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const text = (message.text || message.body || message.content || "").trim();

    if (!text) {
      await snap.ref.update({
        visible: false,
        moderation: {
          status: "pending_image_review",
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "sanctuary_message",
        sanctuaryId: context.params.sanctuaryId,
        authorId: message.senderId || message.authorId || null,
        preview: "[media-only message — pending visual review]",
        status: "pending",
        categories: [],
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
      return;
    }

    const authorId = message.senderId || message.authorId || null;
    const selfHarm = detectSelfHarm(text);

    let status;
    let categories = [];
    try {
      const verdict = await checkSafety(text);
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      console.error("moderateSanctuaryMessage: NIM call failed:", err);
      status = "pending";
    }

    // Self-harm overrides NeMo verdict: always "pending" (never silently blocked)
    if (selfHarm) {
      status = "pending";
    }

    await snap.ref.update({
      visible: status === "approved",
      removed: status === "blocked",
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
      },
    });

    // Persist to moderationDecisions/ and (if self-harm) crisisEscalations/
    await persistUGCDecision(
      authorId,
      "sanctuary_message",
      snap.ref.path,
      status,
      categories,
      selfHarm,
      text
    );

    if (status !== "approved") {
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "sanctuary_message",
        sanctuaryId: context.params.sanctuaryId,
        authorId,
        preview: text.slice(0, 280),
        status,
        categories,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }
  });

// ─────────────────────────────────────────────────────────────────────────────
// moderatePrayerRequest
// Path: prayers/{prayerId}
// NIM errors always fail closed ("pending") — prayer requests are sensitive.
// ─────────────────────────────────────────────────────────────────────────────
exports.moderatePrayerRequest = ugcFunctions.firestore
  .document("prayers/{prayerId}")
  .onCreate(async (snap, context) => {
    const prayer = snap.data();
    const text = (prayer.text || prayer.body || prayer.request || "").trim();
    const authorId = prayer.authorId || prayer.userId || null;

    if (!text) {
      await snap.ref.update({
        visible: false,
        moderation: {
          status: "pending_image_review",
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "prayer_request",
        authorId,
        preview: "[no text — pending review]",
        status: "pending",
        categories: [],
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
      return;
    }

    const selfHarm = detectSelfHarm(text);

    let status;
    let categories = [];
    try {
      const verdict = await checkSafety(text);
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      console.error("moderatePrayerRequest: NIM call failed:", err);
      status = "pending";
    }

    // Self-harm in a prayer request must NEVER be silently blocked — route to crisis support
    if (selfHarm) {
      status = "pending"; // Keep visible to author; hold for crisis team review
    }

    await snap.ref.update({
      visible: status === "approved" || selfHarm, // self-harm prayers stay visible to author
      removed: status === "blocked" && !selfHarm,
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
        crisisEscalated: selfHarm,
      },
    });

    // Persist to moderationDecisions/ and (if self-harm) crisisEscalations/
    await persistUGCDecision(
      authorId,
      "prayer_request",
      snap.ref.path,
      status,
      categories,
      selfHarm,
      text
    );

    if (status !== "approved") {
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "prayer_request",
        authorId,
        preview: text.slice(0, 280),
        status,
        categories,
        crisisEscalated: selfHarm,
        priority: selfHarm ? "critical" : "normal",
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }
  });

// ─────────────────────────────────────────────────────────────────────────────
// moderateDMMessage
// Path: conversations/{conversationId}/messages/{messageId}
// Image-only DMs are hidden for SafeSearch review — NOT enqueued separately.
// ─────────────────────────────────────────────────────────────────────────────
exports.moderateDMMessage = ugcFunctions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const text = (message.text || message.content || "").trim();
    const authorId = message.senderId || null;

    if (!text) {
      await snap.ref.update({
        visible: false,
        moderation: {
          status: "pending_image_review",
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      return;
    }

    const selfHarm = detectSelfHarm(text);

    let status;
    let categories = [];
    try {
      const verdict = await checkSafety(text);
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      console.error("moderateDMMessage: NIM call failed:", err);
      status = "pending";
    }

    // Self-harm in DMs: always deliver (never silent block) + escalate to crisis path
    if (selfHarm) {
      status = "approved"; // Message is delivered; crisis resources shown by client
    }

    await snap.ref.update({
      visible: status === "approved",
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
        crisisEscalated: selfHarm,
      },
    });

    // Persist to moderationDecisions/ and (if self-harm) crisisEscalations/
    await persistUGCDecision(
      authorId,
      "dm_message",
      snap.ref.path,
      status,
      categories,
      selfHarm,
      text
    );

    if (status !== "approved") {
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "dm_message",
        conversationId: context.params.conversationId,
        authorId,
        preview: text.slice(0, 280),
        status,
        categories,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }
  });
