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
const { withRetry } = require("./retryHelper");

// Shared decision persistence + crisis escalation
function getGateway() { return require("./moderationGateway"); }

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

// If the safety check errors out, should the post stay visible?
// false = fail closed (hide + queue for admin review) — matches Amen's "safe" promise.
const FAIL_OPEN = false;

// TTL helpers
// TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
const TTL_PENDING_MS  = 90 * 24 * 60 * 60 * 1000; // 90 days — unresolved items
const TTL_RESOLVED_MS = 30 * 24 * 60 * 60 * 1000; // 30 days — resolved items

exports.moderatePost = onDocumentCreated(
  {
    document: "posts/{postId}",
    secrets: [NVIDIA_API_KEY],
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const post = snap.data();
    const text = (post.text || post.body || "").trim();

    if (!text) {
      // Image-only post: hold it invisible until the Storage trigger
      // (moderateUploadedImage) clears the media via SafeSearch.
      await snap.ref.update({
        visible: false,
        flaggedForReview: true,
        removed: false,
        moderation: {
          status: "pending_image_review",
          categories: [],
          provider: "image-review-pending",
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
      await getFirestore().collection("moderationQueue").add({
        postRef: snap.ref.path,
        authorId: post.authorId || null,
        preview: "[image-only post — pending visual review]",
        status: "pending",
        categories: [],
        reason: "image_only_pending_visual_review",
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
      return;
    }

    const authorId = post.authorId || post.userId || null;
    const selfHarm = detectSelfHarm(text);

    let status;
    let categories = [];
    try {
      const verdict = await checkSafety(text, NVIDIA_API_KEY.value());
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      console.error("NIM moderation failed:", err);
      status = FAIL_OPEN ? "approved" : "pending";
    }

    // Self-harm posts must never be silently blocked — route to crisis review
    if (selfHarm) {
      status = "pending"; // Kept visible to author; surfaced as urgent for admin
    }

    await snap.ref.update({
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

    // Persist to canonical moderationDecisions/ and handle crisis escalation
    const { persistDecision, escalateSelfHarm } = getGateway();
    const decisionId = await persistDecision({
      uid: authorId,
      contentType: "post",
      contextId: snap.ref.path,
      decision: selfHarm ? "review" : (status === "approved" ? "allow" : status === "blocked" ? "block" : "review"),
      reason: selfHarm ? "Self-harm language detected in post" : (categories.length ? categories.join(", ") : null),
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

    // Anything not auto-approved goes to the Admin Center queue.
    if (status !== "approved") {
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
      await getFirestore().collection("moderationQueue").add({
        postRef: snap.ref.path,
        authorId: authorId || null,
        preview: text.slice(0, 280),
        status,
        categories,
        crisisEscalated: selfHarm,
        priority: selfHarm ? "critical" : "normal",
        moderationDecisionId: decisionId,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }
  }
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
exports.adminReviewPost = onCall({ region: "us-central1" }, async (request) => {
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
    const queueSnap = await db.collection("moderationQueue")
      .where("postRef", "==", `posts/${postId}`)
      .where("status", "in", ["blocked", "pending"])
      .get();

    const blockedUrls = new Set(
      queueSnap.docs
        .map((d) => d.data().blockedMediaUrl)
        .filter(Boolean)
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

    console.log(`[adminReviewPost] Admin ${request.auth.uid} approved post ${postId}, stripped ${blockedUrls.size} blocked URL(s).`);
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

async function checkSafety(text, apiKey) {
  // M-01: wrap NIM fetch in retry/backoff
  const res = await withRetry(() => fetch(NIM_URL, {
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
  }), 3, 500);

  if (!res.ok) {
    throw new Error(`NIM ${res.status}: ${await res.text()}`);
  }

  const data = await res.json();
  const raw = data.choices?.[0]?.message?.content ?? "";

  // NemoGuard returns JSON like:
  //   {"User Safety": "unsafe", "Safety Categories": "Hate, Harassment"}
  let safe = true;
  let categories = [];
  try {
    const parsed = JSON.parse(raw);
    safe = String(parsed["User Safety"] ?? "safe").toLowerCase() === "safe";
    if (parsed["Safety Categories"]) {
      categories = String(parsed["Safety Categories"])
        .split(",")
        .map((c) => c.trim().toLowerCase())
        .filter(Boolean);
    }
  } catch {
    // Fallback if the model returns plain text instead of JSON.
    safe = !/unsafe/i.test(raw);
  }

  return { safe, categories };
}
