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
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const SAFETY_MODEL = "nvidia/llama-3.1-nemoguard-8b-content-safety";

// If the safety check errors out, should the post stay visible?
// false = fail closed (hide + queue for admin review) — matches Amen's "safe" promise.
const FAIL_OPEN = false;

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
        moderation: {
          status: "pending_image_review",
          categories: [],
          provider: "image-review-pending",
          checkedAt: FieldValue.serverTimestamp(),
        },
      });
      await getFirestore().collection("moderationQueue").add({
        postRef: snap.ref.path,
        authorId: post.authorId || null,
        preview: "[image-only post — pending visual review]",
        status: "pending",
        categories: [],
        reason: "image_only_pending_visual_review",
        createdAt: FieldValue.serverTimestamp(),
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
      console.error("NIM moderation failed:", err);
      status = FAIL_OPEN ? "approved" : "pending";
    }

    await snap.ref.update({
      visible: status === "approved",
      moderation: {
        status, // approved | blocked | pending
        categories, // e.g. ["hate", "harassment"]
        provider: "nvidia-nemoguard",
        checkedAt: FieldValue.serverTimestamp(),
      },
    });

    // Anything not auto-approved goes to the Admin Center queue.
    if (status !== "approved") {
      await getFirestore().collection("moderationQueue").add({
        postRef: snap.ref.path,
        authorId: post.authorId || null,
        preview: text.slice(0, 280),
        status,
        categories,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  }
);

async function checkSafety(text, apiKey) {
  const res = await fetch(NIM_URL, {
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
