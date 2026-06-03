// moderateUGC.js — v1 Cloud Functions (avoids Cloud Run quota)
// Server-side onCreate moderation triggers for Sanctuary messages, prayer requests,
// and DM messages. Reuses the same NVIDIA NeMo Guard pipeline as moderatePost.js.
// All three triggers fail closed: if the NIM call errors, the document is hidden
// and queued for admin review.

const functions = require("firebase-functions");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { withRetry } = require("./retryHelper");

const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";
const TTL_PENDING_MS = 90 * 24 * 60 * 60 * 1000;

const ugcFunctions = functions.region("us-central1").runWith({ secrets: ["NVIDIA_API_KEY"] });

async function checkSafety(text) {
  const apiKey = process.env.NVIDIA_API_KEY;
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
    safe = !/unsafe/i.test(raw);
  }

  return { safe, categories };
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

    if (status !== "approved") {
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "sanctuary_message",
        sanctuaryId: context.params.sanctuaryId,
        authorId: message.senderId || message.authorId || null,
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

    if (status !== "approved") {
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "prayer_request",
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

    await snap.ref.update({
      visible: status === "approved",
      moderation: {
        status,
        categories,
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
      },
    });

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
