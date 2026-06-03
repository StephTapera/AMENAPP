// moderateUGC.js
// Server-side onDocumentCreated moderation triggers for Sanctuary messages,
// prayer requests, and DM messages. Reuses the same NVIDIA NeMo Guard pipeline
// (checkSafety) as moderatePost.js. All three triggers fail closed: if the NIM
// call errors, the document is hidden and queued for admin review.
//
// Deploy:
//   firebase deploy --only \
//     functions:moderateSanctuaryMessage,functions:moderatePrayerRequest,functions:moderateDMMessage \
//     --project amen-5e359

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { withRetry } = require("./retryHelper");

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

// TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
const TTL_PENDING_MS = 90 * 24 * 60 * 60 * 1000; // 90 days — unresolved items

// ─────────────────────────────────────────────────────────────────────────────
// checkSafety — shared NeMo Guard call (same implementation as moderatePost.js)
// M-01: fetch wrapped with withRetry for transient NVIDIA NIM failures.
// ─────────────────────────────────────────────────────────────────────────────
async function checkSafety(text, apiKey) {
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
exports.moderateSanctuaryMessage = onDocumentCreated(
  {
    document: "sanctuaries/{sanctuaryId}/messages/{messageId}",
    secrets: [NVIDIA_API_KEY],
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

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
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "sanctuary_message",
        sanctuaryId: event.params.sanctuaryId,
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
      const verdict = await checkSafety(text, NVIDIA_API_KEY.value());
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
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "sanctuary_message",
        sanctuaryId: event.params.sanctuaryId,
        authorId: message.senderId || message.authorId || null,
        preview: text.slice(0, 280),
        status,
        categories,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// moderatePrayerRequest
// Path: prayers/{prayerId}
// Note: prayer content is sensitive; NIM errors always fail closed ("pending"),
// never auto-approved.
// ─────────────────────────────────────────────────────────────────────────────
exports.moderatePrayerRequest = onDocumentCreated(
  {
    document: "prayers/{prayerId}",
    secrets: [NVIDIA_API_KEY],
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

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
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
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
      const verdict = await checkSafety(text, NVIDIA_API_KEY.value());
      status = verdict.safe ? "approved" : "blocked";
      categories = verdict.categories;
    } catch (err) {
      console.error("moderatePrayerRequest: NIM call failed:", err);
      // Fail closed — prayer requests are sensitive; never auto-approve on error.
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
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
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
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// moderateDMMessage
// Path: conversations/{conversationId}/messages/{messageId}
// Note: image-only DMs are set to visible: false + pending_image_review but are
// NOT added to the moderation queue (they have a separate image review path).
// ─────────────────────────────────────────────────────────────────────────────
exports.moderateDMMessage = onDocumentCreated(
  {
    document: "conversations/{conversationId}/messages/{messageId}",
    secrets: [NVIDIA_API_KEY],
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const message = snap.data();
    const text = (message.text || message.content || "").trim();
    const authorId = message.senderId || null;

    if (!text) {
      // Image-only DM: hide until the Storage trigger clears it via SafeSearch.
      // Do NOT enqueue — images have a dedicated review path.
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
      const verdict = await checkSafety(text, NVIDIA_API_KEY.value());
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
      // TTL: Firestore TTL policy should be enabled on moderationQueue.expireAt in Firebase Console
      await getFirestore().collection("moderationQueue").add({
        contentRef: snap.ref.path,
        contentType: "dm_message",
        conversationId: event.params.conversationId,
        authorId,
        preview: text.slice(0, 280),
        status,
        categories,
        createdAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + TTL_PENDING_MS),
      });
    }
  }
);
