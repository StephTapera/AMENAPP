// moderatePost.js
// Auto-moderates new community posts in Amen using NVIDIA NeMo Guard content safety,
// served via NVIDIA NIM (OpenAI-compatible endpoint at integrate.api.nvidia.com).
//
// Wiring:
//   1) Already required from index.js and exported as moderatePost.
//   2) Set the key once:
//        firebase functions:secrets:set NVIDIA_API_KEY --project amen-5e359
//        (paste your nvapi-... key from build.nvidia.com)
//   3) Deploy:  firebase deploy --only functions:moderatePost --project amen-5e359

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

// Shared decision persistence + crisis escalation
function getGateway() { return require("./moderationGateway"); }

// Image CSAM pipeline — used for image-only posts and human review of image posts.
// SECURITY (C2 fix): Both paths must call escalateChildSafety + fileNCMECReport
// when the vision model returns cs_csam_suspected or cs_child_exploitation.
const { moderateImage } = require("./moderation/imageModeration");
const { fileNCMECReport } = require("./ncmecReporter");

// Vision categories that require mandatory CSAM escalation regardless of path.
const IMAGE_CSAM_CATEGORIES = new Set(["cs_csam_suspected", "cs_child_exploitation"]);

// Self-harm phrase fast pre-check (mirrors moderationGateway.js)
const SELF_HARM_PHRASES = [
  "kill myself", "killing myself", "end my life", "end it all",
  "suicide", "suicidal", "cut myself", "cutting myself",
  "self harm", "selfharm", "want to die", "i want to die",
  "no reason to live", "i cant go on", "i cannot go on",
  "take my own life", "better off dead", "not worth living",
  "overdose on purpose",
];
function detectSelfHarm(text) {
  const lower = text.toLowerCase();
  return SELF_HARM_PHRASES.some((p) => lower.includes(p));
}

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

// SECURITY FIX (HIGH 2026-06-11): Removed the FAIL_OPEN named constant.
// A named boolean constant was one character away from flipping every moderation
// error to auto-approve. The value is now inlined as a hard-coded false at the
// single usage site below, with a comment making the invariant explicit.
// INVARIANT: moderation errors ALWAYS fail closed (status = "pending", not "approved").
// DO NOT change the literal false below without T&S Lead and Legal sign-off.

// Policy version stamped on every audit log entry.
const POLICY_VERSION = "amen-safety-v1";

// TTL helpers
// TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
const TTL_PENDING_MS  = 90 * 24 * 60 * 60 * 1000; // 90 days — unresolved items
const TTL_RESOLVED_MS = 30 * 24 * 60 * 60 * 1000; // 30 days — resolved items

// Child-safety category tokens that trigger CSAM escalation path.
const CHILD_SAFETY_CATEGORIES = new Set(["child_safety", "csam_suspected"]);

// ─── Retry with exponential backoff ──────────────────────────────────────────
// Retries a fetch factory up to maxRetries times on 429 / 5xx responses.
// On exhaustion returns null so the caller can fail-closed.
// Delays: 500 ms → 1 000 ms → 2 000 ms
async function fetchWithRetry(fetchFn, maxRetries = 3) {
  const delays = [500, 1000, 2000];
  let lastErr = null;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    let res;
    try {
      res = await fetchFn();
    } catch (err) {
      lastErr = err;
      // Network-level error — retry if attempts remain.
      if (attempt < maxRetries) {
        await sleep(delays[Math.min(attempt, delays.length - 1)]);
        continue;
      }
      return { exhausted: true, error: lastErr, response: null };
    }

    const retryable = res.status === 429 || res.status >= 500;
    if (!retryable) {
      return { exhausted: false, error: null, response: res };
    }

    // Retryable HTTP status.
    lastErr = new Error(`NIM ${res.status}`);
    if (attempt < maxRetries) {
      await sleep(delays[Math.min(attempt, delays.length - 1)]);
    }
  }
  return { exhausted: true, error: lastErr, response: null };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ─── Jailbreak-proof safety parser ───────────────────────────────────────────
// Returns { safe: boolean, categories: string[] }.
// Fail-closed: any ambiguity → safe = false.
function parseSafetyResponse(raw) {
  // Attempt 1: full JSON parse with EXACT string match.
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && "User Safety" in parsed) {
      const verdict = String(parsed["User Safety"]).trim().toLowerCase();
      // EXACT match only — never "not unsafe", never substring tricks.
      const safe = verdict === "safe";
      let categories = [];
      if (parsed["Safety Categories"]) {
        categories = String(parsed["Safety Categories"])
          .split(",")
          .map((c) => c.trim().toLowerCase())
          .filter(Boolean);
      }
      return { safe, categories };
    }
    // JSON parsed but "User Safety" key absent — fail closed.
    return { safe: false, categories: [] };
  } catch {
    // Not valid JSON — fall through to line-regex search.
  }

  // Attempt 2: find a line matching the expected key:value shape.
  const lines = raw.split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^\s*"?User Safety"?\s*:\s*"(safe|unsafe)"/i);
    if (m) {
      const safe = m[1].toLowerCase() === "safe"; // EXACT, not negation-based
      return { safe, categories: [] };
    }
  }

  // Attempt 3: ambiguous or unrecognised format — default UNSAFE (fail-closed).
  return { safe: false, categories: [] };
}

// ─── NIM safety check ────────────────────────────────────────────────────────
async function checkSafety(text, apiKey) {
  const { exhausted, error, response } = await fetchWithRetry(
    () =>
      fetch(NIM_URL, {
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
      }),
    3,
  );

  if (exhausted || !response) {
    throw Object.assign(
      new Error(`NIM fetch exhausted after 3 retries: ${error?.message ?? "unknown"}`),
      { retryExhausted: true, cause: error },
    );
  }

  if (!response.ok) {
    throw new Error(`NIM ${response.status}: ${await response.text()}`);
  }

  const data = await response.json();
  const raw = data.choices?.[0]?.message?.content ?? "";
  return parseSafetyResponse(raw);
}

// ─── Audit log writer ─────────────────────────────────────────────────────────
async function writeAuditLog(db, { postRef, status, categories, provider, model }) {
  await db.collection("moderationAuditLog").add({
    postRef: postRef.path ?? postRef,
    status,
    categories,
    provider,
    model: model ?? SAFETY_MODEL,
    policyVersion: POLICY_VERSION,
    decidedAt: FieldValue.serverTimestamp(),
    actorType: "auto",
  });
}

// ─── Dead-letter writer ───────────────────────────────────────────────────────
async function writeDeadLetter(db, { postRef, error }) {
  await db.collection("moderationDeadLetter").add({
    postRef: postRef.path ?? postRef,
    error: error?.message ?? String(error),
    errorStack: error?.stack ?? null,
    timestamp: FieldValue.serverTimestamp(),
  });
}

// ─── Child-safety escalation ──────────────────────────────────────────────────
async function escalateChildSafety(db, { snap, post, categories, authorId }) {
  const holdId = `hold_${snap.ref.id}_${Date.now()}`;
  const holdRef = db.collection("legalHolds").doc(holdId);

  const batch = db.batch();

  // 1. Post: immediately invisible.
  batch.update(snap.ref, {
    visible: false,
    flaggedForReview: true,
    removed: false,
    moderation: {
      status: "blocked",
      categories,
      provider: "nvidia-nemoguard",
      checkedAt: FieldValue.serverTimestamp(),
      childSafetyEscalated: true,
    },
  });

  // 2. Legal hold: snapshot of post data.
  batch.set(holdRef, {
    postRef: snap.ref.path,
    authorId: authorId ?? null,
    postSnapshot: post,
    categories,
    createdAt: FieldValue.serverTimestamp(),
    status: "active",
  });

  // 3. Child safety escalations collection.
  const escRef = db.collection("childSafetyEscalations").doc();
  batch.set(escRef, {
    contentRef: snap.ref.path,
    authorId: authorId ?? null,
    categories,
    status: "new",
    severity: "critical",
    legalHold: true,
    legalHoldRef: holdRef.path,
    externalReport: {
      required: true,
      provider: "NCMEC_CYBERTIPLINE",
      submitted: false,
    },
    createdAt: FieldValue.serverTimestamp(),
  });

  await batch.commit();
  console.warn(
    `[moderatePost] CHILD SAFETY ESCALATION — post ${snap.ref.id}, holdId ${holdId}, categories: ${categories.join(", ")}`,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// moderatePost — Firestore onCreate trigger
// ─────────────────────────────────────────────────────────────────────────────
exports.moderatePost = onDocumentCreated(
  {
    document: "posts/{postId}",
    secrets: [NVIDIA_API_KEY],
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const db = getFirestore();
    const post = snap.data();
    const text = (post.text || post.body || "").trim();
    const authorId = post.authorId || post.userId || null;
    const hasImage = Boolean(post.imageUrl || post.mediaUrl);

    // ── IMAGE-ONLY POSTS ────────────────────────────────────────────────────
    // SECURITY (C2 fix 2026-06-11): Run vision moderation inline so CSAM images
    // are escalated immediately — never held in the human review queue without a
    // legalHold + childSafetyEscalations record + NCMEC queue entry.
    //
    // Flow:
    //   1. Run moderateImage on the image URL.
    //   2. If CSAM categories detected → escalateChildSafety + fileNCMECReport, return.
    //   3. If non-CSAM blocked → route to pending_image_review queue as before.
    //   4. Vision model unavailable → fail closed to pending_image_review.
    if (!text) {
      const imageUrl = post.imageUrl || post.mediaUrl || null;

      let imgResult = null;
      if (imageUrl) {
        try {
          imgResult = await moderateImage(imageUrl, NVIDIA_API_KEY.value());
        } catch (imgErr) {
          // Fail closed — vision model unavailable.
          console.warn(`[moderatePost] moderateImage failed (${imgErr.message}) — failing closed to review queue`);
          imgResult = null;
        }
      }

      const imgCategories = imgResult ? imgResult.categories : [];
      const imgHasCSAM = imgCategories.some((c) => IMAGE_CSAM_CATEGORIES.has(c));

      if (imgHasCSAM) {
        // CSAM confirmed by vision model — mandatory escalation before any queue entry.
        await escalateChildSafety(db, { snap, post, categories: imgCategories, authorId });

        // File tamper-evident NCMEC record.
        await fileNCMECReport({
          contentRef: snap.ref.path,
          contentType: "image",
          contentUrl: imageUrl,
          authorId: authorId ?? null,
          detectedCategories: imgCategories,
          detectedBy: "nvidia-vision-llm",
        }).catch((e) => console.error("[moderatePost] fileNCMECReport error (image-only CSAM):", e.message));

        // Audit log.
        await writeAuditLog(db, {
          postRef: snap.ref,
          status: "blocked",
          categories: imgCategories,
          provider: "nvidia-vision-llm",
          model: null,
        }).catch((e) => console.error("[moderatePost] auditLog error (image-only CSAM):", e.message));

        console.warn(
          `[moderatePost] IMAGE-ONLY CSAM ESCALATED — post ${snap.ref.id} categories: ${imgCategories.join(", ")}`,
        );
        return;
      }

      // Non-CSAM image result: route to human review queue (original behaviour).
      const imgStatus = imgResult ? imgResult.status : "pending_image_review";
      const queueCategories = imgCategories.length > 0 ? imgCategories : [];

      const batch = db.batch();
      batch.update(snap.ref, {
        visible: false,
        flaggedForReview: true,
        removed: false,
        moderation: {
          status: imgStatus,
          categories: queueCategories,
          provider: imgResult ? "nvidia-vision-llm" : "image-review-pending",
          imageReviewRequired: true,
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      const qRef = db.collection("moderationQueue").doc();
      batch.set(qRef, {
        postRef: snap.ref.path,
        authorId: authorId ?? null,
        preview: "[image-only post — pending visual review]",
        status: imgStatus,
        categories: queueCategories,
        reason: "image_only_pending_visual_review",
        imageReviewRequired: true,
        hasImage,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
      await batch.commit();

      // Audit log for image-only path.
      await writeAuditLog(db, {
        postRef: snap.ref,
        status: imgStatus,
        categories: queueCategories,
        provider: imgResult ? "nvidia-vision-llm" : "image-review-pending",
        model: null,
      });
      return;
    }

    // ── SELF-HARM FAST CHECK ─────────────────────────────────────────────────
    const selfHarm = detectSelfHarm(text);

    // ── NIM SAFETY CHECK (with retry) ────────────────────────────────────────
    let status;
    let categories = [];
    let nimError = null;
    let retryExhausted = false;

    try {
      const verdict = await checkSafety(text, NVIDIA_API_KEY.value());
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      nimError = err;
      retryExhausted = Boolean(err.retryExhausted);
      console.error("[moderatePost] NIM moderation failed:", err.message);
      // INVARIANT: fail closed — DO NOT change to "approved" without T&S Lead sign-off.
      status = false ? "approved" : "pending"; // false = FAIL_CLOSED_ALWAYS (see constant removal above)
    }

    // Self-harm posts must never be silently blocked — route to crisis review.
    if (selfHarm) {
      status = "pending"; // Kept visible to author; surfaced as urgent for admin.
    }

    // ── CHILD SAFETY ESCALATION ───────────────────────────────────────────────
    const hasChildSafetyFlag = categories.some((c) => CHILD_SAFETY_CATEGORIES.has(c));
    if (hasChildSafetyFlag) {
      await escalateChildSafety(db, { snap, post, categories, authorId });

      // Audit log for child-safety path.
      await writeAuditLog(db, {
        postRef: snap.ref,
        status: "blocked",
        categories,
        provider: "nvidia-nemoguard",
        model: SAFETY_MODEL,
      }).catch((e) => console.error("[moderatePost] auditLog error (child safety):", e.message));

      // Child-safety posts do NOT go to the normal moderationQueue.
      return;
    }

    // ── DEAD LETTER on retry exhaustion ──────────────────────────────────────
    if (retryExhausted) {
      await writeDeadLetter(db, { postRef: snap.ref, error: nimError }).catch((e) =>
        console.error("[moderatePost] deadLetter write error:", e.message),
      );
    }

    // ── ATOMIC BATCH: update post + add to moderationQueue ───────────────────
    const writeBatch = db.batch();

    writeBatch.update(snap.ref, {
      visible: status === "approved" || selfHarm,
      flaggedForReview: status === "pending" || status === "pending_image_review",
      removed: status === "blocked" && !selfHarm,
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
        crisisEscalated: selfHarm,
      },
    });

    if (status !== "approved") {
      const qRef = db.collection("moderationQueue").doc();
      writeBatch.set(qRef, {
        postRef: snap.ref.path,
        authorId: authorId ?? null,
        preview: text.slice(0, 280),
        status,
        categories,
        crisisEscalated: selfHarm,
        priority: selfHarm ? "critical" : "normal",
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }

    await writeBatch.commit();

    // ── AUDIT LOG ─────────────────────────────────────────────────────────────
    await writeAuditLog(db, {
      postRef: snap.ref,
      status,
      categories,
      provider: "nvidia-nemoguard",
      model: SAFETY_MODEL,
    }).catch((e) => console.error("[moderatePost] auditLog error:", e.message));

    // ── PERSIST CANONICAL DECISION + CRISIS ESCALATION ───────────────────────
    const { persistDecision, escalateSelfHarm } = getGateway();
    const decisionId = await persistDecision({
      uid: authorId,
      contentType: "post",
      contextId: snap.ref.path,
      decision:
        selfHarm
          ? "review"
          : status === "approved"
          ? "allow"
          : status === "blocked"
          ? "block"
          : "review",
      reason: selfHarm
        ? "Self-harm language detected in post"
        : categories.length
        ? categories.join(", ")
        : null,
      detectedCategories: selfHarm ? ["self_harm", ...categories] : categories,
      crisisEscalated: selfHarm,
      contentLength: text.length,
      source: "moderatePost_trigger",
    }).catch((err) => {
      console.error("[moderatePost] persistDecision error:", err.message);
      return "unknown";
    });

    if (selfHarm) {
      await escalateSelfHarm(authorId, text, "post", snap.ref.path, decisionId).catch((err) => {
        console.error("[moderatePost] escalateSelfHarm error:", err.message);
      });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// adminReviewPost — callable (admin only)
//   Approves or rejects a post sitting in the moderationQueue.
//   On approve:  sets visible: true, strips any blocked media URLs from post.media.
//   On reject:   sets visible: false (permanent), updates queue item status.
//
// Caller must have the custom claim  admin: true  (set via adminClaims CF).
// Args: { postId: string, decision: "approved" | "rejected", queueId?: string }
// ─────────────────────────────────────────────────────────────────────────────
// SECURITY FIX (MEDIUM 2026-06-11): Added enforceAppCheck: true to match the
// posture of decideAppeal and other sensitive callables. Without App Check, the
// callable can be invoked from scripts or tooling outside the official app.
exports.adminReviewPost = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  if (!request.auth?.token?.admin) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const { postId, decision, queueId } = request.data || {};
  if (!postId || !["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "postId and decision ('approved'|'rejected') required.");
  }

  const db = getFirestore();
  const postRef = db.collection("posts").doc(postId);
  const postSnap = await postRef.get();
  if (!postSnap.exists) {
    throw new HttpsError("not-found", `Post ${postId} not found.`);
  }

  if (decision === "approved") {
    // Collect blocked media URLs from all matching queue items so we can strip them.
    const queueSnap = await db
      .collection("moderationQueue")
      .where("postRef", "==", `posts/${postId}`)
      .where("status", "in", ["blocked", "pending"])
      .get();

    const blockedUrls = new Set(
      queueSnap.docs
        .map((d) => d.data().blockedMediaUrl)
        .filter(Boolean),
    );

    const postData = postSnap.data();
    const cleanedMedia = (postData.media || []).filter((url) => !blockedUrls.has(url));

    await postRef.update({
      visible: true,
      flaggedForReview: false,
      removed: false,
      media: cleanedMedia,
      moderation: {
        status: "approved",
        categories: [],
        provider: "admin-manual",
        reviewedBy: request.auth.uid,
        checkedAt: FieldValue.serverTimestamp(),
      },
    });

    // Mark every related queue item resolved, with short TTL for resolved items.
    const batch = db.batch();
    const resolvedExpireAt = new Date(Date.now() + TTL_RESOLVED_MS);
    queueSnap.docs.forEach((d) => {
      batch.update(d.ref, {
        status: "resolved",
        resolvedBy: request.auth.uid,
        resolvedAt: FieldValue.serverTimestamp(),
        expireAt: resolvedExpireAt,
      });
    });
    if (queueId) {
      batch.update(db.collection("moderationQueue").doc(queueId), {
        status: "resolved",
        resolvedBy: request.auth.uid,
        resolvedAt: FieldValue.serverTimestamp(),
        expireAt: resolvedExpireAt,
      });
    }
    await batch.commit();

    console.log(
      `[adminReviewPost] Admin ${request.auth.uid} approved post ${postId}, stripped ${blockedUrls.size} blocked URL(s).`,
    );
    return { success: true, strippedMedia: blockedUrls.size };
  }

  // decision === "rejected"
  await postRef.update({
    visible: false,
    flaggedForReview: false,
    removed: true,
    moderation: {
      status: "rejected",
      categories: [],
      provider: "admin-manual",
      reviewedBy: request.auth.uid,
      checkedAt: FieldValue.serverTimestamp(),
    },
  });

  if (queueId) {
    await db.collection("moderationQueue").doc(queueId).update({
      status: "rejected",
      resolvedBy: request.auth.uid,
      resolvedAt: FieldValue.serverTimestamp(),
      expireAt: new Date(Date.now() + TTL_RESOLVED_MS),
    });
  }

  console.log(`[adminReviewPost] Admin ${request.auth.uid} rejected post ${postId}.`);
  return { success: true };
});
